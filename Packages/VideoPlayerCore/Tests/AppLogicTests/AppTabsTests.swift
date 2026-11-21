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

    // R348 (item B): re-selecting the selected tab takes it back to its root; selecting another tab does not.
    func testReselectingTheSelectedTabRaisesOnlyThatTabsRootGeneration() {
        var roots = TabRoots()
        XCTAssertEqual(roots.generation(of: .settings), 0)
        XCTAssertTrue(roots.select(.settings, current: .settings), "pressing Settings again is a re-selection")
        XCTAssertEqual(roots.generation(of: .settings), 1)
        XCTAssertEqual(roots.generation(of: .home), 0, "the other tabs keep their pages")
        XCTAssertTrue(roots.select(.settings, current: .settings))
        XCTAssertEqual(roots.generation(of: .settings), 2)
    }

    func testSelectingAnotherTabKeepsEveryTabsPages() {
        var roots = TabRoots()
        XCTAssertFalse(roots.select(.movies, current: .home))
        XCTAssertFalse(roots.select(.home, current: .movies))
        for tab in AppTabID.allCases { XCTAssertEqual(roots.generation(of: tab), 0, tab.rawValue) }
    }

    func testEveryTabCanBeReselected() {
        var roots = TabRoots()
        for tab in AppTabID.allCases {
            XCTAssertTrue(roots.select(tab, current: tab), tab.rawValue)
            XCTAssertEqual(roots.generation(of: tab), 1, tab.rawValue)
        }
    }
}
