import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// #26 item 9: the key-free sources with mocked responses only (no network).
final class IntroDBClientTests: XCTestCase {
    static let found = """
    {"imdb_id":"tt0000001","media_type":"tv","is_movie":false,"season":1,"episode":2,
     "intro":{"start_sec":31.5,"end_sec":91.5,"start_ms":31500,"end_ms":91500,"confidence":0.92,"submission_count":4,"updated_at":"2026-01-01"},
     "recap":null,
     "outro":{"start_sec":1300,"end_sec":1390,"confidence":0.8,"submission_count":2},
     "post_credits":null,"no_intro":false,"no_recap":true,"no_outro":false}
    """

    func client(_ transport: MockTransport, cache: any MetadataCache = InMemoryMetadataCache(), clock: FakeClock = FakeClock()) -> IntroDBClient {
        IntroDBClient(transport: transport, cache: cache, queueConfiguration: plainQueue(retries: 0), clock: clock, userAgent: "VideoPlayerTests/1.0")
    }

    func testEpisodeLookupSendsOnlyTheIDsAndParsesTimings() async throws {
        let t = MockTransport { _ in response(200, Self.found) }
        let timings = try await client(t).timings(for: .episode(seriesIMDbID: "tt0000001", season: 1, episode: 2))
        XCTAssertEqual(timings?.intro, .init(start: 31.5, end: 91.5, confidence: 0.92, submissions: 4))
        XCTAssertNil(timings?.recap)
        XCTAssertEqual(timings?.outro?.start, 1300)
        let url = try XCTUnwrap(t.requests.first?.url.absoluteString)
        XCTAssertEqual(url, "https://api.introdb.app/segments?imdb_id=tt0000001&season=1&episode=2")
        XCTAssertEqual(t.requests.first?.headers["User-Agent"], "VideoPlayerTests/1.0")
        XCTAssertNil(t.requests.first?.headers["Authorization"], "IntroDB reads need no key")
    }

    func testMovieLookupAndCacheKeepsRequestsLow() async throws {
        let t = MockTransport { _ in response(200, Self.found) }
        let c = client(t)
        _ = try await c.timings(for: .movie(imdbID: "tt0000002"))
        _ = try await c.timings(for: .movie(imdbID: "tt0000002"))
        XCTAssertEqual(t.count, 1, "the second ask is answered from the cache")
        XCTAssertTrue(t.requests[0].url.absoluteString.hasSuffix("imdb_id=tt0000002&is_movie=true"))
    }

    func testNotInDatabaseIsNilAndCachedForADay() async throws {
        let t = MockTransport { _ in response(404, "{}") }
        let clock = FakeClock()
        let c = client(t, clock: clock)
        let first = try await c.timings(for: .movie(imdbID: "tt0000003"))
        XCTAssertNil(first)
        _ = try await c.timings(for: .movie(imdbID: "tt0000003"))
        XCTAssertEqual(t.count, 1)
        clock.advance(IntroDBClient.missingTTL + 1)
        _ = try await c.timings(for: .movie(imdbID: "tt0000003"))
        XCTAssertEqual(t.count, 2)
    }

    func testOfflineFailureThrowsWithoutCacheAndUsesStaleCacheWithOne() async throws {
        let t = MockTransport { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client(t).timings(for: .movie(imdbID: "tt0000004"))
            XCTFail("expected an error")
        } catch let error as MetadataError {
            guard case .network = error else { return XCTFail("\(error)") }
        }
        let cache = InMemoryMetadataCache()
        let clock = FakeClock()
        let good = MockTransport { _ in response(200, Self.found) }
        _ = try await client(good, cache: cache, clock: clock).timings(for: .movie(imdbID: "tt0000004"))
        clock.advance(IntroDBClient.foundTTL + 1)
        let stale = try await client(t, cache: cache, clock: clock).timings(for: .movie(imdbID: "tt0000004"))
        XCTAssertEqual(stale?.intro?.start, 31.5)
    }

    func testMalformedIDIsNeverSent() async {
        let t = MockTransport { _ in response(200, Self.found) }
        for bad in ["", "0000001", "tt12", "tt0000001&x=1", "nm0000001"] {
            _ = try? await client(t).timings(for: .movie(imdbID: bad))
        }
        XCTAssertEqual(t.count, 0)
    }

