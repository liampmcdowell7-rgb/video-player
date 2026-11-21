import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// Two-way watch state, stage 1 (R306 b, R308): the exact requests of the write client, against the fake server. No network.
final class PlexWatchWriterTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    private func writer(_ fake: FakePlexServer) -> PlexWatchWriter {
        PlexWatchWriter(baseURL: base, token: "server-token-placeholder", identity: identity, transport: fake)
    }

    private func query(_ request: HTTPRequest) -> [String] {
        (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }
    }

    private func assertHeaders(_ request: HTTPRequest, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.headers["X-Plex-Token"], "server-token-placeholder", file: file, line: line)
        XCTAssertEqual(request.headers["X-Plex-Client-Identifier"], "install-1234", file: file, line: line)
        XCTAssertEqual(request.headers["Accept"], "application/json", file: file, line: line)
        XCTAssertFalse(request.url.absoluteString.contains("server-token-placeholder"), "the token is never in the address", file: file, line: line)
    }

    func testAPlayingReportIsOnePOSTToTheTimelineWithExactlyTheseParameters() async throws {
        let fake = try FakePlexServer()
        try await writer(fake).report(ServerTimelineReport(itemKey: "1001", state: .playing, position: 754.3219, duration: 5400,
                                                          sessionIdentifier: "session-1"))
        XCTAssertEqual(fake.requests.map { "\($0.method) \($0.url.path)" }, ["GET /media/providers", "POST /:/timeline"])
        let request = try XCTUnwrap(fake.serverWrites.first)
        XCTAssertEqual(query(request), ["key=/library/metadata/1001", "ratingKey=1001", "state=playing", "time=754322", "duration=5400000"])
        XCTAssertEqual(request.headers["X-Plex-Session-Identifier"], "session-1")
        XCTAssertNil(request.body)
        assertHeaders(request)
    }

    func testAStopReportSaysWhetherPlaybackContinuesAndAnOfflineReplayCarriesItsTime() async throws {
        let fake = try FakePlexServer()
        let plex = writer(fake)
        try await plex.report(ServerTimelineReport(itemKey: "1002", state: .stopped, position: 60, duration: nil, continuing: false))
        let changed = Date(timeIntervalSince1970: 1_763_700_000.75)
        try await plex.report(ServerTimelineReport(itemKey: "1002", state: .stopped, position: 120.5, duration: 3600,
                                                   continuing: true, offlineUpdated: changed))
        // `continuing` is sent with `stopped` only.
        try await plex.report(ServerTimelineReport(itemKey: "1002", state: .paused, position: 0, continuing: true))
        XCTAssertEqual(fake.serverWrites.map(query), [
            ["key=/library/metadata/1002", "ratingKey=1002", "state=stopped", "time=60000", "continuing=0"],
            ["key=/library/metadata/1002", "ratingKey=1002", "state=stopped", "time=120500", "duration=3600000", "continuing=1",
             "offline=1", "updated=1763700000"],
            ["key=/library/metadata/1002", "ratingKey=1002", "state=paused", "time=0"],
        ])
        XCTAssertNil(fake.serverWrites[0].headers["X-Plex-Session-Identifier"])
    }

    func testMarkPlayedAndUnplayedArePUTsWithTheLibraryIdentifierAndTheRatingKey() async throws {
        let fake = try FakePlexServer()
        let plex = writer(fake)
        try await plex.markPlayed(itemKey: "1001")
        try await plex.markUnplayed(itemKey: "3101")
        XCTAssertEqual(fake.requests.map { "\($0.method) \($0.url.path)" },
                       ["GET /media/providers", "PUT /:/scrobble", "PUT /:/unscrobble"], "the paths are read once")
        XCTAssertEqual(fake.serverWrites.map(query), [["identifier=com.plexapp.plugins.library", "key=1001"],
                                                     ["identifier=com.plexapp.plugins.library", "key=3101"]])
        fake.serverWrites.forEach { assertHeaders($0) }
    }

    func testThePathsComeFromTheServersFeatureKeysAndUnsafeOrMissingOnesFallBack() async throws {
        let fake = try FakePlexServer()
        fake.providers = Data("""
        {"MediaContainer": {"MediaProvider": [
          {"identifier": "tv.plex.providers.epg.cloud:12", "Feature": [{"type": "timeline", "key": "/epg/:/timeline"}]},
          {"identifier": "com.plexapp.plugins.library", "Feature": [
            {"type": "timeline", "key": "/custom/:/timeline", "scrobbleKey": "https://elsewhere.example.invalid/:/scrobble"}]}]}}
        """.utf8)
        fake.writePaths = ["/custom/:/timeline", "/:/scrobble", "/:/unscrobble"]
        let plex = writer(fake)
        try await plex.report(ServerTimelineReport(itemKey: "1001", state: .paused, position: 1))
        try await plex.markPlayed(itemKey: "1001")
        try await plex.markUnplayed(itemKey: "1001")
        XCTAssertEqual(fake.serverWrites.map(\.url.path), ["/custom/:/timeline", "/:/scrobble", "/:/unscrobble"],
                       "the library provider's own timeline key; another host is never used; a missing key is the documented one")
        XCTAssertTrue(fake.serverWrites.allSatisfy { $0.url.host == "192-168-1-20.machine0001.plex.direct" })

        let older = try FakePlexServer()
        older.providers = nil   // answers 404
        try await writer(older).markPlayed(itemKey: "1001")
        XCTAssertEqual(older.serverWrites.map(\.url.path), ["/:/scrobble"])
    }

    func testAServerThatCannotBeReachedThrowsWithoutTheTokenAndIsAskedForItsPathsAgain() async throws {
        let fake = try FakePlexServer()
        fake.reachableHosts = []
        let plex = writer(fake)
        do {
            try await plex.markPlayed(itemKey: "1001")
            XCTFail("expected a transport error")
        } catch let SourceError.transport(text) {
            XCTAssertFalse(text.contains("server-token-placeholder"))
        }
        fake.reachableHosts = ["192-168-1-20.machine0001.plex.direct"]
        try await plex.markPlayed(itemKey: "1001")
        XCTAssertEqual(fake.requests.map { "\($0.method) \($0.url.path)" },
                       ["GET /media/providers", "GET /media/providers", "PUT /:/scrobble"])
    }

    func testARefusedWriteThrowsItsStatus() async throws {
        let fake = try FakePlexServer()
        fake.writeStatus = 404
        do {
            try await writer(fake).markUnplayed(itemKey: "9999")
            XCTFail("expected not found")
        } catch let error as SourceError {
            XCTAssertEqual(error, .notFound)
        }
        fake.writeStatus = 400
        do {
            try await writer(fake).report(ServerTimelineReport(itemKey: "1001", state: .playing, position: 3))
            XCTFail("expected a refusal")
        } catch let error as SourceError {
            XCTAssertEqual(error, .httpStatus(400))
        }
    }
}

