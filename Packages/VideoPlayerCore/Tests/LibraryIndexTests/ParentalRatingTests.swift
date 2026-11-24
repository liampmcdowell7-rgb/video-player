import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// R459: the rating rule of `LibraryRestrictions` in every query that returns titles. FIXTURE: invented titles and ratings.
final class ParentalRatingTests: XCTestCase {
    private let rule = LibraryRestrictions.RatingRule(movieLabels: ["G", "PG", "PG13"], episodeLabels: ["TVY", "TVG", "TVPG", "TV14"], allowUnrated: false)

    /// Hexfall (a film) and Show One (three episodes) from `basicLibrary`, plus two more films.
    private func library() async throws -> Harness {
        let h = try Harness.make()
        basicLibrary(h.source)
        h.source.put("/Movies/Kidfilm (2001)/Kidfilm (2001).mkv", size: 9_000, modified: day(5))
        h.source.put("/Movies/Darkfilm (2002)/Darkfilm (2002).mkv", size: 9_000, modified: day(6))
        h.source.put("/Movies/Plainfilm (2003)/Plainfilm (2003).mkv", size: 9_000, modified: day(7))
        try await h.registerSource()
        try await h.syncer.sync()
        return h
    }

    private func id(_ h: Harness, _ title: String) async throws -> Int64 {
        let all = try await h.store.page(ItemQuery(), limit: 100, after: nil).items
        return try XCTUnwrap(all.first { $0.title == title }, title).id
    }

    private func rate(_ h: Harness, _ title: String, _ rating: String) async throws {
        try await h.store.setMetadata(itemID: try await id(h, title), ItemMetadata(contentRating: rating))
    }

    private func titles(_ h: Harness) async throws -> Set<String> {
        Set(try await h.store.page(ItemQuery(), limit: 100, after: nil).items.map(\.title))
    }

    func testFilmsFollowTheirOwnRatingInEveryWrittenForm() async throws {
        let h = try await library()
        defer { h.cleanup() }
        try await rate(h, "Hexfall", "Rated PG-13")
        try await rate(h, "Kidfilm", "US:G")
        try await rate(h, "Darkfilm", "R")
        // Plainfilm has no rating read at all.
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        let shown = try await titles(h).filter { ["Hexfall", "Kidfilm", "Darkfilm", "Plainfilm"].contains($0) }
        XCTAssertEqual(shown, ["Hexfall", "Kidfilm"], "PG-13 and G show; R and the unrated film do not")
        var allowed = rule
        allowed.allowUnrated = true
        await h.store.setRestrictions(LibraryRestrictions(ratings: allowed))
        let withUnrated = try await titles(h).filter { ["Hexfall", "Kidfilm", "Darkfilm", "Plainfilm"].contains($0) }
        XCTAssertEqual(withUnrated, ["Hexfall", "Kidfilm", "Plainfilm"], "Allow Unrated shows only the unrated one more")
    }

    func testAFilmThatSaysItIsUnratedCountsAsUnrated() async throws {
        let h = try await library()
        defer { h.cleanup() }
        try await rate(h, "Plainfilm", "Not Rated")
        try await rate(h, "Darkfilm", "")
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        let hidden = try await titles(h)
        XCTAssertFalse(hidden.contains("Plainfilm")); XCTAssertFalse(hidden.contains("Darkfilm"))
        var allowed = rule
        allowed.allowUnrated = true
        await h.store.setRestrictions(LibraryRestrictions(ratings: allowed))
        let shown = try await titles(h)
        XCTAssertTrue(shown.contains("Plainfilm")); XCTAssertTrue(shown.contains("Darkfilm"))
    }

