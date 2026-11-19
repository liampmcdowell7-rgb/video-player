import XCTest
@testable import UserData

final class WatchlistTests: XCTestCase {
    private func entry(_ id: Int, _ title: String, at t: Double, kind: String = "movie") -> UDWatchlistEntry {
        UDWatchlistEntry(kind: kind, tmdbID: id, title: title, year: 2001, posterPath: "/p\(id).jpg", addedAt: Date(timeIntervalSince1970: t))
    }

    func testAddListRemoveAndReAdd() {
        let ledger = UserDataLedger(deviceID: "A")
        ledger.addToWatchlist(entry(1, "One", at: 100), at: Date(timeIntervalSince1970: 100))
        ledger.addToWatchlist(entry(2, "Two", at: 200, kind: "series"), at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(ledger.watchlist().map(\.title), ["Two", "One"], "newest first")
        ledger.removeFromWatchlist(kind: "movie", tmdbID: 1, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(ledger.watchlist().map(\.title), ["Two"])
        ledger.addToWatchlist(entry(1, "One", at: 400), at: Date(timeIntervalSince1970: 400))
        XCTAssertEqual(Set(ledger.watchlist().map(\.title)), ["One", "Two"], "a later add brings a removed title back")
    }

    func testTheSameNumberAsMovieAndSeriesAreTwoEntries() {
        let ledger = UserDataLedger(deviceID: "A")
        ledger.addToWatchlist(entry(5, "Film", at: 1, kind: "movie"))
        ledger.addToWatchlist(entry(5, "Show", at: 2, kind: "series"))
        XCTAssertEqual(ledger.watchlist().count, 2)
    }

    func testTwoDevicesMergeAndARemovalOnOneWinsOverAnOlderAdd() async throws {
        let cloud = InMemoryCloud()
        let a = UserDataLedger(deviceID: "A"), b = UserDataLedger(deviceID: "B")
        a.addToWatchlist(entry(1, "One", at: 100), at: Date(timeIntervalSince1970: 100))
        _ = await UserDataSyncEngine(ledger: a, cloud: cloud, sleep: { _ in }).sync()
        _ = await UserDataSyncEngine(ledger: b, cloud: cloud, sleep: { _ in }).sync()
        XCTAssertEqual(b.watchlist().map(\.title), ["One"], "the second device receives it")
        b.removeFromWatchlist(kind: "movie", tmdbID: 1, at: Date(timeIntervalSince1970: 500))
        b.addToWatchlist(entry(2, "Two", at: 510), at: Date(timeIntervalSince1970: 510))
        _ = await UserDataSyncEngine(ledger: b, cloud: cloud, sleep: { _ in }).sync()
        _ = await UserDataSyncEngine(ledger: a, cloud: cloud, sleep: { _ in }).sync()
        XCTAssertEqual(a.watchlist().map(\.title), ["Two"])
    }

    func testAnUnknownFieldFromANewerAppIsKeptWhenMerging() {
        var newer = UDWatchlist.patch(entry(7, "Septima", at: 10), at: UDStamp(time: 10, device: "N"))
        newer.set("futureField", .string("x"), at: UDStamp(time: 11, device: "N"))
        let ledger = UserDataLedger(deviceID: "A")
        ledger.apply(newer)
        ledger.apply(UDWatchlist.patch(entry(7, "Septima", at: 10), at: UDStamp(time: 12, device: "A")))
        XCTAssertEqual(ledger.record(type: "watchlist", id: "movie-7")?["futureField"], .string("x"))
        XCTAssertEqual(ledger.watchlist().count, 1)
    }

    func testARecordWithMissingFieldsIsIgnoredNotACrash() {
        let ledger = UserDataLedger(deviceID: "A")
        ledger.apply(UDRecord(type: "watchlist", id: "movie-9", fields: ["kind": UDField(.string("movie"), UDStamp(time: 1, device: "A"))]))
        XCTAssertTrue(ledger.watchlist().isEmpty)
    }
}
