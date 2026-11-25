import XCTest
@testable import AppLogic

/// R471 item 3: the capsule Play button's content.
final class PlayCapsuleTests: XCTestCase {
    func testNotStartedSaysPlay() {
        for progress in [nil, 0, 1, 1.2, -0.1] as [Double?] {
            let c = PlayCapsule.make(progress: progress, durationSeconds: 2_580)
            XCTAssertEqual(c.title, "Play")
            XCTAssertNil(c.progress)
            XCTAssertNil(c.timeLeft)
            XCTAssertEqual(c.spoken, "Play")
        }
    }

    func testPartlyWatchedShowsTheBarAndTheTimeLeft() {
        // 43 min, 25 min watched: 18 min left (the frames' "18m").
        let c = PlayCapsule.make(progress: 25.0 / 43.0, durationSeconds: 43 * 60)
        XCTAssertEqual(c.progress ?? 0, 25.0 / 43.0, accuracy: 1e-9)
        XCTAssertEqual(c.timeLeft, "18m")
        XCTAssertEqual(c.spoken, "Resume, 18 min left")
    }

    func testProgressWithoutADurationInventsNoTime() {
        let c = PlayCapsule.make(progress: 0.5, durationSeconds: nil)
        XCTAssertEqual(c.progress, 0.5)
        XCTAssertNil(c.timeLeft)
        XCTAssertEqual(c.spoken, "Resume")
    }

    func testTheWatchlistButton() {
        XCTAssertEqual(WatchlistButton.symbol(onList: false), "plus")
        XCTAssertEqual(WatchlistButton.symbol(onList: true), "checkmark")
        XCTAssertEqual(WatchlistButton.label(onList: false), "Add to Watchlist")
    }
}
