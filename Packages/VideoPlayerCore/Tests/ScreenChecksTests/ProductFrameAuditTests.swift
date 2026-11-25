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

    /// R471 (29): an episode's list entry is named "Show: Episode", interpolated, not the literal text.
    func testAnEpisodesListNameIsInterpolated() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(detail.contains(#"return "\(content.title): \(episode)""#))
        XCTAssertFalse(detail.contains(#"return "(content.title): (episode)""#))
    }
}
