import XCTest
@testable import AppLogic
import PlaybackLogic

/// R340: the system Up Next timing and the player's Episodes tab.
final class PlayerPanelsTests: XCTestCase {
    func testAcceptanceIntervalCountsFromTheCard() {
        // Card at the credits start, 120 s before the end: accept 10 s later, 110 s before the end.
        XCTAssertEqual(UpNextCard.acceptanceInterval(autoPlay: true, position: 2_280, duration: 2_400), -110)
        // Card 3 s before the end: accept 7 s after the end.
        XCTAssertEqual(UpNextCard.acceptanceInterval(autoPlay: true, position: 2_397, duration: 2_400), 7)
        XCTAssertTrue(UpNextCard.acceptanceInterval(autoPlay: false, position: 2_280, duration: 2_400).isNaN, "Auto-Play off: the system never accepts")
        XCTAssertEqual(UpNextCard.acceptanceInterval(autoPlay: true, position: 10, duration: nil), 10)
    }

    func testRemainingFollowsThePlayhead() {
        XCTAssertEqual(UpNextCard.remaining(position: 2_280, duration: 2_400, interval: -110), 10)
        XCTAssertEqual(UpNextCard.remaining(position: 2_287.5, duration: 2_400, interval: -110), 3)
        XCTAssertEqual(UpNextCard.remaining(position: 2_400, duration: 2_400, interval: -110), 0)
        XCTAssertNil(UpNextCard.remaining(position: 2_280, duration: 2_400, interval: .nan))
        XCTAssertEqual(UpNextCard.countdownText(7), "Playing in 7 seconds")
        XCTAssertNil(UpNextCard.countdownText(0))
    }

    func testTheLogicWaitsForTheSystem() {
        XCTAssertEqual(PlayerSessionFactory.systemUpNextSettings().mode, .ask)
    }

    func testAskModeAcceptAdvancesOnce() {
        let clock = ManualClock()
        let next = EpisodeRef(seriesID: "1", season: 1, episode: 2, lastEpisode: nil, fileID: "42")
        var machine = NextEpisodeMachine(duration: 100, credits: CreditsTiming(start: 90, end: 100), next: .next(next),
                                         policy: NextEpisodePolicy(settings: PlayerSessionFactory.systemUpNextSettings()), clock: clock)
        XCTAssertTrue(machine.handle(.playhead(91, .natural)).contains(.presentProposal(next)))
        clock.advance(by: 60)
        XCTAssertFalse(machine.handle(.tick).contains(.advance(next)), "no countdown of our own")
        XCTAssertEqual(machine.handle(.ended).filter { if case .advance = $0 { return true } else { return false } }.count, 0)
        XCTAssertEqual(machine.handle(.accept), [.advance(next)], "the system's accept starts the next episode")
        XCTAssertEqual(machine.handle(.accept), [], "once")
        XCTAssertEqual(NextEpisodeFeed.libraryItemID(for: next), 42)
    }
}
