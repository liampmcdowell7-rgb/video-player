import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// "Your Library Only": library-facing results never include titles the user does not own, and fetches
/// happen only for matched library items. Discover is not part of this target.
final class LibraryOnlyTests: XCTestCase {

    /// Records every details call, so tests can say exactly which titles were fetched.
    final class SpyDetails: TitleDetailsProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        private func record(_ s: String) { lock.lock(); _calls.append(s); lock.unlock() }

        var movies: [Int: MovieMetadata] = [:]
        var allSeries: [Int: SeriesMetadata] = [:]
        var seasons: [String: SeasonMetadata] = [:]
        var collections: [Int: CollectionMetadata] = [:]

        func movie(id: Int) async throws -> MovieMetadata {
            record("movie:\(id)")
            guard let m = movies[id] else { throw MetadataError.notFound }
            return m
        }
        func series(id: Int) async throws -> SeriesMetadata {
            record("series:\(id)")
            guard let s = allSeries[id] else { throw MetadataError.notFound }
            return s
        }
        func season(seriesID: Int, number: Int) async throws -> SeasonMetadata {
            record("season:\(seriesID):\(number)")
            guard let s = seasons["\(seriesID)/\(number)"] else { throw MetadataError.notFound }
            return s
        }
        func collection(id: Int) async throws -> CollectionMetadata {
            record("collection:\(id)")
            guard let c = collections[id] else { throw MetadataError.notFound }
            return c
        }
    }

    final class SpyRatings: RatingsProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        var result: Result<OMDbResult, MetadataError> = .failure(.notFound)
        func ratings(imdbID: String) async throws -> OMDbResult {
            lock.withLock { _calls.append(imdbID) }
            return try result.get()
        }
    }

    private struct Rig {
        var service: LibraryMetadataService
        var catalog: FakeCatalog
        var details: SpyDetails
        var ratings: SpyRatings
        var cache: InMemoryMetadataCache
    }

    private func rig(owned: Set<String> = ["item-1"], ownedTMDB: Set<Int> = [603, 605], withRatings: Bool = true) -> Rig {
        let catalog = MatchEngineTests.catalog()
        let details = SpyDetails()
        details.movies[603] = MovieMetadata(
            ids: ProviderIDs(tmdb: 603, imdb: "tt0133093"), title: "The Matrix", overview: "TMDB overview", releaseDate: CalendarDate(year: 1999, month: 3, day: 31),
            runtimeMinutes: 136, genres: ["Action"], posterPath: "/p.jpg",
            collection: CollectionRef(id: 2344, name: "The Matrix Collection"),
            ratings: RatingSet(tmdb: Rating(source: .tmdb, percent: 82, display: "8.2/10", votes: 1))
        )
        details.movies[841] = MovieMetadata(ids: ProviderIDs(tmdb: 841), title: "Dune", releaseDate: CalendarDate(year: 1984, month: 12, day: 14))
        details.allSeries[1396] = SeriesMetadata(ids: ProviderIDs(tmdb: 1396, imdb: "tt0903747"), name: "Breaking Bad", firstAirDate: CalendarDate(year: 2008, month: 1, day: 20), seasons: [SeasonSummary(seasonNumber: 1, episodeCount: 3)])
        details.seasons["1396/1"] = SeasonMetadata(seriesID: 1396, seasonNumber: 1, episodes: [
            EpisodeMetadata(seriesID: 1396, seasonNumber: 1, episodeNumber: 1, name: "Pilot", overview: "Ep text", runtimeMinutes: 58),
            EpisodeMetadata(seriesID: 1396, seasonNumber: 1, episodeNumber: 2, name: "Cat's in the Bag...", runtimeMinutes: 48)
        ])
        details.collections[2344] = CollectionMetadata(id: 2344, name: "The Matrix Collection", parts: [
            CollectionPart(tmdbID: 603, title: "The Matrix", releaseDate: CalendarDate(year: 1999, month: 3, day: 31)),
            CollectionPart(tmdbID: 604, title: "The Matrix Reloaded", releaseDate: CalendarDate(year: 2003, month: 5, day: 15)),
            CollectionPart(tmdbID: 605, title: "The Matrix Revolutions", releaseDate: CalendarDate(year: 2003, month: 11, day: 5))
        ])
        let ratings = SpyRatings()
        let cache = InMemoryMetadataCache()
        let fix = FixMatchService(engine: MatchEngine(provider: catalog), store: InMemoryMatchStore())
        let service = LibraryMetadataService(library: FakeLibrary(items: owned, tmdbIDs: ownedTMDB), fixMatch: fix, details: details, ratings: withRatings ? ratings : nil, cache: cache)
        return Rig(service: service, catalog: catalog, details: details, ratings: ratings, cache: cache)
    }

    private let file = FileIdentity(path: "/movies/The Matrix (1999).mkv")
    private let movieInput = MatchInput(parsed: P.movie("The Matrix", year: 1999))

    // MARK: Ownership gate

    func testAnItemNotInTheLibraryIsRejectedBeforeAnyProviderIsCalled() async {
        let r = rig()
        do {
            _ = try await r.service.resolve(itemID: "not-mine", file: file, input: movieInput)
            XCTFail("expected notInLibrary")
        } catch {
            XCTAssertEqual(error as? MetadataError, .notInLibrary)
        }
        XCTAssertTrue(r.catalog.calls.isEmpty, "no search")
        XCTAssertTrue(r.details.calls.isEmpty, "no details")
        XCTAssertTrue(r.ratings.calls.isEmpty, "no ratings")
    }

    func testFixMatchSearchAndChoiceAlsoRequireAnOwnedItem() async {
        let r = rig()
        do {
            _ = try await r.service.fixMatchCandidates(itemID: "not-mine", query: "Dune", year: nil, kind: .movie, input: nil)
            XCTFail("expected notInLibrary")
        } catch {
            XCTAssertEqual(error as? MetadataError, .notInLibrary)
        }
        do {
            _ = try await r.service.choose(itemID: "not-mine", candidate: .movie(841, "Dune", year: 1984), file: file, input: movieInput, scope: .file)
            XCTFail("expected notInLibrary")
        } catch {
            XCTAssertEqual(error as? MetadataError, .notInLibrary)
        }
        XCTAssertTrue(r.catalog.calls.isEmpty)
        XCTAssertTrue(r.details.calls.isEmpty)
    }

    func testCollectionRequiresAnOwnedItem() async throws {
        // An item that was owned when matched but has since left the library is refused.
        let owned = rig()
        let resolution = try await owned.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        let gone = rig(owned: [])
        do {
            _ = try await gone.service.collection(for: item)
            XCTFail("expected notInLibrary")
        } catch {
            XCTAssertEqual(error as? MetadataError, .notInLibrary)
        }
        XCTAssertTrue(gone.details.calls.isEmpty)
    }

    // MARK: Fetches only for matched library items

    func testOnlyTheMatchedTitleIsFetched() async throws {
        let r = rig()
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(item.match.tmdbID, 603)
        XCTAssertEqual(r.details.calls, ["movie:603"], "the sequel that the search also returned is never fetched")
        XCTAssertEqual(item.movie?.title, "The Matrix")
        XCTAssertEqual(item.itemID, "item-1")
    }

    func testNeedsReviewFetchesNothingAndCarriesNoCandidates() async throws {
        let r = rig()
        let ambiguous = MatchInput(parsed: P.movie("Dune"))
        let resolution = try await r.service.resolve(itemID: "item-1", file: FileIdentity(path: "/movies/dune.mkv"), input: ambiguous)
        // Exhaustive: if a case that carries titles is ever added, this stops compiling.
        switch resolution {
        case .needsReview(let itemID, let reason):
            XCTAssertEqual(itemID, "item-1")
            XCTAssertEqual(reason, .closeScores)
        case .matched, .unmatched:
            XCTFail("expected needsReview, got \(resolution)")
        }
        XCTAssertTrue(r.details.calls.isEmpty, "nothing is fetched for an item that needs review")
        XCTAssertTrue(r.ratings.calls.isEmpty)
        let text = String(describing: resolution)
        XCTAssertFalse(text.contains("1984") || text.contains("2021") || text.contains("438631") || text.contains("841"), "no candidate leaks into the library-facing value: \(text)")
    }

    func testUnmatchedFetchesNothing() async throws {
        let r = rig()
        let resolution = try await r.service.resolve(itemID: "item-1", file: FileIdentity(path: "/x.mkv"), input: MatchInput(parsed: P.movie("Zzzyxx Qqwwpp")))
        guard case .unmatched(let id) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(id, "item-1")
        XCTAssertTrue(r.details.calls.isEmpty)
    }

    func testTheLibraryFacingValuesHaveNoTitleListsOtherThanTheMatch() async throws {
        let r = rig()
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        let text = String(describing: item)
        for foreign in ["Reloaded", "Revolutions", "Dune"] {
            XCTAssertFalse(text.contains(foreign), "\(foreign) must not appear in a library item: \(text)")
        }
    }

    // MARK: Collections

    func testCollectionsAreCutDownToOwnedParts() async throws {
        let r = rig(ownedTMDB: [603, 605])
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        let owned = try await r.service.collection(for: item)
        let collection = try XCTUnwrap(owned)
        XCTAssertEqual(collection.name, "The Matrix Collection")
        XCTAssertEqual(collection.ownedParts.map(\.tmdbID), [603, 605])
        XCTAssertFalse(String(describing: collection).contains("Reloaded"), "a part the user does not own is not in the result")
    }

    func testACollectionWithNothingOwnedBeyondTheItemListsOnlyThatItem() async throws {
        let r = rig(ownedTMDB: [603])
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        let collection = try await r.service.collection(for: item)
        XCTAssertEqual(collection?.ownedParts.map(\.tmdbID), [603])
    }

    func testNoCollectionForATitleWithoutOne() async throws {
        let r = rig()
        let resolution = try await r.service.resolve(itemID: "item-1", file: FileIdentity(path: "/movies/dune.mkv"), input: MatchInput(parsed: P.movie("Dune", year: 1984)))
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        let c = try await r.service.collection(for: item)
        XCTAssertNil(c)
        XCTAssertFalse(r.details.calls.contains { $0.hasPrefix("collection") })
    }

    // MARK: Series

    func testSeriesItemLoadsItsEpisodesAndNothingElse() async throws {
        let r = rig()
        let input = MatchInput(parsed: P.episode("Breaking Bad", season: 1, episodes: [1, 2]))
        let resolution = try await r.service.resolve(itemID: "item-1", file: FileIdentity(path: "/tv/Breaking Bad/S01E01E02.mkv"), input: input)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(item.series?.name, "Breaking Bad")
        XCTAssertEqual(item.episodes.map(\.name), ["Pilot", "Cat's in the Bag..."])
        XCTAssertEqual(r.details.calls, ["series:1396", "season:1396:1"])
        XCTAssertEqual(item.merged.fields.title, "Pilot", "an episode file shows the episode, not the series")
        XCTAssertNil(item.movie)
    }

    // MARK: Ratings

    func testOMDbScoresAreAddedToTheTMDBScoreByIMDbID() async throws {
        let r = rig()
        r.ratings.result = .success(OMDbResult(imdbID: "tt0133093", title: "The Matrix", year: "1999", ratings: RatingSet(imdb: Rating(source: .imdb, percent: 87, display: "8.7/10"), rottenTomatoes: Rating(source: .rottenTomatoes, percent: 83, display: "83%"))))
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(r.ratings.calls, ["tt0133093"])
        XCTAssertEqual(item.ratings.visible.map(\.label), ["TMDB", "IMDb", "Rotten Tomatoes"], "Metacritic is missing and simply not there")
        XCTAssertEqual(item.movie?.ratings, item.ratings)
    }

    func testRatingsFailuresDoNotFailTheItem() async throws {
        for failure in [MetadataError.quotaExhausted, .invalidAPIKey, .notFound, .network("down")] {
            let r = rig()
            r.ratings.result = .failure(failure)
            let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
            guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
            XCTAssertEqual(item.ratings.visible.map(\.label), ["TMDB"], "\(failure)")
        }
    }

    func testNoOMDbKeyMeansNoOMDbCall() async throws {
        let r = rig(withRatings: false)
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(item.ratings.visible.map(\.label), ["TMDB"])
        XCTAssertTrue(r.ratings.calls.isEmpty)
    }

    func testTitleWithoutAnIMDbIDIsNotLookedUpInOMDb() async throws {
        let r = rig()
        let resolution = try await r.service.resolve(itemID: "item-1", file: FileIdentity(path: "/movies/dune.mkv"), input: MatchInput(parsed: P.movie("Dune", year: 1984)))
        guard case .matched = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertTrue(r.ratings.calls.isEmpty)
    }

    // MARK: Merging in the service

    func testSidecarDataWinsOverOnlineDataInTheLibraryItem() async throws {
        let r = rig()
        let local = LocalMetadataInput(title: "My Title", poster: .local("poster.jpg"))
        let embedded = EmbeddedMetadataInput(overview: "unused", certification: "NR")
        let resolution = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput, local: local, embedded: embedded)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(item.merged.fields.title, "My Title")
        XCTAssertEqual(item.merged.source(of: .title), .sidecar)
        XCTAssertEqual(item.merged.fields.overview, "TMDB overview")
        XCTAssertEqual(item.merged.source(of: .overview), .tmdb)
        XCTAssertEqual(item.merged.fields.certification, "NR")
        XCTAssertEqual(item.merged.source(of: .certification), .embedded)
        XCTAssertEqual(item.merged.fields.poster, .local("poster.jpg"))
    }

    // MARK: Fix Match through the service

    func testChoosingAMatchLoadsTheChosenTitleAndIsRememberedForTheItem() async throws {
        let r = rig()
        let dune = SearchHit.movie(841, "Dune", year: 1984)
        let (change, item) = try await r.service.choose(itemID: "item-1", candidate: dune, file: file, input: movieInput, scope: .file)
        XCTAssertEqual(item.match.tmdbID, 841)
        XCTAssertEqual(item.match.source, .userChosen)
        XCTAssertEqual(r.details.calls, ["movie:841"])
        let again = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let second) = again else { return XCTFail("got \(again)") }
        XCTAssertEqual(second.match.tmdbID, 841)
        XCTAssertEqual(second.match.source, .stored)
        try await r.service.undo(change)
        let third = try await r.service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let reverted) = third else { return XCTFail("got \(third)") }
        XCTAssertEqual(reverted.match.tmdbID, 603)
    }

    func testFixMatchCandidatesAreOnlyForAnOwnedItem() async throws {
        let r = rig()
        let list = try await r.service.fixMatchCandidates(itemID: "item-1", query: "Dune", year: nil, kind: .movie, input: nil)
        XCTAssertFalse(list.isEmpty)
        XCTAssertTrue(r.details.calls.isEmpty, "searching for candidates fetches no details")
    }

    // MARK: Refresh

    func testRefreshDropsCachedDataForTheItem() async throws {
        let r = rig()
        await r.cache.store(Data("x".utf8), for: CacheKey(provider: "tmdb", kind: "movie", id: "603", variant: "en-US"), ttl: 1, at: Date())
        await r.cache.store(Data("x".utf8), for: CacheKey(provider: "tmdb", kind: "movie", id: "604", variant: "en-US"), ttl: 1, at: Date())
        let n = await r.service.refresh(.item(ProviderIDs(tmdb: 603), kind: .movie))
        XCTAssertEqual(n, 1)
        let keys = await r.cache.keys
        XCTAssertEqual(keys, ["tmdb/movie/604/en-US"])
    }

    // MARK: Whole stack against the mock transport

    func testEndToEndWithTheRealClientOnlyTouchesTheMatchedTitle() async throws {
        let transport = MockTransport.routes([
            "/search/movie": Fixtures.searchMovieMatrix,
            "/movie/603": Fixtures.movie603,
            "/collection/2344": Fixtures.collection2344
        ])
        let clock = FakeClock()
        let tmdb = TMDBClient(credentials: .apiKey("test-key-not-real"), transport: transport, queueConfiguration: plainQueue(), clock: clock)
        let fix = FixMatchService(engine: MatchEngine(provider: tmdb), store: InMemoryMatchStore())
        let service = LibraryMetadataService(library: FakeLibrary(items: ["item-1"], tmdbIDs: [603, 605]), fixMatch: fix, details: tmdb)

        let resolution = try await service.resolve(itemID: "item-1", file: file, input: movieInput)
        guard case .matched(let item) = resolution else { return XCTFail("got \(resolution)") }
        XCTAssertEqual(item.movie?.title, "The Matrix")
        XCTAssertEqual(item.movie?.certification, "R")
        let collection = try await service.collection(for: item)
        XCTAssertEqual(collection?.ownedParts.map(\.title), ["The Matrix", "The Matrix Revolutions"])

        let paths = transport.requests.map { $0.url.path }
        XCTAssertEqual(paths, ["/3/search/movie", "/3/movie/603", "/3/collection/2344"])
        for banned in ["discover", "trending", "recommendations", "similar", "popular", "upcoming", "now_playing", "top_rated", "watch/providers", "/person/"] {
            XCTAssertFalse(paths.contains { $0.contains(banned) }, "no \(banned) request")
        }
    }

    func testEndToEndNotInLibraryMakesNoRequest() async {
        let transport = MockTransport.routes([:])
        let tmdb = TMDBClient(credentials: .apiKey("test-key-not-real"), transport: transport, queueConfiguration: plainQueue(), clock: FakeClock())
        let fix = FixMatchService(engine: MatchEngine(provider: tmdb), store: InMemoryMatchStore())
        let service = LibraryMetadataService(library: FakeLibrary(items: []), fixMatch: fix, details: tmdb)
        do {
            _ = try await service.resolve(itemID: "stranger", file: file, input: movieInput)
            XCTFail("expected notInLibrary")
        } catch {
            XCTAssertEqual(error as? MetadataError, .notInLibrary)
        }
        XCTAssertEqual(transport.count, 0)
    }
}
