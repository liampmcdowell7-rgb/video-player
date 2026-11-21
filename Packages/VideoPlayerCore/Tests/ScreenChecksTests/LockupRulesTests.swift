import XCTest
@testable import ScreenChecks

/// R335: a portrait card's caption is inside the focused lockup.
final class LockupRulesTests: XCTestCase {
    private let button = AXRect(x: 100, y: 300, width: 250, height: 470)

    func testCaptionInsideTheFocusedCardPasses() {
        let caption = AXRect(x: 116, y: 690, width: 200, height: 30)
        let result: CheckResult = ScreenRules.captionInLockup(focused: button, caption: caption, title: "Sample Movie 1")
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "LOCKUP OK: the caption is inside the focused card")
    }

    /// Before R335: the `.card` button held only the artwork (375 high) and the caption sat below it.
    func testCaptionBelowAnArtworkOnlyButtonFails() {
        let artworkOnly = AXRect(x: 100, y: 300, width: 250, height: 375)
        let caption = AXRect(x: 116, y: 690, width: 200, height: 30)
        let result: CheckResult = ScreenRules.captionInLockup(focused: artworkOnly, caption: caption, title: "Sample Movie 1")
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("CAPTION OUTSIDE THE FOCUSED CARD"))
    }

    func testSmallRoundingIsAllowedAndMissingFramesFail() {
        let nearEdge = AXRect(x: 98, y: 740, width: 254, height: 32)
        XCTAssertTrue(ScreenRules.captionInLockup(focused: button, caption: nearEdge, title: "T").passed)
        XCTAssertFalse(ScreenRules.captionInLockup(focused: nil, caption: nearEdge, title: "T").passed)
        XCTAssertFalse(ScreenRules.captionInLockup(focused: button, caption: nil, title: "T").passed)
    }
}
