import XCTest
@testable import PlaybackLogic

final class PlaybackSessionTests: XCTestCase {
    private let two = Rig.nextEpisode
    private let file = FileIdentity(path: "/tv/Show/S01E01.mkv", size: 1_000_000, duration: 1500)

    private func session(post: TimeInterval? = nil, settings: SkipSettings = SkipSettings(),
                         policy: NextEpisodePolicy = NextEpisodePolicy(), clock: ManualClock = ManualClock()) -> PlaybackSession {
        let candidates = [
            SkipSegment(type: .intro, start: 60, end: 120, source: .embeddedChapters, confidence: 0.9, file: file),
            SkipSegment(type: .credits, start: 1380, end: 1500, source: .embeddedChapters, confidence: 0.9, file: file),
        ]
        let resolved = SegmentResolver.resolve(file: file, candidates: candidates, postCreditsStart: post)
        return PlaybackSession(resolved: resolved, duration: 1500, settings: settings, next: .next(two), policy: policy, clock: clock)
    }

    // SESS-1
    func testSESS1_skipCreditsFlowsIntoNextEpisode() {
        var s = session()
        let shown = s.playhead(1390, kind: .natural)
        XCTAssertEqual(shown.skip, .button(SkipButton(type: .credits, title: "Skip Credits", target: 1500)))
        let skipped = s.skipPressed(.credits)
        XCTAssertEqual(skipped.seek, 1500)
        XCTAssertEqual(skipped.episode, [.advance(two)])
    }

    // SESS-2
    func testSESS2_skipCreditsToAPostCreditsChapterIsJustASeek() {
        var s = session(post: 1450)
        _ = s.playhead(1390, kind: .natural)
        let skipped = s.skipPressed(.credits)
        XCTAssertEqual(skipped.seek, 1450)
        XCTAssertEqual(skipped.episode, [])        // proposal was already showing; no countdown for a scene that plays
        XCTAssertFalse(s.machine.isFinished)
    }

    // SESS-3
    func testSESS3_automaticCreditsSkipSeeksAndFlowsOnWithNoButton() {
        var s = session(settings: SkipSettings(credits: .automatic))
        let update = s.playhead(1380, kind: .natural)
        XCTAssertEqual(update.skip, .jump(type: .credits, target: 1500))
        XCTAssertEqual(update.seek, 1500)
        XCTAssertTrue(update.episode.contains(.advance(two)))
    }

    // SESS-4
    func testSESS4_skipIntroSeeksAndLeavesNextEpisodeAlone() {
        var s = session()
        _ = s.playhead(70, kind: .natural)
        let update = s.skipPressed(.intro)
        XCTAssertEqual(update.seek, 120)
        XCTAssertEqual(update.episode, [])
    }

    // SESS-5
    func testSESS5_skipForATypeWithoutASegmentDoesNothing() {
        var s = session()
        let update = s.skipPressed(.recap)
        XCTAssertNil(update.seek)
        XCTAssertEqual(update.episode, [])
    }

    // SESS-6
    func testSESS6_skipCreditsAfterMenuDismissalDoesNotAdvance() {
        var s = session()
        _ = s.playhead(1385, kind: .natural)
        // Menu dismisses Up Next and, because the prefetch had started, cancels it (changed by the batch-2 spec work).
        XCTAssertEqual(s.event(.menu), [.proposalDismissed, .cancelPrefetch(two)])
        let update = s.skipPressed(.credits)
        XCTAssertEqual(update.seek, 1500)
        XCTAssertEqual(update.episode, [.playbackEnded])
    }

    // SESS-7
    func testSESS7_creditsTimingComesFromTheResolvedSegment() {
        let s = session()
        XCTAssertEqual(s.machine.credits, CreditsTiming(start: 1380, end: 1500))
        XCTAssertEqual(s.machine.proposalTime, 1380)
    }

    /// Credits 1200 to 1300 of a 1500 s file: 200 s of content follow, so Next Episode offers Skip Credits instead of advancing.
    private func sessionWithContentAfterCredits(settings: SkipSettings = SkipSettings(), clock: ManualClock = ManualClock()) -> PlaybackSession {
        let candidates = [SkipSegment(type: .credits, start: 1200, end: 1300, source: .embeddedChapters, confidence: 0.9, file: file)]
        let resolved = SegmentResolver.resolve(file: file, candidates: candidates, postCreditsStart: nil)
        return PlaybackSession(resolved: resolved, duration: 1500, settings: settings, next: .next(two), clock: clock)
    }

    // SESS-8 (NES-4)
    func testSESS8_contentAfterCredits_skipCreditsIsOfferedAndPressingItOnlySeeks() {
        var s = sessionWithContentAfterCredits()
        let shown = s.playhead(1210, kind: .natural)
        XCTAssertEqual(shown.skip, .button(SkipButton(type: .credits, title: "Skip Credits", target: 1300)))
        XCTAssertFalse(shown.episode.contains { if case .presentProposal = $0 { return true } else { return false } })
        XCTAssertFalse(shown.episode.contains { if case .advance = $0 { return true } else { return false } })
        let pressed = s.skipPressed(.credits)
        XCTAssertEqual(pressed.seek, 1300)
        XCTAssertFalse(pressed.episode.contains { if case .advance = $0 { return true } else { return false } })
        XCTAssertFalse(s.machine.isFinished)
        XCTAssertNil(s.machine.skipCreditsOfferTarget)
    }

    // SESS-9 (NES-4): the offer is made even when the Skip Credits setting is Off
    func testSESS9_contentAfterCredits_theOfferShowsEvenWhenTheSkipSettingIsOff() {
        var s = sessionWithContentAfterCredits(settings: SkipSettings(credits: .off))
        let update = s.playhead(1250, kind: .natural)
        XCTAssertEqual(update.skip, .button(SkipButton(type: .credits, title: "Skip Credits", target: 1300)))
        let after = s.playhead(1300, kind: .natural)
        XCTAssertEqual(after.skip, .none)
    }

    // SESS-10 (NES-4): Automatic Skip Credits jumps to the segment end and does not advance
    func testSESS10_contentAfterCredits_automaticSkipJumpsToTheSegmentEndWithoutAdvancing() {
        var s = sessionWithContentAfterCredits(settings: SkipSettings(credits: .automatic))
        let update = s.playhead(1200, kind: .natural)
        XCTAssertEqual(update.skip, .jump(type: .credits, target: 1300))
        XCTAssertEqual(update.seek, 1300)
        XCTAssertFalse(update.episode.contains { if case .advance = $0 { return true } else { return false } })
    }

    // SESS-11 (NES-8): the display decision travels with the session
    func testSESS11_displayDecisionComesFromTheFormatsGivenToTheSession() {
        let a = DisplayFormat(width: 1920, height: 1080, frameRate: 24, dynamicRange: .sdr)
        let resolved = SegmentResolver.resolve(file: file, candidates: [], postCreditsStart: nil)
        let keep = PlaybackSession(resolved: resolved, duration: 1500, next: .next(two), clock: ManualClock(), currentFormat: a, nextFormat: a)
        XCTAssertEqual(keep.machine.displayModeDecision, .keep(.formatsMatch))
        let b = DisplayFormat(width: 1920, height: 1080, frameRate: 24, dynamicRange: .hdr10)
        let change = PlaybackSession(resolved: resolved, duration: 1500, next: .next(two), clock: ManualClock(), currentFormat: a, nextFormat: b)
        XCTAssertEqual(change.machine.displayModeDecision, .switchMode(to: b, differences: [.dynamicRange]))
    }
}
