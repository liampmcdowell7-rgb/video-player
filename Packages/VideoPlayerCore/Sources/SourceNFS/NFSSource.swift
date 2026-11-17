import Foundation
import VideoPlayerCore

/// Path helpers: source paths are "/a/b" with decoded names. Nothing may climb out of the export.
public enum NFSPath {
    /// Collapses repeated slashes and "." parts, strips a trailing slash. Throws `.forbidden` for "..".
    public static func normalize(_ path: String) throws -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { throw SourceError.forbidden }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    public static func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }
}

/// Reads files from an NFSv3 export (a NAS, a Linux box, a Mac sharing a folder).
///
/// What it does: lists folders, reports sizes and modified times, reads byte ranges. What it does not:
/// NFSv4 (the library is used in v3 mode only), Kerberos (AUTH_SYS only, so only trusted home networks),
/// encryption (NFSv3 has none, `capabilities.alwaysEncrypted` is false), locking, writing.
/// Export access is decided by the server by address, so there is no login: `authenticate()` mounts
/// the export and throws `.forbidden` when the server refuses this device.
public struct NFSSource: MediaSource {
    public let configuration: NFSConfiguration
    private let session: Session

    public var kind: SourceKind { .nfs }

    public var capabilities: SourceCapabilities {
        SourceCapabilities(
            authMethods: [.none],
            byteRanges: true,
            changeSignals: [.modified, .size],
            discovery: false,
            directPlaybackURL: false,
            alwaysEncrypted: false
        )
    }

    public init(configuration: NFSConfiguration, backend: NFSBackend) {
        self.configuration = configuration
        self.session = Session(configuration: configuration, backend: backend)
    }

    // MARK: MediaSource

    public func authenticate() async throws {
        do { try await session.remount() } catch { throw Self.map(error) }
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        let folder = try NFSPath.normalize(path)
        let raw = try await session.run { try await $0.readDirectory(folder) }
        var result: [SourceEntry] = []
        for item in raw {
            if item.name == "." || item.name == ".." || item.name.isEmpty || item.name.contains("/") { continue }
            let childPath = NFSPath.join(folder, item.name)
            var kind = item.kind
            var size = item.size
            var modified = item.modified
            if kind == .symlink {
                // Follow the link; a link that leads nowhere is not shown.
                guard let target = try? await session.run({ try await $0.status(childPath) }) else { continue }
                kind = target.kind
                size = target.size
                modified = target.modified ?? modified
            }
            guard kind == .file || kind == .directory else { continue }
            result.append(SourceEntry(
                path: childPath,
                name: item.name,
                isDirectory: kind == .directory,
                size: kind == .file ? Int64(clamping: size) : nil,
                modified: modified
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let normalized = try NFSPath.normalize(path)
        let status = try await session.run { try await $0.status(normalized) }
        let name = normalized == "/" ? "/" : String(normalized.split(separator: "/").last ?? "/")
        let isDirectory = status.kind == .directory
        guard isDirectory || status.kind == .file else { throw SourceError.notFound }
        return SourceEntry(
            path: normalized,
            name: name,
            isDirectory: isDirectory,
            size: isDirectory ? nil : Int64(clamping: status.size),
            modified: status.modified
        )
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        let normalized = try NFSPath.normalize(path)
        guard range.length > 0 else { return Data() }
        let chunk = configuration.maxReadChunk
        var collected = Data()
        var offset = UInt64(range.offset)
        var remaining = range.length
        while remaining > 0 {
            let ask = Int(min(Int64(chunk), remaining))
            let at = offset
            let piece = try await session.run { try await $0.read(normalized, offset: at, count: ask) }
            if piece.isEmpty { break }   // end of file
            // A backend must never hand back more than asked; guard so a bad one cannot corrupt the offsets.
            let used = piece.count > ask ? piece.prefix(ask) : piece
            collected.append(used)
            offset += UInt64(used.count)
            remaining -= Int64(used.count)
        }
        return collected
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        _ = try NFSPath.normalize(path)
        return .byteReader
    }

    // MARK: Errors

    static func map(_ error: Error) -> Error {
        if let source = error as? SourceError { return source }
        guard let backend = error as? NFSBackendError else { return SourceError.transport(String(describing: error)) }
        switch backend {
        case .connection(let message): return SourceError.transport(message)
        case .notFound: return SourceError.notFound
        case .accessDenied: return SourceError.forbidden
        case .notDirectory: return SourceError.notFound
        case .isDirectory: return SourceError.unsupported("This path is a folder, not a file")
        case .failed(let message): return SourceError.transport(message)
        }
    }

    // MARK: Connection state

    /// Serialises mounting and retries one dropped connection per call.
    private actor Session {
        let configuration: NFSConfiguration
        let backend: NFSBackend
        private var mounted = false

        init(configuration: NFSConfiguration, backend: NFSBackend) {
            self.configuration = configuration
            self.backend = backend
        }

        func remount() async throws {
            mounted = false
            try await backend.mount(configuration)
            mounted = true
        }

        private func ensureMounted() async throws {
            if !mounted { try await remount() }
        }

        func run<T: Sendable>(_ operation: @Sendable (NFSBackend) async throws -> T) async throws -> T {
            do {
                try await ensureMounted()
                return try await operation(backend)
            } catch NFSBackendError.connection {
                // One reconnect and one retry. A second failure is reported.
                do {
                    try await remount()
                    return try await operation(backend)
                } catch {
                    mounted = false
                    throw NFSSource.map(error)
                }
            } catch {
                throw NFSSource.map(error)
            }
        }
    }
}
