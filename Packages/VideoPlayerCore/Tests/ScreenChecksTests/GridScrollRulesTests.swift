import XCTest
@testable import ScreenChecks

/// R443: the scrolled library grid. Frames are 1920 x 1080 points, five columns of 300 x 450 posters.
final class GridScrollRulesTests: XCTestCase {
    private func card(_ name: String, col: Int, top: Double, height: Double = 560) -> (String, AXRect) {
        (name, AXRect(x: 90 + Double(col) * 340, y: top, width: 300, height: height))
    }

    private let controls: [(String, AXRect)] = [
        ("Sort and Filter", AXRect(x: 1500, y: 100, width: 90, height: 90)),
        ("Save View", AXRect(x: 1610, y: 100, width: 90, height: 90)),
        ("More", AXRect(x: 1720, y: 100, width: 90, height: 90)),
    ]

    /// Five cards a row, rows 660 pt apart (the run's pitch), the first row's top at `firstTop`; names "R<row>C<col>".
    private func grid(rows: Int, firstTop: Double) -> [(String, AXRect)] {
        (0..<rows).flatMap { row in (0..<5).map { col in card("R\(row)C\(col)", col: col, top: firstTop + Double(row) * 660) } }
    }

    /// What R443's `WholeRowOnly` drew: only cards at least 98 % on the 1080 pt screen.
    private func drawnByWholeRowOnly(_ cards: [(String, AXRect)]) -> [(String, AXRect)] {
        cards.filter { card in
            let visible: Double = max(0, min(card.1.maxY, 1080) - max(card.1.y, 0))
            return visible / card.1.height >= 0.98
        }
    }

    /// R471 (49): the owner's report, one Down from the first row landing three rows on, fails; the next row passes.
    func testDownSkippingRowsFails() {
        let before = grid(rows: 5, firstTop: 260)
        let skipped = GridScrollRules.downReachesNextRow(before: before, focusedBefore: "R0C2", focusedAfter: "R3C2")
        XCTAssertFalse(skipped.passed, skipped.text)
        XCTAssertTrue(skipped.text.contains("2 row(s) skipped"), skipped.text)
        XCTAssertTrue(GridScrollRules.downReachesNextRow(before: before, focusedBefore: "R0C2", focusedAfter: "R1C2").passed)
        XCTAssertTrue(GridScrollRules.downReachesNextRow(before: before, focusedBefore: "R1C4", focusedAfter: "R2C0").passed, "any card of the next row")
        XCTAssertTrue(GridScrollRules.downReachesNextRow(before: before, focusedBefore: "R4C1", focusedAfter: "R4C1").passed, "the last row has none under it")
        XCTAssertFalse(GridScrollRules.downReachesNextRow(before: before, focusedBefore: "R0C0", focusedAfter: "R9C0").passed, "a card not on the page")
    }

    /// R471 (49): the focused row is wholly on screen after the move, not cut by an edge.
    func testTheFocusedRowIsWholeOnScreen() {
        let cards = grid(rows: 3, firstTop: 100)
        XCTAssertTrue(GridScrollRules.focusedRowWhole(cards: cards, focused: "R0C1", screenTop: 0, screenBottom: 1080).passed)
        let cut = GridScrollRules.focusedRowWhole(cards: cards, focused: "R1C1", screenTop: 0, screenBottom: 1080)
        XCTAssertFalse(cut.passed, "row 1 runs 760 to 1320: \(cut.text)")
    }

    /// R471 (49): "only one row displays at a time". With rows 660 pt apart on a 1080 pt screen, R443's whole-row rule drew
    /// a single row; drawing every card shows the focused row and part of the next.
    func testMoreThanOneRowIsShown() {
        let cards = grid(rows: 4, firstTop: 100)
        let before = GridScrollRules.moreThanOneRowShown(shown: drawnByWholeRowOnly(cards), totalRows: 4, screenTop: 0, screenBottom: 1080)
        XCTAssertFalse(before.passed, "R443 drew one row: \(before.text)")
        let after = GridScrollRules.moreThanOneRowShown(shown: cards, totalRows: 4, screenTop: 0, screenBottom: 1080)
        XCTAssertTrue(after.passed, after.text)
        XCTAssertTrue(GridScrollRules.moreThanOneRowShown(shown: grid(rows: 1, firstTop: 100), totalRows: 1, screenTop: 0, screenBottom: 1080).passed,
                      "a grid of one row has no second row to show")
    }

    func testControlsOnPostersFail() {
        // The run's picture: posters scrolled under the three pinned buttons.
        let posters = [card("Poster A", col: 4, top: 60), card("Poster B", col: 2, top: 700)]
        let result = GridScrollRules.controlsClearOfPosters(controls: controls, posters: posters)
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("“Sort and Filter” is on “Poster A”") || result.text.contains("is on “Poster A”"), result.text)
    }

    func testControlsAboveTheFirstRowPass() {
        let posters = [card("Poster A", col: 4, top: 260), card("Poster B", col: 3, top: 260)]
        XCTAssertTrue(GridScrollRules.controlsClearOfPosters(controls: controls, posters: posters).passed)
        // Touching edges are not an overlap.
        XCTAssertTrue(GridScrollRules.controlsClearOfPosters(controls: controls, posters: [card("Edge", col: 4, top: 190)]).passed)
    }

    func testAHalfRowUnderTheHeaderFails() {
        // Header ends at 200; the row of "A" starts at 40 and ends at 600: cut by the edge, with clipped titles.
        let cards = [card("A", col: 0, top: 40), card("B", col: 1, top: 41), card("C", col: 0, top: 740)]
        let result = GridScrollRules.noHalfRowUnderHeader(cards: cards, headerBottom: 200)
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("row of “A”"), result.text)
    }

    func testWholeRowsPass() {
        // The first row sits right under the header, the second further down; a row that scrolled away is not in the tree.
        let cards = [card("A", col: 0, top: 220), card("B", col: 1, top: 220), card("C", col: 0, top: 880)]
        XCTAssertTrue(GridScrollRules.noHalfRowUnderHeader(cards: cards, headerBottom: 200).passed)
        // A row that ends exactly at the edge is fully above it.
        XCTAssertTrue(GridScrollRules.noHalfRowUnderHeader(cards: [card("Gone", col: 0, top: -400)], headerBottom: 160).passed)
    }

    func testRowPitchIsMeasuredAndMustBeEqual() {
        let same = [card("A", col: 0, top: 200), card("B", col: 0, top: 860), card("C", col: 0, top: 1520)]
        let measured = GridScrollRules.rowPitch(cards: same)
        XCTAssertEqual(measured.pitch, 660)
        XCTAssertTrue(measured.result.passed, measured.result.text)
        let uneven = [card("A", col: 0, top: 200), card("B", col: 0, top: 860), card("C", col: 0, top: 1700)]
        XCTAssertFalse(GridScrollRules.rowPitch(cards: uneven).result.passed)
        XCTAssertNil(GridScrollRules.rowPitch(cards: [card("A", col: 0, top: 200)]).pitch)
    }

    func testCutTitlesAreListed() {
        XCTAssertTrue(GridScrollRules.noTitleCut(cut: [], total: 12).passed)
        let result = GridScrollRules.noTitleCut(cut: ["People We Meet On Vacation"], total: 12)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.text.contains("“People We Meet On Vacation”"), result.text)
    }
}
