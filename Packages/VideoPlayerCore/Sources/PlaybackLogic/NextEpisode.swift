import Foundation

// Next Episode: which episode comes next, and the state machine for the "Up Next" proposal.
// The Apple TV side (AVContentProposal, the Menu button) is a thin layer that sends events in and
// applies actions out. Time comes from a `PlaybackClock`, so tests drive it with a fake.

// MARK: Clock

public protocol PlaybackClock: Sendable {
    /// Seconds on a monotonic clock.
    var now: TimeInterval { get }
}

/// A clock that only moves when told to. Used by tests (and usable by anything that needs a fake).
public final class ManualClock: PlaybackClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval

    public init(start: TimeInterval = 0) { value = start }

    public var now: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        value += seconds
    }
}

// MARK: Episodes

public struct EpisodeRef: Equatable, Hashable, Sendable {
    public var seriesID: String
    public var season: Int
    public var episode: Int
    /// Last episode number of a multi-episode file (S01E01-E02 has `episode` 1 and `lastEpisode` 2).
    public var lastEpisode: Int?
    /// What the player opens (a path or an id the app understands).
    public var fileID: String

    public init(seriesID: String, season: Int, episode: Int, lastEpisode: Int? = nil, fileID: String) {
        self.seriesID = seriesID
        self.season = season
        self.episode = episode
        self.lastEpisode = lastEpisode
        self.fileID = fileID
    }

    var lastNumber: Int { max(episode, lastEpisode ?? episode) }
}

public enum NoNextReason: Equatable, Sendable {
    /// Last available episode of the last available season.
    case endOfSeries
    /// Season 0 (specials) never advances automatically.
    case special
    /// Not an episode (a movie, or a file that is not matched to a series).
    case notAnEpisode
}

public enum NextEpisodeDecision: Equatable, Sendable {
    case next(EpisodeRef)
    case none(NoNextReason)
}

/// Supplies the next episode. The state machine never sees the library.
public protocol NextEpisodeProvider: Sendable {
    func nextEpisode(after current: EpisodeRef) async -> NextEpisodeDecision
}

public enum EpisodeOrder {
    /// Rules (docs/PLAYBACK_LOGIC.md):
    /// - Season 0 never advances, and rollover never enters Season 0.
    /// - The next episode is the lowest-numbered AVAILABLE episode after the current one (a multi-episode
    ///   file counts up to its last number), so gaps in the library are skipped.
    /// - After the last available episode of a season, the first available episode of the next available
    ///   season (a missing season is skipped).
    /// - Several files of the same season and episode (versions) count once; the first in the list wins.
    public static func next(after current: EpisodeRef, in available: [EpisodeRef]) -> NextEpisodeDecision {
        guard current.season > 0 else { return .none(.special) }

        var seen = Set<[Int]>()
        var candidates: [EpisodeRef] = []
        for ep in available where ep.season > 0 && ep.seriesID == current.seriesID {
            if seen.insert([ep.season, ep.episode]).inserted { candidates.append(ep) }
        }

        let sameSeason = candidates
            .filter { $0.season == current.season && $0.episode > current.lastNumber }
            .min { $0.episode < $1.episode }
        if let ep = sameSeason { return .next(ep) }

        let laterSeasons = candidates.filter { $0.season > current.season }
        guard let nextSeason = laterSeasons.map(\.season).min() else { return .none(.endOfSeries) }
        let first = laterSeasons.filter { $0.season == nextSeason }.min { $0.episode < $1.episode }
        return first.map { .next($0) } ?? .none(.endOfSeries)
    }
}

/// A provider backed by a closure that lists the available episodes of a series.
public struct LibraryNextEpisodeProvider: NextEpisodeProvider {
    private let loadEpisodes: @Sendable (String) async -> [EpisodeRef]

    public init(loadEpisodes: @escaping @Sendable (String) async -> [EpisodeRef]) {
        self.loadEpisodes = loadEpisodes
    }

