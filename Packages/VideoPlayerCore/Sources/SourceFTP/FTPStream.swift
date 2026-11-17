import Foundation

/// A byte stream to an FTP server. The protocol logic only sees this seam, so it runs the same
/// on Linux (POSIX sockets, tests) and on Apple platforms (Network.framework).
public protocol FTPStream: AnyObject, Sendable {
    func send(_ data: Data) async throws
    /// Up to `maxLength` bytes. An empty result means the peer closed the connection.
    func receive(maxLength: Int) async throws -> Data
    /// Upgrades the connection to TLS in place (explicit FTPS, after `AUTH TLS`).
    /// Only valid on a stream opened with `allowUpgrade: true`.
    func startTLS(serverName: String) async throws
    func close() async
}

public protocol FTPConnector: Sendable {
    /// Opens a TCP connection.
    /// - tls: handshake immediately (implicit FTPS control channel, or a protected data channel).
    /// - allowUpgrade: the caller will call `startTLS` later (explicit FTPS control channel).
    func connect(host: String, port: Int, tls: Bool, allowUpgrade: Bool) async throws -> FTPStream
}

public enum FTPStreamError: Error, Equatable, Sendable {
    case tlsUnavailable(String)
    case timedOut
    case closed
    case failed(String)
}

public enum FTPSecurity: Sendable, Equatable {
    case none
    /// Plain connect, then `AUTH TLS`.
    case explicitTLS
    /// TLS from the first byte (port 990 by convention).
    case implicitTLS
}

public struct FTPCredentials: Sendable, Equatable {
    public var username: String
    public var password: String
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
    /// The conventional anonymous FTP password (an email-like placeholder, not a secret).
    private static let anonymousPassword = "anonymous@"
    /// What anonymous FTP sends.
    public static let anonymous = FTPCredentials(username: "anonymous", password: anonymousPassword)
}

/// Used where no transport exists for the platform.
public struct UnavailableFTPConnector: FTPConnector {
    public init() {}
    public func connect(host: String, port: Int, tls: Bool, allowUpgrade: Bool) async throws -> FTPStream {
        throw FTPStreamError.failed("No FTP transport is available on this platform")
    }
}

/// Network.framework on Apple platforms, POSIX sockets elsewhere.
public func makeDefaultFTPConnector() -> FTPConnector {
    #if canImport(Network)
    return NetworkFTPConnector()
    #elseif canImport(Glibc) || canImport(Musl)
    return POSIXFTPConnector()
    #else
    return UnavailableFTPConnector()
    #endif
}
