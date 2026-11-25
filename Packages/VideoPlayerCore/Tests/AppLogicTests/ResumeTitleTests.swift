import XCTest
@testable import AppLogic

/// R471 (34): the menu's Resume says how much is left.
final class ResumeTitleTests: XCTestCase {
    func testResumeWithTheTimeLeft() {
        XCTAssertEqual(ProductAction.resumeTitle(timeLeft: DisplayText.remaining(41 * 60)), "Resume · 41 min left")
        XCTAssertEqual(ProductAction.resumeTitle(timeLeft: "2 h 29 min left"), "Resume · 2 h 29 min left")
    }

    func testThePlainTitleWithoutATimeLeft() {
        XCTAssertEqual(ProductAction.resumeTitle(timeLeft: nil), "Resume")
        XCTAssertEqual(ProductAction.resumeTitle(timeLeft: "  "), "Resume")
    }
}
