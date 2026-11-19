import Foundation

// Segment model, safety limits and the source-priority resolver (Part B of the spec).
// Pure logic: no Apple frameworks, no clock. Everything here is tested in WSL; what only an
// Apple TV can check is listed in docs/PLAYBACK_LOGIC.md.

public enum SegmentType: String, Sendable, CaseIterable, Codable {
    case recap, intro, credits

    /// Button wording (OPEN_QUESTIONS B7).
    public var buttonTitle: String {
        switch self {
        case .recap: return "Skip Recap"
        case .intro: return "Skip Intro"
        case .credits: return "Skip Credits"
        }
    }
}

/// Where a segment came from. A higher `priority` wins when sources disagree (B3):
/// user-marked > embedded chapters > local sidecar > online database > on-device detection.
public enum SegmentSource: String, Sendable, CaseIterable, Codable {
    case onDeviceDetection, onlineDatabase, localSidecar, embeddedChapters, userMarked

    public var priority: Int {
        switch self {
        case .onDeviceDetection: return 0
        case .onlineDatabase: return 1
        case .localSidecar: return 2
        case .embeddedChapters: return 3
        case .userMarked: return 4
        }
    }
}

/// What a segment is keyed to: the file's path, size and duration, not only the episode.
public struct FileIdentity: Equatable, Hashable, Sendable, Codable {
    public var path: String
    public var size: Int64
    public var duration: TimeInterval

    public init(path: String, size: Int64, duration: TimeInterval) {
        self.path = path
        self.size = size
        self.duration = duration
    }

    /// Same file: path and size equal, duration equal within `tolerance` (players and probes report
    /// slightly different durations for the same file). PROVISIONAL: default tolerance 0.5 s.
    public func isSameFile(as other: FileIdentity, tolerance: TimeInterval = 0.5) -> Bool {
        path == other.path && size == other.size && abs(duration - other.duration) <= tolerance
    }
}

public struct SkipSegment: Equatable, Hashable, Sendable, Codable {
    public var type: SegmentType
    public var start: TimeInterval
    public var end: TimeInterval
    public var source: SegmentSource
    /// 0...1. Below `SegmentLimits.confidenceThreshold` nothing is shown (B2).
    public var confidence: Double
    /// The file this segment was made for.
    public var file: FileIdentity
    /// Duration of the release the timestamps were made for (online databases, sidecars). When it is
    /// present, or the source is an online database, it must match the file's duration (B1).
    public var referenceDuration: TimeInterval?

    public init(type: SegmentType, start: TimeInterval, end: TimeInterval, source: SegmentSource,
                confidence: Double, file: FileIdentity, referenceDuration: TimeInterval? = nil) {
        self.type = type
        self.start = start
        self.end = end
        self.source = source
        self.confidence = confidence
        self.file = file
        self.referenceDuration = referenceDuration
    }

    public var length: TimeInterval { end - start }
    public func contains(_ time: TimeInterval) -> Bool { time >= start && time < end }
}

/// The numbers from the spec. All values are parameters so tests (and later Settings) can see them.
public struct SegmentLimits: Equatable, Sendable {
    /// B2.
    public var confidenceThreshold = 0.7
    /// B1: greater of 2 seconds or 0.5 percent of the file's duration.
    public var durationToleranceSeconds = 2.0
    public var durationToleranceFraction = 0.005
    /// B4: an intro is 10 to 180 seconds long.
    public var introLength: ClosedRange<TimeInterval> = 10...180
    /// B4: a recap starts within the first 60 seconds.
    public var recapMaxStart = 60.0
    /// PROVISIONAL INTERPRETATION: the spec gives no recap length limit; 180 s (same as intro).
    public var recapMaxLength = 180.0
    /// B4: credits start in the last 40 percent, so at or after 60 percent of the runtime.
    public var creditsMinStartFraction = 0.6
    /// PROVISIONAL INTERPRETATION: credits "run to the end". A credits segment that ends within this many
    /// seconds of the end of the file is extended to the end. More than this remaining means real content
    /// follows (see docs/PLAYBACK_LOGIC.md). The same 60 s is the "more than 60 seconds remaining" rule.
    public var creditsTrailingTolerance = 60.0
    /// PROVISIONAL (#26, OPEN_QUESTIONS R208): an online database that gives no reference duration (IntroDB) may still
    /// place an intro or a recap, because those sit near the start of the file and do not depend on the release length.
    /// Credits from such a source are still rejected (they depend on the runtime). False restores the strict B1 rule.
    public var acceptsUnreferencedOnlineIntroAndRecap = true

    public init() {}

    public func durationTolerance(for duration: TimeInterval) -> TimeInterval {
        max(durationToleranceSeconds, durationToleranceFraction * duration)
    }
}

public enum SegmentRejection: Error, Equatable, Sendable {
    case differentFile
    case unknownFileDuration
    case durationMismatch
    /// An online intro or recap without a reference duration ends after the end of this file (#27 item 2).
    case endsAfterFile
    case lowConfidence
    case emptyOrInverted
    case introLength
    case recapStartsTooLate
    case recapTooLong
    case creditsStartTooEarly
    case outranked(by: SegmentSource)
    /// Dropped by `SegmentMerger`: it overlaps, by more than the tolerance, a segment of another type that ranks higher.
    case overlapsHigherRanked(SegmentType)
}