    public func nextEpisode(after current: EpisodeRef) async -> NextEpisodeDecision {
        EpisodeOrder.next(after: current, in: await loadEpisodes(current.seriesID))
    }
}


// MARK: Settings (Settings > Playback > Next Episode)

/// The four choices of Settings > Playback > Next Episode, in the order the row shows them.
///
/// What each one does is written out in docs/PLAYBACK_LOGIC.md ("Modes"). The user's text names the choices and
/// describes the default; the behavior of the other three is an Interpretation (PROVISIONAL).
public enum NextEpisodeMode: String, Sendable, CaseIterable, Codable {
    /// Default. Up Next at the credits start (credits known) or at the end of the file; a countdown, then the next
    /// episode starts by itself.
    case whenCreditsBegin
    /// Up Next only at the end of the file, even when the credits are known; a countdown, then the next episode.
    case whenEpisodeEnds
    /// Up Next at the credits start (or the end of the file), no countdown: it waits for the user.
    case ask
    /// No Up Next and no advance. The episode is still marked watched by the usual rule.
    case off

    /// The row text.
    public var title: String {
        switch self {
        case .whenCreditsBegin: return "When Credits Begin"
        case .whenEpisodeEnds: return "When Episode Ends"
        case .ask: return "Ask"
        case .off: return "Off"
        }
    }

    public static let `default`: NextEpisodeMode = .whenCreditsBegin

    /// A countdown runs and the next episode starts by itself.
    var countsDown: Bool { self == .whenCreditsBegin || self == .whenEpisodeEnds }
    /// An Up Next proposal is shown at all.
    var proposes: Bool { self != .off }
}

/// What the user sets: the mode and the countdown row. `NextEpisodePolicy(settings:)` turns it into the policy.
public struct NextEpisodeSettings: Equatable, Sendable, Codable {
    /// Values the countdown row offers (seconds; 0 starts the next episode as soon as Up Next appears).
    /// Interpretation (PROVISIONAL): the user's text only says "a countdown row".
    public static let countdownChoices: [Int] = [0, 5, 10, 15, 20, 30]
    public static let countdownRange: ClosedRange<Int> = 0...30
    public static let defaultCountdownSeconds = 10

    public var mode: NextEpisodeMode
    /// Clamped to `countdownRange`.
    public private(set) var countdownSeconds: Int

    public init(mode: NextEpisodeMode = .default, countdownSeconds: Int = NextEpisodeSettings.defaultCountdownSeconds) {
        self.mode = mode
        self.countdownSeconds = min(max(countdownSeconds, Self.countdownRange.lowerBound), Self.countdownRange.upperBound)
    }

    public mutating func setCountdown(seconds: Int) {
        countdownSeconds = min(max(seconds, Self.countdownRange.lowerBound), Self.countdownRange.upperBound)
    }

    private enum CodingKeys: String, CodingKey { case mode, countdownSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try c.decodeIfPresent(NextEpisodeMode.self, forKey: .mode) ?? .default
        let seconds = try c.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? Self.defaultCountdownSeconds
        self.init(mode: mode, countdownSeconds: seconds)
    }
}

// MARK: State machine

public struct NextEpisodePolicy: Equatable, Sendable {
    public var mode: NextEpisodeMode
    /// The countdown, in seconds, between Up Next appearing and the next episode starting by itself. 0 = at once.
    /// Used by `whenCreditsBegin` and `whenEpisodeEnds`; `ask` never counts down.
    public var autoAdvanceDelay: TimeInterval
    /// The "more than 60 seconds remaining after the credits segment" rule.
    public var trailingLimit: TimeInterval
    /// The playhead counts as "at the end" this close to the duration.
    public var endEpsilon: TimeInterval
    /// How long before Up Next appears the next episode starts to prefetch (Interpretation, PROVISIONAL).
    public var prefetchLead: TimeInterval

