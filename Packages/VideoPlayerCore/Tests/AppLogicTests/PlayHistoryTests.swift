import XCTest
import UserData
@testable import AppLogic

/// R471 (20), Part 4: Play History keeps one entry per playback (progress saves close together continue it), says how far
/// and whether it finished, travels to another device, and Clear removes the item's entries only.
final class PlayHistoryTests: XCTestCase {
    private func ledger(_ device: String = "A") -> UserDataLedger { UserDataLedger(deviceID: device, clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }
    private func t(_ minutes: Double) -> Date { Date(timeIntervalSince1970: 1_000_000 + minutes * 60) }

    func testSavesCloseTogetherAreOnePlaybackAndALaterOneIsANewEntry() {
        let l = ledger()
        l.recordPlay(itemKey: "m|a", position: 60, duration: 6_000, finished: false, at: t(0))
        l.recordPlay(itemKey: "m|a", position: 1_200, duration: 6_000, finished: false, at: t(20))
        l.recordPlay(itemKey: "m|a", position: 5_900, duration: 6_000, finished: true, at: t(45))
        l.recordPlay(itemKey: "m|a", position: 300, duration: 6_000, finished: false, at: t(200))
        l.recordPlay(itemKey: "m|b", position: 10, duration: 100, finished: false, at: t(201))
        let history = l.playHistory(itemKey: "m|a")
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].startedAt, t(200), "newest first")
        XCTAssertEqual(history[1].startedAt, t(0))
        XCTAssertEqual(history[1].lastAt, t(45))
        XCTAssertEqual(history[1].position, 5_900)
        XCTAssertTrue(history[1].finished)
        XCTAssertFalse(history[0].finished)
    }

    func testClearRemovesTheItemsEntriesOnlyAndTravels() {
        let a = ledger("A"), b = ledger("B")
        a.recordPlay(itemKey: "m|a", position: 60, duration: 600, finished: false, at: t(0))
        a.recordPlay(itemKey: "m|b", position: 60, duration: 600, finished: false, at: t(1))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertEqual(b.playHistory(itemKey: "m|a").count, 1)
        a.clearPlayHistory(itemKey: "m|a", at: t(5))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertTrue(b.playHistory(itemKey: "m|a").isEmpty)
        XCTAssertEqual(b.playHistory(itemKey: "m|b").count, 1)
    }

    func testTwoDevicesKeepTheirOwnEntries() {
        let a = ledger("A"), b = ledger("B")
        a.recordPlay(itemKey: "m|a", position: 60, duration: 600, finished: false, at: t(0))
        for r in a.allRecords() { b.apply(r) }
        b.recordPlay(itemKey: "m|a", position: 90, duration: 600, finished: false, at: t(2))
        XCTAssertEqual(b.playHistory(itemKey: "m|a").map(\.device), ["B", "A"])
    }

    func testOnlyTheNewestEntriesAreKept() {
        let l = ledger()
        for n in 0..<(UDPlayHistory.keptPerItem + 3) {
            l.recordPlay(itemKey: "m|a", position: 1, duration: 10, finished: false, at: t(Double(n) * 60))
        }
        XCTAssertEqual(l.playHistory(itemKey: "m|a").count, UDPlayHistory.keptPerItem)
    }

    func testTheRowsAndTheConfirmation() {
        let entry = UDPlayRecord(id: "x", itemKey: "m|a", device: "A", startedAt: t(0), lastAt: t(30), position: 1_830, duration: 6_000, finished: false)
        XCTAssertEqual(PlayHistoryText.progress(entry), "Stopped at 30:30 of 1:40:00")
        var done = entry
        done.finished = true
        XCTAssertEqual(PlayHistoryText.progress(done), "Finished")
        var unknown = entry
        unknown.duration = nil
        XCTAssertEqual(PlayHistoryText.progress(unknown), "Stopped at 30:30")
        XCTAssertTrue(PlayHistoryText.clearMessage.contains("watched"))
        XCTAssertTrue(ProductActions.manageList(ProductActionContext(kind: .movie)).contains(.playHistory))
    }
}

extension PlayHistoryTests {
    func testAShowOrASeasonHasNoPlayHistoryOfItsOwn() {
        XCTAssertTrue(ProductActions.manageList(ProductActionContext(kind: .episode)).contains(.playHistory))
        XCTAssertFalse(ProductActions.manageList(ProductActionContext(kind: .show)).contains(.playHistory))
        XCTAssertFalse(ProductActions.manageList(ProductActionContext(kind: .season)).contains(.playHistory))
    }
}
