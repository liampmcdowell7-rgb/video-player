import Foundation

/// What kind of object a directory entry or a stat call returned.
public enum NFSFileKind: Equatable, Sendable {
    case file, directory, symlink, other
}

public struct NFSDirectoryEntry: Equatable, Sendable {
    public var name: String
    public var kind: NFSFileKind
    public var size: UInt64
    public var modified: Date?

    public init(name: String, kind: NFSFileKind, size: UInt64, modified: Date? = nil) {
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
    }
}

public struct NFSFileStatus: Equatable, Sendable {
    public var kind: NFSFileKind
    public var size: UInt64
    public var modified: Date?

    public init(kind: NFSFileKind, size: UInt64, modified: Date? = nil) {
        self.kind = kind
        self.size = size
        self.modified = modified
    }
}

/// Failures a backend reports. `NFSSource` turns these into `SourceError`.
public enum NFSBackendError: Error, Equatable, Sendable {
    /// The connection is gone or never worked (timeout, reset, refused, stale handle). The source
    /// reconnects once and retries when it sees this.
    case connection(String)
    case notFound
    case accessDenied
    case notDirectory
    case isDirectory
    case failed(String)
}

/// How to reach one NFS export.
public struct NFSConfiguration: Equatable, Sendable {
    public var host: String
    /// Folder exported by the server, for example "/volume1/video". "/" for servers that export a root.
    public var exportPath: String
    /// Fixed NFS / mount port. Nil asks the server's portmapper (port 111), which is what real servers expect.
    public var port: Int?
    /// AUTH_SYS user and group sent with every request. Nil keeps the library default.
    public var uid: Int?
    public var gid: Int?
    public var timeoutMilliseconds: Int
    /// Largest piece asked for in one call, bytes.
    public var maxReadChunk: Int

    public init(
        host: String,
        exportPath: String = "/",
        port: Int? = nil,
        uid: Int? = nil,
        gid: Int? = nil,
        timeoutMilliseconds: Int = 10_000,
        maxReadChunk: Int = 4 * 1024 * 1024
    ) {
        self.host = host
        self.exportPath = exportPath.isEmpty ? "/" : exportPath
        self.port = port
        self.uid = uid
        self.gid = gid
        self.timeoutMilliseconds = timeoutMilliseconds
        self.maxReadChunk = max(4096, maxReadChunk)
    }
}

/// The thin layer over a native NFS library. Everything above it (paths, errors, short reads,
/// reconnect) is plain Swift and tested with a fake. NFSv3 only; AUTH_SYS only.
///
/// Paths passed in are normalised by `NFSSource`: they start with "/" and contain no ".." or empty parts.
/// `read` may return fewer bytes than asked (the source loops) and returns empty data at or past the end.
public protocol NFSBackend: Sendable {
    /// Connects and mounts the export. Calling it again drops any old connection first.
    func mount(_ configuration: NFSConfiguration) async throws
    func unmount() async
    func readDirectory(_ path: String) async throws -> [NFSDirectoryEntry]
    func status(_ path: String) async throws -> NFSFileStatus
    func read(_ path: String, offset: UInt64, count: Int) async throws -> Data
}
