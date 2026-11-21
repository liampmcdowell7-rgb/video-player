import Foundation

// Merging the segment sources of one file into the segments the player uses (docs/SEGMENTS.md).
// Pure logic, no clock, no I/O.

/// The name the app layer uses for one skippable stretch of a file ("segment"). It is the model of Segments.swift.
public typealias Segment = SkipSegment

public extension ResolvedSegments {
    /// Wraps segments that were already validated and merged (what `SegmentService` hands to the player), so a session can
    /// be built from them without validating a second time. A second validation would be wrong for credits that end at a
    /// post-credits chapter: the resolver would stretch them to the end of the file when that chapter is near the end.
    init(merged segments: [SkipSegment], postCreditsStart: TimeInterval? = nil) {
        self.init(segments: segments.sorted { $0.start < $1.start }, postCreditsStart: postCreditsStart, rejected: [])
    }
}

/// Candidate segments of one file, grouped by where they came from. Each list may be empty.
public struct SegmentSourceInputs: Equatable, Sendable {
    public var userMarked: [SkipSegment]
    public var localSidecar: [SkipSegment]
    public var embeddedChapters: [SkipSegment]
    /// Start of a post-credits chapter, from the chapters.
    public var postCreditsStart: TimeInterval?
    /// Later items on the backlog (online timestamp lookups, on-device detection): the merger already accepts them so the
    /// feeds can be added without changing it. Nothing fills them yet.
    public var onlineDatabase: [SkipSegment]
    /// R316: what the app found by comparing the audio of episodes of one season (`SeasonSegmentMemory`).
    public var onDeviceDetection: [SkipSegment]
    /// R315: the intro and credits markers of a media server (Plex).
    public var serverMarkers: [SkipSegment]

    public init(userMarked: [SkipSegment] = [], localSidecar: [SkipSegment] = [], embeddedChapters: [SkipSegment] = [],
                postCreditsStart: TimeInterval? = nil, onlineDatabase: [SkipSegment] = [], onDeviceDetection: [SkipSegment] = [],
                serverMarkers: [SkipSegment] = []) {
        self.userMarked = userMarked
        self.localSidecar = localSidecar
        self.embeddedChapters = embeddedChapters
        self.postCreditsStart = postCreditsStart
        self.onlineDatabase = onlineDatabase
        self.onDeviceDetection = onDeviceDetection
        self.serverMarkers = serverMarkers
    }
}

public enum SegmentMerger {
    /// PROVISIONAL: two segments of different types overlap when they share more than this many seconds. Segments that only
    /// touch (a recap that ends where the intro begins) or that differ by rounding do not.
    public static let defaultOverlapTolerance: TimeInterval = 1.0

    /// Precedence (B3, docs/PLAYBACK_LOGIC.md SEG-5): user-marked, then embedded chapters, then local sidecar, then online
    /// database, then on-device detection.
    ///
    /// 1. Every candidate is stamped with the source of the list it came from (a parser cannot claim to be a user mark).
    /// 2. `SegmentResolver` validates all of them (limits, confidence, file identity, duration match, clamps) and keeps the best
    ///    one per type (de-duplication: user mark over chapter over sidecar; same source: higher confidence, then earlier).
    /// 3. Overlap resolution across types, PROVISIONAL: the survivors are taken best first (source priority, confidence, earlier
    ///    start); a segment that overlaps an already kept one of another type by more than `overlapTolerance` is dropped, with the
    ///    reason `overlapsHigherRanked`. Alternative (not built): trim the lower one to the free part, which then needs the
    ///    length limits applied again.
    public static func merge(file: FileIdentity, inputs: SegmentSourceInputs, limits: SegmentLimits = SegmentLimits(),
                             overlapTolerance: TimeInterval = defaultOverlapTolerance) -> ResolvedSegments {
        func tagged(_ list: [SkipSegment], _ source: SegmentSource) -> [SkipSegment] {
            list.map { var s = $0; s.source = source; return s }
        }
        let detected = tagged(inputs.onDeviceDetection, .onDeviceDetection)
        // R314 (R288's audio check): an online timing that on-device detection found too, at both ends, is confirmed.
        let online = tagged(inputs.onlineDatabase, .onlineDatabase).map { timing -> SkipSegment in
            var checked = timing
            let agrees = detected.contains {
                $0.type == timing.type && abs($0.start - timing.start) <= limits.audioAgreement
                    && abs($0.end - timing.end) <= limits.audioAgreement
            }
            if agrees { checked.audioConfirmed = true }
            return checked
        }
        let candidates = tagged(inputs.userMarked, .userMarked)
            + tagged(inputs.embeddedChapters, .embeddedChapters)
            + tagged(inputs.localSidecar, .localSidecar)
            + tagged(inputs.serverMarkers, .serverMarkers)
            + online
            + detected
        let resolved = SegmentResolver.resolve(file: file, candidates: candidates, postCreditsStart: inputs.postCreditsStart, limits: limits)

        var kept: [SkipSegment] = []
        var rejected = resolved.rejected
        for segment in resolved.segments.sorted(by: SegmentResolver.ranksBefore) {
            if let winner = kept.first(where: { $0.type != segment.type && overlap($0, segment) > overlapTolerance }) {
                rejected.append(RejectedSegment(segment: segment, reason: .overlapsHigherRanked(winner.type)))
            } else {
                kept.append(segment)
            }
        }
        kept.sort { $0.start < $1.start }
        return ResolvedSegments(segments: kept, postCreditsStart: resolved.postCreditsStart, rejected: rejected)
    }

    static func overlap(_ a: SkipSegment, _ b: SkipSegment) -> TimeInterval {
        max(0, min(a.end, b.end) - max(a.start, b.start))
    }
}
