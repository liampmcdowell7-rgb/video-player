import XCTest
import LibraryIndex
@testable import AppLogic

/// R471 (25): Related on the show page, from the library's own shows that share a genre; genres kept once a page has
/// read them. FIXTURE: invented shows and genres.
final class RelatedShowsTests: XCTestCase {
    private func episodeIDs(_ rig: LibraryRig, _ title: String) async throws -> [Int64] {
        try await rig.episodes(ofSeriesTitle: title).map(\.id)
    }

    func testAShowFindsTheOtherShowsThatShareItsGenresButNotItself() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let recorder = GenreRecorder()
        let one = try await episodeIDs(rig, "Show One")
        let two = try await episodeIDs(rig, "Show Two")
        let oneEpisodes = try await rig.episodes(ofSeriesTitle: "Show One")
        let twoEpisodes = try await rig.episodes(ofSeriesTitle: "Show Two")
        let oneID = try XCTUnwrap(oneEpisodes.first?.seriesID)
        let twoID = try XCTUnwrap(twoEpisodes.first?.seriesID)

        var none = try await RelatedShows.find(seriesID: oneID, genres: ["Drama"], store: rig.store)
        XCTAssertTrue(none.isEmpty, "no genres in the library yet")

        let written = await recorder.record(["Drama", "Mystery"], itemIDs: one, store: rig.store)
        XCTAssertEqual(written, one.count)
        await recorder.record(["Drama"], itemIDs: two, store: rig.store)

        let related = try await RelatedShows.find(seriesID: oneID, genres: ["Drama", "Mystery"], store: rig.store)
        XCTAssertEqual(related.map(\.id), [twoID], "the show itself is left out")
        XCTAssertEqual(related.first?.title, "Show Two")
        XCTAssertEqual(related.first?.episodeCount, 1)
        XCTAssertEqual(related.first?.artworkKey, "series-" + String(twoID))
        none = try await RelatedShows.find(seriesID: oneID, genres: ["Western"], store: rig.store)
        XCTAssertTrue(none.isEmpty)
        let noGenres = try await RelatedShows.find(seriesID: oneID, genres: [" "], store: rig.store)
        XCTAssertTrue(noGenres.isEmpty, "no genres, no shelf")
    }

    func testTheRecorderWritesEachTitleOnceAndAgainOnlyWhenItsGenresChange() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        let recorder = GenreRecorder()
        let first = await recorder.record(["Drama", " Crime "], itemIDs: [hexfall], store: rig.store)
        let same = await recorder.record(["Crime", "Drama"], itemIDs: [hexfall], store: rig.store)
        let empty = await recorder.record([], itemIDs: [hexfall], store: rig.store)
        let changed = await recorder.record(["Drama"], itemIDs: [hexfall], store: rig.store)
        XCTAssertEqual([first, same, empty, changed], [1, 0, 0, 1])

        // The movie page's Related now finds the movie by its genre (R471 (7) had no genres to match).
        let query = try XCTUnwrap(RelatedTitles.query(kind: .movie, genres: ["Drama"]))
        let found = try await rig.store.page(query, limit: RelatedTitles.candidateLimit, offset: 0)
        XCTAssertEqual(found.map(\.id), [hexfall])
    }

    func testAShowsCardCountsAllItsEpisodes() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        let id = try XCTUnwrap(episodes.first?.seriesID)
        let card = try XCTUnwrap(RelatedShows.summary(id: id, episodes: episodes))
        XCTAssertEqual(card.episodeCount, 5)
        XCTAssertEqual(card.seasonCount, 2, "Season 0 specials do not count as a season")
        XCTAssertEqual(card.unwatchedCount, 5)
        XCTAssertNil(RelatedShows.summary(id: id, episodes: []))
    }
}
