import XCTest
import MetadataOnline
import UserData
import LibraryIndex
@testable import AppLogic

// FIXTURE: every title, id and provider below is invented test data; no service is contacted (the data source is a fake).

final class FixtureDiscoverSource: DiscoverDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var seriesByID: [Int: SeriesMetadata] = [:]
    var seasons: [String: SeasonMetadata] = [:]
    var movies: [Int: MovieMetadata] = [:]
    var collections: [Int: CollectionMetadata] = [:]
    var similarByKey: [String: [SearchHit]] = [:]
    var providers: [String: [String: WatchAvailability]] = [:]
    var failure: MetadataError?

    var calls: [String] { lock.withLock { _calls } }
    private func record(_ s: String) { lock.withLock { _calls.append(s) } }

    func series(id: Int) async throws -> SeriesMetadata { record("series:\(id)"); if let failure { throw failure }; guard let s = seriesByID[id] else { throw MetadataError.notFound }; return s }
    func season(seriesID: Int, number: Int) async throws -> SeasonMetadata { record("season:\(seriesID):\(number)"); if let failure { throw failure }; guard let s = seasons["\(seriesID)/\(number)"] else { throw MetadataError.notFound }; return s }
    func movie(id: Int) async throws -> MovieMetadata { record("movie:\(id)"); if let failure { throw failure }; guard let m = movies[id] else { throw MetadataError.notFound }; return m }
    func collection(id: Int) async throws -> CollectionMetadata { record("collection:\(id)"); if let failure { throw failure }; guard let c = collections[id] else { throw MetadataError.notFound }; return c }
    func similar(kind: TitleKind, id: Int) async throws -> [SearchHit] { record("similar:\(kind.rawValue):\(id)"); if let failure { throw failure }; return similarByKey["\(kind.rawValue)-\(id)"] ?? [] }
    func watchProviders(kind: TitleKind, id: Int) async throws -> [String: WatchAvailability] { record("watch:\(kind.rawValue):\(id)"); return providers["\(kind.rawValue)-\(id)"] ?? [:] }
}

final class MemoryWatchlist: WatchlistStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [UDWatchlistEntry] = []
    func entries() -> [UDWatchlistEntry] { lock.withLock { list } }
    func add(_ entry: UDWatchlistEntry) { lock.withLock { list.removeAll { $0.kind == entry.kind && $0.tmdbID == entry.tmdbID }; list.append(entry) } }
    func remove(kind: TitleKind, tmdbID: Int) { lock.withLock { list.removeAll { $0.kind == kind.rawValue && $0.tmdbID == tmdbID } } }
}

struct FixedLibrary: DiscoverLibraryProviding {
    var value: DiscoverLibrary
    func discoverLibrary() async throws -> DiscoverLibrary { value }
}

private let nowDate = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14
private func d(_ s: String) -> CalendarDate? { CalendarDate(s) }

private func episode(_ series: Int, _ s: Int, _ e: Int, air: String?) -> EpisodeMetadata {
    EpisodeMetadata(seriesID: series, seasonNumber: s, episodeNumber: e, name: "Ep \(s)x\(e)", airDate: air.flatMap { CalendarDate($0) })
}

private func availability(_ region: String, stream: [String] = [], rent: [String] = [], buy: [String] = []) -> WatchAvailability {
    func p(_ names: [String]) -> [WatchProvider] { names.enumerated().map { WatchProvider(id: $0.offset + 1, name: $0.element) } }
    return WatchAvailability(region: region, link: "https://example.invalid/\(region)", flatrate: p(stream), rent: p(rent), buy: p(buy))
}

final class DiscoverEngineTests: XCTestCase {
    private func engine(_ source: FixtureDiscoverSource, region: String = "US") -> DiscoverEngine {
        DiscoverEngine(source: source, region: region, now: { nowDate })
    }

    private func showSource() -> FixtureDiscoverSource {
        let src = FixtureDiscoverSource()
        src.seriesByID[10] = SeriesMetadata(ids: ProviderIDs(tmdb: 10), name: "Fixture Show")
        src.seasons["10/1"] = SeasonMetadata(seriesID: 10, seasonNumber: 1, episodes: [
            episode(10, 1, 1, air: "2020-01-01"), episode(10, 1, 2, air: "2020-01-08"), episode(10, 1, 3, air: "2020-01-15"),
            episode(10, 1, 4, air: "2099-01-01"), episode(10, 1, 5, air: nil)])
        src.seasons["10/2"] = SeasonMetadata(seriesID: 10, seasonNumber: 2, episodes: [episode(10, 2, 1, air: "2021-01-01")])
        return src
    }

