import Foundation
import CryptoKit
import Security
import VideoPlayerCore

/// An HTTP transport for servers that may present a certificate the system does not trust (a home server with its own
/// certificate). A certificate the system trusts is used as usual. Otherwise the `CertificatePin` decides: only the SHA-256
/// fingerprint the user approved is accepted, anything else is refused and remembered in the pin, so the app can show
/// "the server’s certificate changed" instead of a vague network error. With no pin the system's decision stands.
final class PinnedTransport: NSObject, HTTPTransport, URLSessionDelegate, @unchecked Sendable {
    private let pin: CertificatePin?
    private var session: URLSession?

    init(pin: CertificatePin?) {
        self.pin = pin
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    deinit { session?.invalidateAndCancel() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let session else { throw SourceError.malformedResponse }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            // A refused certificate shows up here as a cancelled request; the pin holds the real reason (TrustGuardedSource reads it).
            throw SourceError.transport((error as NSError).localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SourceError.malformedResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String { headers[k] = v }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust, let pin else {
            return (.performDefaultHandling, nil)
        }
        var evaluationError: CFError?
        if SecTrustEvaluateWithError(trust, &evaluationError) { return (.performDefaultHandling, nil) }
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        if pin.accepts(presented: hex) { return (.useCredential, URLCredential(trust: trust)) }
        return (.cancelAuthenticationChallenge, nil)
    }
}
