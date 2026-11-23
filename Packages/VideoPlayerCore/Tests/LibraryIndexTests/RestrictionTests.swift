import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// R458: the library's one restriction rule (`LibraryRestrictions`) reaches every query that returns titles. FIXTURE: invented
/// names; two sources, one of them hidden.
final class RestrictionTests: XCTestCase {
    private func twoSources() async throws -> (Harness, FakeSource) {
        let h = try Harness.make()
        basicLibrary(h.source)
        try await h.registerSource()
        try await h.syncer.sync()
        let other = FakeSource()
        other.put("/Movies/Other Film (2001)/Other Film (2001).mkv", size: 9_000, modified: day(5))
        other.put("/TV/Show Two (2012)/Season 1/Show Two - S01E01 - Start.mkv", size: 5_000, modified: day(6))
        try await h.store.upsertSource(LibrarySourceRecord(id: "src2", kind: .webdav, name: "Second", addedAt: t0))
        try await h.syncer(source: other, id: "src2").sync()
        return (h, other)
    }

    func testAHiddenSourceLeavesEveryListCountAndLookup() async throws {
        let (h, _) = try await twoSources()
        defer { h.cleanup() }
        let all = try await h.store.page(ItemQuery(), limit: 100, after: nil).items
        XCTAssertTrue(all.contains { $0.title == "Other Film" })
        let hiddenIDs = all.filter { $0.title == "Other Film" || $0.seriesTitle == "Show Two" }.map(\.id)
        XCTAssertFalse(hiddenIDs.isEmpty)
        let countBefore = try await h.store.counts()

        await h.store.setRestrictions(LibraryRestrictions(hiddenSourceIDs: ["src2"]))

        let page = try await h.store.page(ItemQuery(), limit: 100, after: nil).items
        XCTAssertFalse(page.contains { hiddenIDs.contains($0.id) }, "the cursor page")
        let offsetPage = try await h.store.page(ItemQuery(), limit: 100, offset: 0)
        XCTAssertFalse(offsetPage.contains { hiddenIDs.contains($0.id) }, "the offset page")
        let count = try await h.store.count(ItemQuery())
        XCTAssertEqual(count, page.count, "the count follows the list")
        let letters = try await h.store.alphabetIndex(ItemQuery()).map(\.count).reduce(0, +)
        XCTAssertEqual(letters, page.count, "the letter index follows the list")
        let recent = try await h.store.recentlyAdded(limit: 50, kind: nil)
        XCTAssertFalse(recent.contains { hiddenIDs.contains($0.id) })
        let recentMovies = try await h.store.recentlyAdded(limit: 50, kind: .movie)
        XCTAssertFalse(recentMovies.contains { hiddenIDs.contains($0.id) })
        for id in hiddenIDs {
            let one = try await h.store.item(id: id)
            XCTAssertNil(one, "one title by id")
        }
        let counts = try await h.store.counts()
        XCTAssertLessThan(counts.items, countBefore.items)
        XCTAssertLessThan(counts.series, countBefore.series)
    }

    func testAHiddenSourcesEpisodesAndContinueWatchingAndNextUpAreLeftOut() async throws {
        let (h, _) = try await twoSources()
        defer { h.cleanup() }
        var filter = ItemFilter()
        filter.kinds = [.episode]
        let episodes = try await h.store.page(ItemQuery(filter: filter), limit: 100, after: nil).items
        let second = try XCTUnwrap(episodes.first { $0.seriesTitle == "Show Two" })
        let seriesID = try XCTUnwrap(second.seriesID)
        try await h.store.updateProgress(itemID: second.id, position: 100, duration: 1_000, at: day(100))
        let before = try await h.store.continueWatching(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertTrue(before.contains { $0.id == second.id })
        let seriesEpisodesBefore = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertFalse(seriesEpisodesBefore.isEmpty)

        await h.store.setRestrictions(LibraryRestrictions(hiddenSourceIDs: ["src2"]))

        let after = try await h.store.continueWatching(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertFalse(after.contains { $0.id == second.id }, "Continue Watching")
        let seriesEpisodes = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertTrue(seriesEpisodes.isEmpty, "a show's episodes")
        let next = try await h.store.nextUp(limit: 10, now: day(101), retentionDays: 90)
        XCTAssertFalse(next.contains { $0.item.seriesID == seriesID }, "Next Up")
    }

    func testATitleInAShownSourceStaysEvenWhenAnotherSourceIsHidden() async throws {
        let (h, other) = try await twoSources()
        defer { h.cleanup() }
        // The same film in both sources: it stays while one of them is shown.
        other.put("/Movies/Hexfall (1995)/Hexfall (1995).mkv", size: 10_000, modified: day(7))
        try await h.syncer(source: other, id: "src2").sync()
        await h.store.setRestrictions(LibraryRestrictions(hiddenSourceIDs: ["src2"]))
        let titles = try await h.store.page(ItemQuery(), limit: 100, after: nil).items.map(\.title)
        XCTAssertTrue(titles.contains("Hexfall"))
    }

    func testNoRestrictionChangesNothing() async throws {
        let (h, _) = try await twoSources()
        defer { h.cleanup() }
        let before = try await h.store.page(ItemQuery(), limit: 100, after: nil).items.map(\.id)
        await h.store.setRestrictions(LibraryRestrictions())
        let after = try await h.store.page(ItemQuery(), limit: 100, after: nil).items.map(\.id)
        XCTAssertEqual(before, after)
        let current = await h.store.currentRestrictions
        XCTAssertTrue(current.isEmpty)
    }
}
