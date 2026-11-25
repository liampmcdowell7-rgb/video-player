import XCTest
import Foundation
import VideoPlayerCore
@testable import SourcePlex

/// R471 (64), PROVISIONAL (owner 25 Nov 2026 round 7, Part B item 2, finding P2): a library walk that fails after a newer
/// one started (a refresh) no longer throws the newer walk away, so the next lookup joins it instead of walking again.
final class PlexLateTreeFailureR471Tests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    /// The first `/library/sections` request waits until `release()` and then answers 503; every later one is the library's.
    final class SlowFirstWalk: HTTPTransport, @unchecked Sendable {
        let library: FakePlexServer
        private let lock = NSLock()
        private var sectionRequests = 0
        private var released = false
        init(_ library: FakePlexServer) { self.library = library }
        func release() { lock.withLock { released = true } }
        var walks: Int { lock.withLock { sectionRequests } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            if request.url.path == "/library/sections" {
                let first: Bool = lock.withLock { sectionRequests += 1; return sectionRequests == 1 }
                if first {
                    while !lock.withLock({ released }) { try await Task.sleep(nanoseconds: 5_000_000) }
                    return HTTPResponse(statusCode: 503)
                }
            }
            return try await library.send(request)
        }
    }

    func testALateFailureOfAnOlderWalkKeepsTheNewerOne() async throws {
        let transport = SlowFirstWalk(try FakePlexServer())
        let plex = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: transport)
        let first = Task { try await plex.list("/Movies") }
        while transport.walks < 1 { try await Task.sleep(nanoseconds: 5_000_000) }
        try await plex.refresh()                       // the newer walk, complete
        XCTAssertEqual(transport.walks, 2)
        transport.release()                            // the older walk fails now
        _ = try? await first.value
        _ = try await plex.list("/Movies")             // joins the newer walk
        print("R471 (64) | library walks after the late failure and one more lookup: \(transport.walks)")
        XCTAssertEqual(transport.walks, 2, "the lookup after the late failure reuses the newer walk")
    }
}
