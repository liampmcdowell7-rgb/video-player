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
