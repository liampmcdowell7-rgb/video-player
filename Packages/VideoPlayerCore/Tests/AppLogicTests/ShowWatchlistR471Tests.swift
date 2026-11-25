import XCTest
import Foundation
import MetadataOnline
import UserData
@testable import AppLogic

/// R471 (61), PROVISIONAL: a matched show's list has the watchlist entry, and a show is found on the watchlist under its
/// own kind only (a movie with the same online id is another title).
final class ShowWatchlistR471Tests: XCTestCase {
    func testAMatchedShowsListHasTheWatchlist() {
        var c = ProductActionContext(kind: .show)
        c.matched = true
        XCTAssertTrue(ProductActions.list(c).contains(.addToWatchlist))
        c.onWatchlist = true
        XCTAssertTrue(ProductActions.list(c).contains(.removeFromWatchlist))
        c.matched = false
        XCTAssertFalse(ProductActions.list(c).contains { $0 == .addToWatchlist || $0 == .removeFromWatchlist })
    }

    func testMembershipIsPerKind() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = [UDWatchlistEntry(kind: "movie", tmdbID: 7, title: "A Film", addedAt: now),
                       UDWatchlistEntry(kind: "series", tmdbID: 9, title: "A Show", addedAt: now)]
        XCTAssertTrue(WatchlistMembership.contains(entries, kind: .series, tmdbID: 9))
        XCTAssertFalse(WatchlistMembership.contains(entries, kind: .series, tmdbID: 7))
        XCTAssertTrue(WatchlistMembership.contains(entries, kind: .movie, tmdbID: 7))
        XCTAssertFalse(WatchlistMembership.contains(entries, kind: .series, tmdbID: nil))
    }
}
