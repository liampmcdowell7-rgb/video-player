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

    /// R438: the blind loop presses Menu only when the screen changed, checks `player.screen` afterwards, and the Up Next
    /// step says so when the player closed. From the source (structure only).
    func testBlindPressLoopDoesNotLeaveThePlayer() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift") else { return }
        let start: String.Index = try XCTUnwrap(tests.range(of: "for (number, presses) in blind {")?.lowerBound)
        let loop: String = String(try XCTUnwrap(Self.braceBody(of: tests, after: start)))
        XCTAssertTrue(loop.contains("ScreenRules.changed("), "no pixel comparison in the blind loop")
        XCTAssertTrue(loop.contains("matching(identifier: \"player.screen\")"), "no player.screen check in the blind loop")
        XCTAssertTrue(loop.contains("-NO-CHANGE") && loop.contains("-LEFT-THE-PLAYER"))
        // Every Menu press in the loop is inside the `if opened {` branch.
        let branch: Range<String.Index> = try XCTUnwrap(loop.range(of: "if opened {"))
        var search: String.Index = loop.startIndex
        var presses: Int = 0
        while let m = loop.range(of: "press(.menu)", range: search..<loop.endIndex) {
            presses += 1
            XCTAssertTrue(m.lowerBound > branch.lowerBound, "a Menu press before the `if opened` branch")
            let between: Substring = loop[branch.upperBound..<m.lowerBound]
            XCTAssertFalse(between.contains("}"), "an unconditional Menu press after the `if opened` branch closed")
            search = m.upperBound
        }
        XCTAssertEqual(presses, 1)
        XCTAssertTrue(tests.contains("not reached because the player closed after"), "the Up Next step does not say the player closed")
    }
}