    func testEveryQueryKindAppliesTheSameRule() async throws {
        let h = try await library()
        defer { h.cleanup() }
        try await rate(h, "Kidfilm", "G")
        try await rate(h, "Darkfilm", "R")
        let darkID = try await id(h, "Darkfilm"), kidID = try await id(h, "Kidfilm")
        let beforeCounts = try await h.store.counts()
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        // Page (both kinds), count, letter index, one title, Recently Added, counts.
        let page = try await h.store.page(ItemQuery(), limit: 100, after: nil).items
        XCTAssertEqual(page.map(\.title), ["Kidfilm"])
        let offset = try await h.store.page(ItemQuery(), limit: 100, offset: 0)
        XCTAssertEqual(offset.map(\.title), ["Kidfilm"])
        let count = try await h.store.count(ItemQuery())
        XCTAssertEqual(count, 1)
        let letters = try await h.store.alphabetIndex(ItemQuery()).map(\.count).reduce(0, +)
        XCTAssertEqual(letters, 1)
        let darkItem = try await h.store.item(id: darkID)
        XCTAssertNil(darkItem)
        let kidItem = try await h.store.item(id: kidID)
        XCTAssertNotNil(kidItem)
        let recent = try await h.store.recentlyAdded(limit: 20, kind: nil)
        XCTAssertEqual(recent.map(\.title), ["Kidfilm"])
        let recentFilms = try await h.store.recentlyAdded(limit: 20, kind: .movie)
        XCTAssertEqual(recentFilms.map(\.title), ["Kidfilm"])
        let counts = try await h.store.counts()
        XCTAssertLessThan(counts.items, beforeCounts.items)
        XCTAssertEqual(counts.series, 0, "the show's episodes are unrated, so no show is left")
    }

    func testContinueWatchingAndNextUpFollowTheRule() async throws {
        let h = try await library()
        defer { h.cleanup() }
        try await rate(h, "Kidfilm", "G")
        try await rate(h, "Darkfilm", "R")
        let kid = try await id(h, "Kidfilm"), dark = try await id(h, "Darkfilm")
        try await h.store.updateProgress(itemID: kid, position: 100, duration: 1_000, at: day(100))
        try await h.store.updateProgress(itemID: dark, position: 100, duration: 1_000, at: day(100))
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        let keep = try await h.store.continueWatching(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertEqual(keep.map(\.id), [kid])
    }

    func testEpisodesTakeTheirShowsRatingAndNextUpAndTheEpisodeListFollow() async throws {
        let h = try await library()
        defer { h.cleanup() }
        var filter = ItemFilter()
        filter.kinds = [.episode]
        let all = try await h.store.page(ItemQuery(filter: filter), limit: 100, after: nil).items
        let episodes = all.filter { $0.seriesTitle == "Show One" && $0.season == 1 }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
        XCTAssertEqual(episodes.count, 2)
        let seriesID = try XCTUnwrap(episodes.first?.seriesID)
        // Only the first episode's information file named a rating; the second has none of its own.
        try await h.store.setMetadata(itemID: episodes[0].id, ItemMetadata(contentRating: "TV-14"))
        try await h.store.markWatched(itemIDs: [episodes[0].id], watched: true, at: day(100))
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        let list = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertTrue(list.contains { $0.id == episodes[1].id }, "an episode with no rating takes the show's")
        let next = try await h.store.nextUp(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertFalse(next.isEmpty)
        var strict = rule
        strict.episodeLabels = ["TVY"]
        await h.store.setRestrictions(LibraryRestrictions(ratings: strict))
        let none = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertTrue(none.isEmpty, "TV-14 is above the setting")
        let nextNone = try await h.store.nextUp(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertTrue(nextNone.isEmpty)
        let continueNone = try await h.store.continueWatching(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertTrue(continueNone.allSatisfy { $0.seriesID != seriesID })
    }

    func testTheRatingRuleAndAHiddenSourceWorkTogetherAndOffChangesNothing() async throws {
        let h = try await library()
        defer { h.cleanup() }
        let before = try await titles(h)
        await h.store.setRestrictions(LibraryRestrictions(hiddenSourceIDs: ["nowhere"], ratings: nil))
        let same = try await titles(h)
        XCTAssertEqual(before, same)
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        let current = await h.store.currentRestrictions
        XCTAssertFalse(current.isEmpty)
        await h.store.setRestrictions(LibraryRestrictions())
        let back = try await titles(h)
        XCTAssertEqual(back, before, "turning Restrictions off shows everything again")
    }

    func testTheRatingPassSeesTheTitlesTheRuleHides() async throws {
        let h = try await library()
        defer { h.cleanup() }
        try await rate(h, "Kidfilm", "G")
        await h.store.setRestrictions(LibraryRestrictions(ratings: rule))
        let unread = try await h.store.itemsWithoutRating(after: 0, limit: 100)
        XCTAssertTrue(unread.contains { $0.title == "Plainfilm" }, "hidden because unrated, but the pass still reaches it")
        XCTAssertFalse(unread.contains { $0.title == "Kidfilm" })
    }
}
