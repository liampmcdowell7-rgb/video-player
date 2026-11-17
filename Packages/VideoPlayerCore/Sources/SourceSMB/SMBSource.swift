import Foundation
import VideoPlayerCore

/// SMB2/3 source. The first path component is the share: "/" lists the shares, "/Movies/a.mkv" is
/// the file "/a.mkv" on the share "Movies". Playback goes through `read(range:)` (`.byteReader`),
/// because the system player cannot open smb:// addresses.
public actor SMBClient: MediaSource {
    public nonisolated let kind: SourceKind = .smb
    public nonisolated let capabilities = SourceCapabilities(
        authMethods: [.none, .usernamePassword],
        byteRanges: true,
        changeSignals: [.modified, .size],
        discovery: false,
        directPlaybackURL: false,
        alwaysEncrypted: false
    )

    private let configuration: SMBConfiguration
    private let backend: any SMBBackend
    /// Bumped on every reconnect so two failed calls at the same moment reconnect only once.
    private var generation = 0
    private var connected = false
    private var connectTask: Task<Void, Error>?

    public init(configuration: SMBConfiguration, backend: any SMBBackend) {
        self.configuration = configuration
        self.backend = backend
    }

    // MARK: MediaSource

    public func authenticate() async throws {
        do {
            try await backend.connect(share: configuration.defaultShare)
            if configuration.defaultShare == nil {
                _ = try await backend.listShares()
            }
            connected = true
            generation += 1
        } catch {
            connected = false
            throw Self.sourceError(error, whileConnecting: true)
        }
    }

    public func list(_ path: String) async throws -> [SourceEntry] {
        guard let location = SMBLocation(path) else { throw SourceError.notFound }
        guard let share = location.share else {
            return try await perform { backend in
                // Administrative shares (IPC$, ADMIN$, C$) end with "$" and hold no media.
                try await backend.listShares().filter { !$0.hasSuffix("$") }.map {
                    SourceEntry(path: location.child($0), name: $0, isDirectory: true)
                }
            }
        }
        let items = try await perform { backend in
            try await backend.listDirectory(share: share, path: location.path)
        }
        return items.filter { $0.name != "." && $0.name != ".." && !$0.name.isEmpty }.map {
            SourceEntry(
                path: location.child($0.name), name: $0.name, isDirectory: $0.isDirectory,
                size: $0.isDirectory ? nil : $0.size, modified: $0.modified
            )
        }
    }

    public func info(_ path: String) async throws -> SourceEntry {
        guard let location = SMBLocation(path) else { throw SourceError.notFound }
        guard let share = location.share else {
            return SourceEntry(path: "/", name: "/", isDirectory: true)
        }
        if location.path == "/" {
            // A share itself: check that it can be opened.
            _ = try await perform { backend in try await backend.listDirectory(share: share, path: "/") }
            return SourceEntry(path: location.sourcePath, name: share, isDirectory: true)
        }
        let item = try await stat(share: share, path: location.path)
        return SourceEntry(
            path: location.sourcePath, name: item.name.isEmpty ? Self.lastComponent(location.path) : item.name,
            isDirectory: item.isDirectory, size: item.isDirectory ? nil : item.size, modified: item.modified
        )
    }

    public func read(_ path: String, range: ByteRange) async throws -> Data {
        guard let location = SMBLocation(path), let share = location.share, location.path != "/" else {
            throw SourceError.notFound
        }
        if range.length == 0 { return Data() }
        let data = try await perform { backend in
            try await backend.read(share: share, path: location.path, offset: range.offset, length: range.length)
        }
        if data.isEmpty {
            // Nothing came back: either the offset is at or past the end, or the file is gone.
            let item = try await stat(share: share, path: location.path)
            if item.isDirectory { throw SourceError.unsupported("This is a folder, not a file.") }
            if range.offset >= (item.size ?? 0) { throw SourceError.rangeNotSatisfiable }
            throw SourceError.malformedResponse
        }
        return data.count > Int(range.length) ? data.prefix(Int(range.length)) : data
    }

    public func playbackAccess(for path: String) async throws -> PlaybackAccess {
        let entry = try await info(path)
        if entry.isDirectory { throw SourceError.unsupported("This is a folder, not a file.") }
        return .byteReader
    }

    /// Closes the connection. A later call connects again.
    public func disconnect() async {
        connected = false
        await backend.disconnect()
    }

    /// `stat` with one extra check: some servers (impacket's test server among them) answer "access denied"
    /// for a file that does not exist. When that happens, look in the parent folder before reporting it.
    private func stat(share: String, path: String) async throws -> SMBItem {
        do {
            return try await perform { backend in try await backend.stat(share: share, path: path) }
        } catch let error as SourceError where error == .forbidden {
            let parts = path.split(separator: "/").map(String.init)
            guard let name = parts.last else { throw error }
            let parent = "/" + parts.dropLast().joined(separator: "/")
            if let siblings = try? await perform({ backend in try await backend.listDirectory(share: share, path: parent) }),
               !siblings.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                throw SourceError.notFound
            }
            throw error
        }
    }

    // MARK: Reconnect and error mapping

    /// Runs one backend call. If the connection dropped, reconnects once and runs it again.
    private func perform<T: Sendable>(_ operation: @Sendable (any SMBBackend) async throws -> T) async throws -> T {
        do { try await ensureConnected() } catch { throw Self.sourceError(error, whileConnecting: true) }
        let startedAt = generation
        do {
            return try await operation(backend)
        } catch let error as SMBBackendError {
            guard case .connectionLost = error else { throw Self.sourceError(error, whileConnecting: false) }
            try await reconnect(ifStillAt: startedAt)
            do {
                return try await operation(backend)
            } catch {
                throw Self.sourceError(error, whileConnecting: false)
            }
        } catch {
            throw Self.sourceError(error, whileConnecting: false)
        }
    }

    private func reconnect(ifStillAt startedAt: Int) async throws {
        guard generation == startedAt else { return }   // someone else already reconnected
        try await runConnection(dropFirst: true)
    }

    /// Connects when not connected. Calls that arrive while a connect or reconnect is running wait for it
    /// instead of starting their own.
    private func ensureConnected() async throws {
        if connected, connectTask == nil { return }
        try await runConnection(dropFirst: false)
    }

    private func runConnection(dropFirst: Bool) async throws {
        if let running = connectTask {
            try await running.value
            return
        }
        let task = Task { [self] in
            if dropFirst {
                await backend.disconnect()
                connected = false
            }
            try await authenticate()
        }
        connectTask = task
        defer { connectTask = nil }
        try await task.value
    }

    static func sourceError(_ error: Error, whileConnecting: Bool) -> SourceError {
        if let source = error as? SourceError { return source }
        if let backendError = error as? SMBBackendError {
            switch backendError {
            case .authenticationFailed: return .unauthorized
            case .accessDenied: return whileConnecting ? .unauthorized : .forbidden
            case .notFound: return .notFound
            case .connectionLost(let text): return .transport(text)
            case .other(let text): return .transport(text)
            }
        }
        return .transport(String(describing: error))
    }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
