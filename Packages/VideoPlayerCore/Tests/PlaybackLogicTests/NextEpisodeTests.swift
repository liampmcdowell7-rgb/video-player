import XCTest
@testable import PlaybackLogic

/// Drives a machine with a ManualClock and scripted playhead timelines (one playhead event and one tick per second).
struct Rig {
    let clock = ManualClock()
    var machine: NextEpisodeMachine
    var head: TimeInterval = 0
    var log: [NextEpisodeAction] = []

    static let nextEpisode = EpisodeRef(seriesID: "s", season: 1, episode: 2, fileID: "S01E02.mkv")

    init(duration: TimeInterval = 1500, credits: CreditsTiming? = CreditsTiming(start: 1380, end: 1500),
         next: NextEpisodeDecision = .next(Rig.nextEpisode), policy: NextEpisodePolicy = NextEpisodePolicy()) {
        machine = NextEpisodeMachine(duration: duration, credits: credits, next: next, policy: policy, clock: clock)
    }

    /// `log` and `send` carry the core actions only (proposal, watched, advance, end); `fullLog` and `sendFull` also
    /// carry the prefetch and Skip Credits offer actions, which the newer NES tests look at.
    var fullLog: [NextEpisodeAction] = []

    static func isCore(_ a: NextEpisodeAction) -> Bool {
        switch a {
        case .prefetch, .cancelPrefetch, .offerSkipCredits, .withdrawSkipCreditsOffer: return false
        default: return true
        }
    }

    @discardableResult
    mutating func sendFull(_ event: NextEpisodeEvent) -> [NextEpisodeAction] {
        let all = machine.handle(event)
        fullLog += all
        log += all.filter(Rig.isCore)
        return all
    }

    @discardableResult
    mutating func send(_ event: NextEpisodeEvent) -> [NextEpisodeAction] {
        sendFull(event).filter(Rig.isCore)
    }

    /// Normal playback up to `time`, one second at a time.
    mutating func play(to time: TimeInterval) {
        while head < time {
            head = min(head + 1, time)
            clock.advance(by: 1)
            send(.playhead(head, .natural))
            send(.tick)
        }
    }

    /// Wall-clock seconds pass while the playhead stays put (paused).
    mutating func wait(_ seconds: Int) {
        for _ in 0..<seconds { clock.advance(by: 1); send(.tick) }
    }

    mutating func seek(to time: TimeInterval) {
        head = time
        send(.playhead(time, .seek))
    }

    func count(_ matches: (NextEpisodeAction) -> Bool) -> Int { log.filter(matches).count }
    var presented: Int { count { if case .presentProposal = $0 { return true } else { return false } } }
    var advanced: Int { count { if case .advance = $0 { return true } else { return false } } }
    var watched: Int { count { $0 == .markWatched } }
}

final class NextEpisodeTests: XCTestCase {
    private let two = Rig.nextEpisode

    // NE-1
    func testNE1_proposalAppearsAtCreditsStart() {
        var rig = Rig()
        rig.play(to: 1379)
        XCTAssertEqual(rig.presented, 0)
        rig.play(to: 1380)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertTrue(rig.machine.isProposalVisible)
        XCTAssertEqual(rig.log.last, .presentProposal(two))
    }

