import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

/// #21 F: Shows has the same Sort, Filter and Saved Views controls as Movies.
final class ShowsToolbarTests: XCTestCase {
    private let now = epoch.addingTimeInterval(100 * 86_400)

    private func titles(_ vm: ShowsViewModel) -> [String] { vm.state.content?.map(\.title) ?? [] }

    func testTheWatchFilterWorksAtShowLevel() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let two = try await rig.episodes(ofSeriesTitle: "Show Two")
        try await rig.store.markWatched(itemIDs: two.map(\.id), watched: true, at: now)
        var vm = ShowsViewModel(store: rig.store)
        await vm.load()
        XCTAssertEqual(titles(vm), ["Show One", "Show Two"])

        await vm.toggle(.watch(.watched))
        XCTAssertEqual(titles(vm), ["Show Two"], "Watched: every episode watched")
        XCTAssertTrue(vm.isFiltered)
        XCTAssertEqual(vm.chips.map(\.title), ["Watched"])

        await vm.toggle(.watch(.unwatched))
        XCTAssertEqual(titles(vm), ["Show One"], "Unwatched: something left to watch")

        await vm.toggle(.watch(.inProgress))
        guard case .empty(let e) = vm.state else { return XCTFail("\(vm.state)") }
        XCTAssertEqual(e.reason, .noMatches, "nothing started in Show One yet")
        XCTAssertEqual(e.actionTitle, "Clear Filters")
        XCTAssertNil(vm.countText)

        let one = try await rig.episodes(ofSeriesTitle: "Show One")
        try await rig.store.markWatched(itemIDs: [one[0].id], watched: true, at: now)
        await vm.load()
        XCTAssertEqual(titles(vm), ["Show One"], "In Progress: one episode watched, others left")

        await vm.clearFilters()
        XCTAssertFalse(vm.isFiltered)
        XCTAssertEqual(titles(vm), ["Show One", "Show Two"])
        XCTAssertEqual(vm.countText, "2 shows")
    }

    func testEpisodeFiltersKeepAShowWhenOneEpisodeMatches() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let two = try await rig.episodes(ofSeriesTitle: "Show Two")
        try await rig.store.setFavorite(itemID: two[0].id, favorite: true)
        var vm = ShowsViewModel(store: rig.store)
        await vm.load()
        await vm.toggle(.favorites)
        XCTAssertEqual(titles(vm), ["Show Two"])
        XCTAssertEqual(vm.countText, "1 show")
        if let chip = vm.chips.first {
            await vm.removeChip(chip)
        }
        XCTAssertEqual(titles(vm), ["Show One", "Show Two"])
    }

    func testSortsAndTheJumpListOnlyForTitle() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let two = try await rig.episodes(ofSeriesTitle: "Show Two")
        try await rig.store.updateProgress(itemID: two[0].id, position: 60, duration: 1_200, at: now)
        var vm = ShowsViewModel(store: rig.store)
        await vm.load()
        XCTAssertEqual(vm.sortChoices.map(\.title), ["Title", "Year", "Date Added", "Last Played"])
        XCTAssertFalse(vm.jumpTargets.isEmpty)

        await vm.chooseSort(.title)
        XCTAssertEqual(titles(vm), ["Show Two", "Show One"], "choosing the active key flips the direction")
        XCTAssertFalse(vm.jumpTargets.isEmpty)

        await vm.chooseSort(.lastPlayed)
        XCTAssertEqual(titles(vm), ["Show Two", "Show One"], "played show first, never played last")
        XCTAssertTrue(vm.jumpTargets.isEmpty, "no letters for a sort that is not by title")
        await vm.chooseSort(.lastPlayed)
        XCTAssertEqual(titles(vm), ["Show Two", "Show One"], "a show never played stays last in both directions")
    }

    func testSavedViewsAreKeptApartFromMovies() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var vm = ShowsViewModel(store: rig.store)
        await vm.load()
        await vm.toggle(.watch(.unwatched))
        await vm.chooseSort(.added)
        let saved = try await vm.saveCurrentView(name: "  Left to Watch ", pinned: false)
        XCTAssertEqual(saved.name, "Left to Watch")
        XCTAssertEqual(saved.scope, .shows)
        XCTAssertEqual(vm.savedViews.map(\.name), ["Left to Watch"])

        var movies = ItemGridViewModel.movies(store: rig.store)
        await movies.refreshSavedViews()
        XCTAssertTrue(movies.savedViews.isEmpty, "a Shows view is not offered on Movies")

        await vm.clearFilters()
        await vm.chooseSort(.title)
        await vm.apply(saved)
        XCTAssertEqual(vm.query.filter.watch, .unwatched)
        XCTAssertEqual(vm.query.sort.key, .added)

        var fresh = ShowsViewModel(store: rig.store)
        await fresh.refreshSavedViews()
        XCTAssertEqual(fresh.savedViews.map(\.scope), [.shows], "the scope survives a reload from the database")
        await fresh.deleteView(id: saved.id)
        XCTAssertTrue(fresh.savedViews.isEmpty)
    }

    // MARK: Long-press menu (#21 F)

    func testCardsOfferGoToAndRemoveFromContinueOnlyWhenItChangesSomething() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        let one = try await rig.episodes(ofSeriesTitle: "Show One")
        func fetch() async throws -> LibraryItem {
            let found = try await rig.store.item(id: hexfall)
            return try XCTUnwrap(found)
        }
        var card = CardBuilder.card(try await fetch())
        XCTAssertEqual(card.goToTitle, "Go to Movie")
        XCTAssertNil(card.seriesID)
        XCTAssertFalse(card.canRemoveFromContinue, "not started: not in Continue Watching")

        try await rig.store.updateProgress(itemID: hexfall, position: 1_800, duration: 6_000, at: now)
        card = CardBuilder.card(try await fetch(), style: .continueWatching)
        XCTAssertTrue(card.canRemoveFromContinue)
        try await rig.store.hideFromContinue(itemID: hexfall, hidden: true)
        card = CardBuilder.card(try await fetch())
        XCTAssertFalse(card.canRemoveFromContinue, "already removed")
        let row = try await rig.store.continueWatching(limit: 20, now: now, retentionDays: 90)
        XCTAssertFalse(row.contains { $0.id == hexfall }, "the hide mark takes it out of the row")

        let episode = CardBuilder.card(one[0])
        XCTAssertEqual(episode.goToTitle, "Go to Show")
        XCTAssertEqual(episode.seriesID, one[0].seriesID)
        XCTAssertNotNil(episode.seriesID)
    }

    func testShowsSummaryCarriesTheSortValues() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let one = try await rig.episodes(ofSeriesTitle: "Show One")
        try await rig.store.updateProgress(itemID: one[0].id, position: 30, duration: 1_200, at: now)
        let list = try await EpisodeGroupingCatalog(store: rig.store).allSeries()
        let show = try XCTUnwrap(list.first { $0.title == "Show One" })
        XCTAssertEqual(show.inProgressCount, 1)
        XCTAssertNotNil(show.latestAdded)
        XCTAssertEqual(show.lastPlayed, now)
        XCTAssertNil(list.first { $0.title == "Show Two" }?.lastPlayed)
    }
}
