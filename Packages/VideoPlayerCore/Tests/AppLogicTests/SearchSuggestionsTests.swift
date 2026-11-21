import XCTest
@testable import AppLogic

/// R337: suggestions are the library titles already found, each once, at most five, nothing when the field is empty.
final class SearchSuggestionsTests: XCTestCase {
    func testResultTitlesInOrderOnceAndAtMostTheLimit() {
        let titles = ["Sample Movie 1", "Sample Show 1", "sample movie 1", "Sample Movie 2", "Sample Movie 3", "Sample Movie 4", "Sample Movie 5"]
        XCTAssertEqual(SearchSuggestions.titles(titles, query: "sam"),
                       ["Sample Movie 1", "Sample Show 1", "Sample Movie 2", "Sample Movie 3", "Sample Movie 4"])
    }

    func testNothingTypedGivesNothingAndTheTypedTitleIsLeftOut() {
        XCTAssertEqual(SearchSuggestions.titles(["Sample Movie 1"], query: ""), [])
        XCTAssertEqual(SearchSuggestions.titles(["Sample Movie 1"], query: "   "), [])
        XCTAssertEqual(SearchSuggestions.titles(["Sample Movie 1", "Sample Movie 2"], query: "sample movie 1 "), ["Sample Movie 2"])
        XCTAssertEqual(SearchSuggestions.titles(["A", ""], query: "x", limit: 0), [])
    }
}
