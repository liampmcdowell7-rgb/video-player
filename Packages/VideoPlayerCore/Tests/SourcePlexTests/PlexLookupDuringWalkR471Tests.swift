import XCTest
import Foundation
import VideoPlayerCore
@testable import SourcePlex

/// R471 (71), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding B): looking up one file the last listing has
/// (the 8 s track probe's `info`, a play's file address) does not wait for a new walk of the whole library when the listing
/// has expired; the walk runs in the background. A folder list still waits for it.
final class PlexLookupDuringWalkR471Tests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!
    let moviePath = "/Movies/Test Movie (2020)/Test Movie (2020).mp4"

    /// After `hold()`, every `/library/sections` request waits until `release()`.
    final class HeldWalk: HTTPTransport, @unchecked Sendable {
        let library: FakePlexServer
        private let lock = NSLock()
        private var sectionRequests = 0
        private var held = false
        init(_ library: FakePlexServer) { self.library = library }
        func hold() { lock.withLock { held = true } }
        func release() { lock.withLock { held = false } }
        var walks: Int { lock.withLock { sectionRequests } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            if request.url.path == "/library/sections" {
                lock.withLock { sectionRequests += 1 }
                while lock.withLock({ held }) { try await Task.sleep(nanoseconds: 5_000_000) }
            }
            return try await library.send(request)
        }
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }

    private func setUp(_ clock: MovingClock) async throws -> (PlexClient, HeldWalk) {
        let transport = HeldWalk(try FakePlexServer())
        let plex = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: transport,
                              treeLifetime: 300, now: { clock.now })
        _ = try await plex.list("/Movies")                  // the listing, complete
        clock.advance(301)                                  // expired
        transport.hold()                                    // the next walk takes as long as the test wants
        return (plex, transport)
    }

    func testAnExpiredListingAnswersALookupOfAFileItHasWithoutWaiting() async throws {
        let clock = MovingClock()
        let (plex, transport) = try await setUp(clock)
        let done = Flag()
        let lookup = Task { () -> SourceEntry in let e = try await plex.info(moviePath); done.set(); return e }
        let start = Date()
        while !done.isSet && Date().timeIntervalSince(start) < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        let answeredWhileWalking = done.isSet
        print("R471 (71) | lookup answered while the new walk was held: \(answeredWhileWalking), walks \(transport.walks)")
        transport.release()
        let entry = try await lookup.value
        XCTAssertTrue(answeredWhileWalking, "the file's lookup does not wait for the whole library to be read again")
        XCTAssertFalse(entry.isDirectory)
        while transport.walks < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(transport.walks, 2, "a new walk was started in the background")
    }

    func testAFolderListStillWaitsForTheNewWalk() async throws {
        let clock = MovingClock()
        let (plex, transport) = try await setUp(clock)
        let done = Flag()
        let listing = Task { _ = try await plex.list("/Movies"); done.set() }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(done.isSet, "a folder list (the scan) waits for the new listing")
        transport.release()
        try await listing.value
        XCTAssertTrue(done.isSet)
    }

    func testAFileTheLastListingDoesNotHaveWaitsForTheNewWalk() async throws {
        let clock = MovingClock()
        let (plex, transport) = try await setUp(clock)
        let done = Flag()
        let lookup = Task { _ = try? await plex.info("/Movies/Not There (2021)/Not There (2021).mkv"); done.set() }
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(done.isSet, "a file the last listing lacks may be new on the server: wait for the new listing")
        transport.release()
        await lookup.value
    }
}