/// The 10-second rhythm plus every state change (R308).
final class ServerTimelineRhythmTests: XCTestCase {
    func testAStateChangeIsDueAtOnceAndTheSameStateEveryTenSeconds() {
        var rhythm = ServerTimelineRhythm()
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(ServerTimelineRhythm.interval, 10)
        XCTAssertTrue(rhythm.isDue(.playing, at: t0), "the first report")
        XCTAssertFalse(rhythm.isDue(.playing, at: t0.addingTimeInterval(1)))
        XCTAssertFalse(rhythm.isDue(.playing, at: t0.addingTimeInterval(9.9)))
        XCTAssertTrue(rhythm.isDue(.playing, at: t0.addingTimeInterval(10)), "ten seconds without a change")
        XCTAssertTrue(rhythm.isDue(.paused, at: t0.addingTimeInterval(11)), "a change, at once")
        XCTAssertTrue(rhythm.isDue(.playing, at: t0.addingTimeInterval(11.5)), "and back, at once")
        XCTAssertFalse(rhythm.isDue(.playing, at: t0.addingTimeInterval(15)))
        XCTAssertTrue(rhythm.isDue(.buffering, at: t0.addingTimeInterval(16)))
        XCTAssertTrue(rhythm.isDue(.stopped, at: t0.addingTimeInterval(17)))
        XCTAssertFalse(rhythm.isDue(.stopped, at: t0.addingTimeInterval(18)), "stopped is not sent twice")
    }
}
