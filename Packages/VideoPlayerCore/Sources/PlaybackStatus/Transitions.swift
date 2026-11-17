import Foundation

// Smooth transitions between episodes (FEATURE_BACKLOG Tier A item 13).
// Pure decisions only. Tests cover the decisions; whether tvOS actually avoids a black screen when the
// mode is kept is UNVERIFIED and needs a device test.

/// What an episode needs from the display.
public struct EpisodeVideoTraits: Equatable, Sendable {
    public var format: HDRFormat
    public var frameRate: Double?
    public var profile7: Profile7Conversion

    public init(format: HDRFormat, frameRate: Double?, profile7: Profile7Conversion = .available) {
        self.format = format
        self.frameRate = frameRate
        self.profile7 = profile7
    }
}

public enum DisplayChangeReason: String, Sendable {
    case dynamicRange
    case frameRate
    /// The display's abilities are unknown, so a switch cannot be ruled out.
    case displayUnknown
}

public enum DisplayModeDecision: Equatable, Sendable {
    /// Leave the display as it is. No black screen.
    case keep
    case change(DisplayChangeReason)
}

public enum Transitions {
    /// Frame rates closer than this are the same (23.976 vs 23.9760239…).
    public static let frameRateTolerance = 0.005

    /// Does moving from one episode to the next need a display mode switch?
    /// Interpretation (PROVISIONAL): a switch is needed when the dynamic-range mode the display ends up in
    /// differs, or (when the user matches frame rate) when the frame rates differ. An unknown frame rate on
    /// either side counts as "same". When the display's abilities are unknown and the formats differ,
    /// the answer is `.change(.displayUnknown)` because a switch cannot be ruled out.
    public static func displayModeChange(from a: EpisodeVideoTraits, to b: EpisodeVideoTraits,
                                         availableHDR: DisplayHDRModes?, matchDynamicRange: Bool = true,
                                         matchFrameRate: Bool = true) -> DisplayModeDecision {
        if matchDynamicRange && a.format != b.format {
            let ma = StatusRules.expectedMode(a.format, availableHDR: availableHDR, profile7: a.profile7)
            let mb = StatusRules.expectedMode(b.format, availableHDR: availableHDR, profile7: b.profile7)
            if ma == nil || mb == nil { return .change(.displayUnknown) }
            if ma != mb { return .change(.dynamicRange) }
        }
        if matchFrameRate, let fa = a.frameRate, let fb = b.frameRate, abs(fa - fb) > frameRateTolerance {
            return .change(.frameRate)
        }
        return .keep
    }
}

/// Decides when to start preparing the next episode (item 13: "prepare next episode during credits").
public struct NextEpisodePreparer: Equatable, Sendable {
    public enum Phase: String, Sendable { case idle, preparing, ready }
    public enum Action: Equatable, Sendable { case none, startPreparing }

    /// When credits are unknown, preparing starts this long before the end. PROVISIONAL (no number from the user).
    public static let fallbackLeadSeconds = 30.0

    public private(set) var phase: Phase = .idle
    public let duration: Double
    public let creditsStart: Double?
    public let hasNextEpisode: Bool

    public init(duration: Double, creditsStart: Double?, hasNextEpisode: Bool) {
        self.duration = duration
        self.creditsStart = creditsStart
        self.hasNextEpisode = hasNextEpisode
    }

    /// Position at which preparation starts; nil when there is nothing to prepare or the duration is unknown.
    public var triggerPosition: Double? {
        guard hasNextEpisode, duration.isFinite, duration > 0 else { return nil }
        if let c = creditsStart, c.isFinite, c >= 0, c < duration { return c }
        return max(0, duration - Self.fallbackLeadSeconds)
    }

    /// Call as playback position changes. Starts at most once per episode: seeking back does not restart it.
    public mutating func update(position: Double) -> Action {
        guard phase == .idle, let trigger = triggerPosition, position.isFinite, position >= trigger else { return .none }
        phase = .preparing
        return .startPreparing
    }

    public mutating func finishedPreparing() {
        if phase == .preparing { phase = .ready }
    }

    /// The user chose another episode or left: forget the preparation.
    public mutating func cancel() { phase = .idle }
}
