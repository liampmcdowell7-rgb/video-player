import XCTest
@testable import AppLogic

/// R336: initials in place of a missing cast photo (HIG Lockups, Monograms).
final class MonogramTests: XCTestCase {
    func testFirstAndLastWord() {
        XCTAssertEqual(Monogram.initials("Sample Actor 2"), "S2")
        XCTAssertEqual(Monogram.initials("ada lovelace"), "AL")
        XCTAssertEqual(Monogram.initials("Mary Ann Evans"), "ME")
    }

    func testOneWordGivesOneLetter() {
        XCTAssertEqual(Monogram.initials("Cher"), "C")
        XCTAssertEqual(Monogram.initials("  Cher  "), "C")
    }

    func testPunctuationIsSkippedAndNoLetterGivesNothing() {
        XCTAssertEqual(Monogram.initials("\u{201C}Sample\u{201D} (Actor)"), "SA")
        XCTAssertEqual(Monogram.initials(""), "")
        XCTAssertEqual(Monogram.initials(" - "), "")
    }

    #if DEBUG
    /// The sample cast's even-numbered actors have no photo: each gets initials (pictures 60, 61, 77).
    func testFixtureCastHasInitials() {
        let withoutPhoto = UITestFixtureDetails.cast(4).filter { $0.photo == nil }
        XCTAssertEqual(withoutPhoto.count, 2)
        for member in withoutPhoto {
            XCTAssertFalse(Monogram.initials(member.name).isEmpty, member.name)
        }
    }
    #endif
}
