import XCTest
@testable import ScreenChecks

/// R471 (35), PROVISIONAL: the About card's synopsis keeps five lines (the reference card's length); selecting the card
/// still opens the whole text. Structure only, from the source: nothing is compiled or run on tvOS here.
extension ScreenChecksTests {
    func testTheAboutSynopsisKeepsFiveLines() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("Text(summary)\n                                .font(.callout)"))
        XCTAssertTrue(sections.contains(".lineLimit(5, reservesSpace: true)"))
        XCTAssertTrue(sections.contains("SynopsisCover(title: title, text: summary"), "the whole text one select away")
    }
}
