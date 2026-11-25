import XCTest
import Foundation
import VideoPlayerCore
@testable import SourcePlex

/// R471 (54), PROVISIONAL: what `PlexClient.read` throws for each answer of the server to a ranged read, the error the
/// converted path's loopback then keeps (`String(describing:)`, RemuxHost.start). Records today's behaviour only.
final class PlexReadErrorsR471Tests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    /// The fake server's library, but every Part read answered by `answer` (or thrown).
    final class PartAnswers: HTTPTransport, @unchecked Sendable {
        let library: FakePlexServer
        let answer: @Sendable (HTTPRequest) throws -> HTTPResponse
        init(_ library: FakePlexServer, answer: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) {
            self.library = library; self.answer = answer
        }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            if request.url.path.hasPrefix("/library/parts/") { return try answer(request) }
            return try await library.send(request)
        }
    }

    private func readError(_ answer: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) async throws -> Error? {
        let transport = PartAnswers(try FakePlexServer(), answer: answer)
        let plex = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: transport)
        let path = try await plex.list("/Movies")[0].path
        do { _ = try await plex.read(path, range: ByteRange(offset: 4096, length: 1024)); return nil } catch { return error }
    }

    func testEachAnswerToARangedReadAndTheTextTheLoopbackKeeps() async throws {
        let cases: [(status: Int, text: String)] = [
            (200, "rangesNotSupported"), (416, "rangeNotSatisfiable"), (401, "unauthorized"), (403, "forbidden"),
            (404, "notFound"), (500, "httpStatus(500)"), (503, "httpStatus(503)"),
        ]
        for (status, text) in cases {
            let error = try await readError { _ in HTTPResponse(statusCode: status, body: Data(count: 16)) }
            print("R471 (54) Plex read | HTTP \(status) | \(error.map { String(describing: $0) } ?? "no error")")
            XCTAssertEqual(error.map { String(describing: $0) }, text, "HTTP \(status)")
        }
    }

    /// A 206 with fewer bytes than asked for is returned as it is (no error); one with more is cut to the length asked for.
    func testA206ShorterThanAskedIsReturnedAsItIs() async throws {
        let transport = PartAnswers(try FakePlexServer()) { _ in HTTPResponse(statusCode: 206, body: Data(count: 100)) }
        let plex = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: transport)
        let path = try await plex.list("/Movies")[0].path
        let data = try await plex.read(path, range: ByteRange(offset: 0, length: 1024))
        XCTAssertEqual(data.count, 100, "no error, and no retry for the rest")
    }

    /// The request timeout (URLError .timedOut, 30 s with no byte) and a cancelled request (URLError .cancelled, what a
    /// cancelled URLSession task throws) both become transport(text), with no token. Neither is a CancellationError, so
    /// the loopback logs a cancelled read as a 500 like any other failure.
    func testATimeoutAndACancelledRequestBecomeTransportErrors() async throws {
        for code in [URLError.Code.timedOut, .cancelled, .networkConnectionLost] {
            let error = try await readError { _ in throw URLError(code) }
            let text = error.map { String(describing: $0) } ?? "no error"
            print("R471 (54) Plex read | URLError \(code.rawValue) | \(text)")
            guard case SourceError.transport(let inner)? = error as? SourceError else { return XCTFail(text) }
            XCTAssertEqual(text, "transport(\(String(reflecting: inner)))")
            XCTAssertTrue(inner.contains("\(code.rawValue)"), inner)
            XCTAssertFalse(text.contains("server-token-placeholder"))
            XCTAssertFalse(error is CancellationError)
        }
    }
}
