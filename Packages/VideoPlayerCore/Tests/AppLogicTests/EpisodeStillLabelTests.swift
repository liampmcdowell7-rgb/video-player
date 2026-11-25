import XCTest
@testable import AppLogic

/// R471 (28): the running time or the time left at the foot of an episode's still.
final class EpisodeStillLabelTests: XCTestCase {
    func testAnUnwatchedEpisodeShowsItsRunningTime() {
        XCTAssertEqual(EpisodeStillLabel.text(durationSeconds: 47 * 60, progress: nil, isWatched: false), "47m")
        XCTAssertEqual(EpisodeStillLabel.text(durationSeconds: 65 * 60, progress: 0, isWatched: false), "1h 5m")
    }

    func testAPartWatchedEpisodeShowsTheTimeLeftRoundedUp() {
        // 47 minutes, a little over 60 % watched: 18.2 minutes left, rounded up as on the Play button.
        XCTAssertEqual(EpisodeStillLabel.text(durationSeconds: 47 * 60, progress: 0.6128, isWatched: false), "19m")
        XCTAssertEqual(EpisodeStillLabel.text(durationSeconds: 60 * 60, progress: 0.5, isWatched: false), "30m")
    }

    func testNothingForAWatchedEpisodeOrAnUnknownDuration() {
        XCTAssertNil(EpisodeStillLabel.text(durationSeconds: 47 * 60, progress: nil, isWatched: true))
        XCTAssertNil(EpisodeStillLabel.text(durationSeconds: nil, progress: 0.5, isWatched: false))
        XCTAssertNil(EpisodeStillLabel.text(durationSeconds: 0, progress: nil, isWatched: false))
        XCTAssertNil(EpisodeStillLabel.text(durationSeconds: .nan, progress: nil, isWatched: false))
    }
}
