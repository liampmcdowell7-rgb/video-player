import Foundation

/// The one contract every source type implements. Foundation-only, so every implementation
/// and its tests can run on Linux. Credentials are given to the implementation when it is
/// created (the app reads them from the Keychain); implementations never store them.
public protocol MediaSource: Sendable {
    var kind: SourceKind { get }
    var capabilities: SourceCapabilities { get }

    /// Connects and checks the credentials. Throws `.unauthorized` / `.unsupportedAuthentication`.
    /// Safe to call again after a dropped connection (reconnect).
    func authenticate() async throws

    /// Direct children of a folder. The folder itself is not included.
    func list(_ path: String) async throws -> [SourceEntry]

    /// The entry for one path (file or folder).
    func info(_ path: String) async throws -> SourceEntry

    /// Reads `range` of a file. Returns fewer bytes only at the end of the file.
    func read(_ path: String, range: ByteRange) async throws -> Data

    /// How to hand a file to the player.
    func playbackAccess(for path: String) async throws -> PlaybackAccess
}

/// A server found on the local network.
public struct DiscoveredSource: Equatable, Hashable, Sendable {
    public var kind: SourceKind
    public var name: String
    public var host: String
    public var port: Int?
    /// A complete address when host and port are not enough (a UPnP device description URL, an https web folder).
    public var address: String?

    public init(kind: SourceKind, name: String, host: String, port: Int? = nil, address: String? = nil) {
        self.kind = kind
        self.name = name
        self.host = host
        self.port = port
        self.address = address
    }
}

/// Finds servers without a typed address (Bonjour, SSDP...). Platform code implements this in
/// the app; a source package only defines what to look for.
public protocol SourceDiscovery: Sendable {
    var kind: SourceKind { get }
    func discover() -> AsyncStream<DiscoveredSource>
}

public extension MediaSource {
    /// True / false when the source can tell, nil when it cannot (no signal in common).
    func hasChanged(_ old: FileVersion, comparedTo entry: SourceEntry) -> Bool? {
        entry.version.isSame(as: old).map { !$0 }
    }

    /// Folders first is the caller's job; this only reads a whole folder tree level by level.
    func walk(_ path: String = "/", maxDepth: Int = 8) async throws -> [SourceEntry] {
        var result: [SourceEntry] = []
        var pending: [(String, Int)] = [(path, 0)]
        while let (folder, depth) = pending.popLast() {
            for entry in try await list(folder) {
                result.append(entry)
                if entry.isDirectory, depth < maxDepth { pending.append((entry.path, depth + 1)) }
            }
        }
        return result
    }
}
