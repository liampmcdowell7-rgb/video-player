import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R471 (60), PROVISIONAL (owner 25 Nov 2026 round 6, Part B item 2): the Last Event row names the resource and the cause
/// even when the session's error is a plain cancellation. The loopback answers 500 for every error unless the player
/// closed the request; the serve log used to keep no status for any cancellation, so the row showed only "HTTP 500".
final class LastEventCancelledR471Tests: XCTestCase {
    /// Keeps the handler `RemuxHost.start` installs, so a test can call it as the loopback would.
    final class CapturingServer: LoopbackServer, @unchecked Sendable {
        private let lock = NSLock()
        private var _handler: LoopbackHandler?
        var handler: LoopbackHandler? { lock.withLock { _handler } }
        func start(handler: @escaping LoopbackHandler) throws -> URL {
            lock.withLock { _handler = handler }
            return URL(string: "http://127.0.0.1:1/test/")!
        }
        func stop() {}
    }

    private func host(_ error: Error) async throws -> (RemuxHost, LoopbackHandler, PlexConvertedPathR471Tests.AfterOpenReader) {
        let data = PlexConvertedPathR471Tests.shape().build().data
        let reader = PlexConvertedPathR471Tests.AfterOpenReader(data, mode: .fails(error))
        let server = CapturingServer()
        let host = RemuxHost(reader: reader, options: PlexConvertedPathR471Tests.options(), server: server)
        _ = try await host.start()
        reader.arm()
        return (host, try XCTUnwrap(server.handler), reader)
    }

    private static func request(_ name: String) -> LoopbackRequest {
        LoopbackRequest(method: "GET", path: "/" + name, headers: [:])
    }

    /// A source that reports a plain cancellation while the player still waits: the player gets 500, and the row now says
    /// which resource and why.
    func testACancellationThePlayerDidNotCauseIsNamedInLastEvent() async throws {
        for error in [CancellationError() as Error, RemuxError.cancelled] {
            let (host, handler, _) = try await host(error)
            _ = try? await handler(Self.request("seg_video_0.m4s"))
            do { _ = try await handler(Self.request("seg_video_1.m4s")); XCTFail("expected a failure") } catch {}
            let failure = host.serveLog?.firstFailure()
            print("R471 (60) | \(error) | Last Event: Loopback \(failure ?? "nil")")
            XCTAssertEqual(failure, "seg_video_1.m4s: \(String(describing: error))")
            await host.stop()
        }
    }

    /// The player closed the request (the loopback cancels the handler's task): no answer was sent, so no 500 is logged.
    func testARequestThePlayerClosedIsStillNoFailure() async throws {
        let (host, handler, _) = try await host(CancellationError())
        let call = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            _ = try? await handler(Self.request("seg_video_1.m4s"))
        }
        call.cancel()
        await call.value
        XCTAssertNil(host.serveLog?.firstFailure())
        XCTAssertTrue(host.serveLog?.lines().first?.contains("seg_video_1.m4s") ?? false, "the request is still listed")
        await host.stop()
    }
}
