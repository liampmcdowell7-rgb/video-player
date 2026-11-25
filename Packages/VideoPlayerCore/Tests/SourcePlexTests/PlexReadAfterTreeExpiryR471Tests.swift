import XCTest
import Foundation
import VideoPlayerCore
@testable import SourcePlex

/// R471 (59), PROVISIONAL (owner 25 Nov 2026 round 6, Part B item 1 (c)): a 500 the player did not cause. Every
/// `PlexClient.read` found the file's address through the library listing, which expires after 300 s; a segment read 5
/// minutes into a film (or 5 minutes after the last browse) first read the whole library again, and failed with any
/// error of that walk. The address of a file being read is now kept.
final class PlexReadAfterTreeExpiryR471Tests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.withLock { t } }
        func advance(_ s: TimeInterval) { lock.withLock { t = t.addingTimeInterval(s) } }
    }

    /// Fails every library request once `listsFail` is set; file reads still work.
    final class FlakyLists: HTTPTransport, @unchecked Sendable {
        let library: FakePlexServer
        private let lock = NSLock()
        private var _listsFail = false
        init(_ library: FakePlexServer) { self.library = library }
        func failLists() { lock.withLock { _listsFail = true } }
        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            if !request.url.path.hasPrefix("/library/parts/"), lock.withLock({ _listsFail }) {
                return HTTPResponse(statusCode: 503)
            }
            return try await library.send(request)
        }
    }

    func testReadsOfAnOpenFileDoNotWalkTheLibraryAgainAfterItExpires() async throws {
        let fake = try FakePlexServer()
        let transport = FlakyLists(fake)
        let clock = Clock()
        let plex = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: transport,
                              now: { clock.now })
        let path = try await plex.list("/Movies")[0].path
        _ = try await plex.read(path, range: ByteRange(offset: 0, length: 16))
        let listRequests = fake.requests.filter { !$0.url.path.hasPrefix("/library/parts/") }.count
        clock.advance(301)
        transport.failLists()
        let data = try await plex.read(path, range: ByteRange(offset: 100, length: 16))
        XCTAssertEqual([UInt8](data), FakePlexServer.bytes(100, 16))
        XCTAssertEqual(fake.requests.filter { !$0.url.path.hasPrefix("/library/parts/") }.count, listRequests,
                       "no library request for a read of a file already being read")
    }

    /// A file the server no longer has (404) forgets its kept address, so the next read looks it up again.
    func testANotFoundReadForgetsTheKeptAddress() async throws {
        let fake = try FakePlexServer()
        let clock = Clock()
        let plex = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: fake,
                              now: { clock.now })
        let path = try await plex.list("/Movies")[0].path
        _ = try await plex.read(path, range: ByteRange(offset: 0, length: 16))
        let kept = await plex.keptPartURLCount
        XCTAssertEqual(kept, 1)
        let missing = PlexReadErrorsR471Tests.PartAnswers(fake) { _ in HTTPResponse(statusCode: 404) }
        let gone = PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: missing,
                              now: { clock.now })
        let gonePath = try await gone.list("/Movies")[0].path
        do { _ = try await gone.read(gonePath, range: ByteRange(offset: 0, length: 16)); XCTFail("expected notFound") }
        catch SourceError.notFound {}
        let left = await gone.keptPartURLCount
        XCTAssertEqual(left, 0)
    }
}
