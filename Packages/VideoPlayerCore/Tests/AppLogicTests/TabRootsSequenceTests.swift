import XCTest
@testable import AppLogic

/// Sidebar (R359) with R348: a longer run of selections, as someone moves around the sidebar. Only a re-selection of the
/// selected item raises a root generation, and only that item's.
final class TabRootsSequenceTests: XCTestCase {
    func testALongRunOfSelectionsCountsOnlyReselections() {
        var roots = TabRoots()
        var current: AppTabID = .home
        let presses: [AppTabID] = [.home, .movies, .movies, .shows, .files, .files, .files, .search, .settings, .home, .home]
        var expected: [AppTabID: Int] = [:]
        for tab in presses {
            let wasReselection: Bool = roots.select(tab, current: current)
            XCTAssertEqual(wasReselection, tab == current, "\(tab) after \(current)")
            if tab == current { expected[tab, default: 0] += 1 }
            current = tab
        }
        for tab in AppTabID.allCases {
            XCTAssertEqual(roots.generation(of: tab), expected[tab, default: 0], tab.rawValue)
        }
        XCTAssertEqual(expected, [.home: 2, .movies: 1, .files: 2])
    }

    func testGenerationsNeverGoDown() {
        var roots = TabRoots()
        var last: [AppTabID: Int] = [:]
        for tab in AppTabID.allCases + AppTabID.allCases.reversed() {
            _ = roots.select(tab, current: tab)
            _ = roots.select(.home, current: tab)
            for other in AppTabID.allCases {
                XCTAssertGreaterThanOrEqual(roots.generation(of: other), last[other, default: 0], other.rawValue)
                last[other] = roots.generation(of: other)
            }
        }
    }

    func testTwoCopiesAreIndependent() {
        var first = TabRoots()
        let second = first
        _ = first.select(.settings, current: .settings)
        XCTAssertEqual(first.generation(of: .settings), 1)
        XCTAssertEqual(second.generation(of: .settings), 0, "a value type: the copy keeps its own count")
    }
}
