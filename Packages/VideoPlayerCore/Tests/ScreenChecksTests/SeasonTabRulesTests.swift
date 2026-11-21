import XCTest
@testable import ScreenChecks

/// R339: one season's episodes under the season tabs.
final class SeasonTabRulesTests: XCTestCase {
    func testOneSeasonPasses() {
        let result = ScreenRules.oneSeasonListed(cardLabels: ["S1 E1, Pilot", "S1 E2, Second", "Season 1", "More"])
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "ONE SEASON OK")
    }

    func testEverySeasonAsItsOwnShelfFails() {
        let result = ScreenRules.oneSeasonListed(cardLabels: ["S1 E1, Pilot", "S2 E1, Return", "S2 E3, A very long episode title"])
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.text.contains("S1, S2"))
    }

    func testNoCardsFails() {
        XCTAssertFalse(ScreenRules.oneSeasonListed(cardLabels: ["Season 1", "Sample Show 1"]).passed)
    }
}
