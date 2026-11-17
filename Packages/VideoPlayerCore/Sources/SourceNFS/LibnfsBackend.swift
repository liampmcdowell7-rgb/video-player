import Foundation

// The libnfs-backed implementation. Only compiled when the `CLibnfs` module exists:
//  - Apple platforms: a C target (header + one empty .c file) that depends on the NFSKit
//    `Libnfs.xcframework` binary target (static libnfs.a, NFSv3 + NFSv4 client code).
//  - Linux (tests only): a system-library target pointing at a libnfs built from source.
// See docs/SOURCES.md and the manifest snippet in the NFS report for the wiring.
#if canImport(CLibnfs)
import CLibnfs
import Dispatch

/// NFSv3 over libnfs's synchronous API. libnfs contexts are not thread-safe, so every call runs on
/// one private serial queue. One open file handle is kept for the file read last (video playback
/// reads the same file again and again).
public final class LibnfsBackend: NFSBackend, @unchecked Sendable {
    private let queue = DispatchQueue(label: "videoplayer.nfs.libnfs")
    private var context: OpaquePointer?
    private var handle: OpaquePointer?
    private var handlePath: String?

    // Protocol constants (NFSv3 ftype3).
    private static let regular: UInt32 = 1
    private static let directory: UInt32 = 2
    private static let symlink: UInt32 = 5

    public init() {}

    deinit { teardown() }

    // MARK: NFSBackend

    public func mount(_ configuration: NFSConfiguration) async throws {
        try await perform { [self] in
            teardown()
            guard let ctx = nfs_init_context() else { throw NFSBackendError.failed("libnfs could not create a context") }
            _ = nfs_set_version(ctx, 3)                    // NFSv3 only
            nfs_set_auto_traverse_mounts(ctx, 0)           // servers without MOUNT EXPORT (rclone, some embedded ones) fail otherwise
            nfs_set_autoreconnect(ctx, 0)                  // reconnect is handled above, once, with a clean mount
            nfs_set_timeout(ctx, Int32(clamping: configuration.timeoutMilliseconds))
            nfs_set_dircache(ctx, 0)
            if let port = configuration.port {
                nfs_set_nfsport(ctx, Int32(port))
                nfs_set_mountport(ctx, Int32(port))
            }
            if let uid = configuration.uid { nfs_set_uid(ctx, Int32(uid)) }
            if let gid = configuration.gid { nfs_set_gid(ctx, Int32(gid)) }
            let status = nfs_mount(ctx, configuration.host, configuration.exportPath)
            if status != 0 {
                let message = Self.errorText(ctx)
                nfs_destroy_context(ctx)
                throw Self.mountError(status, message)
            }
            context = ctx
        }
    }

    public func unmount() async {
        _ = try? await perform { [self] in teardown() }
    }

    public func readDirectory(_ path: String) async throws -> [NFSDirectoryEntry] {
        try await perform { [self] in
            let ctx = try requireContext()
            var dir: OpaquePointer?
            let status = nfs_opendir(ctx, path, &dir)
            if status != 0 { throw Self.error(status, Self.errorText(ctx)) }
            defer { nfs_closedir(ctx, dir) }
            var result: [NFSDirectoryEntry] = []
            while let raw = nfs_readdir(ctx, dir) {
                let entry = raw.pointee
                guard let namePointer = entry.name else { continue }
                let seconds = Double(entry.mtime.tv_sec) + Double(entry.mtime_nsec) / 1_000_000_000
                result.append(NFSDirectoryEntry(
                    name: String(cString: namePointer),
                    kind: Self.kind(entry.type),
                    size: entry.size,
                    modified: seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
                ))
            }
            return result
        }
    }