    // NE-2
    func testNE2_creditsUnknown_proposalAndWatchedAtTheEnd() {
        var rig = Rig(credits: nil)
        rig.play(to: 1499)
        XCTAssertEqual(rig.presented, 0)
        XCTAssertEqual(rig.watched, 0)
        rig.play(to: 1499.5)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.watched, 1)
        XCTAssertEqual(rig.log, [.markWatched, .presentProposal(two)])
    }

    // NE-3 (table: credits start, credits end, expected proposal time)
    func testNE3_moreThanSixtySecondsAfterCredits_proposalWaitsForTheEnd() {
        let rows: [(TimeInterval, TimeInterval, TimeInterval)] = [
            (1380, 1500, 1380),          // credits run to the end
            (1300, 1440, 1300),          // exactly 60 s remain: not "more than 60"
            (1300, 1439.9, 1499.5),      // 60.1 s remain
            (1200, 1300, 1499.5),        // 200 s of content after the credits
        ]
        for (start, end, expected) in rows {
            var rig = Rig(credits: CreditsTiming(start: start, end: end))
            XCTAssertEqual(rig.machine.proposalTime, expected, "credits \(start)-\(end)")
            rig.play(to: expected - 1)
            XCTAssertEqual(rig.presented, 0, "credits \(start)-\(end)")
            rig.play(to: expected)
            XCTAssertEqual(rig.presented, 1, "credits \(start)-\(end)")
        }
    }

    // NE-4
    func testNE4_acceptAdvancesAndNothingElseHappensAfterwards() {
        var rig = Rig()
        rig.play(to: 1385)
        XCTAssertEqual(rig.send(.accept), [.advance(two)])
        XCTAssertTrue(rig.machine.isFinished)
        XCTAssertEqual(rig.send(.accept), [])
        XCTAssertEqual(rig.send(.playhead(1400, .natural)), [])
        XCTAssertEqual(rig.send(.menu), [])
        XCTAssertEqual(rig.advanced, 1)
    }

    // NE-5
    func testNE5_acceptWithoutVisibleProposalDoesNothing() {
        var rig = Rig()
        rig.play(to: 100)
        XCTAssertEqual(rig.send(.accept), [])
        XCTAssertEqual(rig.advanced, 0)
    }

    // NE-6
    func testNE6_autoplayCountsDownTenSecondsOnTheFakeClockThenAdvances() {
        var rig = Rig()
        rig.play(to: 1380)
        let shown = rig.clock.now
        XCTAssertEqual(rig.machine.automaticAcceptanceDeadline, shown + 10)
        rig.play(to: 1389)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1390)
        XCTAssertEqual(rig.advanced, 1)
        XCTAssertEqual(rig.log.last, .advance(two))
    }

    // NE-7
    func testNE7_delayIsAParameter() {
        var rig = Rig(policy: NextEpisodePolicy(autoAdvanceDelay: 3))
        rig.play(to: 1382)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1383)
        XCTAssertEqual(rig.advanced, 1)
    }

    // NE-8
    func testNE8_autoplayOffNeverAdvancesByItself() {
        var rig = Rig(policy: NextEpisodePolicy(mode: .ask))
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(600)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertTrue(rig.machine.isProposalVisible)
        XCTAssertEqual(rig.count { $0 == .playbackEnded }, 1)
        XCTAssertEqual(rig.send(.accept), [.advance(two)])
    }

    // NE-9
    func testNE9_menuDismissesWithoutReAdvancing() {
        var rig = Rig()
        rig.play(to: 1385)
        XCTAssertEqual(rig.send(.menu), [.proposalDismissed])
        XCTAssertFalse(rig.machine.isProposalVisible)
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(120)
        XCTAssertEqual(rig.presented, 1)          // never shown again
        XCTAssertEqual(rig.advanced, 0)           // never advanced
        XCTAssertEqual(rig.watched, 1)            // and still counted as watched
        XCTAssertEqual(rig.count { $0 == .playbackEnded }, 1)
        XCTAssertTrue(rig.machine.wasDismissed)
    }

    // NE-10
    func testNE10_seekingBackAndForwardAfterDismissalStaysDismissed() {
        var rig = Rig()
        rig.play(to: 1385)
        rig.send(.menu)
        rig.seek(to: 100)
        rig.play(to: 200)
        rig.seek(to: 1400)
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(60)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.advanced, 0)
    }

    // NE-11
    func testNE11_dismissEventBehavesLikeMenu() {
        var rig = Rig()
        rig.play(to: 1385)
        XCTAssertEqual(rig.send(.dismiss), [.proposalDismissed])
        rig.wait(60)
        XCTAssertEqual(rig.advanced, 0)
    }

    // NE-12
    func testNE12_menuWithoutAProposalIsNotHandled() {
        var rig = Rig()
        rig.play(to: 100)
        XCTAssertEqual(rig.send(.menu), [])
        XCTAssertFalse(rig.machine.wasDismissed)
        rig.play(to: 1385)
        XCTAssertEqual(rig.presented, 1)          // the early Menu did not dismiss anything
    }

    // NE-13
    func testNE13_seekingBeforeTheProposalTimeWithdrawsItAndItCanReturn() {
        var rig = Rig()
        rig.play(to: 1385)
        rig.seek(to: 100)
        XCTAssertEqual(rig.log.last, .withdrawProposal)
        XCTAssertFalse(rig.machine.isProposalVisible)
        XCTAssertNil(rig.machine.automaticAcceptanceDeadline)
        rig.wait(60)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertFalse(rig.machine.wasDismissed)
        rig.play(to: 1380)
        XCTAssertEqual(rig.presented, 2)
    }

    // NE-14
    func testNE14_markedWatchedOnceAtCreditsStartEvenAfterSeeksAndDismissal() {
        var rig = Rig()
        rig.play(to: 1379)
        XCTAssertEqual(rig.watched, 0)
        rig.play(to: 1380)
        XCTAssertEqual(rig.watched, 1)
        rig.send(.menu)
        rig.seek(to: 10)
        rig.seek(to: 1400)
        rig.play(to: 1500)
        rig.send(.ended)
        XCTAssertEqual(rig.watched, 1)
    }

    // NE-15
    func testNE15_noCreditsMeansWatchedAtTheEndEvenWhenThereIsNoNextEpisode() {
        var rig = Rig(credits: nil, next: .none(.endOfSeries))
        rig.play(to: 1400)
        XCTAssertEqual(rig.watched, 0)
        rig.play(to: 1499.5)
        XCTAssertEqual(rig.watched, 1)
        XCTAssertEqual(rig.presented, 0)
    }

    // NE-16
    func testNE16_resumingInsideTheCreditsMarksWatchedAndShowsProposalButDoesNotCountDown() {
        var rig = Rig()
        rig.head = 1400
        rig.send(.playhead(1400, .started))
        XCTAssertEqual(rig.log, [.markWatched, .presentProposal(two)])
        XCTAssertNil(rig.machine.automaticAcceptanceDeadline)
        rig.wait(300)
        XCTAssertEqual(rig.advanced, 0)
        rig.send(.ended)                          // the end of the file arms the countdown
        rig.wait(10)
        XCTAssertEqual(rig.advanced, 1)
    }

    // NE-17
    func testNE17_seekingIntoTheCreditsShowsTheProposalWithoutACountdown() {
        var rig = Rig()
        rig.play(to: 100)
        rig.seek(to: 1420)
        XCTAssertEqual(rig.presented, 1)
        rig.wait(60)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertEqual(rig.send(.accept), [.advance(two)])
    }

    // NE-18
    func testNE18_pausingCancelsTheCountdownAndTheEndRearmsIt() {
        var rig = Rig()
        rig.play(to: 1383)
        rig.send(.paused)
        rig.wait(60)
        XCTAssertEqual(rig.advanced, 0)
        rig.send(.resumed)
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(9)
        XCTAssertEqual(rig.advanced, 0)
        rig.wait(1)
        XCTAssertEqual(rig.advanced, 1)
    }

    // NE-19 (changed by the batch-2 spec): 60 s or less of content after the credits does not hold Up Next back;
    // it appears at the credits start and the countdown runs (the old version deferred the countdown to the end).
    func testNE19_shortSceneAfterCredits_proposalAndCountdownStillAtCreditsStart() {
        var rig = Rig(credits: CreditsTiming(start: 1300, end: 1440))
        rig.play(to: 1300)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertNotNil(rig.machine.automaticAcceptanceDeadline)
        rig.play(to: 1309)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1310)
        XCTAssertEqual(rig.advanced, 1)
    }

    // NE-20
    func testNE20_endOfFileWithoutAProposalYetPresentsItAndCountsDown() {
        var rig = Rig(credits: nil)
        rig.play(to: 1499.5)
        rig.send(.ended)
        rig.wait(10)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.advanced, 1)
    }

    // NE-21
    func testNE21_noNextEpisodeNeverProposesAndReportsTheEndOnce() {
        for reason in [NoNextReason.endOfSeries, .special, .notAnEpisode] {
            var rig = Rig(next: .none(reason))
            rig.play(to: 1500)
            rig.send(.ended)
            rig.send(.ended)
            XCTAssertEqual(rig.presented, 0)
            XCTAssertEqual(rig.advanced, 0)
            XCTAssertEqual(rig.watched, 1)        // Season 0 and last episodes still count as watched
            XCTAssertEqual(rig.count { $0 == .playbackEnded }, 1)
        }
    }

    // NE-22
    func testNE22_skipCreditsToTheEndFlowsIntoNextEpisode() {
        var rig = Rig()
        rig.play(to: 1385)
        rig.log.removeAll()
        rig.send(.skipCreditsToEnd)
        XCTAssertEqual(rig.log, [.advance(two)])  // proposal was already visible; autoplay accepts at once
    }

    // NE-23
    func testNE23_skipCreditsFromBeforeTheProposalPresentsThenAdvances() {
        var rig = Rig(credits: CreditsTiming(start: 1200, end: 1500))
        rig.play(to: 100)
        rig.log.removeAll()
        rig.send(.skipCreditsToEnd)
        XCTAssertEqual(rig.log, [.markWatched, .presentProposal(two), .advance(two)])
    }

    // NE-24
    func testNE24_skipCreditsWithAutoplayOffLeavesTheProposalWaiting() {
        var rig = Rig(policy: NextEpisodePolicy(mode: .ask))
        rig.play(to: 1390)
        rig.send(.skipCreditsToEnd)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertTrue(rig.machine.isProposalVisible)
        XCTAssertEqual(rig.send(.accept), [.advance(two)])
    }

    // NE-25
    func testNE25_skipCreditsAfterDismissalDoesNotBringTheProposalBack() {
        var rig = Rig()
        rig.play(to: 1385)
        rig.send(.menu)
        rig.log.removeAll()
        rig.send(.skipCreditsToEnd)
        XCTAssertEqual(rig.log, [.playbackEnded])
    }

    // NE-26
    func testNE26_eventsAfterAdvanceAreIgnored() {
        var rig = Rig()
        rig.play(to: 1390)
        XCTAssertEqual(rig.advanced, 1)
        let before = rig.log.count
        rig.seek(to: 10)
        rig.send(.ended)
        rig.send(.menu)
        rig.wait(30)
        XCTAssertEqual(rig.log.count, before)
    }

    // NE-27
    func testNE27_duplicateEndedEventsDoNotRepeatActions() {
        var rig = Rig(policy: NextEpisodePolicy(mode: .ask))
        rig.play(to: 1500)
        rig.send(.ended)
        rig.send(.ended)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.count { $0 == .playbackEnded }, 1)
    }

    // NE-28: the machine is built from the provider, not the library
    func testNE28_coordinatorAsksTheProviderOnce() async {
        let provider = CountingProvider(decision: .next(two))
        let clock = ManualClock()
        let current = EpisodeRef(seriesID: "s", season: 1, episode: 1, fileID: "S01E01.mkv")
        let machine = await NextEpisodeResolution.makeMachine(
            provider: provider, current: current, duration: 1500,
            credits: CreditsTiming(start: 1380, end: 1500), clock: clock)
        XCTAssertEqual(machine.next, .next(two))
        let asked = await provider.askedAbout
        XCTAssertEqual(asked, [current])
    }

    // NE-29
    func testNE29_nonEpisodeFileHasNoNextEpisode() async {
        let provider = CountingProvider(decision: .next(two))
        let machine = await NextEpisodeResolution.makeMachine(
            provider: provider, current: nil, duration: 5000, credits: nil, clock: ManualClock())
        XCTAssertEqual(machine.next, .none(.notAnEpisode))
        let asked = await provider.askedAbout
        XCTAssertTrue(asked.isEmpty)
    }
}

actor CountingProvider: NextEpisodeProvider {
    private let decision: NextEpisodeDecision
    private(set) var askedAbout: [EpisodeRef] = []
    init(decision: NextEpisodeDecision) { self.decision = decision }
    func nextEpisode(after current: EpisodeRef) async -> NextEpisodeDecision {
        askedAbout.append(current)
        return decision
    }
}
