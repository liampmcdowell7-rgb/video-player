import Foundation

/// Where to connect. `username == nil` means guest. The app reads the password from the Keychain
/// and hands it over here; nothing in this package stores it.
public struct SMBConfiguration: Sendable, Equatable {
    public var host: String
    public var port: Int?
    public var domain: String
    public var username: String?
    public var password: String?
    /// Ask for SMB3 encryption (fails if the server cannot do it).
    public var encrypted: Bool
    /// Optional share used to check the credentials in `authenticate()`. Without it the check lists the
    /// shares, which some servers forbid to ordinary users.
    public var defaultShare: String?
    public var timeout: TimeInterval

    public init(
        host: String,
        port: Int? = nil,
        domain: String = "",
        username: String? = nil,
        password: String? = nil,
        encrypted: Bool = false,
        defaultShare: String? = nil,
        timeout: TimeInterval = 30
    ) {
        self.host = host
        self.port = port
        self.domain = domain
        self.username = username
        self.password = password
        self.encrypted = encrypted
        self.defaultShare = defaultShare
        self.timeout = timeout
    }
}

/// One file or folder as the SMB library reports it.
public struct SMBItem: Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modified: Date?

    public init(name: String, isDirectory: Bool, size: Int64? = nil, modified: Date? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }
}

/// What the SMB library can fail with, in terms the source understands.
public enum SMBBackendError: Error, Equatable, Sendable {
    case authenticationFailed
    case accessDenied
    case notFound
    /// The connection dropped or timed out; a reconnect may fix it.
    case connectionLost(String)
    case other(String)
}

/// The small slice of an SMB client library the source needs. `AMSMB2Backend` is the real one; tests use a fake.
/// Paths are share-relative with a leading "/" ("/" is the top of the share).
public protocol SMBBackend: Sendable {
    /// Opens the connection and checks the credentials.
    func connect(share: String?) async throws
    func listShares() async throws -> [String]
    func listDirectory(share: String, path: String) async throws -> [SMBItem]
    func stat(share: String, path: String) async throws -> SMBItem
    /// Up to `length` bytes from `offset`. Fewer (or none) at and after the end of the file.
    func read(share: String, path: String, offset: Int64, length: Int64) async throws -> Data
    func disconnect() async
}

/// Splits a source path ("/Movies/Folder/file.mkv") into the share and the path inside it.
/// The first component is always the share; "/" lists the shares.
struct SMBLocation: Equatable {
    var share: String?
    /// Inside the share, always starts with "/".
    var path: String

    init?(_ sourcePath: String) {
        var parts: [String] = []
        for part in sourcePath.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { return nil }
            parts.append(String(part))
        }
        if parts.isEmpty { share = nil; path = "/"; return }
        share = parts[0]
        path = "/" + parts.dropFirst().joined(separator: "/")
    }

    var sourcePath: String {
        guard let share else { return "/" }
        return path == "/" ? "/" + share : "/" + share + path
    }

    func child(_ name: String) -> String {
        sourcePath == "/" ? "/" + name : sourcePath + "/" + name
    }
}
