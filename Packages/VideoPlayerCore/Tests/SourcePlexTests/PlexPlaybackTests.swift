import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// Stage 5 (docs/PLEX_SOURCE.md section 5; R305): what the player is given for a Plex file, which files are refused
/// because only the server could convert them, and that the server's transcoder is never asked. No network.
final class PlexPlaybackTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    private func client(_ fake: FakePlexServer, lifetime: TimeInterval = 300, now: @escaping @Sendable () -> Date = { Date() }) -> PlexClient {
        PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: fake,
                   treeLifetime: lifetime, now: now)
    }

    private func movie(_ n: Int, codec: String, container: String = "mkv") -> [String: Any] {
        var item = makeMovie(n, container: container)
        var media = (item["Media"] as! [[String: Any]])[0]
        media["videoCodec"] = codec
        item["Media"] = [media]
        return item
    }

    private let mp4Path = "/Movies/Test Movie (2020)/Test Movie (2020).mp4"

    func testAnMP4IsPlayedFromThePartAddressWithTheTokenInAHeaderOnly() async throws {
        let fake = try FakePlexServer()
        let access = try await client(fake).playbackAccess(for: mp4Path)
        guard case .url(let url, let headers) = access else { return XCTFail("expected a link, got \(access)") }
        XCTAssertEqual(url.absoluteString, base.absoluteString + "/library/parts/2001/1700000000/file.mp4")
        XCTAssertFalse(url.absoluteString.contains("server-token-placeholder"), "the token is never in the address")
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(headers["X-Plex-Token"], "server-token-placeholder")
    }

    /// The app's own remux reads an MKV through ranged reads of the same Part (MKV with DTS, Dolby Vision 7: the remux
    /// engine handles the streams; here only the byte path is checked).
    func testAnMKVIsReadInRangesForTheAppsOwnRemux() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        let path = "/Movies/Second Test Movie (2021).mkv"
        let head = try await plex.read(path, range: ByteRange(offset: 0, length: 4))
        let tail = try await plex.read(path, range: ByteRange(offset: 996, length: 4))
        XCTAssertEqual([UInt8](head), FakePlexServer.bytes(0, 4))
        XCTAssertEqual([UInt8](tail), FakePlexServer.bytes(996, 4))
        let ranges = fake.requests.compactMap { $0.headers["Range"] }
        XCTAssertEqual(ranges, ["bytes=0-3", "bytes=996-999"])
    }

    func testAVideoFormatOnlyTheServerCouldConvertIsRefusedByName() async throws {
        let fake = try FakePlexServer()
        fake.lists["/library/sections/1/all"] = [movie(1, codec: "mpeg2video"), movie(2, codec: "vc1"), movie(3, codec: "h264"),
                                                 movie(4, codec: "hevc"), movie(5, codec: "av1"), movie(6, codec: "a-word-not-known")]
        let plex = client(fake)
        func needed(_ n: Int) async throws -> String? {
            try await plex.conversionNeeded(at: "/Movies/Paged Movie \(n) (\(2000 + n % 20)).mkv")
        }
        let results = [try await needed(1), try await needed(2), try await needed(3), try await needed(4), try await needed(5), try await needed(6)]
        XCTAssertEqual(results, ["MPEG-2 video", "VC-1", nil, nil, nil, nil],
                       "only the listed formats are refused; an unknown word goes to the player, which reports its own error")
    }

    func testTheServersTranscoderIsNeverAskedAndNothingIsWritten() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        _ = try await plex.playbackAccess(for: mp4Path)
        _ = try await plex.read("/Movies/Second Test Movie (2021).mkv", range: ByteRange(offset: 0, length: 8))
        _ = try await plex.conversionNeeded(at: mp4Path)
        XCTAssertFalse(fake.requests.contains { $0.url.path.contains("transcode") || $0.url.path.contains("/decision") })
        XCTAssertTrue(fake.serverWrites.isEmpty)
    }

    func testTheListingIsReusedWithinItsLifetimeAndReadAgainAfterIt() async throws {
        let fake = try FakePlexServer()
        let clock = MovingClock()
        let plex = client(fake, lifetime: 300, now: { clock.now })
        _ = try await plex.list("/Movies")
        _ = try await plex.playbackAccess(for: mp4Path)
        XCTAssertEqual(fake.requests.filter { $0.url.path == "/library/sections" }.count, 1, "play right after browsing: no new listing")
        clock.advance(301)
        _ = try await plex.list("/Movies")
        XCTAssertEqual(fake.requests.filter { $0.url.path == "/library/sections" }.count, 2, "read again after five minutes")
    }

    func testTheAppSharesOneClientPerServerAndToken() {
        let a = PlexClient.shared(baseURL: base, token: "server-token-placeholder", identity: identity)
        let b = PlexClient.shared(baseURL: base, token: "server-token-placeholder", identity: identity)
        let other = PlexClient.shared(baseURL: base, token: "server-token-friend-placeholder", identity: identity)
        XCTAssertTrue(a === b)
        XCTAssertFalse(a === other)
    }
}

final class MovingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_700_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}
