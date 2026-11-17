#if canImport(Network)
import Foundation
import VideoPlayerCore
#if canImport(CryptoKit)
import CryptoKit
#endif
import Network
#if canImport(Security)
import Security
#endif

// Apple-platform transport. This file cannot be compiled or run on Linux: it is checked only
// when the package is built on a Mac (Codemagic) and exercised on a device or simulator.

/// Calls a continuation exactly once even when several callbacks race.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { body() }
    }
}

/// Network.framework for plain and implicit-TLS connections (control and data), and
/// URLSessionStreamTask for an explicit-TLS control channel, because NWConnection cannot start
/// TLS on a connection that is already open.
public struct NetworkFTPConnector: FTPConnector {
    public var timeout: TimeInterval
    /// For servers with a self-signed certificate that the user chose to trust. Off by default.
    public var trustAnyCertificate: Bool
    /// When set, a certificate the system does not trust is accepted only if this pin accepts its SHA-256 fingerprint (the user approved it).
    /// A refusal is remembered in the pin. Takes precedence over `trustAnyCertificate`.
    public var pin: CertificatePin?

    public init(timeout: TimeInterval = 15, trustAnyCertificate: Bool = false, pin: CertificatePin? = nil) {
        self.pin = pin
        self.timeout = timeout
        self.trustAnyCertificate = trustAnyCertificate
    }

    public func connect(host: String, port: Int, tls: Bool, allowUpgrade: Bool) async throws -> FTPStream {
        if allowUpgrade && !tls {
            return URLSessionFTPStream(host: host, port: port, timeout: timeout, trustAny: trustAnyCertificate, pin: pin)
        }
        return try await NetworkFTPStream.open(host: host, port: port, tls: tls, timeout: timeout, trustAny: trustAnyCertificate, pin: pin)
    }
}


/// The one place an FTPS certificate is judged. A certificate the system trusts is accepted; otherwise the pin decides
/// (only the fingerprint the user approved is accepted; anything else is refused and remembered in the pin).
enum FTPTrustEvaluation {
    static func accepts(_ trust: SecTrust, pin: CertificatePin) -> Bool {
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return true }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else { return false }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        return pin.accepts(presented: digest.map { String(format: "%02x", $0) }.joined())
    }
}

final class NetworkFTPStream: FTPStream, @unchecked Sendable {
    private let connection: NWConnection
    private let timeout: TimeInterval

    private init(connection: NWConnection, timeout: TimeInterval) {
        self.connection = connection
        self.timeout = timeout
    }

    static func open(host: String, port: Int, tls: Bool, timeout: TimeInterval, trustAny: Bool, pin: CertificatePin?) async throws -> NetworkFTPStream {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { throw FTPStreamError.failed("Bad port \(port)") }
        let queue = DispatchQueue(label: "ftp.network")
        let parameters: NWParameters
        if tls {
            let options = NWProtocolTLS.Options()
            if let pin {
                sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, secTrust, complete in
                    complete(FTPTrustEvaluation.accepts(sec_trust_copy_ref(secTrust).takeRetainedValue(), pin: pin))
                }, queue)
            } else if trustAny {
                sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in complete(true) }, queue)
            }
            parameters = NWParameters(tls: options, tcp: NWProtocolTCP.Options())
        } else {
            parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let stream = NetworkFTPStream(connection: connection, timeout: timeout)
        let once = ResumeOnce()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { cont.resume() }
                case .failed(let error):
                    once.run { cont.resume(throwing: FTPStreamError.failed("\(error)")) }
                case .waiting(let error):
                    connection.cancel()
                    once.run { cont.resume(throwing: FTPStreamError.failed("\(error)")) }
                case .cancelled:
                    once.run { cont.resume(throwing: FTPStreamError.closed) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            // Fixed 2026-11-17 (Network/Security check): the cancel now runs only when the connection has NOT become ready yet.
            // Before, it ran unconditionally, so every FTP connection was cancelled `timeout` seconds after it opened, mid-transfer.
            queue.asyncAfter(deadline: .now() + timeout) {
                once.run {
                    connection.cancel()
                    cont.resume(throwing: FTPStreamError.timedOut)
                }
            }
        }
        connection.stateUpdateHandler = nil
        return stream
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: FTPStreamError.failed("\(error)")) } else { cont.resume() }
            })
        }
    }

    func receive(maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max(1, maxLength)) { data, _, isComplete, error in
                if let error { cont.resume(throwing: FTPStreamError.failed("\(error)")); return }
                if let data, !data.isEmpty { cont.resume(returning: data); return }
                cont.resume(returning: Data())   // peer closed (isComplete) or nothing more
            }
        }
    }

    func startTLS(serverName: String) async throws {
        throw FTPStreamError.tlsUnavailable("NWConnection cannot upgrade to TLS in place; open the stream with allowUpgrade")
    }

    func close() async { connection.cancel() }
}

/// Control channel for explicit FTPS: URLSessionStreamTask supports `startSecureConnection()`.
final class URLSessionFTPStream: NSObject, FTPStream, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var task: URLSessionStreamTask!
    private let timeout: TimeInterval
    private let trustAny: Bool
    private let pin: CertificatePin?

    init(host: String, port: Int, timeout: TimeInterval, trustAny: Bool, pin: CertificatePin?) {
        self.pin = pin
        self.timeout = timeout
        self.trustAny = trustAny
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        task = session.streamTask(withHostName: host, port: port)
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let pin, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            // The system trusts it, or the user approved exactly this fingerprint; anything else is refused and remembered.
            if FTPTrustEvaluation.accepts(trust, pin: pin) { completionHandler(.useCredential, URLCredential(trust: trust)) }
            else { completionHandler(.cancelAuthenticationChallenge, nil) }
        } else if trustAny, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.write(data, timeout: timeout) { error in
                if let error { cont.resume(throwing: FTPStreamError.failed("\(error)")) } else { cont.resume() }
            }
        }
    }

    func receive(maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            task.readData(ofMinLength: 1, maxLength: max(1, maxLength), timeout: timeout) { data, atEOF, error in
                if let error { cont.resume(throwing: FTPStreamError.failed("\(error)")); return }
                cont.resume(returning: data ?? Data())
            }
        }
    }

    func startTLS(serverName: String) async throws {
        task.startSecureConnection()
    }

    func close() async {
        task.closeRead()
        task.closeWrite()
        session.invalidateAndCancel()
    }
}
#endif
