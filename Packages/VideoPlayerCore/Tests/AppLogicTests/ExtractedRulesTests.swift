import XCTest
@testable import AppLogic

/// R378 (audit docs/AUDIT_INVENTED_UI.md item 4, owner 21 Nov 2026): the logic of R362, R364 and R355, moved out of the
/// views into AppLogic with no change of behaviour, so it has Linux tests.
final class CoverCountTests: XCTestCase {
    func testOneCoverCoversThePage() {
        var count = CoverCount()
        XCTAssertFalse(count.isCovered)
        count.opened()
        XCTAssertTrue(count.isCovered)
        XCTAssertEqual(count.open, 1)
        count.closed()
        XCTAssertFalse(count.isCovered)
    }

    func testACoverOverACoverKeepsThePageCoveredUntilBothClose() {
        var count = CoverCount()
        count.opened(); count.opened()
        count.closed()
        XCTAssertTrue(count.isCovered)
        count.closed()
        XCTAssertFalse(count.isCovered)
    }

    func testAnExtraCloseNeverGoesBelowZero() {
        var count = CoverCount()
        count.closed()
        XCTAssertEqual(count.open, 0)
        count.opened()
        XCTAssertTrue(count.isCovered, "a stray close before must not swallow the next open")
    }
}

final class KeyEntryFlowTests: XCTestCase {
    func testDoneSavesWhatWasTyped() {
        XCTAssertTrue(KeyEntryFlow.savesOnDone(entered: "abc123", working: false))
    }

    func testDoneWithNothingTypedSavesNothing() {
        XCTAssertFalse(KeyEntryFlow.savesOnDone(entered: "", working: false))
    }

    func testDoneDuringASaveDoesNotStartASecondOne() {
        XCTAssertFalse(KeyEntryFlow.savesOnDone(entered: "abc123", working: true))
    }

    func testTheRowsSayWhetherAKeyIsSaved() {
        XCTAssertEqual(KeyEntryFlow.entryTitle(hasKey: false), "Enter Key")
        XCTAssertEqual(KeyEntryFlow.entryTitle(hasKey: true), "Replace Key")
        XCTAssertEqual(KeyEntryFlow.status(hasKey: false), "Not set")
        XCTAssertEqual(KeyEntryFlow.status(hasKey: true), "On")
    }

    func testTheResultIsFooterTextBeforeTheHelp() {
        XCTAssertEqual(KeyEntryFlow.footer(message: nil, help: "Help."), "Help.")
        XCTAssertEqual(KeyEntryFlow.footer(message: KeyEntryFlow.savedMessage, help: "Help."), "Key saved. Help.")
        XCTAssertEqual(KeyEntryFlow.footer(message: KeyEntryFlow.removedMessage, help: "Help."), "Key removed. Help.")
    }
}

final class TextFittingTests: XCTestCase {
    func testTheLadderIsTheStyleThenTheFloorThenWrapped() {
        XCTAssertEqual(TextFitting.wrapLadder(.body), [.oneLine(.body), .oneLine(.caption2), .wrapped(.caption2)])
        XCTAssertEqual(TextFitting.floorStyle.pointSize, TVTextStyle.minimumPointSize)
    }

    func testAShortNameStaysOnOneLineInItsStyle() {
        let step = TextFitting.step(for: .body, naturalWidth: { $0 == .body ? 300 : 200 }, available: 500)
        XCTAssertEqual(step, .oneLine(.body))
    }

    func testANameTooWideForItsStyleTakesTheFloorOnOneLine() {
        let step = TextFitting.step(for: .body, naturalWidth: { $0 == .body ? 700 : 450 }, available: 500)
        XCTAssertEqual(step, .oneLine(.caption2))
    }

    func testANameTooWideAtTheFloorWrapsAndIsNeverCut() {
        let step = TextFitting.step(for: .body, naturalWidth: { $0 == .body ? 1400 : 900 }, available: 500)
        XCTAssertEqual(step, .wrapped(.caption2))
    }

    func testTheMarqueeIsUsedOnlyBelowTheReadableFloor() {
        XCTAssertFalse(TextFitting.isTooLong(natural: 0, available: 400, readable: 0.5), "not measured yet")
        XCTAssertFalse(TextFitting.isTooLong(natural: 600, available: 0, readable: 0.5), "not measured yet")
        XCTAssertFalse(TextFitting.isTooLong(natural: 600, available: 300, readable: 0.5), "fits at exactly the floor")
        XCTAssertTrue(TextFitting.isTooLong(natural: 600, available: 299, readable: 0.5))
    }
}
