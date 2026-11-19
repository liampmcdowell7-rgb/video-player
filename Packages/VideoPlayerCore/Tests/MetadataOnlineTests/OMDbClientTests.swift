import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// OMDb client against a mock transport with hand-written fixtures (not recorded from the real service).
final class OMDbClientTests: XCTestCase {
    private let key = "omdb-test-key-not-real"

    private func client(_ transport: MockTransport, cache: (any MetadataCache)? = nil, clock: FakeClock = FakeClock(), queue: QueueConfiguration? = nil, apiKey: String? = nil) -> OMDbClient {
        OMDbClient(apiKey: apiKey ?? key, transport: transport, cache: cache ?? InMemoryMetadataCache(), queueConfiguration: queue ?? plainQueue(), clock: clock)
    }

    private func body(_ text: String, status: Int = 200) -> MockTransport {
        MockTransport { _ in response(status, text) }
    }

    private func query(_ r: HTTPRequest) -> [String: String] {
        Dictionary((URLComponents(url: r.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Scores

    func testAllThreeScoresAreParsedAndLabelledBySource() async throws {
        let transport = body(Fixtures.omdbMarrowgate)
        let result = try await client(transport).ratings(imdbID: "tt0133093")
        let q = query(transport.requests[0])
        XCTAssertEqual(q["i"], "tt0133093")
        XCTAssertEqual(q["apikey"], key)
        XCTAssertEqual(transport.requests[0].url.host, "www.omdbapi.com")

        XCTAssertEqual(result.imdbID, "tt0133093")
        let r = result.ratings
        XCTAssertEqual(r.imdb?.label, "IMDb")
        XCTAssertEqual(r.imdb?.display, "8.7/10")
        XCTAssertEqual(r.imdb?.percent ?? 0, 87, accuracy: 0.001)
        XCTAssertEqual(r.imdb?.votes, 2_000_000)
        XCTAssertEqual(r.rottenTomatoes?.label, "Rotten Tomatoes")
        XCTAssertEqual(r.rottenTomatoes?.display, "83%")
        XCTAssertEqual(r.rottenTomatoes?.percent ?? 0, 83, accuracy: 0.001)
        XCTAssertEqual(r.metacritic?.label, "Metacritic")
        XCTAssertEqual(r.metacritic?.display, "73/100")
        XCTAssertEqual(r.metacritic?.percent ?? 0, 73, accuracy: 0.001)
        XCTAssertEqual(r.visible.map(\.label), ["IMDb", "Rotten Tomatoes", "Metacritic"])
    }

    func testMissingScoresAreHiddenCleanly() async throws {
        let only = try await client(body(Fixtures.omdbOnlyIMDb)).ratings(imdbID: "tt7654321")
        XCTAssertEqual(only.ratings.visible.map(\.source), [.imdb])
        XCTAssertNil(only.ratings.rottenTomatoes)
        XCTAssertNil(only.ratings.metacritic)
        XCTAssertNil(only.ratings.imdb?.votes, "N/A votes")

        let none = try await client(body(Fixtures.omdbNothing)).ratings(imdbID: "tt1111111")
        XCTAssertTrue(none.ratings.visible.isEmpty)
        XCTAssertEqual(none.ratings, .empty)
    }

    func testFlatFieldsAreUsedWhenTheRatingsArrayIsAbsent() async throws {
        let r = try await client(body(Fixtures.omdbFlatOnly)).ratings(imdbID: "tt2222222").ratings
        XCTAssertEqual(r.imdb?.display, "7.4/10")
        XCTAssertEqual(r.imdb?.votes, 12345)
        XCTAssertEqual(r.metacritic?.display, "61/100")
        XCTAssertNil(r.rottenTomatoes)
    }

    func testScoreParserHandlesEveryFormatAndRejectsGarbage() {
        XCTAssertEqual(OMDbScoreParser.parse("8.7/10")?.percent ?? 0, 87, accuracy: 0.001)
        XCTAssertEqual(OMDbScoreParser.parse("87%")?.percent ?? 0, 87, accuracy: 0.001)
        XCTAssertEqual(OMDbScoreParser.parse("73/100")?.percent ?? 0, 73, accuracy: 0.001)
        XCTAssertEqual(OMDbScoreParser.parse(" 100% ")?.display, "100%")
        XCTAssertEqual(OMDbScoreParser.parse("0%")?.percent, 0)
        for bad in [nil, "", "N/A", "n/a", "abc", "11/10", "5/0", "-3/10", "150%", "/", "8.7", "8.7/10/5"] as [String?] {
            XCTAssertNil(OMDbScoreParser.parse(bad), "\(bad ?? "nil")")
        }
    }

    func testRatingSetMergeKeepsTMDBAndAddsOMDb() {
        let tmdb = RatingSet(tmdb: Rating(source: .tmdb, percent: 82, display: "8.2/10", votes: 10))
        let omdb = RatingSet(imdb: Rating(source: .imdb, percent: 87, display: "8.7/10"))
        let merged = tmdb.merging(omdb)
        XCTAssertEqual(merged.visible.map(\.label), ["TMDB", "IMDb"])
    }

    // MARK: Title and year

    func testLookupByTitleAndYear() async throws {
        let transport = body(Fixtures.omdbMarrowgate)
        let result = try await client(transport).ratings(title: "The Marrowgate", year: 1999, kind: .movie)
        let q = query(transport.requests[0])
        XCTAssertEqual(q["t"], "The Marrowgate")
        XCTAssertEqual(q["y"], "1999")
        XCTAssertEqual(q["type"], "movie")
        XCTAssertNil(q["i"])
        XCTAssertEqual(result.ratings.imdb?.display, "8.7/10")
        let series = body(Fixtures.omdbMarrowgate)
        _ = try await client(series).ratings(title: "Crossing Brine", year: nil, kind: .series)
        XCTAssertEqual(query(series.requests[0])["type"], "series")
        XCTAssertNil(query(series.requests[0])["y"])
    }

    func testTitleLookupIsAlsoCachedUnderTheIMDbID() async throws {
        let transport = body(Fixtures.omdbMarrowgate)
        let c = client(transport)
        _ = try await c.ratings(title: "The Marrowgate", year: 1999, kind: .movie)
        let byID = try await c.ratings(imdbID: "tt0133093")
        XCTAssertEqual(byID.ratings.imdb?.display, "8.7/10")
        XCTAssertEqual(transport.count, 1)
    }

    // MARK: Errors

    func testErrorsInsideTheBodyAreMapped() async {
        let cases: [(String, Int, MetadataError)] = [
            (Fixtures.omdbInvalidKey, 401, .invalidAPIKey),
            (Fixtures.omdbLimit, 401, .quotaExhausted),
            (Fixtures.omdbNotFound, 200, .notFound),
            (Fixtures.omdbBadID, 200, .notFound)
        ]
        for (text, status, expected) in cases {
            do {
                _ = try await client(body(text, status: status)).ratings(imdbID: "tt0000001")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? MetadataError, expected)
            }
        }
    }

    func testPlainStatusErrors() async {
        let cases: [(Int, MetadataError)] = [(401, .invalidAPIKey), (500, .server(500)), (418, .unexpectedStatus(418))]
        for (status, expected) in cases {
            do {
                _ = try await client(body("", status: status), queue: plainQueue(retries: 0)).ratings(imdbID: "tt0000001")
                XCTFail("expected \(expected)")
            } catch {
                XCTAssertEqual(error as? MetadataError, expected, "status \(status)")
            }
        }
    }

    func testNonObjectBodyIsADecodingError() async {
        do {
            _ = try await client(body("[1,2,3]")).ratings(imdbID: "tt1")
            XCTFail("expected an error")
        } catch {
            guard case .decoding = error as? MetadataError else { return XCTFail("wrong error \(error)") }
        }
    }

    func testEmptyKeyFailsWithoutARequest() async {
        let transport = body(Fixtures.omdbMarrowgate)
        do {
            _ = try await client(transport, apiKey: "").ratings(imdbID: "tt1")
            XCTFail("expected missingCredentials")
        } catch {
            XCTAssertEqual(error as? MetadataError, .missingCredentials)
        }
        XCTAssertEqual(transport.count, 0)
    }

    func testQuotaErrorFromTheServerIsNotRetriedAndErrorsAreNotCached() async throws {
        let transport = body(Fixtures.omdbLimit, status: 401)
        let c = client(transport)
        for _ in 0..<2 {
            do { _ = try await c.ratings(imdbID: "tt0000001") } catch { XCTAssertEqual(error as? MetadataError, .quotaExhausted) }
        }
        XCTAssertEqual(transport.count, 2, "an error body is not cached")
    }

    // MARK: Queue and cache

    func testFreeKeyDailyLimitStopsLocallyBeforeSendingMore() async throws {
        let transport = body(Fixtures.omdbMarrowgate)
        let c = client(transport, queue: plainQueue(daily: 3))
        for i in 0..<3 { _ = try await c.ratings(imdbID: "tt000000\(i)") }
        do {
            _ = try await c.ratings(imdbID: "tt0000009")
            XCTFail("expected quotaExhausted")
        } catch {
            XCTAssertEqual(error as? MetadataError, .quotaExhausted)
        }
        XCTAssertEqual(transport.count, 3)
    }

    func testCachedScoresServeWithoutTheNetworkAndOfflineAfterExpiry() async throws {
        let transport = body(Fixtures.omdbMarrowgate)
        let clock = FakeClock()
        let c = client(transport, clock: clock, queue: plainQueue(retries: 0))
        let first = try await c.ratings(imdbID: "tt0133093")
        _ = try await c.ratings(imdbID: "tt0133093")
        XCTAssertEqual(transport.count, 1)
        clock.advance(8 * 86_400)
        struct Offline: Error {}
        transport.setHandler { _ in throw Offline() }
        let stale = try await c.ratings(imdbID: "tt0133093")
        XCTAssertEqual(first, stale)
    }

    func testExpiredEntriesAreRefetched() async throws {
        let transport = body(Fixtures.omdbMarrowgate)
        let clock = FakeClock()
        let c = client(transport, clock: clock)
        _ = try await c.ratings(imdbID: "tt0133093")
        clock.advance(8 * 86_400)
        _ = try await c.ratings(imdbID: "tt0133093")
        XCTAssertEqual(transport.count, 2)
    }

    func testKeyIsNotCached() async throws {
        let cache = InMemoryMetadataCache()
        _ = try await client(body(Fixtures.omdbMarrowgate), cache: cache).ratings(imdbID: "tt0133093")
        for k in await cache.keys {
            XCTAssertFalse(k.contains(key))
            let entry = await cache.entry(for: CacheKey(provider: "omdb", kind: "title", id: "tt0133093", variant: ""))
            XCTAssertFalse(String(decoding: entry?.data ?? Data(), as: UTF8.self).contains(key))
        }
    }
}