    func testMissingEpisodesListOnlyAiredOnesFromSeasonsTheUserHas() async {
        let src = showSource()
        var problems = ProblemCollector()
        let library = DiscoverLibrary(ownedSeriesIDs: [10], ownedEpisodes: [10: [EpisodeKey(season: 1, episode: 1)]])
        let groups = await engine(src).missingEpisodes(library, &problems)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].seriesTitle, "Fixture Show")
        XCTAssertEqual(groups[0].episodes.map(\.code), ["S1, E2", "S1, E3"], "episode 4 is unaired, 5 has no date, season 2 is not owned at all")
        XCTAssertFalse(src.calls.contains("season:10:2"), "a season the user never collected is not even asked for")
        XCTAssertTrue(problems.sentences.isEmpty)
    }

    func testADoubleEpisodeFileCountsBothNumbersAndAFullSeasonHasNoGap() async {
        let src = showSource()
        var problems = ProblemCollector()
        let library = DiscoverLibrary(ownedSeriesIDs: [10], ownedEpisodes: [10: [EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 2), EpisodeKey(season: 1, episode: 3)]])
        let groups = await engine(src).missingEpisodes(library, &problems)
        XCTAssertTrue(groups.isEmpty)
    }

    func testCollectionGapsListReleasedPartsNotOwnedAndCountWhatIsOwned() async {
        let src = FixtureDiscoverSource()
        let ref = CollectionRef(id: 500, name: "Fixture Saga")
        src.movies[1] = MovieMetadata(ids: ProviderIDs(tmdb: 1), title: "Part 1", collection: ref)
        src.movies[2] = MovieMetadata(ids: ProviderIDs(tmdb: 2), title: "Part 2", collection: ref)
        src.collections[500] = CollectionMetadata(id: 500, name: "Fixture Saga", parts: [
            CollectionPart(tmdbID: 1, title: "Part 1", releaseDate: d("2001-01-01")),
            CollectionPart(tmdbID: 2, title: "Part 2", releaseDate: d("2003-01-01")),
            CollectionPart(tmdbID: 3, title: "Part 3", releaseDate: d("2005-01-01")),
            CollectionPart(tmdbID: 4, title: "Part 4 (future)", releaseDate: d("2099-01-01")),
            CollectionPart(tmdbID: 0 + 5, title: "Part 0", releaseDate: d("1999-01-01"))])
        src.providers["movie-3"] = ["US": availability("US", stream: ["Fixture Stream"])]
        var problems = ProblemCollector()
        let gaps = await engine(src).collectionGaps(DiscoverLibrary(ownedMovieIDs: [1, 2]), listed: ["movie-5"], &problems)
        XCTAssertEqual(gaps.count, 1, "two owned parts of one collection make one gap entry, fetched once")
        XCTAssertEqual(src.calls.filter { $0 == "collection:500" }.count, 1)
        XCTAssertEqual(gaps[0].ownedCount, 2)
        XCTAssertEqual(gaps[0].missing.map(\.title), ["Part 0", "Part 3"], "oldest first; the unreleased part is not a gap")
        XCTAssertEqual(gaps[0].missing[1].watch?.stream, ["Fixture Stream"])
        XCTAssertTrue(gaps[0].missing[0].onWatchlist, "already on the watchlist is flagged")
    }

    func testSimilarExcludesOwnedTitlesDuplicatesAndExplainsWhy() async {
        let src = FixtureDiscoverSource()
        src.similarByKey["movie-1"] = [SearchHit(tmdbID: 20, kind: .movie, title: "Owned Already", popularity: 99),
                                       SearchHit(tmdbID: 21, kind: .movie, title: "New A", popularity: 5),
                                       SearchHit(tmdbID: 22, kind: .movie, title: "New B", popularity: 50)]
        src.similarByKey["series-2"] = [SearchHit(tmdbID: 22, kind: .movie, title: "New B", popularity: 50),
                                        SearchHit(tmdbID: 30, kind: .series, title: "New Show", popularity: 1)]
        let library = DiscoverLibrary(ownedMovieIDs: [1, 20], ownedSeriesIDs: [2], seeds: [DiscoverSeed(kind: .movie, tmdbID: 1, title: "Seed Film"), DiscoverSeed(kind: .series, tmdbID: 2, title: "Seed Show")])
        var problems = ProblemCollector()
        let out = await engine(src).similar(library, owned: ["movie-1", "movie-20", "series-2"], listed: [], &problems)
        XCTAssertEqual(out.map(\.title), ["New B", "New A", "New Show"], "most popular first within a seed; a repeat is listed once")
        XCTAssertEqual(out[0].reason, "Similar to Seed Film")
        XCTAssertEqual(out[2].reason, "Similar to Seed Show")
    }

    func testWhereToWatchUsesOnlyTheUsersRegionAndSaysNothingWhenThereIsNone() async {
        let src = FixtureDiscoverSource()
        src.providers["movie-1"] = ["US": availability("US", stream: ["A", "B"], rent: ["C"]), "DE": availability("DE", buy: ["Only DE"])]
        let us = await engine(src, region: "us").watch(.movie, 1)
        XCTAssertEqual(us?.stream, ["A", "B"])
        XCTAssertEqual(us?.rent, ["C"])
        XCTAssertEqual(us?.summary, "Stream: A, B. Rent: C.")
        XCTAssertEqual(us?.link, "https://example.invalid/US", "the link back to the data supplier's page is kept")
        let de = await engine(src, region: "DE").watch(.movie, 1)
        XCTAssertEqual(de?.buy, ["Only DE"])
        let fr = await engine(src, region: "FR").watch(.movie, 1)
        XCTAssertNil(fr, "no data for the region is nil, never a guess from another region")
        let unknown = await engine(src).watch(.movie, 404)
        XCTAssertNil(unknown)
    }

    func testAWrongKeyStopsAskingAndSaysSoOnce() async {
        let src = showSource()
        src.failure = .invalidAPIKey
        let library = DiscoverLibrary(ownedMovieIDs: [1, 2, 3], ownedSeriesIDs: [10, 11], ownedEpisodes: [10: [EpisodeKey(season: 1, episode: 1)], 11: [EpisodeKey(season: 1, episode: 1)]],
                                      seeds: [DiscoverSeed(kind: .movie, tmdbID: 1, title: "S")])
        let content = await engine(src).build(library: library, watchlist: [])
        XCTAssertTrue(content.isEmpty)
        XCTAssertFalse(content.problems.isEmpty)
        XCTAssertTrue(content.problems.allSatisfy { $0.contains("Settings > Online Lookup") })
        XCTAssertLessThanOrEqual(src.calls.filter { $0.hasPrefix("series:") }.count, 1, "stopped after the first rejection")
    }

    func testTheWatchlistHidesTitlesNowOwned() async {
        let src = FixtureDiscoverSource()
        src.providers["movie-8"] = ["US": availability("US", rent: ["R"])]
        let list = [UDWatchlistEntry(kind: "movie", tmdbID: 8, title: "Wanted", year: 2010, addedAt: nowDate),
                    UDWatchlistEntry(kind: "movie", tmdbID: 9, title: "Got It", year: 2011, addedAt: nowDate)]
        let content = await engine(src).build(library: DiscoverLibrary(ownedMovieIDs: [9]), watchlist: list)
        XCTAssertEqual(content.watchlist.map(\.title), ["Wanted"])
        XCTAssertEqual(content.watchlist[0].watch?.rent, ["R"])
        XCTAssertTrue(content.watchlist[0].onWatchlist)
    }
}

