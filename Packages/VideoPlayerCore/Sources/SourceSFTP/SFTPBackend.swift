import Foundation
import VideoPlayerCore

// The SFTP protocol client is behind this seam so the SSH library can be swapped
// (Citadel or libssh2, see docs/SOURCES.md) without touching SFTPSource or its tests.

public enum SFTPCredential: Equatable, Sendable {
    case password(username: String, password: String)
    /// OpenSSH or PEM private key text. The app reads it from the Keychain.
    case privateKey(username: String, pem: String, passphrase: String?)

    public var username: String {
        switch self {
        case .password(let u, _), .privateKey(let u, _, _): return u
        }
    }
}

/// Where the server's host key is checked. Never silently accepts an unknown key.
public protocol SFTPKnownHosts: Sendable {
    func fingerprint(forHost host: String, port: Int) async -> String?
    func remember(fingerprint: String, forHost host: String, port: Int) async
}

public enum SFTPHostKeyPolicy: Sendable {
    /// Must equal this SHA-256 fingerprint ("SHA256:..." as ssh-keygen prints it).
    case pinned(String)
    /// Remember the key on first connect and refuse a different one later.
    case trustOnFirstUse(any SFTPKnownHosts)
    /// For tests against a throwaway local server only. Never offered in the app.
    case acceptAnyForTesting
}

public struct SFTPAttributes: Equatable, Sendable {
    public var size: Int64?
    public var modified: Date?
    public var isDirectory: Bool
    public var isSymlink: Bool

    public init(size: Int64? = nil, modified: Date? = nil, isDirectory: Bool = false, isSymlink: Bool = false) {
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
    }
}

public struct SFTPDirectoryEntry: Equatable, Sendable {
    public var name: String
    public var attributes: SFTPAttributes
    public init(name: String, attributes: SFTPAttributes) {
        self.name = name
        self.attributes = attributes
    }
}

/// Failures a backend reports. `SFTPSource` maps them to `SourceError`.
public enum SFTPBackendError: Error, Equatable, Sendable {
    case authenticationFailed
    case hostKeyRejected(fingerprint: String)
    case noSuchFile
    case permissionDenied
    /// The connection dropped or timed out; reconnecting may help.
    case connectionLost(String)
    case other(String)
}

public protocol SFTPBackend: Sendable {
    /// Connects, checks the host key through `acceptHostKey` (called with the SHA-256 fingerprint)
    /// and authenticates.
    func connect(
        host: String,
        port: Int,
        credential: SFTPCredential,
        acceptHostKey: @escaping @Sendable (String) async -> Bool
    ) async throws

    func listDirectory(_ path: String) async throws -> [SFTPDirectoryEntry]
    func attributes(of path: String) async throws -> SFTPAttributes
    /// Returns fewer bytes than `length` only at the end of the file, and an empty Data past it.
    func read(_ path: String, offset: UInt64, length: UInt32) async throws -> Data
    func disconnect() async
}
