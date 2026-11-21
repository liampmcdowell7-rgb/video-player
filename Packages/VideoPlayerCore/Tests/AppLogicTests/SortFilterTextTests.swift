import XCTest
@testable import AppLogic

/// R344: the one Sort and Filter menu.
final class SortFilterTextTests: XCTestCase {
    func testTheSortSubmenuSaysTheCurrentOrder() {
        XCTAssertEqual(SortFilterText.sortTitle(order: "Title, A to Z"), "Sort By (Title, A to Z)")
        XCTAssertEqual(SortFilterText.sortTitle(order: ""), "Sort By")
        // The menu check accepts "Sort By" or "Sort By (…" (ScreenRules.menu), like "Resolution (2)".
        XCTAssertTrue(SortFilterText.sortTitle(order: "Year, Newest First").hasPrefix("Sort By ("))
    }

    func testVoiceOverHearsTheOrderAndTheFilters() {
        XCTAssertEqual(SortFilterText.spokenValue(order: "Title, A to Z", filtersOn: 0), "Title, A to Z; no filters")
        XCTAssertEqual(SortFilterText.spokenValue(order: "Title, A to Z", filtersOn: 1), "Title, A to Z; 1 filter on")
        XCTAssertEqual(SortFilterText.spokenValue(order: "Title, A to Z", filtersOn: 3), "Title, A to Z; 3 filters on")
    }
}