final class DiscoverViewModelTests: XCTestCase {
    func testWithNoKeyTheScreenSaysExactlyWhatIsNeededAndAsksNothing() async {
        var vm = DiscoverViewModel(source: nil, library: FixedLibrary(value: DiscoverLibrary(ownedMovieIDs: [1])), watchlist: MemoryWatchlist())
        await vm.load()
        guard case .empty(let empty) = vm.state else { return XCTFail("state \(vm.state)") }
        XCTAssertEqual(empty.title, "Discover Needs a Key")
        XCTAssertEqual(empty.reason, .needsKey, "#15 10.1: drawn with a key symbol")
        XCTAssertTrue(empty.message.contains("Settings > Online Lookup"))
        XCTAssertTrue(empty.message.contains("TMDB key"))
    }

    func testAnEmptyLibraryAndWatchlistSaysThereIsNothingToSuggest() async {
        var vm = DiscoverViewModel(source: FixtureDiscoverSource(), library: FixedLibrary(value: DiscoverLibrary()), watchlist: MemoryWatchlist())
        await vm.load()
        XCTAssertEqual(vm.state, .empty(DiscoverViewModel.nothingYet))
    }

    func testFailureInEverySectionIsAnErrorStateWithTheReason() async {
        let src = FixtureDiscoverSource()
        src.failure = .network("down")
        let library = DiscoverLibrary(ownedMovieIDs: [1], seeds: [DiscoverSeed(kind: .movie, tmdbID: 1, title: "S")])
        var vm = DiscoverViewModel(source: src, library: FixedLibrary(value: library), watchlist: MemoryWatchlist())
        await vm.load()
        guard case .failed(let error) = vm.state else { return XCTFail("state \(vm.state)") }
        XCTAssertTrue(error.message.contains("could not be reached"))
    }

