import Foundation

/// Settings > Playback: Skip Intro / Skip Recap / Skip Credits, each Ask, Automatic or Off (B9). Default Ask.
public enum SkipSetting: String, Sendable, CaseIterable, Codable {
    case ask, automatic, off
}

public struct SkipSettings: Equatable, Sendable, Codable {
    public var recap: SkipSetting
    public var intro: SkipSetting
    public var credits: SkipSetting

    public init(recap: SkipSetting = .ask, intro: SkipSetting = .ask, credits: SkipSetting = .ask) {
        self.recap = recap
        self.intro = intro
        self.credits = credits
    }

    public func setting(for type: SegmentType) -> SkipSetting {
        switch type {
        case .recap: return recap
        case .intro: return intro
        case .credits: return credits
        }
    }
}

/// How the playhead got to its new value.
public enum PlayheadKind: Sendable, Equatable {
    /// Playback started (possibly resuming at a saved position).
    case started
    /// Normal playback moved forward.
    case natural
    /// The user (or a skip) jumped the playhead.
    case seek
}

public struct SkipButton: Equatable, Sendable {
    public var type: SegmentType
    /// "Skip Intro", "Skip Recap" or "Skip Credits" (B7).
    public var title: String
    /// Where the player jumps to when the button is activated.
    public var target: TimeInterval
}

public enum SkipOutput: Equatable, Sendable {
    /// Nothing to show.
    case none
    /// Show Apple's contextual action while the playhead is inside the segment (setting Ask).
    case button(SkipButton)
    /// Jump now without any UI (setting Automatic, B10: no toast, no confirmation).
    case jump(type: SegmentType, target: TimeInterval)
}

/// Decides what the skip UI shows at each playhead update. Pure and deterministic. The Apple TV side
/// (contextualActions, the actual seek) is a thin layer that only calls this and applies the output.
public struct SkipController: Sendable {
    public let segments: [SkipSegment]
    public var settings: SkipSettings
    private var autoJumped: Set<SegmentType> = []

    public init(segments: [SkipSegment], settings: SkipSettings = SkipSettings()) {
        self.segments = segments
        self.settings = settings
    }

    /// Where a segment's action jumps to: the end of the segment. For credits that already is the
    /// post-credits chapter (when there is one) or the end of the file (see `SegmentResolver`). Never past the end of the
    /// file (#27 item 2), even for a segment that did not go through the resolver.
    public func target(for segment: SkipSegment) -> TimeInterval {
        let duration = segment.file.duration
        guard duration > 0, duration.isFinite else { return segment.end }
        return min(segment.end, duration)
    }

    /// Segment containing `time` that the user has not switched off, best source first.
    public func activeSegment(at time: TimeInterval) -> SkipSegment? {
        segments
            .filter { $0.contains(time) && settings.setting(for: $0.type) != .off }
            .sorted { a, b in
                a.source.priority != b.source.priority ? a.source.priority > b.source.priority : a.start < b.start
            }
            .first
    }

    public mutating func update(playhead: TimeInterval, kind: PlayheadKind) -> SkipOutput {
        guard let segment = activeSegment(at: playhead) else { return .none }
        switch settings.setting(for: segment.type) {
        case .off:
            return .none
        case .ask:
            return .button(SkipButton(type: segment.type, title: segment.type.buttonTitle, target: target(for: segment)))
        case .automatic:
            // Jumps once per segment, and only when playback reaches it (or starts inside it). A seek into
            // it (for example the user stepping back after an automatic skip) never jumps again (B10).
            guard kind != .seek, !autoJumped.contains(segment.type) else { return .none }
            autoJumped.insert(segment.type)
            return .jump(type: segment.type, target: target(for: segment))
        }
    }
}
