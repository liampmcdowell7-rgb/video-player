import XCTest
@testable import AppLogic

/// R471 (31): an episode's Go to Season names the season it opens.
final class GoToSeasonTitleTests: XCTestCase {
    func testTheSeasonIsNamed() {
        XCTAssertEqual(ProductAction.goToSeasonTitle(4), "Go to Season 4")
        XCTAssertEqual(ProductAction.goToSeasonTitle(0), "Go to Specials")
    }

    func testThePlainTitleWithoutASeason() {
        XCTAssertEqual(ProductAction.goToSeasonTitle(nil), ProductAction.goToSeason.title)
        XCTAssertEqual(ProductAction.goToSeasonTitle(-1), ProductAction.goToSeason.title)
    }
}
