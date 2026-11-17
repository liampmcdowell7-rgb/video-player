import XCTest
@testable import PlaybackLogic

/// One test (or more) per sentence of the user's Next Episode spec (batch-2 message), on the fake clock.
/// Test names start with the row id used in docs/PLAYBACK_LOGIC.md ("Next Episode spec" table).
/// Spec sentences:
///  S1 Settings > Playback > Next Episode: "When Credits Begin" (default), "When Episode Ends", "Ask", "Off"; plus a countdown row.
///  S2 Credits known: Up Next at the credits start; jump straight to the next episode when the countdown ends.
///  S3 Credits unknown: wait for the end of the file.
///  S4 More than 60 s of content after the credits segment ends: offer "Skip Credits" to the segment end instead of advancing.
///  S5 Menu dismisses the proposal, and the app never re-advances that episode afterwards.
///  S6 Next episode: same season; then the first episode of the next season; then stop. Season 0 never auto-advanced.
///  S7 The episode is marked watched when advancing at the credits start.
///  S8 Prefetch the next episode. Keep the display mode when the next episode's format matches.
final class NextEpisodeSpecTests: XCTestCase {
    private let two = Rig.nextEpisode

    private func ep(_ season: Int, _ episode: Int) -> EpisodeRef {
        EpisodeRef(seriesID: "s", season: season, episode: episode, fileID: "S\(season)E\(episode).mkv")
    }

    // MARK: S1 choices and the countdown row

    func testNES1a_fourChoicesInOrderWithTheSpecTexts() {
        XCTAssertEqual(NextEpisodeMode.allCases, [.whenCreditsBegin, .whenEpisodeEnds, .ask, .off])
        XCTAssertEqual(NextEpisodeMode.allCases.map(\.title), ["When Credits Begin", "When Episode Ends", "Ask", "Off"])
    }

    func testNES1b_whenCreditsBeginIsTheDefault() {
        XCTAssertEqual(NextEpisodeMode.default, .whenCreditsBegin)
        XCTAssertEqual(NextEpisodeSettings().mode, .whenCreditsBegin)
        XCTAssertEqual(NextEpisodePolicy().mode, .whenCreditsBegin)
        XCTAssertEqual(NextEpisodePolicy(settings: NextEpisodeSettings()).mode, .whenCreditsBegin)
    }

    func testNES1c_countdownRowDefaultChoicesAndClamp() {
        XCTAssertEqual(NextEpisodeSettings().countdownSeconds, 10)
        XCTAssertEqual(NextEpisodeSettings.countdownChoices, [0, 5, 10, 15, 20, 30])
        XCTAssertEqual(NextEpisodeSettings(countdownSeconds: 99).countdownSeconds, 30)
        XCTAssertEqual(NextEpisodeSettings(countdownSeconds: -4).countdownSeconds, 0)
        var s = NextEpisodeSettings()
        s.setCountdown(seconds: 45)
        XCTAssertEqual(s.countdownSeconds, 30)
        s.setCountdown(seconds: 5)
        XCTAssertEqual(s.countdownSeconds, 5)
        XCTAssertEqual(NextEpisodePolicy(settings: s).autoAdvanceDelay, 5)
    }

    func testNES1d_settingsSurviveEncodingAndMissingKeysFallBackToTheDefaults() throws {
        let original = NextEpisodeSettings(mode: .ask, countdownSeconds: 20)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(NextEpisodeSettings.self, from: data), original)
        let empty = try JSONDecoder().decode(NextEpisodeSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(empty, NextEpisodeSettings())
        let tooLong = try JSONDecoder().decode(NextEpisodeSettings.self, from: Data(#"{"mode":"off","countdownSeconds":500}"#.utf8))
        XCTAssertEqual(tooLong.countdownSeconds, 30)
        XCTAssertEqual(tooLong.mode, .off)
    }

    func testNES1e_theCountdownRowSetsTheCountdownOnTheFakeClock() {
        var rig = Rig(policy: NextEpisodePolicy(settings: NextEpisodeSettings(countdownSeconds: 5)))
        rig.play(to: 1384)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1385)
        XCTAssertEqual(rig.advanced, 1)
    }

    // MARK: S2 credits known

    func testNES2a_creditsKnown_upNextAppearsAtTheCreditsStart() {
        var rig = Rig()
        rig.play(to: 1379)
        XCTAssertEqual(rig.presented, 0)
        rig.play(to: 1380)
        XCTAssertEqual(rig.log.last, .presentProposal(two))
        XCTAssertEqual(rig.machine.proposalTime, 1380)
    }

    func testNES2b_jumpsStraightToTheNextEpisodeWhenTheCountdownEnds_noFurtherPress() {
        var rig = Rig()
        rig.play(to: 1380)
        let shown = rig.clock.now
        XCTAssertEqual(rig.machine.automaticAcceptanceDeadline, shown + 10)
        rig.play(to: 1389)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1390)
        XCTAssertEqual(rig.advanced, 1)
        XCTAssertEqual(rig.log.last, .advance(two))
        XCTAssertTrue(rig.machine.isFinished)
    }

