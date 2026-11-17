import Foundation
import PlaybackLogic

// The player's skip button and Up Next proposal: state for the UI, the calls to the proposal presenter, and the
// effects the player must carry out (seek, mark watched, advance, prefetch). It sits on top of PlaybackLogic's
// `PlaybackSession`; every decision about WHEN things happen is made there (docs/PLAYBACK_LOGIC.md). This file only
// turns its output into what is drawn.
//
// Apple side (in the app: App/Features/Player/ProposalPresenter.swift and SkipButtonPresenter.swift): AVContentProposal presented through
// AVPlayerViewController, and the skip button as an AVPlayerViewController contextual action. Both sit behind
// `UpNextProposalPresenting` and `SkipButtonPresenting` below.

// MARK: Up Next

/// What the proposal shows. `automaticAcceptanceInterval` is the countdown our own state machine runs (seconds until it plays
/// by itself; nil = none). Apple's AVContentProposal has a countdown too, but it counts from the END of playback, not from the
/// credits start, so the Apple wrapper switches it off (NaN) and shows this one (Interpretation, PROVISIONAL: checked against
/// Apple's documentation only; the real behaviour is on the Apple TV checklist).
public struct UpNextProposal: Equatable, Sendable {
    public var episode: EpisodeRef
    /// "Up Next".
    public var heading: String
    /// The next episode's title ("The Long Night"), or "Episode 4" when it has none.
    public var episodeTitle: String
    /// "S2 E4".
    public var episodeCode: String?
    /// Key of the preview image the app can load (the next episode's still), nil = none.
    public var previewKey: String?
    /// Seconds until it plays by itself; nil = no countdown (the Ask mode waits for the user).
    public var automaticAcceptanceInterval: TimeInterval?
    public var acceptTitle: String
    public var dismissTitle: String
}

public protocol UpNextProposalHandler: AnyObject, Sendable {
    /// The user pressed Play Now (or the system's countdown ended).
    func proposalAccepted()
    /// The user pressed Menu on the proposal.
    func proposalRejected()
}

/// The platform's Up Next presenter (AVContentProposal on tvOS). `handler` is set by the controller.
public protocol UpNextProposalPresenting: AnyObject, Sendable {
    var handler: (any UpNextProposalHandler)? { get set }
    func present(_ proposal: UpNextProposal)
    /// Changes the countdown text while the proposal is up (a presenter that cannot do this may ignore it).
    func updateCountdown(seconds: Int?)
    func dismiss()
}

public protocol SkipButtonPresenting: AnyObject, Sendable {
    /// Shows the button with this title and calls `onPress` when it is activated.
    func show(title: String, onPress: @escaping @Sendable () -> Void)
    func hide()
}

/// Names the next episode for the proposal. The app implements it over the library.
public protocol EpisodeDescribing: Sendable {
    func describe(_ ref: EpisodeRef) -> EpisodeDescription
}

public struct EpisodeDescription: Equatable, Sendable {
    public var title: String?
    public var previewKey: String?
    public init(title: String?, previewKey: String? = nil) {
        self.title = title
        self.previewKey = previewKey
    }
}

// MARK: State

public enum OverlayFocus: Equatable, Sendable { case none, skipButton, upNext }

public struct SkipButtonState: Equatable, Sendable {
    public var type: SegmentType
    /// "Skip Intro", "Skip Recap", "Skip Credits".
    public var title: String
    public var target: TimeInterval
}

public struct UpNextState: Equatable, Sendable {
    public var proposal: UpNextProposal
    /// "Playing in 7 seconds", or nil when there is no countdown running.
    public var countdownText: String?
}

public struct PlayerOverlayState: Equatable, Sendable {
    public var skipButton: SkipButtonState?
    public var upNext: UpNextState?
    /// Interpretation (PROVISIONAL): Up Next takes focus when it appears, then the skip button, else focus stays on playback.
    public var focus: OverlayFocus {
        if upNext != nil { return .upNext }
        if skipButton != nil { return .skipButton }
        return .none
    }
}

/// What the player must do. Presenter calls (show/hide the UI) are made by the controller itself.
public enum PlayerOverlayEffect: Equatable, Sendable {
    case seek(to: TimeInterval)
    case markWatched
    case advance(EpisodeRef)
    case playbackEnded
    case prefetch(EpisodeRef)
    case cancelPrefetch(EpisodeRef)
}

