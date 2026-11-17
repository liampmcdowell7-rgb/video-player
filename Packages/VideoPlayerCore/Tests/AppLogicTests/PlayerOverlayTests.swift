import XCTest
import PlaybackLogic
@testable import AppLogic

final class FakeUpNextPresenter: UpNextProposalPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (any UpNextProposalHandler)?
    private var _presented: [UpNextProposal] = []
    private var _countdowns: [Int?] = []
    private var _dismissals = 0
    var handler: (any UpNextProposalHandler)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }
    var presented: [UpNextProposal] { lock.withLock { _presented } }
    var countdowns: [Int?] { lock.withLock { _countdowns } }
    var dismissals: Int { lock.withLock { _dismissals } }
    func present(_ proposal: UpNextProposal) { lock.withLock { _presented.append(proposal) } }
    func updateCountdown(seconds: Int?) { lock.withLock { _countdowns.append(seconds) } }
    func dismiss() { lock.withLock { _dismissals += 1 } }
}

final class FakeSkipPresenter: SkipButtonPresenting, @unchecked Sendable {
    private let lock = NSLock()
    private var _shown: [String] = []
    private var _hides = 0
    private var _press: (@Sendable () -> Void)?
    var shown: [String] { lock.withLock { _shown } }
    var hides: Int { lock.withLock { _hides } }
    func show(title: String, onPress: @escaping @Sendable () -> Void) { lock.withLock { _shown.append(title); _press = onPress } }
    func hide() { lock.withLock { _hides += 1 } }
    func press() { let p = lock.withLock { _press }; p?() }
}

struct FakeDescriber: EpisodeDescribing {
    var title: String? = "The Return"
    func describe(_ ref: EpisodeRef) -> EpisodeDescription { EpisodeDescription(title: title, previewKey: "still-\(ref.fileID)") }
}

final class PlayerOverlayTests: XCTestCase {
    private let next = EpisodeRef(seriesID: "show", season: 1, episode: 2, fileID: "f2")
    private let file = FileIdentity(path: "/tv/Show/S01E01.mkv", size: 1_000_000, duration: 1500)

    private struct Rig {
        let controller: PlayerOverlayController
        let clock: ManualClock
        let up: FakeUpNextPresenter
        let skip: FakeSkipPresenter
        let effects: Locked<[PlayerOverlayEffect]>
    }

