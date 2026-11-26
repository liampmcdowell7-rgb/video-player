import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

/// R471 (72), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding D): the detail page's header read and the Fix
/// Match search no longer write an older copy of the screen back. The app's `ScreenModel.run` copies the model, awaits and
/// writes the copy back; these steps now wait outside it and apply their answer to the model as it is then.
final class ScreenWriteBackR471Tests: XCTestCase {
    private struct StubSearcher: MatchSearching {
        func search(title: String, year: Int?, kind: ItemKind) async throws -> [MatchCandidate] {
            [MatchCandidate(id: title.count, title: title, year: 2020)]
        }
    }

    private let tracks = FileTrackDetails(frameRate: 23.976, audio: [], subtitles: [])

    /// The old way, as `ScreenModel.run` did it: a copy read the header across the wait and was written back last.
    func testTheOldWholeCopyWriteBackUndidAFavoriteMadeDuringTheRead() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let details = tracks
        var screen = ItemDetailViewModel(store: rig.store, itemID: id, trackReader: { _ in details })
        await screen.load()
        var copy = screen                                  // run { await $0.loadTrackDetails() } starts
        await screen.toggleFavorite()                      // the user's change, written while the read waits
        await copy.loadTrackDetails()
        screen = copy                                      // the read's copy is written back
        XCTAssertEqual(screen.state.content?.isFavorite, false, "the shape of the bug: the Favorite change is undone")
    }

    func testTheHeaderReadKeepsAChangeMadeDuringIt() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let details = tracks
        var screen = ItemDetailViewModel(store: rig.store, itemID: id, trackReader: { _ in details })
        await screen.load()
        let maybeRead = await screen.readTrackDetails()      // the wait, with no copy held
        let read = try XCTUnwrap(maybeRead)
        await screen.toggleFavorite()
        screen.applyTrackDetails(read)                     // applied to the page as it is now
        XCTAssertEqual(screen.state.content?.isFavorite, true, "the Favorite change made during the read stays")
        XCTAssertEqual(screen.state.content.flatMap { c in c.mediaInfo.first { $0.label == "Frame Rate" }?.value }, "23.976 fps")
        let kept = try await rig.store.trackDetails(fileID: read.fileID)
        XCTAssertNotNil(kept, "kept in the library index")
    }

    func testDetailsOfAnotherFileAreNotApplied() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        var screen = ItemDetailViewModel(store: rig.store, itemID: try await rig.movieID("Hexfall"), trackReader: { _ in nil })
        await screen.load()
        screen.applyTrackDetails(ItemDetailViewModel.ReadTrackDetails(fileID: -1, details: tracks))
        XCTAssertEqual(screen.state.content.flatMap { c in c.mediaInfo.first { $0.label == "Frame Rate" }?.value }, MediaInfo.notChecked)
    }

    func testAnOlderSearchAnsweredLastIsNotShown() async throws {
        let rig = try LibraryRig.make()
        var screen = FixMatchViewModel(store: rig.store, searcher: StubSearcher(), itemID: 1, kind: .movie, currentTitle: "x")
        let first = try XCTUnwrap(screen.beginSearch("Alpha"))
        let older = await screen.findMatches(first)
        let second = try XCTUnwrap(screen.beginSearch("Beta Two"))
        let newer = await screen.findMatches(second)
        screen.finishSearch(newer)
        screen.finishSearch(older)                          // the older answer arrives last
        guard case .loaded(let shown) = screen.state else { return XCTFail("state \(screen.state)") }
        XCTAssertEqual(shown.map(\.title), ["Beta Two"])
        XCTAssertEqual(screen.query, "Beta Two")
    }

    func testAppliesToChangedDuringASearchStays() async throws {
        let rig = try LibraryRig.make()
        var screen = FixMatchViewModel(store: rig.store, searcher: StubSearcher(), itemID: 1, kind: .episode, currentTitle: "x")
        let asked = try XCTUnwrap(screen.beginSearch("Gamma"))
        let found = await screen.findMatches(asked)
        screen.setScope(.wholeShow)                         // changed while the search waited
        screen.finishSearch(found)
        XCTAssertEqual(screen.scope, .wholeShow)
        guard case .loaded = screen.state else { return XCTFail("state \(screen.state)") }
    }

    func testAnEmptyQueryClearsTheList() async throws {
        let rig = try LibraryRig.make()
        var screen = FixMatchViewModel(store: rig.store, searcher: StubSearcher(), itemID: 1, kind: .movie, currentTitle: "x")
        XCTAssertNil(screen.beginSearch("   "))
        guard case .idle = screen.state else { return XCTFail("state \(screen.state)") }
    }
}