public struct MenuResult: Equatable, Sendable {
    /// True when the proposal was on screen and Menu dismissed it; false = not ours, the player should exit as usual.
    public var handled: Bool
    public var effects: [PlayerOverlayEffect]
}

// MARK: Controller

/// One playback of one file. Create a new controller per playback. Thread-safe (one lock); presenter calls and the
/// effect sink run after the lock is released, so a presenter may call back into the controller.
public final class PlayerOverlayController: @unchecked Sendable, UpNextProposalHandler {
    private let lock = NSLock()
    private var session: PlaybackSession
    private let clock: any PlaybackClock
    private let describer: any EpisodeDescribing
    private let upNextPresenter: any UpNextProposalPresenting
    private let skipPresenter: (any SkipButtonPresenting)?
    private let sink: @Sendable ([PlayerOverlayEffect]) -> Void
    private var overlay = PlayerOverlayState()

    private enum UICall {
        case present(UpNextProposal)
        case countdown(Int?)
        case dismissUpNext
        case showSkip(String)
        case hideSkip
    }

    public init(
        session: PlaybackSession, clock: any PlaybackClock, upNextPresenter: any UpNextProposalPresenting,
        skipPresenter: (any SkipButtonPresenting)? = nil, describer: any EpisodeDescribing,
        sink: @escaping @Sendable ([PlayerOverlayEffect]) -> Void = { _ in }
    ) {
        self.session = session
        self.clock = clock
        self.upNextPresenter = upNextPresenter
        self.skipPresenter = skipPresenter
        self.describer = describer
        self.sink = sink
        upNextPresenter.handler = self
    }

    public var state: PlayerOverlayState { lock.withLock { overlay } }

    /// Whether the display mode must change for the next episode (pass-through of PlaybackLogic's decision).
    public var displayModeDecision: DisplayModeDecision { lock.withLock { session.machine.displayModeDecision } }

    // MARK: Inputs

    @discardableResult
    public func playhead(_ time: TimeInterval, kind: PlayheadKind) -> [PlayerOverlayEffect] {
        run { me, calls in
            let update = me.session.playhead(time, kind: kind)
            var effects: [PlayerOverlayEffect] = []
            me.applySkip(update.skip, calls: &calls)
            if let seek = update.seek { effects.append(.seek(to: seek)) }
            effects += me.apply(update.episode, calls: &calls)
            me.refreshCountdown(calls: &calls)
            return effects
        }
    }

    /// The user activated the skip button.
    @discardableResult
    public func skipPressed() -> [PlayerOverlayEffect] {
        run { me, calls in
            guard let button = me.overlay.skipButton else { return [] }
            let update = me.session.skipPressed(button.type)
            me.overlay.skipButton = nil
            calls.append(.hideSkip)
            var effects: [PlayerOverlayEffect] = []
            if let seek = update.seek { effects.append(.seek(to: seek)) }
            effects += me.apply(update.episode, calls: &calls)
            me.refreshCountdown(calls: &calls)
            return effects
        }
    }

    /// Drive this about once a second while a countdown may be running (a platform timer calls it).
    @discardableResult
    public func tick() -> [PlayerOverlayEffect] {
        run { me, calls in
            let actions = me.session.event(.tick)
            let effects = me.apply(actions, calls: &calls)
            me.refreshCountdown(calls: &calls)
            return effects
        }
    }

    @discardableResult public func paused() -> [PlayerOverlayEffect] { event(.paused) }
    @discardableResult public func resumed() -> [PlayerOverlayEffect] { event(.resumed) }
    @discardableResult public func ended() -> [PlayerOverlayEffect] { event(.ended) }
    /// The user left the player.
    @discardableResult public func stopped() -> [PlayerOverlayEffect] { event(.stopped) }

    /// Menu on the remote. `handled == false` means no proposal was on screen: the player should exit as usual.
    public func menuPressed() -> MenuResult {
        var handled = false
        let effects = run { me, calls in
            let actions = me.session.event(.menu)
            handled = actions.contains(.proposalDismissed)
            let effects = me.apply(actions, calls: &calls)
            me.refreshCountdown(calls: &calls)
            return effects
        }
        return MenuResult(handled: handled, effects: effects)
    }

    // MARK: UpNextProposalHandler

    public func proposalAccepted() { _ = event(.accept) }
    public func proposalRejected() { _ = event(.dismiss) }

    // MARK: Internals

    @discardableResult
    private func event(_ e: NextEpisodeEvent) -> [PlayerOverlayEffect] {
        run { me, calls in
            let actions = me.session.event(e)
            let effects = me.apply(actions, calls: &calls)
            me.refreshCountdown(calls: &calls)
            return effects
        }
    }

