import XCTest
@testable import AppLogic

// The tab bar and the Search tab (OPEN_QUESTIONS R167, option (c), PROVISIONAL).

final class AppTabsTests: XCTestCase {
    func testSixTabsInOrderWithoutDiscover() {
        XCTAssertEqual(AppTabID.allCases.map(\.title), ["Home", "Movies", "Shows", "Files", "Search", "Settings"])
        XCTAssertEqual(AppTabID.allCases.map(\.rawValue), ["home", "movies", "shows", "files", "search", "settings"])
        XCTAssertNil(AppTabID(rawValue: "discover"), "Discover is no longer a tab; it lives in Search")
    }

    func testScreenIdentifiers() {
        XCTAssertEqual(AppTabID.allCases.map(\.screenIdentifier),
                       ["screen.home", "screen.movies", "screen.shows", "screen.files", "screen.search", "screen.settings"])
    }

    func testLibraryOnlyTabs() {
        XCTAssertEqual(AppTabID.allCases.filter(\.showsLibraryOnly), [.home, .movies, .shows, .files])
    }

    func testEmptyFieldShowsDiscover() {
        XCTAssertEqual(SearchTabContent.forQuery("", showDiscover: true), .discover)
        XCTAssertEqual(SearchTabContent.forQuery("   ", showDiscover: true), .discover, "spaces alone count as empty")
        XCTAssertEqual(SearchTabContent.forQuery("\n\t", showDiscover: true), .discover)
    }

    func testTypedTextShowsLibraryResults() {
        XCTAssertEqual(SearchTabContent.forQuery("s", showDiscover: true), .libraryResults)
        XCTAssertEqual(SearchTabContent.forQuery(" sam ", showDiscover: true), .libraryResults)
        XCTAssertEqual(SearchTabContent.forQuery("sam", showDiscover: false), .libraryResults)
    }

    func testClearingTheFieldBringsDiscoverBack() {
        let steps = ["", "s", "sa", "s", ""].map { SearchTabContent.forQuery($0, showDiscover: true) }
        XCTAssertEqual(steps, [.discover, .libraryResults, .libraryResults, .libraryResults, .discover])
    }

    func testDiscoverOffShowsPromptAndLoadsNothing() {
        let content = SearchTabContent.forQuery("", showDiscover: false)
        XCTAssertEqual(content, .prompt)
        XCTAssertFalse(content.loadsDiscover)
    }

    func testOnlyTheDiscoverStateLoadsDiscover() {
        XCTAssertTrue(SearchTabContent.discover.loadsDiscover)
        XCTAssertFalse(SearchTabContent.libraryResults.loadsDiscover, "typing never sends a discovery request")
        XCTAssertFalse(SearchTabContent.prompt.loadsDiscover)
    }
}
