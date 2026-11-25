import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

// FIXTURE: an in-memory server that records the ratings it is sent; nothing leaves the process.

private final class RecordingRater: ServerWatchWriting, ServerRatingWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var sent: [String] = []
    var fails = false
    func report(_ report: ServerTimelineReport) async throws {}
    func markPlayed(itemKey: String) async throws {}
    func markUnplayed(itemKey: String) async throws {}
    func rate(itemKey: String, stars: Int?) async throws {
        if fails { throw Boom() }
        lock.withLock { sent.append("\(itemKey)=\(stars.map(String.init) ?? "clear")") }
    }
}

private final class PlainWriter: ServerWatchWriting, @unchecked Sendable {
    func report(_ report: ServerTimelineReport) async throws {}
    func markPlayed(itemKey: String) async throws {}
    func markUnplayed(itemKey: String) async throws {}
}

private struct FakeServer: ServerWatchSource {
    let watchWriter: any ServerWatchWriting
    func serverItemKey(at path: String) async throws -> String? { "key:" + path.split(separator: "/").last.map(String.init)! }
    func serverWatchState(at path: String) async throws -> ServerWatchState? { nil }
    func serverWatchStates() async throws -> [String: ServerWatchState] { [:] }
}

/// R471 (16), Part 4: the rating in the user layer (newest across keys, clear wins, kept to 1 to 5), the menu's words, and
/// what is sent to a server that keeps ratings (only while its switch is on; nothing for a server that cannot take it).
final class RatingTests: XCTestCase {
    private func ledger() -> UserDataLedger { UserDataLedger(deviceID: "A", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    func testTheNewestRatingAcrossTheKeysWinsAndAClearWinsToo() {
        let l = ledger()
        let byID = UDEditKey.movie(tmdbID: 949), byFile = UDEditKey.file(sourceID: "src1", path: "/Movies/a.mkv")
        XCTAssertNil(l.rating(for: [byID, byFile]))
        l.setRating(byFile, stars: 3, at: Date(timeIntervalSince1970: 1))
        l.setRating(byID, stars: 5, at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(l.rating(for: [byID, byFile]), 5)
        l.setRating(byFile, stars: nil, at: Date(timeIntervalSince1970: 3))
        XCTAssertNil(l.rating(for: [byID, byFile]), "a newer clear wins")
        l.setRating(byID, stars: 9, at: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(l.rating(for: [byID]), 5, "kept to five stars")
    }

    func testTheMenuWords() {
        XCTAssertEqual(RatingText.choices, [5, 4, 3, 2, 1])
        XCTAssertEqual(RatingText.title(1), "1 Star")
        XCTAssertEqual(RatingText.title(4), "4 Stars")
        XCTAssertEqual(RatingText.menuTitle(current: nil), "Rate")
        XCTAssertEqual(RatingText.menuTitle(current: 3), "Rate: 3 Stars")
        XCTAssertEqual(RatingText.clear, "No Rating")
    }

    func testARatingGoesToTheServerOnlyWhileItsSwitchIsOn() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let rater = RecordingRater()
        let on = ServerRatingSender(store: rig.store, isOn: { _ in true }, source: { _ in FakeServer(watchWriter: rater) })
        let result = await on.send(itemIDs: [id], stars: 4)
        XCTAssertEqual(result.sent, 1)
        XCTAssertEqual(rater.sent, ["key:Hexfall (1995).mkv=4"])
        await on.send(itemIDs: [id], stars: nil)
        XCTAssertEqual(rater.sent.last, "key:Hexfall (1995).mkv=clear")

        let off = ServerRatingSender(store: rig.store, isOn: { _ in false }, source: { _ in FakeServer(watchWriter: rater) })
        let none = await off.send(itemIDs: [id], stars: 2)
        XCTAssertEqual(none.sent, 0)
        XCTAssertEqual(rater.sent.count, 2, "nothing is sent while the switch is off")

        let plain = ServerRatingSender(store: rig.store, isOn: { _ in true }, source: { _ in FakeServer(watchWriter: PlainWriter()) })
        let skipped = await plain.send(itemIDs: [id], stars: 2)
        XCTAssertEqual(skipped.sent + skipped.failed, 0, "a server that keeps no ratings is not asked")
    }

    func testAFailureIsCountedAndNotThrown() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let rater = RecordingRater()
        rater.fails = true
        let result = await ServerRatingSender(store: rig.store, isOn: { _ in true }, source: { _ in FakeServer(watchWriter: rater) })
            .send(itemIDs: [id], stars: 3)
        XCTAssertEqual(result.failed, 1)
    }

    func testRateIsOfferedForEveryKindAndOnTheLongPress() {
        for kind in [ProductActionContext.Kind.movie, .episode, .show, .season] {
            XCTAssertTrue(ProductActions.list(ProductActionContext(kind: kind)).contains(.rate), "\(kind)")
        }
        XCTAssertTrue(ProductActions.cardSupported.contains(.rate))
    }
}
