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
    public var onDeviceDetection: [SkipSegment]

    public init(userMarked: [SkipSegment] = [], localSidecar: [SkipSegment] = [], embeddedChapters: [SkipSegment] = [],
                postCreditsStart: TimeInterval? = nil, onlineDatabase: [SkipSegment] = [], onDeviceDetection: [SkipSegment] = []) {
        self.userMarked = userMarked
        self.localSidecar = localSidecar
        self.embeddedChapters = embeddedChapters
        self.postCreditsStart = postCreditsStart
        self.onlineDatabase = onlineDatabase
        self.onDeviceDetection = onDeviceDetection
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
        let candidates = tagged(inputs.userMarked, .userMarked)
            + tagged(inputs.embeddedChapters, .embeddedChapters)
            + tagged(inputs.localSidecar, .localSidecar)
            + tagged(inputs.onlineDatabase, .onlineDatabase)
            + tagged(inputs.onDeviceDetection, .onDeviceDetection)
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
