import XCTest
@testable import ScreenChecks

/// R471 (61), PROVISIONAL (owner 25 Nov 2026 round 6, Part B item 3): the owner's actions list for a show (R471 (8)) has
/// Add to or Remove from Watchlist when the show is matched; the show page's details button dropped it. Structure only,
/// from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testTheShowPageOffersTheWatchlistOfAMatchedShow() throws {
        guard let page = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        XCTAssertTrue(page.contains("ProductActions.list(showActions).filter { [.addToWatchlist, .removeFromWatchlist,"),
                      "the show page keeps the watchlist entries of the show's list")
        XCTAssertTrue(page.contains("case .addToWatchlist, .removeFromWatchlist:"), "the show page acts on them")
        XCTAssertTrue(page.contains("c.onWatchlist = onWatchlist"), "the list knows whether the show is on the watchlist")
        XCTAssertTrue(page.contains("WatchlistMembership.contains(services.ledger.watchlist(), kind: .series, tmdbID: showTMDB)"))
    }
}
