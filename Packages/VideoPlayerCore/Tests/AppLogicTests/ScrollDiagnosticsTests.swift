import XCTest
@testable import AppLogic

/// R471 (51): the focus moves and slow frames shown on the diagnostics page.
final class ScrollDiagnosticsTests: XCTestCase {
    func testCellsCountFromOne() {
        XCTAssertEqual(FocusStep.cell(index: 0, columns: 5).row, 1)
        XCTAssertEqual(FocusStep.cell(index: 0, columns: 5).column, 1)
        XCTAssertEqual(FocusStep.cell(index: 7, columns: 5).row, 2)
        XCTAssertEqual(FocusStep.cell(index: 7, columns: 5).column, 3)
        XCTAssertEqual(FocusStep.cell(index: 3, columns: 1).row, 4, "list view: one card a row")
        XCTAssertEqual(FocusStep.cell(index: 3, columns: 0).row, 4, "never divides by zero")
    }

    func testTheTrailKeepsTheLastTwentyAndNoRepeats() {
        var trail = FocusTrail()
        for row in 1...25 { trail.record(FocusStep(screen: "Movies", row: row, column: 1, offset: row * 660)) }
        XCTAssertEqual(trail.steps.count, 20)
        XCTAssertEqual(trail.steps.first?.row, 6)
        trail.record(FocusStep(screen: "Movies", row: 25, column: 1, offset: 25 * 660))
        XCTAssertEqual(trail.steps.count, 20, "the same card twice is one move")
    }

    /// The owner's report: one Down from row 2 to row 5 shows "2 rows passed over" (rows 3 and 4).
    func testAPressThatPassesOverRowsIsNamed() {
        var trail = FocusTrail()
        trail.record(FocusStep(screen: "Movies", row: 1, column: 2, offset: 0))
        trail.record(FocusStep(screen: "Movies", row: 2, column: 2, offset: 660))
        trail.record(FocusStep(screen: "Movies", row: 5, column: 2, offset: 2640))
        XCTAssertEqual(trail.lines.first, "Movies · Row 5, Column 2 · Offset 2640 pt · 2 rows passed over")
        XCTAssertEqual(trail.lines[1], "Movies · Row 2, Column 2 · Offset 660 pt")
        XCTAssertEqual(FocusTrail.rowsPassedOver(from: FocusStep(screen: "Home", row: 1, column: 1, offset: 0),
                                                 to: FocusStep(screen: "Movies", row: 4, column: 1, offset: 0)), 0,
                       "a move to another screen passes over nothing")
    }

    func testNoTitleIsInTheLines() {
        var trail = FocusTrail()
        trail.record(FocusStep(screen: "Home", row: 2, column: 3, offset: 900))
        XCTAssertEqual(trail.lines, ["Home · Row 2, Column 3 · Offset 900 pt"])
    }

    func testSlowFramesPerScreen() {
        var frames = SlowFrames()
        let frame: Double = 1.0 / 60.0
        for _ in 0..<10 { frames.record(screen: "Movies", seconds: frame, frameSeconds: frame) }
        frames.record(screen: "Movies", seconds: 0.048, frameSeconds: frame)
        frames.record(screen: "Movies", seconds: frame * 1.4, frameSeconds: frame)
        frames.record(screen: "Home", seconds: frame, frameSeconds: frame)
        frames.record(screen: "Home", seconds: 0, frameSeconds: frame)
        XCTAssertEqual(frames.screens["Movies"]?.frames, 12)
        XCTAssertEqual(frames.screens["Movies"]?.slow, 1, "1.4 frames is not slow; 48 ms is")
        XCTAssertEqual(frames.lines, ["Home · 0 slow of 1 frames, longest 17 ms", "Movies · 1 slow of 12 frames, longest 48 ms"])
        var total = SlowFrames()
        total.merge(frames)
        var next = SlowFrames()
        next.record(screen: "Movies", seconds: 0.1, frameSeconds: frame)
        total.merge(next)
        XCTAssertEqual(total.screens["Movies"]?.frames, 13)
        XCTAssertEqual(total.screens["Movies"]?.slow, 2)
        XCTAssertEqual(total.rows.last?.value, "2 slow of 13 frames, longest 100 ms")
    }
}
