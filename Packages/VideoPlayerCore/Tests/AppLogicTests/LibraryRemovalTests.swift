import XCTest
import LibraryIndex
import UserData
@testable import AppLogic

/// R471 (15), Part 4: Delete from Library removes a title from the library only, a later scan keeps it out, Bring Back
/// returns it, the confirmation says the file stays on the source, and Restrictions turn the action off.
final class LibraryRemovalTests: XCTestCase {
    private func ledger() -> UserDataLedger { UserDataLedger(deviceID: "A", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    private func movieCount(_ store: SQLiteLibraryStore) async throws -> Int {
        var f = ItemFilter()
        f.kinds = [.movie]
        return try await store.count(ItemQuery(filter: f))
    }

    private func rescan(_ rig: LibraryRig, _ l: UserDataLedger) async throws {
        let syncer = LibrarySyncer(store: rig.store, source: rig.source, sourceID: LibraryRig.sourceID,
                                   clock: { Date(timeIntervalSince1970: 1_800_000_000) }, overrides: LedgerSortOverrides(ledger: l))
        try await syncer.sync(resume: false)
    }

    func testAMovieLeavesTheLibraryStaysOutOnRescanAndComesBack() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let l = ledger()
        let id = try await rig.movieID("Hexfall")
        let before = try await movieCount(rig.store)
        let removed = try await LibraryRemover(store: rig.store, ledger: l).run(.item(itemID: id))
        XCTAssertEqual(removed, 1)
        let afterDelete = try await movieCount(rig.store)
        XCTAssertEqual(afterDelete, before - 1)
        XCTAssertEqual(l.libraryRemovals().map(\.title), ["Hexfall"])
        let listed = try await rig.source.list("/Movies/Hexfall (1995)")
        XCTAssertEqual(listed.map { $0.name }, ["Hexfall (1995).mkv"], "the file stays on the source")

        try await rescan(rig, l)
        let afterRescan = try await movieCount(rig.store)
        XCTAssertEqual(afterRescan, before - 1, "a later scan leaves it out")

        let removal = try XCTUnwrap(l.libraryRemovals().first)
        l.restoreToLibrary(sourceID: removal.sourceID, path: removal.path, at: removal.removedAt.addingTimeInterval(60))
        XCTAssertTrue(l.libraryRemovals().isEmpty)
        try await rescan(rig, l)
        let afterRestore = try await movieCount(rig.store)
        XCTAssertEqual(afterRestore, before, "Bring Back returns it with the next scan")
    }

    func testASeasonRemovesOnlyItsEpisodes() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let l = ledger()
        let eps = try await rig.episodes(ofSeriesTitle: "Show One")
        let seriesID = try XCTUnwrap(eps.first?.seriesID)
        let removed = try await LibraryRemover(store: rig.store, ledger: l).run(.season(seriesID: seriesID, season: 1))
        XCTAssertEqual(removed, 3)
        let left = try await rig.episodes(ofSeriesTitle: "Show One")
        XCTAssertEqual(Set(left.compactMap(\.season)), [0, 2], "season 1 left; the specials and season 2 stay")
        XCTAssertEqual(l.libraryRemovals().count, 3)
        XCTAssertTrue(l.libraryRemovals().allSatisfy { $0.title.hasPrefix("Show One, ") }, "rows name the show and the episode")
    }

    func testTheConfirmationSaysTheFileStaysOnTheSource() {
        let one = LibraryRemover.confirmation(.item(itemID: 1), title: "Hexfall")
        XCTAssertEqual(one.title, "Delete “Hexfall” from the Library?")
        XCTAssertTrue(one.message.contains("The file stays on the source and is not deleted there."))
        XCTAssertEqual(one.button, "Delete from Library")
        let show = LibraryRemover.confirmation(.show(seriesID: 1), title: "Show One", episodeCount: 5)
        XCTAssertTrue(show.message.contains("with its 5 episodes"))
        XCTAssertTrue(show.message.contains("Nothing is deleted from the source"))
    }

    func testRestrictionsTurnDeleteOff() {
        for kind in [ProductActionContext.Kind.movie, .episode, .show, .season] {
            var c = ProductActionContext(kind: kind)
            XCTAssertTrue(ProductActions.manageList(c).contains(.delete), "\(kind)")
            c.deleteAllowed = false
            XCTAssertFalse(ProductActions.manageList(c).contains(.delete), "\(kind)")
        }
    }

    func testTheRowShowsTheFileNameOnly() {
        XCTAssertEqual(LibraryRemovalTexts.fileName("/Movies/Hexfall (1995)/Hexfall (1995).mkv"), "Hexfall (1995).mkv")
    }
}
