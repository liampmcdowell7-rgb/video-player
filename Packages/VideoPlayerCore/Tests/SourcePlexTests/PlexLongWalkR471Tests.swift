import XCTest
import Foundation
import VideoPlayerCore
@testable import SourcePlex

/// R471 (70), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding A): the listing's 300 s count from when the
/// walk ENDS, and a lookup while a walk runs joins it. Before, they counted from the walk's start, so a walk longer than
/// the lifetime (a large library on a slow link) was stale on arrival: every folder of the scan started another full walk.
final class PlexLongWalkR471Tests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    /// Each walk takes `walkSeconds` on the clock (moved forward at the section list); optionally waits for `release()`.
    final class LongWalk: HTTPTransport, @unchecked Sendable {
        let library: FakePlexServer
        let clock: MovingClock
        let walkSeconds: TimeInterval
        private let lock = NSLock()
        private var sectionRequests = 0
        private var held: Bool
        init(_ library: FakePlexServer, clock: MovingClock, walkSeconds: TimeInterval, hold: Bool = false) {
            self.library = library; self.clock = clock; self.walkSeconds = walkSeconds; self.held = hold
        }
        func release() { lock.withLock { held = false } }
        var walks: Int { lock.withLock { sectionRequests } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            if request.url.path == "/library/sections" {
                lock.withLock { sectionRequests += 1 }
                while lock.withLock({ held }) { try await Task.sleep(nanoseconds: 5_000_000) }
                clock.advance(walkSeconds)
            }
            return try await library.send(request)
        }
    }

    private func client(_ transport: LongWalk, clock: MovingClock) -> PlexClient {
        PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: transport,
                   treeLifetime: 300, now: { clock.now })
    }

    func testAWalkLongerThanTheLifetimeServesTheLookupsAfterIt() async throws {
        let clock = MovingClock()
        let transport = LongWalk(try FakePlexServer(), clock: clock, walkSeconds: 400)
        let plex = client(transport, clock: clock)
        _ = try await plex.list("/")
        _ = try await plex.list("/Movies")
        _ = try await plex.list("/TV Shows")
        print("R471 (70) | walks for three lookups after one 400 s walk: \(transport.walks)")
        XCTAssertEqual(transport.walks, 1, "the listing is fresh for 300 s after it arrives")
        clock.advance(301)
        _ = try await plex.list("/Movies")
        XCTAssertEqual(transport.walks, 2, "and read again once 300 s have passed since it arrived")
    }

    func testALookupDuringALongWalkJoinsIt() async throws {
        let clock = MovingClock()
        let transport = LongWalk(try FakePlexServer(), clock: clock, walkSeconds: 0, hold: true)
        let plex = client(transport, clock: clock)
        let first = Task { try await plex.list("/Movies") }
        while transport.walks < 1 { try await Task.sleep(nanoseconds: 5_000_000) }
        clock.advance(400)                                  // the walk is still running 400 s later
        let second = Task { try await plex.list("/TV Shows") }
        try await Task.sleep(nanoseconds: 50_000_000)
        transport.release()
        _ = try await first.value
        _ = try await second.value
        print("R471 (70) | walks for a lookup made during a 400 s walk: \(transport.walks)")
        XCTAssertEqual(transport.walks, 1, "the second lookup joins the running walk")
    }
}