    func testBadSpansAreDroppedAndPercentConfidenceIsScaled() throws {
        let body = #"{"intro":{"start_sec":50,"end_sec":20},"recap":{"start_sec":0,"end_sec":40,"confidence":85},"outro":"x"}"#
        let t = try IntroDBClient.decode(Data(body.utf8))
        XCTAssertNil(t.intro)
        XCTAssertEqual(t.recap?.confidence ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertNil(t.outro)
        XCTAssertThrowsError(try IntroDBClient.decode(Data("[]".utf8)))
    }
}

final class WikidataClientTests: XCTestCase {
    static func row(_ q: String, label: String, imdb: String? = nil, tmdb: String? = nil, date: String? = nil, cast: String? = nil, order: String? = nil) -> String {
        var parts = [#""item":{"type":"uri","value":"http://www.wikidata.org/entity/\#(q)"}"#, #""itemLabel":{"value":"\#(label)"}"#]
        if let imdb { parts.append(#""imdb":{"value":"\#(imdb)"}"#) }
        if let tmdb { parts.append(#""tmdbMovie":{"value":"\#(tmdb)"}"#) }
        if let date { parts.append(#""date":{"value":"\#(date)"}"#) }
        if let cast { parts.append(#""castLabel":{"value":"\#(cast)"}"#) }
        if let order { parts.append(#""order":{"value":"\#(order)"}"#) }
        return "{" + parts.joined(separator: ",") + "}"
    }

    static func body(_ rows: [String]) -> String { #"{"head":{"vars":[]},"results":{"bindings":["# + rows.joined(separator: ",") + "]}}" }

    func client(_ t: MockTransport, clock: FakeClock = FakeClock()) -> WikidataClient {
        WikidataClient(transport: t, queueConfiguration: plainQueue(retries: 0), clock: clock, userAgent: "VideoPlayerTests/1.0 (https://example.invalid)")
    }

    func testTMDBIDLookupParsesFactsAndOrdersCast() async throws {
        let rows = [
            Self.row("Q100", label: "Sample Film", imdb: "tt0000010", tmdb: "77", date: "2001-05-04T00:00:00Z", cast: "Second Actor", order: "2"),
            Self.row("Q100", label: "Sample Film", imdb: "tt0000010", tmdb: "77", date: "2000-11-01T00:00:00Z", cast: "First Actor", order: "1"),
            Self.row("Q100", label: "Sample Film", cast: "Q999"),
        ]
        let t = MockTransport { _ in response(200, Self.body(rows)) }
        let title = try await client(t).title(tmdbID: 77, kind: .movie)
        XCTAssertEqual(title, WikidataTitle(qid: "Q100", label: "Sample Film", year: 2000, imdbID: "tt0000010", tmdbID: 77, cast: ["First Actor", "Second Actor"]))
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.headers["User-Agent"], "VideoPlayerTests/1.0 (https://example.invalid)")
        XCTAssertTrue(request.url.absoluteString.hasPrefix("https://query.wikidata.org/sparql?format=json&query="))
        XCTAssertTrue(request.url.absoluteString.removingPercentEncoding?.contains(#"wdt:P4947 "77""#) == true)
    }

    func testTitleSearchEscapesTheNameAndChecksTheYear() async throws {
        let t = MockTransport { _ in response(200, Self.body([Self.row("Q5", label: "A \\\"Quoted\\\" Show", date: "1990-01-01")])) }
        let c = client(t)
        let near = try await c.title(named: "A \"Quoted\" Show", year: 1991, kind: .series)
        XCTAssertEqual(near?.qid, "Q5")
        let query = try XCTUnwrap(t.requests.first?.url.absoluteString.removingPercentEncoding)
        XCTAssertTrue(query.contains(#"rdfs:label "A \"Quoted\" Show"@en"#), query)
        let far = try await c.title(named: "A \"Quoted\" Show", year: 2020, kind: .series)
        XCTAssertNil(far, "a year more than one away is another title")
        XCTAssertEqual(WikidataClient.literal("a\\b\nc"), #""a\\b\nc""#)
    }

    func testNothingFoundIsCachedAndRateLimitIsReported() async throws {
        let t = MockTransport { _ in response(200, Self.body([])) }
        let c = client(t)
        let none1 = try await c.title(imdbID: "tt0000011")
        let none2 = try await c.title(imdbID: "tt0000011")
        XCTAssertNil(none1); XCTAssertNil(none2)
        XCTAssertEqual(t.count, 1)
        let limited = MockTransport { _ in response(429, "", headers: ["retry-after": "5"]) }
        do {
            _ = try await client(limited).title(tmdbID: 1, kind: .series)
            XCTFail("expected rate limit")
        } catch let error as MetadataError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 5))
        }
    }

    func testLanguageCodeCannotInjectIntoTheQuery() {
        XCTAssertEqual(WikidataClient.safeLanguage("de"), "de")
        XCTAssertEqual(WikidataClient.safeLanguage("pt-br"), "pt-br")
        XCTAssertEqual(WikidataClient.safeLanguage("en\" . }"), "en")
    }
}
