import XCTest
import MetadataOnline
@testable import AppLogic

/// R342: Select on a Discover card opens the title; the watchlist moved into the context menu and onto the page.
final class DiscoverCardActionsTests: XCTestCase {
    private func title(_ id: Int, _ name: String, onList: Bool = false) -> DiscoverTitle {
        DiscoverTitle(kind: .movie, tmdbID: id, title: name, year: 2020, reason: "Similar to Sample Movie 1", onWatchlist: onList)
    }

    func testATitleIsFoundInEverySection() {
        let content = DiscoverContent(collectionGaps: [CollectionGap(collectionID: 1, name: "C", ownedCount: 1, missing: [title(2, "In Gap")])],
                                      similar: [title(3, "Similar")], watchlist: [title(4, "Listed", onList: true)])
        XCTAssertEqual(content.title(id: "movie-2")?.title, "In Gap")
        XCTAssertEqual(content.title(id: "movie-3")?.title, "Similar")
        XCTAssertEqual(content.title(id: "movie-4")?.title, "Listed")
        XCTAssertNil(content.title(id: "movie-5"))
    }

    func testTheWatchlistActionNamesWhatItWillDo() {
        XCTAssertEqual(DiscoverCardText.watchlistAction(title(1, "A")).label, "Add to Watchlist")
        XCTAssertEqual(DiscoverCardText.watchlistAction(title(1, "A", onList: true)).label, "Remove from Watchlist")
        XCTAssertEqual(DiscoverCardText.watchlistAction(title(1, "A")).symbol, "plus.circle")
        XCTAssertEqual(DiscoverCardText.kindText(title(1, "A")), "Movie")
    }

    #if DEBUG // the invented Discover exists only in debug builds (tests are built debug)
    func testThePageSeesTheToggleMadeFromTheMenu() async {
        var model = DiscoverViewModel(source: UITestFixtureDiscover.Source(), library: UITestFixtureDiscover.Library(), watchlist: MemoryWatchlist())
        await model.load()
        guard case .loaded(let before) = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(before.similar.map(\.title), ["Sample Suggestion 1", "Sample Suggestion 2", "Sample Suggested Show"])
        XCTAssertTrue(before.problems.isEmpty, "\(before.problems)")
        let first = before.similar[0]
        model.toggleWatchlist(first)
        XCTAssertEqual(model.state.content?.title(id: first.id)?.onWatchlist, true, "the page reads the title by id, so it shows the new state")
        XCTAssertEqual(model.state.content?.watchlist.first?.id, first.id)
    }
    #endif
}
