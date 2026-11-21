import XCTest
import VideoPlayerCore
import LibraryIndex
import MetadataOnline
@testable import AppLogic

/// R341: the person page lists the library's titles with one cast member, from stored details only.
final class PersonTitlesTests: XCTestCase {
    func testNamesCompareWithoutCaseAccentsOrExtraSpaces() {
        XCTAssertEqual(PersonTitles.normalized("  Zoë   Doe "), PersonTitles.normalized("zoe doe"))
        let cast = [TitleDetails.CastMember(id: 1, name: "Sample Actor 1", role: nil)]
        XCTAssertTrue(PersonTitles.contains(cast, name: "sample actor 1"))
        XCTAssertFalse(PersonTitles.contains(cast, name: "Sample Actor 10"))
        XCTAssertFalse(PersonTitles.contains(cast, name: "   "), "an empty name matches nobody")
    }

    func testTheCountReadsAsTitles() {
        XCTAssertEqual(PersonTitles.Content(movies: [], shows: []).isEmpty, true)
        let show = SeriesSummary(id: 1, title: "S", episodeCount: 1, unwatchedCount: 1, seasonCount: 1, artworkKey: "series-1")
        XCTAssertEqual(PersonTitles.Content(movies: [], shows: [show]).countText, "1 title")
        XCTAssertEqual(PersonTitles.Content(movies: [], shows: [show, show]).countText, "2 titles")
    }

    // MARK: Stored only

    private static let movieJSON = Data(#"{"id":7,"title":"Sample Film","credits":{"cast":[{"id":1,"name":"Sample Actor 1","character":"Sample Role","order":0}]}}"#.utf8)

    func testTheStoredClientAnswersFromTheCacheAndNeverSends() async throws {
        let cache = InMemoryMetadataCache()
        // Stored long ago: an old answer is still used, since nothing newer can be asked for.
        await cache.store(Self.movieJSON, for: CacheKey(provider: "tmdb", kind: "movie", id: "7", variant: "en-US"),
                          ttl: 1, at: Date(timeIntervalSince1970: 0))
        let client = PersonTitles.storedClient(credentials: .apiKey("not-sent"), cache: cache, region: "US")
        let movie = try await client.movie(id: 7)
        XCTAssertEqual(movie.credits.cast.map(\.name), ["Sample Actor 1"])
        do {
            _ = try await client.movie(id: 8)
            XCTFail("nothing is stored for 8, and nothing may be fetched")
        } catch let error as MetadataError {
            guard case .network = error else { return XCTFail("\(error)") }
        }
        let attempts = await client.requestsSent
        XCTAssertEqual(attempts, 2, "one attempt each (no retries), and each failed in NoNetworkTransport before any network")
    }

    func testTheTransportRefusesEveryRequest() async {
        do {
            _ = try await NoNetworkTransport().send(HTTPRequest(url: URL(string: "https://example.invalid/")!, method: "GET", headers: [:]))
            XCTFail("sent")
        } catch {
            XCTAssertTrue(error is NoNetworkTransport.NotSent)
        }
        XCTAssertEqual(QueueConfiguration.storedOnly.maxRetries, 0)
    }

    #if DEBUG
    // MARK: The sample library (the UI-test fixtures, no network)

    func testSampleActorOneIsInFiveMoviesAndOneShow() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        try await UITestFixtures.seed(into: store, now: Date(timeIntervalSince1970: 1_780_000_000))
        let details: PersonTitles.Details = { key in await UITestFixtureDetails.details(key: key, store: store) }
        let one = try await PersonTitles.load(name: "Sample Actor 1", store: store, details: details)
        XCTAssertEqual(one.movies.map(\.title), ["Sample Movie 1", "Sample Movie 2", "Sample Movie 3", "Sample Movie 4", "Sample Movie 5"])
        XCTAssertEqual(one.shows.map(\.title), ["Sample Show 1"])
        let ten = try await PersonTitles.load(name: "Sample Actor 10", store: store, details: details)
        XCTAssertEqual(ten.movies.map(\.title), ["Sample Movie 2"], "only the full cast shelf has a tenth actor")
        XCTAssertTrue(ten.shows.isEmpty)
        let nobody = await PersonTitles.state(name: "Nobody", store: store, details: details)
        XCTAssertEqual(nobody, .empty(PersonTitles.noTitles("Nobody")))
    }
    #endif
}
