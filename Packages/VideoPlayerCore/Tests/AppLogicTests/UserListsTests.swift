import XCTest
import LibraryIndex
import UserData
@testable import AppLogic

/// R471 (17), Part 4: the user's own lists, playlists and collections: create, rename, delete, add and remove titles, the
/// check marks of the menus, sync between two devices, the stable title keys, and the actions now offered.
final class UserListsTests: XCTestCase {
    private func ledger(_ device: String = "A") -> UserDataLedger {
        UserDataLedger(deviceID: device, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    private let movie = UDTitleRef(kind: .movie, key: "m|hexfall|1995")
    private let show = UDTitleRef(kind: .show, key: "s|show one")

    func testCreateRenameAndDeleteAList() throws {
        let l = ledger()
        XCTAssertNil(l.createList(name: "   ", kind: .list), "an empty name makes nothing")
        let list = try XCTUnwrap(l.createList(name: "  Weekend ", kind: .list, id: "L1", at: Date(timeIntervalSince1970: 1)))
        XCTAssertEqual(list.name, "Weekend")
        l.createList(name: "after", kind: .list, id: "L2", at: Date(timeIntervalSince1970: 2))
        l.createList(name: "Road Trip", kind: .playlist, id: "P1", at: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(l.userLists(kinds: [.list]).map(\.name), ["after", "Weekend"], "by name, case ignored")
        XCTAssertEqual(l.userLists().count, 3)

        l.renameList(id: "L1", to: "Sunday", at: Date(timeIntervalSince1970: 4))
        l.renameList(id: "L1", to: " ", at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(l.userList(id: "L1")?.name, "Sunday")

        l.addToList("L1", ref: movie, title: "Hexfall", at: Date(timeIntervalSince1970: 6))
        l.deleteList(id: "L1", at: Date(timeIntervalSince1970: 7))
        XCTAssertNil(l.userList(id: "L1"))
        XCTAssertTrue(l.listEntries("L1").isEmpty)
        XCTAssertTrue(l.listIDs(containing: movie).isEmpty)
    }

    func testAddAndRemoveTitlesKeepTheOrderTheyWereAdded() {
        let l = ledger()
        l.createList(name: "Mine", kind: .collection, id: "C1", at: Date(timeIntervalSince1970: 1))
        l.addToList("C1", ref: show, title: "Show One", at: Date(timeIntervalSince1970: 3))
        l.addToList("C1", ref: movie, title: "Hexfall", at: Date(timeIntervalSince1970: 2))
        l.addToList("missing", ref: movie, title: "Hexfall", at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(l.listEntries("C1").map(\.title), ["Hexfall", "Show One"])
        XCTAssertEqual(l.listIDs(containing: movie), ["C1"])
        XCTAssertTrue(l.listEntries("missing").isEmpty, "no entries for a list that does not exist")
        l.removeFromList("C1", ref: movie, at: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(l.listEntries("C1").map(\.ref), [show])
    }

    func testListsTravelToAnotherDeviceThroughTheLedgerMerge() {
        let a = ledger("A"), b = ledger("B")
        a.createList(name: "Shared", kind: .list, id: "L1", at: Date(timeIntervalSince1970: 1))
        a.addToList("L1", ref: movie, title: "Hexfall", at: Date(timeIntervalSince1970: 2))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertEqual(b.userLists().map(\.name), ["Shared"])
        XCTAssertEqual(b.listEntries("L1").map(\.title), ["Hexfall"])

        b.renameList(id: "L1", to: "Shared Too", at: Date(timeIntervalSince1970: 3))
        a.deleteList(id: "L1", at: Date(timeIntervalSince1970: 4))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertTrue(b.userLists().isEmpty, "the later delete wins over the earlier rename")
    }

    func testTitleRefsRoundTrip() {
        XCTAssertEqual(UDTitleRef(id: movie.id), movie)
        XCTAssertEqual(UDTitleRef(id: "show:s|a:b"), UDTitleRef(kind: .show, key: "s|a:b"))
        XCTAssertNil(UDTitleRef(id: "season:x"))
        XCTAssertNil(UDTitleRef(id: "nokind"))
    }

    func testTheLibraryKeysFindTheSameTitlesAgain() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let ref = await rig.store.titleRef(itemID: id, kind: .movie)
        XCTAssertEqual(ref?.kind, .movie)
        let back = await rig.store.target(of: try XCTUnwrap(ref))
        XCTAssertEqual(back, .item(id))

        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        let seriesID = try XCTUnwrap(episodes.first?.seriesID)
        let showRef = await rig.store.titleRef(seriesID: seriesID)
        XCTAssertEqual(showRef?.kind, .show)
        let showBack = await rig.store.target(of: try XCTUnwrap(showRef))
        XCTAssertEqual(showBack, .series(seriesID))

        let gone = await rig.store.target(of: UDTitleRef(kind: .movie, key: "m|nothing"))
        XCTAssertNil(gone)
    }

    func testTheMenusAndTheirWords() {
        XCTAssertEqual(UserListText.kinds(for: .addToList), [.list])
        XCTAssertEqual(UserListText.kinds(for: .addToPlaylistOrCollection), [.playlist, .collection])
        XCTAssertEqual(UserListText.newEntry(.playlist), "New Playlist…")
        XCTAssertEqual(UserListText.nameTitle(.collection, renaming: true), "Rename Collection")
        let list = UDUserList(id: "P", name: "Road Trip", kind: .playlist, createdAt: Date())
        XCTAssertEqual(UserListText.entry(list, in: .addToPlaylistOrCollection), "Road Trip (Playlist)")
        XCTAssertEqual(UserListText.entry(list, in: .addToList), "Road Trip")
        let ask = UserListText.deleteConfirmation(list)
        XCTAssertEqual(ask.button, "Delete Playlist")
        XCTAssertTrue(ask.message.contains("stay in your library"))
    }

    func testBothActionsAreOfferedForEveryTitleKindAndOnTheLongPress() {
        let season = ProductActions.list(ProductActionContext(kind: .season))
        XCTAssertFalse(season.contains(.addToList), "a season is not a list entry of its own")
        XCTAssertFalse(season.contains(.addToPlaylistOrCollection))
        for kind in [ProductActionContext.Kind.movie, .episode, .show] {
            let list = ProductActions.list(ProductActionContext(kind: kind))
            XCTAssertTrue(list.contains(.addToList), "\(kind)")
            XCTAssertTrue(list.contains(.addToPlaylistOrCollection), "\(kind)")
        }
        XCTAssertTrue(ProductActions.cardSupported.isSuperset(of: [.addToList, .addToPlaylistOrCollection]))
    }
}
