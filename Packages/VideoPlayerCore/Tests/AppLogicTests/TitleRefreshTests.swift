import XCTest
import LibraryIndex
import MetadataOnline
@testable import AppLogic

/// R471 (18), Part 4: Refresh Details for one title drops that title's kept online answers only, then fetches again.
final class TitleRefreshTests: XCTestCase {
    private func filledCache() async -> InMemoryMetadataCache {
        let cache = InMemoryMetadataCache()
        let keys = [
            CacheKey(provider: "tmdb", kind: "movie", id: "949", variant: "details"),
            CacheKey(provider: "tmdb", kind: "movie", id: "9490", variant: "details"),
            CacheKey(provider: "tmdb", kind: "tv", id: "1396", variant: "season-1"),
            CacheKey(provider: "tmdb", kind: "tv", id: "1396", variant: "details"),
            CacheKey(provider: "tmdb", kind: "tv", id: "77", variant: "details"),
            CacheKey(provider: "wikidata", kind: "title", id: "tmdb:movie:949", variant: "en|3"),
            CacheKey(provider: "wikidata", kind: "title", id: "name:movie:hexfall|1995", variant: "en|3"),
            CacheKey(provider: "wikidata", kind: "title", id: "name:series:show one|", variant: "en|3"),
        ]
        for key in keys { await cache.store(Data("{}".utf8), for: key, ttl: 1_000, at: Date()) }
        return cache
    }

    func testTheKeysOfOneTitle() {
        XCTAssertEqual(TitleRefresh.prefixes(tmdbID: 949, kind: .movie, name: " Hexfall "),
                       ["tmdb/movie/949/", "wikidata/title/tmdb:movie:949/", "wikidata/title/name:movie:hexfall|"])
        XCTAssertEqual(TitleRefresh.prefixes(tmdbID: nil, kind: .series, name: ""), [])
    }

    func testAMovieDropsOnlyItsOwnAnswersAndFetchesAgain() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        try await rig.store.setMetadata(itemID: id, ItemMetadata(tmdbID: 949))
        let cache = await filledCache()
        let asked = Asked()
        let result = await TitleRefresher(store: rig.store, cache: cache) { key in await asked.add(key); return true }.run(.movie(itemID: id))
        XCTAssertEqual(result.dropped, 3)
        XCTAssertEqual(result.outcome, .refreshed)
        let fetched = await asked.keys
        XCTAssertEqual(fetched, ["item-\(id)"], "fetched again, not just dropped")
        let left = await cache.keys
        XCTAssertTrue(left.contains("tmdb/movie/9490/details"), "another title with a longer id stays")
        XCTAssertTrue(left.contains("tmdb/tv/1396/details"))
    }

    func testAShowDropsItsSeasonsTooAndSaysWhenNothingAnswers() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        for e in episodes { try await rig.store.setMetadata(itemID: e.id, ItemMetadata(tmdbID: 1396)) }
        let seriesID = try XCTUnwrap(episodes.first?.seriesID)
        let cache = await filledCache()
        let result = await TitleRefresher(store: rig.store, cache: cache) { _ in false }.run(.show(seriesID: seriesID))
        XCTAssertEqual(result.dropped, 3)
        XCTAssertEqual(result.outcome, .nothingFound)
        let left = await cache.keys
        XCTAssertTrue(left.contains("tmdb/tv/77/details"))
        XCTAssertEqual(left.filter { $0.hasPrefix("tmdb/movie/") }.count, 2)
    }

    func testAnEpisodeUsesItsShowsEntriesAndTheResultWords() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let all = try await rig.episodes(ofSeriesTitle: "Show One")
        let episode = try XCTUnwrap(all.first)
        try await rig.store.setMetadata(itemID: episode.id, ItemMetadata(tmdbID: 1396))
        let cache = await filledCache()
        let result = await TitleRefresher(store: rig.store, cache: cache) { _ in true }.run(.episode(itemID: episode.id))
        XCTAssertEqual(result.dropped, 3)
        XCTAssertEqual(TitleRefresh.Target.episode(itemID: 4).detailsKey, "item-4")
        XCTAssertEqual(TitleRefresh.Target.show(seriesID: 2).detailsKey, "series-2")
        XCTAssertTrue(TitleRefresh.result(.refreshed).message.contains("edits"))
    }

    func testRefreshDetailsIsOfferedForMoviesAndShows() {
        XCTAssertTrue(ProductActions.manageList(ProductActionContext(kind: .movie)).contains(.refreshMetadata))
        XCTAssertTrue(ProductActions.manageList(ProductActionContext(kind: .show)).contains(.refreshMetadata))
    }
}

private actor Asked {
    var keys: [String] = []
    func add(_ key: String) { keys.append(key) }
}
