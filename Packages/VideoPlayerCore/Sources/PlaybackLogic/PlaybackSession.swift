import Foundation

/// What the player layer must do after an update.
public struct SessionUpdate: Equatable, Sendable {
    /// Skip button to show, an automatic jump, or nothing.
    public var skip: SkipOutput
    /// Next Episode actions, in order.
    public var episode: [NextEpisodeAction]
    /// Seek here (set when a skip happened).
    public var seek: TimeInterval?
}

/// Combines the skip controller and the Next Episode machine for one playback of one file, so
/// "Skip Credits" flows into Next Episode. The Apple TV layer sends playhead events in and applies
/// the returned `SessionUpdate`. Not verified on a device (AVContentProposal, contextualActions).
public struct PlaybackSession: Sendable {
    public private(set) var skipController: SkipController
    public private(set) var machine: NextEpisodeMachine
    public let resolved: ResolvedSegments
    private let duration: TimeInterval
    private let endEpsilon: TimeInterval

    public init(resolved: ResolvedSegments, duration: TimeInterval, settings: SkipSettings = SkipSettings(),
                next: NextEpisodeDecision, policy: NextEpisodePolicy = NextEpisodePolicy(),
                clock: any PlaybackClock, currentFormat: DisplayFormat? = nil, nextFormat: DisplayFormat? = nil,
                dismissedBefore: Bool = false) {
        self.resolved = resolved
        self.duration = duration
        self.endEpsilon = policy.endEpsilon
        self.skipController = SkipController(segments: resolved.segments, settings: settings)
        let credits = resolved.segment(of: .credits).map { CreditsTiming(start: $0.start, end: $0.end) }
        self.machine = NextEpisodeMachine(duration: duration, credits: credits, next: next, policy: policy, clock: clock,
                                          currentFormat: currentFormat, nextFormat: nextFormat,
                                          dismissedBefore: dismissedBefore)
    }

    /// Report the playhead. An automatic skip is performed here and reported through `seek`.
    ///
    /// When more than 60 s of content follow the credits, Next Episode does not advance at the credits start; it
    /// offers "Skip Credits" to the end of the credits segment instead. That offer shows as the skip button even when
    /// the user set Skip Credits to Off (Interpretation, PROVISIONAL), unless the setting already shows a button
    /// or jumps (Ask, Automatic).
    public mutating func playhead(_ time: TimeInterval, kind: PlayheadKind) -> SessionUpdate {
        var skipOutput = skipController.update(playhead: time, kind: kind)
        var actions = machine.handle(.playhead(time, kind))
        var seek: TimeInterval?
        if case .jump(let type, let target) = skipOutput {
            seek = target
            actions += afterSkip(type: type, target: target)
        } else if case .none = skipOutput, let target = machine.skipCreditsOfferTarget {
            skipOutput = .button(SkipButton(type: .credits, title: SegmentType.credits.buttonTitle, target: target))
        }
        return SessionUpdate(skip: skipOutput, episode: actions, seek: seek)
    }

    /// The user activated the skip button for `type`.
    public mutating func skipPressed(_ type: SegmentType) -> SessionUpdate {
        guard let segment = resolved.segment(of: type) else {
            return SessionUpdate(skip: .none, episode: [], seek: nil)
        }
        let target = skipController.target(for: segment)
        let actions = afterSkip(type: type, target: target)
        return SessionUpdate(skip: .none, episode: actions, seek: target)
    }

    public mutating func event(_ event: NextEpisodeEvent) -> [NextEpisodeAction] { machine.handle(event) }

    private mutating func afterSkip(type: SegmentType, target: TimeInterval) -> [NextEpisodeAction] {
        if type == .credits, target >= duration - endEpsilon { return machine.handle(.skipCreditsToEnd) }
        return machine.handle(.playhead(target, .seek))
    }
}