    public init(mode: NextEpisodeMode = .default, autoAdvanceDelay: TimeInterval = 10, trailingLimit: TimeInterval = 60,
                endEpsilon: TimeInterval = 0.5, prefetchLead: TimeInterval = 120) {
        self.mode = mode
        self.autoAdvanceDelay = max(0, autoAdvanceDelay)
        self.trailingLimit = trailingLimit
        self.endEpsilon = endEpsilon
        self.prefetchLead = max(0, prefetchLead)
    }

    public init(settings: NextEpisodeSettings) {
        self.init(mode: settings.mode, autoAdvanceDelay: TimeInterval(settings.countdownSeconds))
    }

    /// Read-only compatibility with the earlier "Play Next Episode Automatically" flag: on when a countdown runs.
    public var autoplay: Bool { mode.countsDown }
}

/// The credits segment as the machine needs it (already resolved and normalised).
public struct CreditsTiming: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

public enum NextEpisodeEvent: Equatable, Sendable {
    case playhead(TimeInterval, PlayheadKind)
    case paused
    case resumed
    /// Playback reached the end of the file.
    case ended
    /// Time passed (the host sends this regularly, or after advancing the clock in tests).
    case tick
    /// The Menu button.
    case menu
    case accept
    case dismiss
    /// Skip Credits was activated and its target is the end of the file.
    case skipCreditsToEnd
    /// The user left the player without the next episode starting (Menu with no proposal, Stop, a different item).
    case stopped
}

/// The next episode to fetch ahead of time, and the playhead position where the fetch starts.
public struct PrefetchRequest: Equatable, Sendable {
    public var episode: EpisodeRef
    public var startAt: TimeInterval
}

public enum NextEpisodeAction: Equatable, Sendable {
    /// Mark this episode watched (once per playback session).
    case markWatched
    case presentProposal(EpisodeRef)
    /// Take the proposal off screen without dismissing it for good (the user seeked back).
    case withdrawProposal
    /// The user dismissed the proposal; it never comes back in this session and nothing auto-advances.
    case proposalDismissed
    case advance(EpisodeRef)
    /// The file ended and nothing will play next.
    case playbackEnded
    /// More than 60 s of content follows the credits: offer "Skip Credits" to `target` (the end of the credits
    /// segment) instead of advancing.
    case offerSkipCredits(target: TimeInterval)
    /// The playhead left the credits segment (or the offer no longer applies): take the offer away.
    case withdrawSkipCreditsOffer
    /// Start fetching this episode now.
    case prefetch(EpisodeRef)
    /// Stop fetching it (the proposal was dismissed, or the user left).
    case cancelPrefetch(EpisodeRef)
}

/// One playback session of one episode file. Create a new one per playback.
public struct NextEpisodeMachine: Sendable {
    public let duration: TimeInterval
    public let credits: CreditsTiming?
    public let next: NextEpisodeDecision
    public let policy: NextEpisodePolicy
    /// Formats of this file and of the next one, when known, for `displayModeDecision`.
    public let currentFormat: DisplayFormat?
    public let nextFormat: DisplayFormat?
    private let clock: any PlaybackClock

    private var watched = false
    private var visible = false
    private var dismissed = false
    private var finished = false
    private var endReported = false
    private var deadline: TimeInterval?
    private var prefetchIssued = false
    private var prefetchCancelled = false
    private var offerActive = false

    /// `dismissedBefore`: the app remembers that the user already dismissed Up Next for this episode and wants it to
    /// stay dismissed on a replay. Default false: each playback starts fresh (Interpretation, PROVISIONAL).
    public init(duration: TimeInterval, credits: CreditsTiming?, next: NextEpisodeDecision,
                policy: NextEpisodePolicy = NextEpisodePolicy(), clock: any PlaybackClock,
                currentFormat: DisplayFormat? = nil, nextFormat: DisplayFormat? = nil, dismissedBefore: Bool = false) {
        self.duration = duration
        self.credits = credits
        self.next = next
        self.policy = policy
        self.clock = clock
        self.currentFormat = currentFormat
        self.nextFormat = nextFormat
        self.dismissed = dismissedBefore
    }

    // Derived timing.

    private var endThreshold: TimeInterval { max(0, duration - policy.endEpsilon) }