public struct RejectedSegment: Equatable, Sendable {
    public var segment: SkipSegment
    public var reason: SegmentRejection
}

public struct ResolvedSegments: Equatable, Sendable {
    /// At most one per type, already clamped and normalised.
    public var segments: [SkipSegment]
    /// Start of a post-credits chapter, if the file has one.
    public var postCreditsStart: TimeInterval?
    /// Everything that was dropped and why (File Details can show it).
    public var rejected: [RejectedSegment]

    public func segment(of type: SegmentType) -> SkipSegment? { segments.first { $0.type == type } }
}

public enum SegmentResolver {
    /// Validates every candidate for `file`, then picks one per type by source priority.
    ///
    /// Clamps (the segment is kept): start below 0 becomes 0; end beyond the file becomes the file's end;
    /// a credits segment's end is moved to the post-credits chapter or, when it is within
    /// `creditsTrailingTolerance` of the end, to the end of the file.
    /// Rejections (the segment is dropped): everything else that breaks a limit. Limits apply to every
    /// source including user-marked ones (PROVISIONAL INTERPRETATION: "never skip real content").
    /// A candidate that fails validation never blocks a lower-priority valid one.
    public static func resolve(
        file: FileIdentity,
        candidates: [SkipSegment],
        postCreditsStart: TimeInterval? = nil,
        limits: SegmentLimits = SegmentLimits()
    ) -> ResolvedSegments {
        var rejected: [RejectedSegment] = []
        var valid: [SkipSegment] = []

        for original in candidates {
            switch validate(original, file: file, postCreditsStart: postCreditsStart, limits: limits) {
            case .success(let segment): valid.append(segment)
            case .failure(let reason): rejected.append(RejectedSegment(segment: original, reason: reason))
            }
        }

        var chosen: [SkipSegment] = []
        for type in SegmentType.allCases {
            let ofType = valid.filter { $0.type == type }.sorted(by: ranksBefore)
            guard let winner = ofType.first else { continue }
            chosen.append(winner)
            for loser in ofType.dropFirst() {
                rejected.append(RejectedSegment(segment: loser, reason: .outranked(by: winner.source)))
            }
        }
        chosen.sort { $0.start < $1.start }

        let post: TimeInterval? = (postCreditsStart.map { $0 > 0 && $0 < file.duration }) == true ? postCreditsStart : nil
        return ResolvedSegments(segments: chosen, postCreditsStart: post, rejected: rejected)
    }

    /// Higher source priority first, then higher confidence, then earlier start.
    static func ranksBefore(_ a: SkipSegment, _ b: SkipSegment) -> Bool {
        if a.source.priority != b.source.priority { return a.source.priority > b.source.priority }
        if a.confidence != b.confidence { return a.confidence > b.confidence }
        return a.start < b.start
    }

    static func validate(_ original: SkipSegment, file: FileIdentity, postCreditsStart: TimeInterval?,
                         limits: SegmentLimits) -> Result<SkipSegment, SegmentRejection> {
        guard original.file.isSameFile(as: file) else { return .failure(.differentFile) }
        let duration = file.duration
        guard duration > 0, duration.isFinite else { return .failure(.unknownFileDuration) }

        // B1: database timings only fit a release with the same duration.
        let unreferencedStart = original.source == .onlineDatabase && original.referenceDuration == nil
            && limits.acceptsUnreferencedOnlineIntroAndRecap && original.type != .credits
        let mustMatch = !unreferencedStart && (original.source == .onlineDatabase || original.referenceDuration != nil)
        if mustMatch {
            guard let reference = original.referenceDuration,
                  abs(reference - duration) <= limits.durationTolerance(for: duration) else {
                return .failure(.durationMismatch)
            }
        }

        // B2.
        guard original.confidence.isFinite, original.confidence >= limits.confidenceThreshold else {
            return .failure(.lowConfidence)
        }

        // #27 item 2: an online timing with no reference duration that ends after this file's end was made for another
        // (longer) cut. It is dropped, not trimmed: trimming would keep a window that no longer means anything here.
        if unreferencedStart, original.end > duration { return .failure(.endsAfterFile) }

        var segment = original
        segment.start = max(0, segment.start)
        segment.end = min(duration, segment.end)
        guard segment.start.isFinite, segment.end.isFinite, segment.end > segment.start else {
            return .failure(.emptyOrInverted)
        }

        switch segment.type {
        case .intro:
            guard limits.introLength.contains(segment.length) else { return .failure(.introLength) }
        case .recap:
            guard segment.start <= limits.recapMaxStart else { return .failure(.recapStartsTooLate) }
            guard segment.length <= limits.recapMaxLength else { return .failure(.recapTooLong) }
        case .credits:
            guard segment.start >= limits.creditsMinStartFraction * duration else {
                return .failure(.creditsStartTooEarly)
            }
            if let post = postCreditsStart, post > segment.start, post < duration {
                segment.end = post                       // credits run to the post-credits chapter
            } else if duration - segment.end <= limits.creditsTrailingTolerance {
                segment.end = duration                   // credits run to the end
            }
        }
        return .success(segment)
    }
}
