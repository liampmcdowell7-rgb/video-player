import XCTest
@testable import ScreenChecks

/// R471 (27) onwards, PROVISIONAL: differences the frame-by-frame audit of the product pages found, one check per fix.
/// Structure only, from the source: nothing is compiled or run on tvOS here, and nothing here proves the look.
extension ScreenChecksTests {
    /// R471 (27): the Information, Languages and Accessibility headings are a large bold system style.
    func testTheInfoColumnHeadingsAreLargeAndBold() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("Text(heading)\n                .font(.title2.weight(.bold))"), "the column heading style")
    }
}
