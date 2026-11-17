import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// The Discover calls of the TMDB client, against fixtures only (never the network; the transport is a mock).
final class DiscoverClientTests: XCTestCase {
    private func client(_ table: [String: String], status: Int = 200) -> (TMDBClient, MockTransport) {
        let transport = MockTransport.routes(table, status: status)
        return (TMDBClient(credentials: .apiKey("test-key-not-real"), transport: transport, queueConfiguration: plainQueue()), transport)
    }

    func testSimilarTitlesAreReadAndEntriesWithoutAnIDAreSkipped() async throws {
        let (c, t) = client(["/movie/603/similar": DiscoverFixtures.similarMovies])
        let hits = try await c.similar(kind: .movie, id: 603)
        XCTAssertEqual(hits.map(\.tmdbID), [701, 702])
        XCTAssertEqual(hits[0].year, 2001)
        XCTAssertNil(hits[1].year, "an empty release date is no year")
        XCTAssertEqual(t.count, 1)
        XCTAssertTrue(t.requests[0].url.absoluteString.contains("api_key=test-key-not-real"))
        XCTAssertFalse(t.requests[0].url.absoluteString.contains("example"), "only the catalogue address is used")
    }

    func testSeriesUseTheTvPath() async throws {
        let (c, t) = client(["/tv/1396/similar": DiscoverFixtures.similarMovies])
        _ = try await c.similar(kind: .series, id: 1396)
        XCTAssertEqual(t.requests.first?.url.path.hasSuffix("/tv/1396/similar"), true)
    }

    func testWatchProvidersAreGroupedByRegionAndOrderedByPriority() async throws {
        let (c, _) = client(["/movie/701/watch/providers": DiscoverFixtures.watchProviders])
        let all = try await c.watchProviders(kind: .movie, id: 701)
        XCTAssertEqual(Set(all.keys), ["US", "DE", "FR"])
        let us = try XCTUnwrap(all["US"])
        XCTAssertEqual(us.flatrate.map(\.name), ["Fixture Stream A", "Fixture Stream B"], "display priority decides the order")
        XCTAssertEqual(us.rent.map(\.name), ["Fixture Rent"])
        XCTAssertTrue(us.buy.isEmpty)
        XCTAssertEqual(us.link, "https://example.invalid/fixture/US", "the link back is kept")
        XCTAssertTrue(try XCTUnwrap(all["FR"]).isEmpty, "a region with a link only has no providers")
    }

    func testAnEmptyReplyIsNoRegionsNotAnError() async throws {
        let (c, _) = client(["/movie/9/watch/providers": DiscoverFixtures.watchProvidersEmpty])
        let all = try await c.watchProviders(kind: .movie, id: 9)
        XCTAssertTrue(all.isEmpty)
    }

    func testABadKeyIsReportedAndSecondCallUsesTheCache() async throws {
        let (bad, _) = client(["/movie/1/similar": "{}"], status: 401)
        do { _ = try await bad.similar(kind: .movie, id: 1); XCTFail("should throw") } catch { XCTAssertEqual(error as? MetadataError, .invalidAPIKey) }

        let (c, t) = client(["/movie/603/similar": DiscoverFixtures.similarMovies])
        _ = try await c.similar(kind: .movie, id: 603)
        _ = try await c.similar(kind: .movie, id: 603)
        XCTAssertEqual(t.count, 1, "the second call is answered from the cache")
    }
}