    final class Locked<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ v: T) { value = v }
        func with<R>(_ body: (inout T) -> R) -> R { lock.withLock { body(&value) } }
        var get: T { lock.withLock { value } }
    }

    private func rig(policy: NextEpisodePolicy = NextEpisodePolicy(), title: String? = "The Return",
                     decision: NextEpisodeDecision? = nil, credits: Bool = true) -> Rig {
        var candidates = [SkipSegment(type: .intro, start: 60, end: 120, source: .embeddedChapters, confidence: 0.9, file: file)]
        if credits { candidates.append(SkipSegment(type: .credits, start: 1380, end: 1500, source: .embeddedChapters, confidence: 0.9, file: file)) }
        let resolved = SegmentResolver.resolve(file: file, candidates: candidates, postCreditsStart: nil)
        let clock = ManualClock()
        let session = PlaybackSession(resolved: resolved, duration: 1500, next: decision ?? .next(next), policy: policy, clock: clock)
        let up = FakeUpNextPresenter()
        let skip = FakeSkipPresenter()
        let log = Locked<[PlayerOverlayEffect]>([])
        let controller = PlayerOverlayController(session: session, clock: clock, upNextPresenter: up, skipPresenter: skip,
                                                 describer: FakeDescriber(title: title), sink: { e in log.with { $0 += e } })
        return Rig(controller: controller, clock: clock, up: up, skip: skip, effects: log)
    }

    // MARK: Skip button

    func testSkipButtonAppearsInsideTheIntroAndLeavesAfterIt() {
        let r = rig()
        r.controller.playhead(10, kind: .started)
        XCTAssertNil(r.controller.state.skipButton)
        r.controller.playhead(65, kind: .natural)
        XCTAssertEqual(r.controller.state.skipButton, SkipButtonState(type: .intro, title: "Skip Intro", target: 120))
        XCTAssertEqual(r.controller.state.focus, .skipButton)
        XCTAssertEqual(r.skip.shown, ["Skip Intro"])
        r.controller.playhead(66, kind: .natural)
        XCTAssertEqual(r.skip.shown, ["Skip Intro"], "an unchanged button is not shown twice")
        r.controller.playhead(130, kind: .natural)
        XCTAssertNil(r.controller.state.skipButton)
        XCTAssertEqual(r.skip.hides, 1)
        XCTAssertEqual(r.controller.state.focus, .none)
    }

    func testPressingTheSkipButtonSeeksToTheEndOfTheSegment() {
        let r = rig()
        r.controller.playhead(65, kind: .natural)
        let effects = r.controller.skipPressed()
        XCTAssertEqual(effects, [.seek(to: 120)])
        XCTAssertNil(r.controller.state.skipButton)
        XCTAssertEqual(r.effects.get, [.seek(to: 120)])
        XCTAssertEqual(r.controller.skipPressed(), [], "no button, no effect")
    }

    func testThePlatformButtonCallbackDoesTheSameAsPressing() {
        let r = rig()
        r.controller.playhead(65, kind: .natural)
        r.skip.press()
        XCTAssertEqual(r.effects.get, [.seek(to: 120)])
    }

    // MARK: Up Next

    func testUpNextAppearsAtTheCreditsStartWithTheNextEpisodeNamed() {
        let r = rig()
        r.controller.playhead(1_379, kind: .natural)
        XCTAssertTrue(r.up.presented.isEmpty)
        r.controller.playhead(1_380, kind: .natural)
        let p = try? XCTUnwrap(r.up.presented.first)
        XCTAssertEqual(p?.heading, "Up Next")
        XCTAssertEqual(p?.episodeTitle, "The Return")
        XCTAssertEqual(p?.episodeCode, "S1 E2")
        XCTAssertEqual(p?.previewKey, "still-f2")
        XCTAssertEqual(p?.acceptTitle, "Play Now")
        XCTAssertEqual(p?.dismissTitle, "Cancel")
        XCTAssertEqual(try XCTUnwrap(p?.automaticAcceptanceInterval), 10, accuracy: 0.01)
        XCTAssertEqual(r.controller.state.upNext?.countdownText, "Playing in 10 seconds")
        XCTAssertEqual(r.controller.state.focus, .upNext)
    }

    func testAnEpisodeWithNoTitleIsCalledEpisodeNumber() {
        let r = rig(title: "   ")
        r.controller.playhead(1_380, kind: .natural)
        XCTAssertEqual(r.up.presented.first?.episodeTitle, "Episode 2")
    }

    func testTheCountdownFollowsTheClockAndAdvancesWhenItEnds() {
        let r = rig()
        r.controller.playhead(1_380, kind: .natural)
        r.clock.advance(by: 3)
        r.controller.tick()
        XCTAssertEqual(r.controller.state.upNext?.countdownText, "Playing in 7 seconds")
        XCTAssertEqual(r.up.countdowns.last ?? nil, 7)
        r.clock.advance(by: 6)
        r.controller.tick()
        XCTAssertEqual(r.controller.state.upNext?.countdownText, "Playing in 1 second")
        r.clock.advance(by: 1)
        let effects = r.controller.tick()
        XCTAssertTrue(effects.contains(.advance(next)), "\(effects)")
        XCTAssertNil(r.controller.state.upNext)
        XCTAssertGreaterThanOrEqual(r.up.dismissals, 1)
        XCTAssertTrue(r.effects.get.contains(.markWatched), "watched when advancing at the credits start")
    }

    func testPlayNowAdvancesAtOnce() {
        let r = rig()
        r.controller.playhead(1_380, kind: .natural)
        r.up.handler?.proposalAccepted()
        XCTAssertTrue(r.effects.get.contains(.advance(next)))
        XCTAssertNil(r.controller.state.upNext)
    }

    func testMenuDismissesTheProposalAndTheEpisodeIsNeverAdvancedAgain() {
        let r = rig()
        r.controller.playhead(1_380, kind: .natural)
        let result = r.controller.menuPressed()
        XCTAssertTrue(result.handled)
        XCTAssertNil(r.controller.state.upNext)
        XCTAssertEqual(r.up.dismissals, 1)
        r.clock.advance(by: 60)
        XCTAssertFalse(r.controller.tick().contains(.advance(next)))
        r.controller.playhead(1_450, kind: .natural)
        XCTAssertEqual(r.up.presented.count, 1, "never shown again")
        XCTAssertFalse(r.controller.ended().contains(.advance(next)), "not even when the file ends")
        XCTAssertFalse(r.effects.get.contains(.advance(next)))
    }

    func testMenuWithNoProposalIsNotHandledSoThePlayerExits() {
        let r = rig()
        r.controller.playhead(500, kind: .natural)
        let result = r.controller.menuPressed()
        XCTAssertFalse(result.handled)
        XCTAssertTrue(result.effects.isEmpty)
    }

    func testRejectingFromThePlatformPresenterBehavesLikeMenu() {
        let r = rig()
        r.controller.playhead(1_380, kind: .natural)
        r.up.handler?.proposalRejected()
        XCTAssertNil(r.controller.state.upNext)
        r.clock.advance(by: 60)
        XCTAssertFalse(r.controller.tick().contains(.advance(next)))
    }

    func testSeekingBackOutOfTheCreditsWithdrawsTheProposal() {
        let r = rig()
        r.controller.playhead(1_380, kind: .natural)
        r.controller.playhead(900, kind: .seek)
        XCTAssertNil(r.controller.state.upNext)
        XCTAssertNil(r.controller.state.skipButton)
    }

    func testAskModeProposesWithoutACountdown() {
        let r = rig(policy: NextEpisodePolicy(settings: NextEpisodeSettings(mode: .ask)))
        r.controller.playhead(1_380, kind: .natural)
        XCTAssertNotNil(r.controller.state.upNext)
        XCTAssertNil(r.up.presented.first?.automaticAcceptanceInterval)
        XCTAssertNil(r.controller.state.upNext?.countdownText)
        r.clock.advance(by: 120)
        XCTAssertFalse(r.controller.tick().contains(.advance(next)))
    }

    func testOffModeNeverProposesOrAdvances() {
        let r = rig(policy: NextEpisodePolicy(settings: NextEpisodeSettings(mode: .off)))
        r.controller.playhead(1_380, kind: .natural)
        r.clock.advance(by: 120)
        r.controller.tick()
        let ended = r.controller.ended()
        XCTAssertTrue(r.up.presented.isEmpty)
        XCTAssertFalse(ended.contains(.advance(next)))
    }

    func testPrefetchEffectsPassThroughToTheSink() {
        let r = rig()
        var all: [PlayerOverlayEffect] = []
        for t in stride(from: 1_000.0, through: 1_380, by: 20) { all += r.controller.playhead(t, kind: .natural) }
        XCTAssertTrue(all.contains { if case .prefetch(let e) = $0 { return e == next } else { return false } }, "\(all)")
    }

    func testLastEpisodeOfASeriesPresentsNoProposal() {
        let r = rig(decision: NextEpisodeDecision.none(.endOfSeries))
        r.controller.playhead(1_380, kind: .natural)
        XCTAssertTrue(r.up.presented.isEmpty)
    }

    func testCountdownTextWording() {
        XCTAssertEqual(PlayerOverlayController.countdownText(10), "Playing in 10 seconds")
        XCTAssertEqual(PlayerOverlayController.countdownText(1), "Playing in 1 second")
        XCTAssertNil(PlayerOverlayController.countdownText(0))
        XCTAssertNil(PlayerOverlayController.countdownText(nil))
    }
}
