import Foundation

/// Every kind of place the app can read the user's own files from.
/// One Swift package target per kind; none depends on another.
public enum SourceKind: String, Sendable, CaseIterable, Codable {
    case webdav, smb, nfs, sftp, ftp, upnp
    case googleDrive, oneDrive, dropbox, directLink
    case jellyfin, emby, plex
}

public enum AuthMethod: String, Sendable, CaseIterable, Codable {
    case none
    case basic, digest
    case usernamePassword      // SMB, FTP, SFTP, media servers
    case publicKey             // SFTP
    case token                 // pasted or generated API token
    case oauthDeviceCode       // cloud TV sign-in
    case pinLink               // Plex plex.tv/link
}

/// What a source can use to tell that a file changed.
public enum ChangeSignal: String, Sendable, CaseIterable, Codable {
    case etag, modified, size, serverToken
}

public struct SourceCapabilities: Equatable, Sendable {
    public var authMethods: Set<AuthMethod>
    /// Can read an arbitrary byte range (needed for seeking).
    public var byteRanges: Bool
    public var changeSignals: Set<ChangeSignal>
    /// Can find servers on the local network without a typed address.
    public var discovery: Bool
    /// Playback can be handed to a plain URL (possibly with headers); otherwise the app must feed bytes.
    public var directPlaybackURL: Bool
    /// Traffic is encrypted in transit on every configuration the source supports.
    public var alwaysEncrypted: Bool

    public init(
        authMethods: Set<AuthMethod>,
        byteRanges: Bool,
        changeSignals: Set<ChangeSignal>,
        discovery: Bool = false,
        directPlaybackURL: Bool = false,
        alwaysEncrypted: Bool = false
    ) {
        self.authMethods = authMethods
        self.byteRanges = byteRanges
        self.changeSignals = changeSignals
        self.discovery = discovery
        self.directPlaybackURL = directPlaybackURL
        self.alwaysEncrypted = alwaysEncrypted
    }
}

/// A half-open byte range: `length` bytes starting at `offset`.
public struct ByteRange: Equatable, Sendable {
    public var offset: Int64
    public var length: Int64

    public init(offset: Int64, length: Int64) {
        self.offset = max(0, offset)
        self.length = max(0, length)
    }

    /// Last byte index, inclusive. Only meaningful when `length > 0`.
    public var last: Int64 { offset + length - 1 }

    /// HTTP `Range` header value.
    public var httpHeaderValue: String { "bytes=\(offset)-\(last)" }
}

/// Everything a source can offer for deciding "did this file change?".
public struct FileVersion: Equatable, Hashable, Sendable {
    public var etag: String?
    public var modified: Date?
    public var size: Int64?
    /// A server-side change token (Drive/OneDrive/Dropbox revision, Plex/Jellyfin item version...).
    public var serverToken: String?

    public init(etag: String? = nil, modified: Date? = nil, size: Int64? = nil, serverToken: String? = nil) {
        self.etag = etag
        self.modified = modified
        self.size = size
        self.serverToken = serverToken
    }

    /// Compares using the strongest signal both sides have: server token, then ETag, then
    /// modified date plus size. Returns nil when nothing can be compared (treat as "unknown").
    public func isSame(as other: FileVersion) -> Bool? {
        if let a = serverToken, let b = other.serverToken { return a == b }
        if let a = etag, let b = other.etag { return a == b }
        if let a = modified, let b = other.modified {
            if a != b { return false }
            if let x = size, let y = other.size { return x == y }
            return true
        }
        if let x = size, let y = other.size, x != y { return false }
        return nil
    }
}

/// The item type a media server reports for a file.
public enum ServerItemType: String, Equatable, Hashable, Sendable {
    case movie, episode
}

public struct SourceEntry: Equatable, Hashable, Sendable {
    /// Path inside the source, decoded, always starting with "/" ("/" is the root).
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modified: Date?
    public var contentType: String?
    public var etag: String?
    public var serverToken: String?
    /// What a media server's own library says this file is (Jellyfin, Emby). nil for plain file sources and for
    /// anything the server does not call a movie or an episode. Only a hint: docs/SORTING.md says when the file name wins.
    public var serverItemType: ServerItemType?

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        modified: Date? = nil,
        contentType: String? = nil,
        etag: String? = nil,
        serverToken: String? = nil,
        serverItemType: ServerItemType? = nil
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.contentType = contentType
        self.etag = etag
        self.serverToken = serverToken
        self.serverItemType = serverItemType
    }

    public var version: FileVersion {
        FileVersion(etag: etag, modified: modified, size: size, serverToken: serverToken)
    }
}

/// How the player should open a file.
public enum PlaybackAccess: Equatable, Sendable {
    /// A URL the system player can open, with extra headers to send on every request.
    case url(URL, headers: [String: String])
    /// No usable URL: the app must pull bytes with `MediaSource.read` and feed the player.
    case byteReader
}

public enum SourceError: Error, Equatable, Sendable {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case httpStatus(Int)
    case malformedResponse
    case unsupportedAuthentication
    /// Only Basic authentication is offered over plain HTTP, and sending it was not allowed.
    case insecureBasicAuthentication
    case transport(String)
    /// The source does not do this (see `capabilities`).
    case unsupported(String)
    /// The server ignored a byte-range request and sent the whole file.
    case rangesNotSupported
    case rangeNotSatisfiable
}
