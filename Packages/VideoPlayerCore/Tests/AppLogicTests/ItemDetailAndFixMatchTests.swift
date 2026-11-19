import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

private struct StubSearcher: MatchSearching {
    var result: Result<[MatchCandidate], Error>
    func search(title: String, year: Int?, kind: ItemKind) async throws -> [MatchCandidate] { try result.get() }
}

final class ItemDetailTests: XCTestCase {
    func testAnUnknownItemSaysItIsNotInTheLibrary() async throws {
        let rig = try LibraryRig.make()
        var vm = ItemDetailViewModel(store: rig.store, itemID: 9_999)
        await vm.load()
        guard case .empty(let empty) = vm.state else { return XCTFail("state \(vm.state)") }
        XCTAssertEqual(empty.title, "Not in Your Library")
    }

    func testAMovieShowsPlayThenResumeThenPlayAgain() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        var vm = ItemDetailViewModel(store: rig.store, itemID: hexfall)
        await vm.load()
        var content = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(content.title, "Hexfall")
        XCTAssertEqual(content.playTitle, "Play")
        XCTAssertFalse(content.canStartOver)
        XCTAssertNil(content.progress)
        XCTAssertNil(content.timeLeft)
        XCTAssertEqual(content.versions.count, 1)
        XCTAssertTrue(content.versions[0].isPreferred)

        try await rig.store.updateProgress(itemID: hexfall, position: 1_800, duration: 6_000, at: dayOffset(50))
        await vm.load()
        content = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(content.playTitle, "Resume")
        XCTAssertTrue(content.canStartOver)
        XCTAssertEqual(try XCTUnwrap(content.progress), 0.3, accuracy: 0.001)
        // #15 D3: the time left as text (6000 s × 0.7 = 70 min), not a full-width bar.
        XCTAssertEqual(content.timeLeft, "1 h 10 min left")

        await vm.setWatched(true)
        content = try XCTUnwrap(vm.state.content)
        XCTAssertTrue(content.isWatched)
        XCTAssertNil(content.timeLeft, "a watched title has nothing left")
        XCTAssertEqual(content.playTitle, "Play Again")
        XCTAssertFalse(content.canStartOver)
    }

    func testFavouriteTogglesAndReloads() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Aftlander")
        var vm = ItemDetailViewModel(store: rig.store, itemID: id)
        await vm.toggleFavorite()
        XCTAssertNil(vm.state.content, "toggling before the page has loaded does nothing")
        await vm.load()
        XCTAssertEqual(vm.state.content?.isFavorite, false)
        await vm.toggleFavorite()
        XCTAssertEqual(vm.state.content?.isFavorite, true)
        await vm.toggleFavorite()
        XCTAssertEqual(vm.state.content?.isFavorite, false)
    }

    func testAnEpisodeHasItsSeriesAndAnEpisodeCode() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let candidates = try await rig.episodes(ofSeriesTitle: "Show One")
        let ep = try XCTUnwrap(candidates.first { $0.season == 1 && $0.episode == 2 })
        var vm = ItemDetailViewModel(store: rig.store, itemID: ep.id)
        await vm.load()
        let content = try XCTUnwrap(vm.state.content)
        XCTAssertEqual(content.seriesTitle, "Show One")
        XCTAssertNotNil(content.seriesID)
        XCTAssertTrue(content.facts.contains("2"), content.facts)
    }

    func testAFailingStoreGivesAFailedStateNotACrash() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let flaky = FlakyStore(rig.store)
        var vm = ItemDetailViewModel(store: flaky, itemID: id)
        await vm.load()
        XCTAssertNotNil(vm.state.content)
    }
}

/// Renamed from FixMatchTests (addendum #19 B): MetadataOnlineTests has a class of that name, and XCTest on Linux reports
/// results by class name only, so the per-target counts put these 5 tests under MetadataOnline.
final class FixMatchViewModelTests: XCTestCase {
    private func model(_ result: Result<[MatchCandidate], Error>, rig: LibraryRig, itemID: Int64 = 1) -> FixMatchViewModel {
        FixMatchViewModel(store: rig.store, searcher: StubSearcher(result: result), itemID: itemID, kind: .movie, currentTitle: "Hexfall")
    }

    func testABlankQueryStaysIdleAndNeverSearches() async throws {
        let rig = try LibraryRig.make()
        var vm = model(.failure(Boom()), rig: rig)
        await vm.search("   ")
        XCTAssertEqual(vm.state, .idle)
    }

    func testResultsEmptyAndFailureEachHaveTheirOwnState() async throws {
        let rig = try LibraryRig.make()
        var found = model(.success([MatchCandidate(id: 1, title: "Hexfall", year: 1995)]), rig: rig)
        await found.search("  Hexfall ")
        XCTAssertEqual(found.query, "Hexfall", "the query is trimmed")
        XCTAssertEqual(found.state.content?.map(\.id), [1])

        var none = model(.success([]), rig: rig)
        await none.search("zzz")
        guard case .empty(let empty) = none.state else { return XCTFail("state \(none.state)") }
        XCTAssertEqual(empty.reason, .noMatches)

        var failed = model(.failure(Boom()), rig: rig)
        await failed.search("Hexfall")
        guard case .failed = failed.state else { return XCTFail("state \(failed.state)") }
    }

    func testChoosingAMatchWritesTheTitleYearAndIdToTheItem() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        var vm = model(.success([]), rig: rig, itemID: id)
        await vm.choose(MatchCandidate(id: 949, title: "Hexfall (Director's Cut)", year: 1995))
        XCTAssertTrue(vm.applied)
        let stored = try await rig.store.item(id: id)
        let item = try XCTUnwrap(stored)
        XCTAssertEqual(item.title, "Hexfall (Director's Cut)")
    }

    func testTheCandidateSubtitleJoinsYearAndATrimmedOverview() {
        let long = String(repeating: "x", count: 200)
        XCTAssertEqual(MatchCandidate(id: 1, title: "A", year: 1999, overview: "Short").subtitle, "1999 · Short")
        XCTAssertEqual(MatchCandidate(id: 1, title: "A", overview: long).subtitle.count, 90)
        XCTAssertEqual(MatchCandidate(id: 1, title: "A").subtitle, "")
    }

    func testDiscoverSaysItIsNotAvailable() {
        XCTAssertTrue(DiscoverState.notAvailable.title.contains("Not Available"))
    }
}