    public func status(_ path: String) async throws -> NFSFileStatus {
        try await perform { [self] in
            let ctx = try requireContext()
            var st = nfs_stat_64()
            let status = nfs_stat64(ctx, path, &st)       // follows symlinks
            if status != 0 { throw Self.error(status, Self.errorText(ctx)) }
            let seconds = Double(st.nfs_mtime) + Double(st.nfs_mtime_nsec) / 1_000_000_000
            return NFSFileStatus(
                kind: Self.kind(from: UInt32(st.nfs_mode)),
                size: st.nfs_size,
                modified: seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
            )
        }
    }

    public func read(_ path: String, offset: UInt64, count: Int) async throws -> Data {
        try await perform { [self] in
            let ctx = try requireContext()
            let fh = try openHandle(ctx, path)
            var buffer = Data(count: count)
            let got: Int32 = buffer.withUnsafeMutableBytes { raw in
                nfs_pread(ctx, fh, offset, UInt64(count), raw.baseAddress)
            }
            if got < 0 {
                closeHandle(ctx)                           // a handle that failed once is not trusted again
                throw Self.error(got, Self.errorText(ctx))
            }
            return buffer.prefix(Int(got))
        }
    }

    // MARK: Internals (all called on `queue`)

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private func requireContext() throws -> OpaquePointer {
        guard let ctx = context else { throw NFSBackendError.connection("not mounted") }
        return ctx
    }

    private func openHandle(_ ctx: OpaquePointer, _ path: String) throws -> OpaquePointer {
        if let existing = handle, handlePath == path { return existing }
        closeHandle(ctx)
        var fh: OpaquePointer?
        let status = nfs_open(ctx, path, O_RDONLY, &fh)
        if status != 0 { throw Self.error(status, Self.errorText(ctx)) }
        guard let opened = fh else { throw NFSBackendError.failed("libnfs returned no file handle") }
        handle = opened
        handlePath = path
        return opened
    }

    private func closeHandle(_ ctx: OpaquePointer) {
        if let fh = handle { _ = nfs_close(ctx, fh) }
        handle = nil
        handlePath = nil
    }

    private func teardown() {
        if let ctx = context {
            closeHandle(ctx)
            _ = nfs_umount(ctx)
            nfs_destroy_context(ctx)
        }
        context = nil
        handle = nil
        handlePath = nil
    }

    private static func errorText(_ ctx: OpaquePointer?) -> String {
        guard let ctx, let text = nfs_get_error(ctx) else { return "" }
        return String(cString: text)
    }

    private static func kind(_ type: UInt32) -> NFSFileKind {
        switch type {
        case regular: return .file
        case directory: return .directory
        case symlink: return .symlink
        default: return .other
        }
    }

    /// `nfs_stat_64.nfs_mode` carries POSIX mode bits.
    private static func kind(from mode: UInt32) -> NFSFileKind {
        switch mode & 0o170000 {
        case 0o100000: return .file
        case 0o040000: return .directory
        case 0o120000: return .symlink
        default: return .other
        }
    }

    /// libnfs returns -errno.
    private static func error(_ status: Int32, _ message: String) -> NFSBackendError {
        switch -status {
        case ENOENT: return .notFound
        case EACCES, EPERM: return .accessDenied
        case ENOTDIR: return .notDirectory
        case EISDIR: return .isDirectory
        case ECONNRESET, ECONNREFUSED, ECONNABORTED, EPIPE, ETIMEDOUT, ENOTCONN, ENETUNREACH, EHOSTUNREACH,
             ENETDOWN, ESTALE, EIO, EAGAIN, EFAULT:
            return .connection(message.isEmpty ? "connection lost (\(-status))" : message)
        default:
            return .failed(message.isEmpty ? "NFS error \(-status)" : message)
        }
    }

    private static func mountError(_ status: Int32, _ message: String) -> NFSBackendError {
        // libnfs maps MNT3ERR_ACCES to -EACCES and MNT3ERR_NOENT to -ENOENT; anything else is a connection problem.
        switch -status {
        case EACCES, EPERM: return .accessDenied
        case ENOENT: return .notFound
        default: return .connection(message.isEmpty ? "mount failed (\(-status))" : message)
        }
    }
}
#endif
