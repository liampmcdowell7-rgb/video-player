import XCTest
@testable import ScreenChecks

/// R435 (run #30, item 1): badge gaps are measured inside one group only. Frames from 55-show-page-BADGES.txt.
extension ScreenChecksTests {
    private func run30Card(x: Double, y: Double = 1290, gap: Double = 14) -> [(String, AXRect)] {
        [("badge.resolution-badge.hdr", AXRect(x: x, y: y, width: 91 + gap + 96, height: 58)),
         ("badge.resolution", AXRect(x: x, y: y, width: 91, height: 58)),
         ("badge.hdr", AXRect(x: x + 91 + gap, y: y, width: 96, height: 58))]
    }

    func testThreeEpisodeCardsOnOneLineAreNotMeasuredAgainstEachOther() {
        let frames: [(String, AXRect)] = run30Card(x: 177) + run30Card(x: 627) + run30Card(x: 1077)
        let result: CheckResult = ScreenRules.badgeGaps(badges: frames)
        XCTAssertTrue(result.passed, result.text)
    }

    func testARealGapInsideOneGroupStillFails() {
        let frames: [(String, AXRect)] = run30Card(x: 177) + run30Card(x: 627, gap: 60) + run30Card(x: 1077)
        let result: CheckResult = ScreenRules.badgeGaps(badges: frames)
        XCTAssertFalse(result.passed, result.text)
    }
}