    private var hasNext: Bool { if case .next = next { return true } else { return false } }

    /// More than `trailingLimit` seconds remain after the credits segment: real content follows.
    private var contentAfterCredits: Bool {
        guard let c = credits else { return false }
        return duration - c.end > policy.trailingLimit
    }

    /// Where Up Next appears, or nil when this mode never shows it (Off).
    /// - When Episode Ends: the end of the file.
    /// - When Credits Begin / Ask: the credits start; the end of the file when the credits are unknown or when more
    ///   than 60 seconds of content remain after the credits segment (Skip Credits is offered instead).
    public var proposalTime: TimeInterval? {
        guard policy.mode.proposes else { return nil }
        if policy.mode == .whenEpisodeEnds { return endThreshold }
        if let c = credits, !contentAfterCredits { return c.start }
        return endThreshold
    }

    /// Where the episode is marked watched: at the credits start, or at the end when no credits are known.
    /// The same in every mode, Off included.
    public var watchedTime: TimeInterval { credits?.start ?? endThreshold }

    /// What to fetch ahead and from which playhead position; nil when nothing will advance (Off, no next episode).
    public var prefetchRequest: PrefetchRequest? {
        guard case .next(let episode) = next, let t = proposalTime else { return nil }
        return PrefetchRequest(episode: episode, startAt: max(0, t - policy.prefetchLead))
    }

    /// Whether the display mode must change for the next episode, or stays (no needless display switch).
    public var displayModeDecision: DisplayModeDecision {
        DisplayModePlanner.decide(current: currentFormat, next: nextFormat)
    }

    public var isProposalVisible: Bool { visible }
    public var wasDismissed: Bool { dismissed }
    public var isFinished: Bool { finished }
    /// Seconds on the clock when the automatic acceptance will happen, if one is armed.
    public var automaticAcceptanceDeadline: TimeInterval? { deadline }
    /// The "Skip Credits" offer that replaces advancing when more than 60 s of content follow the credits:
    /// its target while the playhead is inside the credits segment, else nil.
    public var skipCreditsOfferTarget: TimeInterval? {
        guard offerActive, !finished, let c = credits else { return nil }
        return c.end
    }

    public mutating func handle(_ event: NextEpisodeEvent) -> [NextEpisodeAction] {
        guard !finished else { return [] }
        switch event {
        case .playhead(let time, let kind): return onPlayhead(time, kind)
        case .paused:
            deadline = nil                      // the user took control: no automatic acceptance
            return []
        case .resumed: return []
        case .tick: return onTick()
        case .ended: return onEnded(immediate: false)
        case .menu, .dismiss: return dismissIfVisible()
        case .accept:
            guard visible, case .next(let episode) = next else { return [] }
            return advance(to: episode)
        case .skipCreditsToEnd: return onEnded(immediate: true)
        case .stopped:
            let out = cancelPrefetchIfNeeded()
            finished = true
            visible = false
            deadline = nil
            return out
        }
    }

    // MARK: Handlers

    private mutating func onPlayhead(_ time: TimeInterval, _ kind: PlayheadKind) -> [NextEpisodeAction] {
        var out: [NextEpisodeAction] = []
        if kind == .seek {
            if visible, let proposalAt = proposalTime, time < proposalAt {
                visible = false
                deadline = nil
                out.append(.withdrawProposal)
            } else {
                deadline = nil                  // the user is in control after a seek
            }
        }
        out += prefetchIfDue(time)
        out += updateSkipCreditsOffer(time)
        if !watched, time >= watchedTime {
            watched = true
            out.append(.markWatched)
        }
        if time >= endThreshold {
            return out + onEnded(immediate: false)
        }
        if let proposalAt = proposalTime, time >= proposalAt {
            out += present(kind)
        }
        return out
    }

    private mutating func prefetchIfDue(_ time: TimeInterval) -> [NextEpisodeAction] {
        guard !prefetchIssued, !dismissed, let request = prefetchRequest, time >= request.startAt else { return [] }
        prefetchIssued = true
        return [.prefetch(request.episode)]
    }

