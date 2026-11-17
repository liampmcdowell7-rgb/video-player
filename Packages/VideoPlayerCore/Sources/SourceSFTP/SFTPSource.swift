import Foundation
import VideoPlayerCore

/// SFTP source (SSH File Transfer Protocol, over SSH). Paths are the server's own paths,
/// optionally under `rootPath`. Always encrypted. Playback uses `.byteReader` (no URL exists).
public actor SFTPSource: MediaSource {
    public nonisolated let kind: SourceKind = .sftp
    public nonisolated let capabilities = SourceCapabilities(
        authMethods: [.usernamePassword, .publicKey],
        byteRanges: true,
        changeSignals: [.modified, .size],
        discovery: false,
        directPlaybackURL: false,
        alwaysEncrypted: true
    )

    private let host: String
    private let port: Int
    private let credential: SFTPCredential
    private let hostKeyPolicy: SFTPHostKeyPolicy
    private let rootPath: String
    private let backend: any SFTPBackend
    /// Largest single SFTP read request. 32 KiB is what every server must accept.
    private let maxChunk: UInt32
    private var connected = false

    public init(
        host: String,
        port: Int = 22,
        credential: SFTPCredential,
        hostKeyPolicy: SFTPHostKeyPolicy,
        rootPath: String = "/",
        backend: any SFTPBackend,
        maxChunk: UInt32 = 32 * 1024
    ) {
        self.host = host
        self.port = port
        self.credential = credential
        self.hostKeyPolicy = hostKeyPolicy
        self.rootPath = SFTPSource.normalize(rootPath)
        self.backend = backend
        self.maxChunk = max(1, maxChunk)
    }

    // MARK: MediaSource

    public func authenticate() async throws {
        connected = false
        await backend.disconnect()
        let policy = hostKeyPolicy, host = host, port = port
        do {
            try await backend.connect(host: host, port: port, credential: credential) { fingerprint in
                await SFTPSource.accept(fingerprint, policy: policy, host: host, port: port)
            }
            connected = true
        } catch {
            throw SFTPSource.map(error)
        }
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        let folder = SFTPSource.normalize(path)
        let remote = serverPath(folder)
        let entries = try await withReconnect { try await $0.listDirectory(remote) }
        return entries
            .filter { $0.name != "." && $0.name != ".." }
            .map { entry in
                SourceEntry(
                    path: SFTPSource.join(folder, entry.name),
                    name: entry.name,
                    isDirectory: entry.attributes.isDirectory,
                    size: entry.attributes.isDirectory ? nil : entry.attributes.size,
                    modified: entry.attributes.modified
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func info(_ path: String) async throws -> SourceEntry {
        let clean = SFTPSource.normalize(path)
        let remote = serverPath(clean)
        let attrs = try await withReconnect { try await $0.attributes(of: remote) }
        let name = clean == "/" ? "/" : String(clean.split(separator: "/").last ?? "")
        return SourceEntry(
            path: clean,
            name: name,
            isDirectory: attrs.isDirectory,
            size: attrs.isDirectory ? nil : attrs.size,
            modified: attrs.modified
        )
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        if range.length == 0 { return Data() }
        let serverPath = self.serverPath(SFTPSource.normalize(path))
        var result = Data()
        var offset = UInt64(range.offset)
        var remaining = range.length
        while remaining > 0 {
            let ask = UInt32(min(Int64(maxChunk), remaining))
            let at = offset
            let chunk = try await withReconnect { try await $0.read(serverPath, offset: at, length: ask) }
            if chunk.isEmpty { break }              // end of file
            result.append(chunk)
            offset += UInt64(chunk.count)
            remaining -= Int64(chunk.count)
            if chunk.count < Int(ask) { break }     // short read is the end of the file
        }
        return result
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }

    // MARK: Helpers

    private func serverPath(_ path: String) -> String {
        rootPath == "/" ? path : (path == "/" ? rootPath : rootPath + path)
    }

    /// Runs `operation`; if the connection was lost, reconnects once and retries.
    private func withReconnect<T: Sendable>(_ operation: @Sendable (any SFTPBackend) async throws -> T) async throws -> T {
        if !connected { try await authenticate() }
        do {
            return try await operation(backend)
        } catch let error as SFTPBackendError {
            guard case .connectionLost = error else { throw SFTPSource.map(error) }
            try await authenticate()
            do { return try await operation(backend) } catch { throw SFTPSource.map(error) }
        } catch {
            throw SFTPSource.map(error)
        }
    }

    static func map(_ error: Error) -> Error {
        guard let e = error as? SFTPBackendError else { return error }
        switch e {
        case .authenticationFailed: return SourceError.unauthorized
        case .hostKeyRejected(let fp): return SourceError.transport("The server's host key changed or is not trusted (\(fp)).")
        case .noSuchFile: return SourceError.notFound
        case .permissionDenied: return SourceError.forbidden
        case .connectionLost(let message): return SourceError.transport(message)
        case .other(let message): return SourceError.transport(message)
        }
    }

    static func accept(_ fingerprint: String, policy: SFTPHostKeyPolicy, host: String, port: Int) async -> Bool {
        switch policy {
        case .acceptAnyForTesting:
            return true
        case .pinned(let expected):
            return expected == fingerprint
        case .trustOnFirstUse(let store):
            if let known = await store.fingerprint(forHost: host, port: port) { return known == fingerprint }
            await store.remember(fingerprint: fingerprint, forHost: host, port: port)
            return true
        }
    }

    /// "/a//b/" -> "/a/b"; "" -> "/". Resolves "." and "..", never above the root.
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast(); continue }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder == "/" ? "/" + name : folder + "/" + name
    }
}
