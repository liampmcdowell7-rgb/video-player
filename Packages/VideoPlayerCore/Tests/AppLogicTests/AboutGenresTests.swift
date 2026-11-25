import XCTest
@testable import AppLogic

/// R471 (30): the About card's genre line. FIXTURE: invented genre lists.
final class AboutGenresTests: XCTestCase {
    func testTheGenresJoinedWithCommas() {
        XCTAssertEqual(AboutGenres.line(["Comedy", "Sports"]), "Comedy, Sports")
    }

    func testBlankAndRepeatedNamesAreDroppedAndAtMostThreeKept() {
        XCTAssertEqual(AboutGenres.line([" Drama ", "", "drama", "Crime", "Mystery", "Western"]), "Drama, Crime, Mystery")
    }

    func testNoLineWithoutAGenre() {
        XCTAssertNil(AboutGenres.line([]))
        XCTAssertNil(AboutGenres.line(["  ", "\n"]))
    }
}