    private mutating func cancelPrefetchIfNeeded() -> [NextEpisodeAction] {
        guard prefetchIssued, !prefetchCancelled, case .next(let episode) = next else { return [] }
        prefetchCancelled = true
        return [.cancelPrefetch(episode)]
    }

    private mutating func updateSkipCreditsOffer(_ time: TimeInterval) -> [NextEpisodeAction] {
        var wanted = false
        // Only the modes that would otherwise advance at the credits start (When Credits Begin, Ask) make the offer.
        let proposesAtCredits = policy.mode == .whenCreditsBegin || policy.mode == .ask
        if let c = credits, proposesAtCredits, hasNext, contentAfterCredits, time >= c.start, time < c.end { wanted = true }
        if wanted, !offerActive, let c = credits {
            offerActive = true
            return [.offerSkipCredits(target: c.end)]
        }
        if !wanted, offerActive {
            offerActive = false
            return [.withdrawSkipCreditsOffer]
        }
        return []
    }

    private mutating func present(_ kind: PlayheadKind) -> [NextEpisodeAction] {
        guard case .next(let episode) = next, !dismissed, !visible else { return [] }
        visible = true
        var out: [NextEpisodeAction] = [.presentProposal(episode)]
        // The countdown starts only when playback reaches the proposal by itself: not after a seek and not when
        // resuming inside the credits. Ask never counts down.
        if policy.mode.countsDown, kind == .natural {
            if policy.autoAdvanceDelay <= 0 { return out + advance(to: episode) }
            deadline = clock.now + policy.autoAdvanceDelay
        }
        return out
    }

    private mutating func onEnded(immediate: Bool) -> [NextEpisodeAction] {
        var out: [NextEpisodeAction] = []
        if !watched {
            watched = true
            out.append(.markWatched)
        }
        guard policy.mode.proposes, case .next(let episode) = next, !dismissed else {
            if !endReported { endReported = true; out.append(.playbackEnded) }
            return out
        }
        if !visible {
            visible = true
            out.append(.presentProposal(episode))
        }
        if policy.mode.countsDown {
            if immediate || policy.autoAdvanceDelay <= 0 { return out + advance(to: episode) }
            if deadline == nil { deadline = clock.now + policy.autoAdvanceDelay }
        } else if !endReported {
            endReported = true
            out.append(.playbackEnded)          // Ask: the proposal stays up, waiting for the user
        }
        return out
    }

    private mutating func onTick() -> [NextEpisodeAction] {
        guard visible, !dismissed, case .next(let episode) = next, let due = deadline, clock.now >= due else { return [] }
        return advance(to: episode)
    }

    private mutating func dismissIfVisible() -> [NextEpisodeAction] {
        // Menu with no proposal on screen is not ours: the host handles it (exits the player).
        guard visible else { return [] }
        dismissed = true
        visible = false
        deadline = nil
        return [.proposalDismissed] + cancelPrefetchIfNeeded()
    }

    private mutating func advance(to episode: EpisodeRef) -> [NextEpisodeAction] {
        finished = true
        visible = false
        deadline = nil
        return [.advance(episode)]
    }
}

public enum NextEpisodeResolution {
    /// Asks the provider once and builds the machine for this playback session.
    public static func makeMachine(
        provider: any NextEpisodeProvider,
        current: EpisodeRef?,
        duration: TimeInterval,
        credits: CreditsTiming?,
        policy: NextEpisodePolicy = NextEpisodePolicy(),
        clock: any PlaybackClock,
        currentFormat: DisplayFormat? = nil,
        nextFormat: DisplayFormat? = nil
    ) async -> NextEpisodeMachine {
        let decision: NextEpisodeDecision
        if let current { decision = await provider.nextEpisode(after: current) } else { decision = .none(.notAnEpisode) }
        return NextEpisodeMachine(duration: duration, credits: credits, next: decision, policy: policy, clock: clock,
                                  currentFormat: currentFormat, nextFormat: nextFormat)
    }
}
