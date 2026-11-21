import Foundation

/// Settings > Playback: Skip Intro / Skip Recap / Skip Credits, each Ask, Automatic or Off (B9). Default Ask.
public enum SkipSetting: String, Sendable, CaseIterable, Codable {
    case ask, automatic, off
}

public struct SkipSettings: Equatable, Sendable, Codable {
    public var recap: SkipSetting
    public var intro: SkipSetting
    public var credits: SkipSetting
    /// R314: what an Automatic kind does when its segment may not skip by itself (`SkipController.allowsAutomatic`):
    /// show the button (Ask, the default) or nothing (Off, when Show Skip Buttons is off).
    public var untrustedFallback: SkipSetting

    public init(recap: SkipSetting = .ask, intro: SkipSetting = .ask, credits: SkipSetting = .ask, untrustedFallback: SkipSetting = .ask) {
        self.recap = recap
        self.intro = intro
        self.credits = credits
        self.untrustedFallback = untrustedFallback == .automatic ? .ask : untrustedFallback
    }

    enum CodingKeys: String, CodingKey { case recap, intro, credits, untrustedFallback }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(recap: try c.decode(SkipSetting.self, forKey: .recap), intro: try c.decode(SkipSetting.self, forKey: .intro),
                  credits: try c.decode(SkipSetting.self, forKey: .credits),
                  untrustedFallback: try c.decodeIfPresent(SkipSetting.self, forKey: .untrustedFallback) ?? .ask)
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

/// What pressing the button does.
public enum SkipButtonAction: Sendable, Equatable {
    /// "Skip Intro": jump to the end of the segment.
    case skip
    /// R314 "Watch Intro": shown for a few seconds after an automatic skip; goes back to the start of the segment.
    case back
}

public struct SkipButton: Equatable, Sendable {
    public var type: SegmentType
    /// "Skip Intro", "Skip Recap" or "Skip Credits" (B7); "Watch Intro" and the like for `.back`.
    public var title: String
    /// Where the player jumps to when the button is activated.
    public var target: TimeInterval
    public var action: SkipButtonAction

    public init(type: SegmentType, title: String, target: TimeInterval, action: SkipButtonAction = .skip) {
        self.type = type
        self.title = title
        self.target = target
        self.action = action
    }
}

public enum SkipOutput: Equatable, Sendable {
    /// Nothing to show.
    case none
    /// Show Apple's contextual action while the playhead is inside the segment (setting Ask), or the way back after an
    /// automatic skip (R314).
    case button(SkipButton)
    /// Jump now (setting Automatic). R314: the way back follows as a `.back` button for `SkipController.backWindow` seconds.
    case jump(type: SegmentType, target: TimeInterval)
}

/// Decides what the skip UI shows at each playhead update. Pure and deterministic. The Apple TV side
/// (contextualActions, the actual seek) is a thin layer that only calls this and applies the output.
///
/// R314 (owner's request of 21 Nov 2026; behaviour of the owner's reference player, decided by the owner's standing rule
/// R312): an automatic skip happens without a press only for a segment the app trusts (`allowsAutomatic`); for any other
/// it shows the button as Ask does. After an automatic skip, a "Watch Intro" action shows for `backWindow` seconds; pressing
/// it goes back to the start, and the segment is not skipped again in this playback.
public struct SkipController: Sendable {
    public let segments: [SkipSegment]
    public var settings: SkipSettings
    public var limits: SegmentLimits
    /// R314: how long the way back stays after an automatic skip, in seconds of playback.
    public static let backWindow: TimeInterval = 5
    private var autoJumped: Set<SegmentType> = []
    /// The last automatic skip whose way back may still show.
    private var back: (type: SegmentType, start: TimeInterval, landed: TimeInterval)?

    public init(segments: [SkipSegment], settings: SkipSettings = SkipSettings(), limits: SegmentLimits = SegmentLimits()) {
        self.segments = segments
        self.settings = settings
        self.limits = limits
    }

    /// R314: whether `segment` may be skipped without a press. Times made for this file (user marks, chapters, sidecars,
    /// server markers) may; an online timing only when the audio confirmed it (R288); on-device detection only at
    /// `SegmentLimits.automaticDetectionConfidence` (two or more agreeing episodes).
    public func allowsAutomatic(_ segment: SkipSegment) -> Bool {
        switch segment.source {
        case .userMarked, .embeddedChapters, .localSidecar, .serverMarkers: return true
        case .onlineDatabase: return segment.audioConfirmed == true
        case .onDeviceDetection: return segment.confidence >= limits.automaticDetectionConfidence
        }
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

    /// The setting that applies to `segment` now: Automatic falls back (`SkipSettings.untrustedFallback`) for a segment
    /// that may not skip by itself.
    public func effectiveSetting(for segment: SkipSegment) -> SkipSetting {
        let setting = settings.setting(for: segment.type)
        if setting == .automatic, !allowsAutomatic(segment) { return settings.untrustedFallback }
        return setting
    }

    public mutating func update(playhead: TimeInterval, kind: PlayheadKind) -> SkipOutput {
        guard let segment = activeSegment(at: playhead) else { return backOutput(at: playhead) }
        back = nil
        switch effectiveSetting(for: segment) {
        case .off:
            return .none
        case .ask:
            return .button(SkipButton(type: segment.type, title: segment.type.buttonTitle, target: target(for: segment)))
        case .automatic:
            // Jumps once per segment, and only when playback reaches it (or starts inside it). A seek into
            // it (for example the user stepping back after an automatic skip) never jumps again (B10).
            guard kind != .seek, !autoJumped.contains(segment.type) else { return .none }
            autoJumped.insert(segment.type)
            let landed = target(for: segment)
            back = (segment.type, segment.start, landed)
            return .jump(type: segment.type, target: landed)
        }
    }

    /// The person chose the way back: no further way back, and the segment stays unskipped for this playback.
    public mutating func wentBack() { back = nil }

    /// The way back while the playhead is just after where the automatic skip landed (the skip's own seek lands there).
    private mutating func backOutput(at playhead: TimeInterval) -> SkipOutput {
        guard let shown = back else { return .none }
        if playhead >= shown.landed - 1, playhead < shown.landed + Self.backWindow {
            return .button(SkipButton(type: shown.type, title: shown.type.backTitle, target: shown.start, action: .back))
        }
        back = nil
        return .none
    }
}