    func testNES2c_countdownZeroJumpsAtOnce() {
        var rig = Rig(policy: NextEpisodePolicy(autoAdvanceDelay: 0))
        rig.play(to: 1379)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1380)
        XCTAssertEqual(rig.log, [.markWatched, .presentProposal(two), .advance(two)])
    }

    func testNES2d_pressingAcceptDuringTheCountdownAdvancesAtOnce() {
        var rig = Rig()
        rig.play(to: 1383)
        XCTAssertEqual(rig.send(.accept), [.advance(two)])
        rig.wait(30)
        XCTAssertEqual(rig.advanced, 1)
    }

    // MARK: S3 credits unknown

    func testNES3a_creditsUnknown_nothingBeforeTheEndOfTheFile() {
        var rig = Rig(credits: nil)
        XCTAssertEqual(rig.machine.proposalTime, 1499.5)
        rig.play(to: 1499)
        XCTAssertEqual(rig.presented, 0)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertNil(rig.machine.automaticAcceptanceDeadline)
    }

    func testNES3b_creditsUnknown_upNextAtTheEndAndTheCountdownThenAdvances() {
        var rig = Rig(credits: nil)
        rig.play(to: 1499.5)
        rig.send(.ended)
        XCTAssertEqual(rig.presented, 1)
        rig.wait(9)
        XCTAssertEqual(rig.advanced, 0)
        rig.wait(1)
        XCTAssertEqual(rig.advanced, 1)
    }

    // MARK: S4 more than 60 s after the credits: offer Skip Credits instead of advancing

    private func rigWithContentAfterCredits(policy: NextEpisodePolicy = NextEpisodePolicy()) -> Rig {
        Rig(credits: CreditsTiming(start: 1200, end: 1300), policy: policy)   // 200 s of content after the credits
    }

    func testNES4a_moreThanSixtySecondsAfterCredits_noUpNextAndNoAdvanceAtTheCreditsStart() {
        var rig = rigWithContentAfterCredits()
        rig.play(to: 1299)
        XCTAssertEqual(rig.presented, 0)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertNil(rig.machine.automaticAcceptanceDeadline)
        XCTAssertEqual(rig.machine.proposalTime, 1499.5)
    }

    func testNES4b_skipCreditsIsOfferedToTheSegmentEndWhileInsideTheCredits() {
        var rig = rigWithContentAfterCredits()
        rig.play(to: 1199)
        XCTAssertFalse(rig.fullLog.contains(.offerSkipCredits(target: 1300)))
        rig.play(to: 1200)
        XCTAssertEqual(rig.fullLog.filter { $0 == .offerSkipCredits(target: 1300) }.count, 1)
        XCTAssertEqual(rig.machine.skipCreditsOfferTarget, 1300)
        rig.play(to: 1299)
        XCTAssertEqual(rig.machine.skipCreditsOfferTarget, 1300)
        XCTAssertFalse(rig.fullLog.contains(.withdrawSkipCreditsOffer))
        rig.play(to: 1300)                                       // end of the segment (exclusive)
        XCTAssertEqual(rig.fullLog.filter { $0 == .withdrawSkipCreditsOffer }.count, 1)
        XCTAssertNil(rig.machine.skipCreditsOfferTarget)
    }

    func testNES4c_exactlySixtySecondsAfterTheCreditsIsNotMoreThanSixty_soItAdvancesAtTheCreditsStart() {
        var rig = Rig(credits: CreditsTiming(start: 1300, end: 1440))
        rig.play(to: 1300)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertFalse(rig.fullLog.contains { if case .offerSkipCredits = $0 { return true } else { return false } })
    }

    func testNES4d_afterSkippingTheCredits_theEpisodeContinuesAndUpNextWaitsForTheEnd() {
        var rig = rigWithContentAfterCredits()
        rig.play(to: 1250)
        rig.seek(to: 1300)                                       // what pressing Skip Credits does
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertEqual(rig.presented, 0)
        rig.play(to: 1499)
        XCTAssertEqual(rig.advanced, 0)
        rig.play(to: 1499.5)
        XCTAssertEqual(rig.presented, 1)
        rig.wait(10)
        XCTAssertEqual(rig.advanced, 1)
    }

    func testNES4e_leavingTheCreditsBySeekingBackWithdrawsTheOffer_andItCanReturn() {
        var rig = rigWithContentAfterCredits()
        rig.play(to: 1250)
        rig.seek(to: 100)
        XCTAssertEqual(rig.fullLog.filter { $0 == .withdrawSkipCreditsOffer }.count, 1)
        rig.seek(to: 1210)
        XCTAssertEqual(rig.fullLog.filter { $0 == .offerSkipCredits(target: 1300) }.count, 2)
    }

    func testNES4f_noOfferWhenThereIsNoNextEpisode_orInModesThatDoNotAdvanceAtTheCreditsStart() {
        func offered(_ rig: Rig) -> Bool {
            rig.fullLog.contains { if case .offerSkipCredits = $0 { return true } else { return false } }
        }
        var noNext = Rig(credits: CreditsTiming(start: 1200, end: 1300), next: .none(.endOfSeries))
        noNext.play(to: 1250)
        XCTAssertFalse(offered(noNext))
        for mode in [NextEpisodeMode.whenEpisodeEnds, .off] {
            var rig = rigWithContentAfterCredits(policy: NextEpisodePolicy(mode: mode))
            rig.play(to: 1250)
            XCTAssertFalse(offered(rig), "\(mode)")
        }
        var ask = rigWithContentAfterCredits(policy: NextEpisodePolicy(mode: .ask))
        ask.play(to: 1250)
        XCTAssertTrue(offered(ask))
    }

    // MARK: S5 Menu dismisses; never re-advances that episode

    func testNES5a_menuDismissesTheProposal() {
        var rig = Rig()
        rig.play(to: 1385)
        XCTAssertEqual(rig.send(.menu), [.proposalDismissed])
        XCTAssertFalse(rig.machine.isProposalVisible)
        XCTAssertNil(rig.machine.automaticAcceptanceDeadline)
        XCTAssertTrue(rig.machine.wasDismissed)
    }

    func testNES5b_afterMenuTheEpisodeIsNeverAdvancedByAnyPath() {
        var rig = Rig()
        rig.play(to: 1385)
        rig.send(.menu)
        rig.wait(300)                                            // the countdown would have long ended
        rig.play(to: 1500)
        rig.send(.ended)
        rig.send(.skipCreditsToEnd)
        rig.send(.accept)
        rig.send(.resumed)
        rig.seek(to: 100)
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(300)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.count { $0 == .playbackEnded }, 1)
    }

    func testNES5c_dismissedForTheCreditsUnknownEndOfFileToo() {
        var rig = Rig(credits: nil)
        rig.play(to: 1499.5)
        rig.send(.ended)
        rig.send(.menu)
        rig.wait(60)
        XCTAssertEqual(rig.advanced, 0)
    }

    func testNES5d_aReplayThatTheAppMarksAsDismissedNeverProposesOrPrefetches() {
        let clock = ManualClock()
        var m = NextEpisodeMachine(duration: 1500, credits: CreditsTiming(start: 1380, end: 1500), next: .next(two),
                                   clock: clock, dismissedBefore: true)
        var all: [NextEpisodeAction] = []
        for t in stride(from: 0.0, through: 1500.0, by: 10) {
            clock.advance(by: 10)
            all += m.handle(.playhead(t, .natural))
            all += m.handle(.tick)
        }
        all += m.handle(.ended)
        XCTAssertFalse(all.contains { if case .presentProposal = $0 { return true } else { return false } })
        XCTAssertFalse(all.contains { if case .advance = $0 { return true } else { return false } })
        XCTAssertFalse(all.contains { if case .prefetch = $0 { return true } else { return false } })
    }

    // MARK: S6 which episode comes next

    func testNES6a_nextEpisodeInTheSameSeason() {
        let all = [ep(1, 1), ep(1, 2), ep(1, 3), ep(2, 1)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: all), .next(ep(1, 2)))
    }

    func testNES6b_thenTheFirstEpisodeOfTheNextSeason() {
        let all = [ep(1, 1), ep(1, 2), ep(2, 1), ep(2, 2)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 2), in: all), .next(ep(2, 1)))
    }

    func testNES6c_thenStop() {
        let all = [ep(1, 1), ep(1, 2), ep(2, 1), ep(2, 2)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(2, 2), in: all), .none(.endOfSeries))
    }

    func testNES6d_season0SpecialsAreNeverAutoAdvanced() {
        let all = [ep(0, 1), ep(0, 2), ep(1, 1)]
        XCTAssertEqual(EpisodeOrder.next(after: ep(0, 1), in: all), .none(.special))     // a special never advances
        XCTAssertEqual(EpisodeOrder.next(after: ep(1, 1), in: [ep(1, 1), ep(0, 1)]), .none(.endOfSeries))  // nor is one entered
    }

    func testNES6e_onTheFakeClock_lastEpisodeOfASeasonAdvancesToTheNextSeasonsFirst() async {
        let all = [ep(1, 1), ep(1, 2), ep(2, 1), ep(2, 2)]
        let provider = LibraryNextEpisodeProvider { _ in all }
        let clock = ManualClock()
        var machine = await NextEpisodeResolution.makeMachine(
            provider: provider, current: ep(1, 2), duration: 1500, credits: CreditsTiming(start: 1380, end: 1500), clock: clock)
        var log: [NextEpisodeAction] = []
        var head = 0.0
        while head < 1400 { head += 1; clock.advance(by: 1); log += machine.handle(.playhead(head, .natural)); log += machine.handle(.tick) }
        XCTAssertEqual(log.last, .advance(ep(2, 1)))
    }

    func testNES6f_onTheFakeClock_lastEpisodeOfTheLastSeasonStops_andASpecialNeverAdvances() async {
        let all = [ep(1, 1), ep(1, 2), ep(0, 1)]
        for current in [ep(1, 2), ep(0, 1)] {
            let provider = LibraryNextEpisodeProvider { _ in all }
            let clock = ManualClock()
            var machine = await NextEpisodeResolution.makeMachine(
                provider: provider, current: current, duration: 1500, credits: CreditsTiming(start: 1380, end: 1500), clock: clock)
            var log: [NextEpisodeAction] = []
            var head = 0.0
            while head < 1500 { head += 1; clock.advance(by: 1); log += machine.handle(.playhead(head, .natural)); log += machine.handle(.tick) }
            log += machine.handle(.ended)
            clock.advance(by: 60)
            log += machine.handle(.tick)
            XCTAssertFalse(log.contains { if case .advance = $0 { return true } else { return false } }, "\(current)")
            XCTAssertFalse(log.contains { if case .presentProposal = $0 { return true } else { return false } }, "\(current)")
            XCTAssertEqual(log.filter { $0 == .playbackEnded }.count, 1, "\(current)")
            XCTAssertEqual(log.filter { $0 == .markWatched }.count, 1, "\(current)")
        }
    }

    // MARK: S7 marked watched when advancing at the credits start

    func testNES7a_watchedAtTheCreditsStart_beforeUpNextAndBeforeTheAdvance() {
        var rig = Rig()
        rig.play(to: 1379)
        XCTAssertEqual(rig.watched, 0)
        rig.play(to: 1390)
        XCTAssertEqual(rig.log, [.markWatched, .presentProposal(two), .advance(two)])
        XCTAssertEqual(rig.watched, 1)
    }

    func testNES7b_markedWatchedOnceEvenWhenTheUserSeeksBackAndForth() {
        var rig = Rig()
        rig.play(to: 1385)
        rig.seek(to: 100)
        rig.play(to: 1390)
        rig.seek(to: 1385)
        XCTAssertEqual(rig.watched, 1)
    }

    func testNES7c_watchedAtTheEndWhenTheCreditsAreUnknown() {
        var rig = Rig(credits: nil)
        rig.play(to: 1499)
        XCTAssertEqual(rig.watched, 0)
        rig.play(to: 1499.5)
        XCTAssertEqual(rig.watched, 1)
    }

    // MARK: S8a prefetch

    func testNES8a_prefetchRequestNamesTheNextEpisodeAndWhenToStart() {
        let rig = Rig()
        XCTAssertEqual(rig.machine.prefetchRequest, PrefetchRequest(episode: two, startAt: 1260))   // 1380 - 120
    }

    func testNES8b_prefetchStartsOnceWhenThePlayheadReachesTheStartPosition() {
        var rig = Rig()
        rig.play(to: 1259)
        XCTAssertFalse(rig.fullLog.contains(.prefetch(two)))
        rig.play(to: 1260)
        XCTAssertEqual(rig.fullLog.filter { $0 == .prefetch(two) }.count, 1)
        rig.play(to: 1379)
        XCTAssertEqual(rig.fullLog.filter { $0 == .prefetch(two) }.count, 1)
    }

    func testNES8c_prefetchAlsoStartsWhenTheUserSeeksOrResumesPastTheStartPosition() {
        var seek = Rig()
        seek.seek(to: 1300)
        XCTAssertEqual(seek.fullLog.filter { $0 == .prefetch(two) }.count, 1)
        var resume = Rig()
        resume.sendFull(.playhead(1370, .started))
        XCTAssertEqual(resume.fullLog.filter { $0 == .prefetch(two) }.count, 1)
    }

    func testNES8d_menuCancelsThePrefetch_andItNeverRestarts() {
        var rig = Rig()
        rig.play(to: 1385)
        let out = rig.sendFull(.menu)
        XCTAssertEqual(out, [.proposalDismissed, .cancelPrefetch(two)])
        rig.seek(to: 100)
        rig.play(to: 1500)
        XCTAssertEqual(rig.fullLog.filter { $0 == .prefetch(two) }.count, 1)
        XCTAssertEqual(rig.fullLog.filter { $0 == .cancelPrefetch(two) }.count, 1)
    }

    func testNES8e_leavingThePlayerCancelsAPrefetchThatIsRunning_andNothingElseHappens() {
        var rig = Rig()
        rig.play(to: 1300)
        XCTAssertEqual(rig.sendFull(.stopped), [.cancelPrefetch(two)])
        XCTAssertTrue(rig.machine.isFinished)
        XCTAssertEqual(rig.sendFull(.stopped), [])
        rig.play(to: 1500)
        XCTAssertEqual(rig.advanced, 0)
        var early = Rig()
        early.play(to: 100)
        XCTAssertEqual(early.sendFull(.stopped), [])             // nothing was prefetched yet, nothing to cancel
    }

    func testNES8f_advancingDoesNotCancelThePrefetch_itIsConsumed() {
        var rig = Rig()
        rig.play(to: 1390)
        XCTAssertEqual(rig.advanced, 1)
        XCTAssertFalse(rig.fullLog.contains(.cancelPrefetch(two)))
    }

    func testNES8g_noPrefetchWhenOffOrWhenThereIsNoNextEpisode() {
        var off = Rig(policy: NextEpisodePolicy(mode: .off))
        off.play(to: 1500)
        XCTAssertNil(off.machine.prefetchRequest)
        XCTAssertFalse(off.fullLog.contains { if case .prefetch = $0 { return true } else { return false } })
        var none = Rig(next: .none(.endOfSeries))
        none.play(to: 1500)
        XCTAssertNil(none.machine.prefetchRequest)
        XCTAssertFalse(none.fullLog.contains { if case .prefetch = $0 { return true } else { return false } })
    }

    func testNES8h_prefetchStartIsNeverBeforeZero_andLeadIsConfigurable() {
        let short = Rig(duration: 100, credits: nil)
        XCTAssertEqual(short.machine.prefetchRequest?.startAt, 0)
        let lead = Rig(policy: NextEpisodePolicy(prefetchLead: 30))
        XCTAssertEqual(lead.machine.prefetchRequest?.startAt, 1350)
    }

    // MARK: S8b keep the display mode when the format matches

    private let hd24 = DisplayFormat(width: 1920, height: 1080, frameRate: 23.976, dynamicRange: .sdr)

    func testNES9a_sameFormat_keepsTheDisplayMode() {
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: hd24), .keep(.formatsMatch))
        // The next file is a 2.40:1 crop of the same class, 1920x800: still the same display mode.
        let scope = DisplayFormat(width: 1920, height: 800, frameRate: 23.976, dynamicRange: .sdr)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: scope), .keep(.formatsMatch))
    }

    func testNES9b_eachDifferenceSwitches_andSaysWhy() {
        let uhd = DisplayFormat(width: 3840, height: 2160, frameRate: 23.976, dynamicRange: .sdr)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: uhd), .switchMode(to: uhd, differences: [.resolution]))
        let fps25 = DisplayFormat(width: 1920, height: 1080, frameRate: 25, dynamicRange: .sdr)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: fps25), .switchMode(to: fps25, differences: [.frameRate]))
        let hdr = DisplayFormat(width: 1920, height: 1080, frameRate: 23.976, dynamicRange: .hdr10)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: hdr), .switchMode(to: hdr, differences: [.dynamicRange]))
        let all = DisplayFormat(width: 3840, height: 2160, frameRate: 50, dynamicRange: .dolbyVision)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: all),
                       .switchMode(to: all, differences: [.resolution, .frameRate, .dynamicRange]))
    }

    func testNES9c_unknownNextFormat_keepsTheMode_andUnknownCurrentToo() {
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: nil), .keep(.nextFormatUnknown))
        XCTAssertEqual(DisplayModePlanner.decide(current: nil, next: hd24), .keep(.currentFormatUnknown))
        XCTAssertEqual(DisplayModePlanner.decide(current: nil, next: nil), .keep(.nextFormatUnknown))
    }

    func testNES9d_frameRatesThatAreDifferentRefreshRatesAreDifferent() {
        let f24 = DisplayFormat(width: 1920, height: 1080, frameRate: 24, dynamicRange: .sdr)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: f24), .switchMode(to: f24, differences: [.frameRate]))
        let same = DisplayFormat(width: 1920, height: 1080, frameRate: 23.976_000_1, dynamicRange: .sdr)
        XCTAssertEqual(DisplayModePlanner.decide(current: hd24, next: same), .keep(.formatsMatch))
    }

    func testNES9e_hdr10PlusIsOutputAsHdr10_butDolbyVisionAndHlgAreOwnModes() {
        func fmt(_ r: DynamicRangeFormat) -> DisplayFormat { DisplayFormat(width: 3840, height: 2160, frameRate: 24, dynamicRange: r) }
        XCTAssertEqual(DisplayModePlanner.decide(current: fmt(.hdr10), next: fmt(.hdr10Plus)), .keep(.formatsMatch))
        XCTAssertEqual(DisplayModePlanner.decide(current: fmt(.hdr10), next: fmt(.dolbyVision)),
                       .switchMode(to: fmt(.dolbyVision), differences: [.dynamicRange]))
        XCTAssertEqual(DisplayModePlanner.decide(current: fmt(.hdr10), next: fmt(.hlg)),
                       .switchMode(to: fmt(.hlg), differences: [.dynamicRange]))
    }

    func testNES9f_resolutionClasses() {
        XCTAssertEqual(ResolutionClass(width: 720, height: 480), .sd)
        XCTAssertEqual(ResolutionClass(width: 1280, height: 720), .hd)
        XCTAssertEqual(ResolutionClass(width: 1920, height: 800), .hd)
        XCTAssertEqual(ResolutionClass(width: 3840, height: 1600), .uhd)
        XCTAssertEqual(ResolutionClass(width: 4096, height: 2160), .uhd)
    }

    func testNES9g_theMachineExposesTheDecisionForTheAdvance() {
        let clock = ManualClock()
        let uhd = DisplayFormat(width: 3840, height: 2160, frameRate: 23.976, dynamicRange: .hdr10)
        let m = NextEpisodeMachine(duration: 1500, credits: nil, next: .next(two), clock: clock, currentFormat: hd24, nextFormat: uhd)
        XCTAssertEqual(m.displayModeDecision, .switchMode(to: uhd, differences: [.resolution, .dynamicRange]))
        let unknown = NextEpisodeMachine(duration: 1500, credits: nil, next: .next(two), clock: clock)
        XCTAssertEqual(unknown.displayModeDecision, .keep(.nextFormatUnknown))
    }

    // MARK: Modes (interpretations, PROVISIONAL): what each of the four choices does

    func testNESM1_whenEpisodeEnds_upNextOnlyAtTheEndEvenWhenCreditsAreKnown_watchedStillAtTheCreditsStart() {
        var rig = Rig(policy: NextEpisodePolicy(mode: .whenEpisodeEnds))
        XCTAssertEqual(rig.machine.proposalTime, 1499.5)
        rig.play(to: 1499)
        XCTAssertEqual(rig.presented, 0)
        XCTAssertEqual(rig.watched, 1)
        rig.play(to: 1499.5)
        rig.send(.ended)
        XCTAssertEqual(rig.presented, 1)
        rig.wait(9)
        XCTAssertEqual(rig.advanced, 0)
        rig.wait(1)
        XCTAssertEqual(rig.advanced, 1)
    }

    func testNESM2_ask_upNextAtTheCreditsStartWithNoCountdown_waitsForTheUser() {
        var rig = Rig(policy: NextEpisodePolicy(mode: .ask))
        rig.play(to: 1380)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertNil(rig.machine.automaticAcceptanceDeadline)
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(600)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertTrue(rig.machine.isProposalVisible)
        XCTAssertEqual(rig.send(.accept), [.advance(two)])
    }

    func testNESM3_ask_creditsUnknown_upNextAtTheEndAndWaits() {
        var rig = Rig(credits: nil, policy: NextEpisodePolicy(mode: .ask))
        rig.play(to: 1499.5)
        rig.send(.ended)
        rig.wait(600)
        XCTAssertEqual(rig.presented, 1)
        XCTAssertEqual(rig.advanced, 0)
    }

    func testNESM4_off_neverProposesNeverAdvancesNeverPrefetches_butTheEpisodeIsStillMarkedWatched() {
        var rig = Rig(policy: NextEpisodePolicy(mode: .off))
        XCTAssertNil(rig.machine.proposalTime)
        rig.play(to: 1500)
        rig.send(.ended)
        rig.wait(600)
        XCTAssertEqual(rig.presented, 0)
        XCTAssertEqual(rig.advanced, 0)
        XCTAssertEqual(rig.watched, 1)
        XCTAssertEqual(rig.count { $0 == .playbackEnded }, 1)
        XCTAssertEqual(rig.send(.accept), [])
        XCTAssertEqual(rig.send(.menu), [])                       // Menu is the player's, not ours
    }

    func testNESM5_creditsSkippedToTheEndInAskAndOffModes_neverAdvanceByThemselves() {
        for mode in [NextEpisodeMode.ask, .off] {
            var rig = Rig(policy: NextEpisodePolicy(mode: mode))
            rig.play(to: 1390)
            rig.send(.skipCreditsToEnd)
            rig.wait(120)
            XCTAssertEqual(rig.advanced, 0, "\(mode)")
        }
    }

    func testNESM6_theOldAutoplayFlagIsNowReadOnly_onForTheCountdownModes() {
        XCTAssertTrue(NextEpisodePolicy(mode: .whenCreditsBegin).autoplay)
        XCTAssertTrue(NextEpisodePolicy(mode: .whenEpisodeEnds).autoplay)
        XCTAssertFalse(NextEpisodePolicy(mode: .ask).autoplay)
        XCTAssertFalse(NextEpisodePolicy(mode: .off).autoplay)
    }
}