    func testTogglingTheWatchlistUpdatesTheScreenAndTheStore() async throws {
        let src = FixtureDiscoverSource()
        src.similarByKey["movie-1"] = [SearchHit(tmdbID: 21, kind: .movie, title: "New A", popularity: 5)]
        let list = MemoryWatchlist()
        let library = DiscoverLibrary(ownedMovieIDs: [1], seeds: [DiscoverSeed(kind: .movie, tmdbID: 1, title: "Seed")])
        var vm = DiscoverViewModel(source: src, library: FixedLibrary(value: library), watchlist: list)
        await vm.load()
        var content = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(content.similar.count, 1)
        XCTAssertFalse(content.similar[0].onWatchlist)
        vm.toggleWatchlist(content.similar[0], now: nowDate)
        content = try XCTUnwrap(vm.state.content)
        XCTAssertTrue(content.similar[0].onWatchlist)
        XCTAssertEqual(content.watchlist.map(\.title), ["New A"])
        XCTAssertEqual(list.entries().map(\.tmdbID), [21])
        vm.toggleWatchlist(content.similar[0], now: nowDate)
        content = try XCTUnwrap(vm.state.content)
        XCTAssertTrue(content.watchlist.isEmpty)
        XCTAssertTrue(list.entries().isEmpty)
    }
}

final class StoreDiscoverLibraryTests: XCTestCase {
    func testOnlyMatchedItemsCountAndEpisodesAreCollectedPerSeries() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        let aftlander = try await rig.movieID("Aftlander")
        try await rig.store.setMetadata(itemID: hexfall, ItemMetadata(tmdbID: 949))
        try await rig.store.setFavorite(itemID: hexfall, favorite: true)
        _ = aftlander   // never matched: must not appear
        let eps = try await rig.episodes(ofSeriesTitle: "Show One")
        for e in eps where e.season != 0 { try await rig.store.setMetadata(itemID: e.id, ItemMetadata(tmdbID: 1396)) }
        try await rig.store.updateProgress(itemID: try XCTUnwrap(eps.first { $0.season == 1 && $0.episode == 1 }).id, position: 100, duration: 1000, at: epoch)

        let library = try await StoreDiscoverLibrary(store: rig.store).discoverLibrary()
        XCTAssertEqual(library.ownedMovieIDs, [949])
        XCTAssertEqual(library.ownedSeriesIDs, [1396])
        XCTAssertEqual(library.ownedEpisodes[1396], [EpisodeKey(season: 1, episode: 1), EpisodeKey(season: 1, episode: 2), EpisodeKey(season: 1, episode: 3), EpisodeKey(season: 2, episode: 1)])
        XCTAssertEqual(library.seeds.map(\.tmdbID), [949, 1396], "the favorite first, then the played show; unplayed titles are not seeds")
    }
}

/// #15 10.2: the Files tab's empty state talks about folders, not about movies and shows.
final class FilesEmptyStateTests: XCTestCase {
    func testTheFilesEmptyStateSaysItBrowsesFolders() {
        let e = HomeViewModel.noSourcesForFiles
        XCTAssertEqual(e.reason, .noSources)
        XCTAssertEqual(e.message, "Add a server or a shared folder to browse its folders here.")
        XCTAssertFalse(e.message.contains("movies and shows"))
        XCTAssertEqual(e.actionTitle, "Add a Source")
    }
}