    private func run(_ body: (PlayerOverlayController, inout [UICall]) -> [PlayerOverlayEffect]) -> [PlayerOverlayEffect] {
        var calls: [UICall] = []
        lock.lock()
        let effects = body(self, &calls)
        lock.unlock()
        for call in calls {
            switch call {
            case .present(let p): upNextPresenter.present(p)
            case .countdown(let s): upNextPresenter.updateCountdown(seconds: s)
            case .dismissUpNext: upNextPresenter.dismiss()
            case .showSkip(let title):
                skipPresenter?.show(title: title, onPress: { [weak self] in _ = self?.skipPressed() })
            case .hideSkip: skipPresenter?.hide()
            }
        }
        if !effects.isEmpty { sink(effects) }
        return effects
    }

    private func applySkip(_ output: SkipOutput, calls: inout [UICall]) {
        switch output {
        case .none:
            if overlay.skipButton != nil {
                overlay.skipButton = nil
                calls.append(.hideSkip)
            }
        case .button(let b):
            let state = SkipButtonState(type: b.type, title: b.title, target: b.target)
            if overlay.skipButton != state {
                overlay.skipButton = state
                calls.append(.showSkip(state.title))
            }
        case .jump:
            // Automatic skip: no UI. The seek arrives in `SessionUpdate.seek`.
            if overlay.skipButton != nil {
                overlay.skipButton = nil
                calls.append(.hideSkip)
            }
        }
    }

    private func apply(_ actions: [NextEpisodeAction], calls: inout [UICall]) -> [PlayerOverlayEffect] {
        var effects: [PlayerOverlayEffect] = []
        for action in actions {
            switch action {
            case .markWatched: effects.append(.markWatched)
            case .presentProposal(let ref):
                let proposal = makeProposal(ref)
                overlay.upNext = UpNextState(proposal: proposal, countdownText: Self.countdownText(proposal.automaticAcceptanceInterval))
                calls.append(.present(proposal))
            case .withdrawProposal, .proposalDismissed:
                if overlay.upNext != nil {
                    overlay.upNext = nil
                    calls.append(.dismissUpNext)
                }
            case .advance(let ref):
                if overlay.upNext != nil {
                    overlay.upNext = nil
                    calls.append(.dismissUpNext)
                }
                if overlay.skipButton != nil {
                    overlay.skipButton = nil
                    calls.append(.hideSkip)
                }
                effects.append(.advance(ref))
            case .playbackEnded: effects.append(.playbackEnded)
            case .prefetch(let ref): effects.append(.prefetch(ref))
            case .cancelPrefetch(let ref): effects.append(.cancelPrefetch(ref))
            case .offerSkipCredits:
                break                       // the skip button itself arrives through `SessionUpdate.skip`
            case .withdrawSkipCreditsOffer:
                if overlay.skipButton?.type == .credits {
                    overlay.skipButton = nil
                    calls.append(.hideSkip)
                }
            }
        }
        return effects
    }

    /// Keeps the countdown text and the presenter's countdown in step with the machine's deadline.
    private func refreshCountdown(calls: inout [UICall]) {
        guard var up = overlay.upNext else { return }
        let remaining = session.machine.automaticAcceptanceDeadline.map { max(0, Int(($0 - clock.now).rounded(.up))) }
        let text = Self.countdownText(remaining.map(TimeInterval.init))
        if text != up.countdownText {
            up.countdownText = text
            overlay.upNext = up
            calls.append(.countdown(remaining))
        }
    }

    private func makeProposal(_ ref: EpisodeRef) -> UpNextProposal {
        let d = describer.describe(ref)
        let interval = session.machine.automaticAcceptanceDeadline.map { max(0, $0 - clock.now) }
        let fallback = "Episode \(ref.episode)"
        let title = d.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? fallback
        return UpNextProposal(
            episode: ref, heading: "Up Next", episodeTitle: title,
            episodeCode: DisplayText.episodeCode(season: ref.season, episode: ref.episode, episodeEnd: ref.lastEpisode),
            previewKey: d.previewKey, automaticAcceptanceInterval: interval,
            acceptTitle: "Play Now", dismissTitle: "Cancel")
    }

    static func countdownText(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        let n = Int(seconds.rounded(.up))
        return n >= 1 ? "Playing in \(DisplayText.seconds(n))" : nil
    }
}
