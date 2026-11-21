import Foundation

// R316: what the app learned about one season of one show by comparing the audio of its episodes. Kept on the Apple TV
// only (the app stores it as a file; it is never synced and never sent anywhere). Each episode that is analysed is
// compared with the episodes analysed before it; every comparison that finds a shared stretch is one vote for where that
// episode's intro (or credits) is. One vote shows the Skip button; two or more votes that agree within a second make the
// segment trusted enough to skip without a press (R314). So the app gets better as more episodes are played.

/// Where detection looks, and how long an intro or the credits may be. PROVISIONAL numbers, from the published defaults of
/// an open-source intro-skip plugin for media servers (docs/PLAYBACK_AUTOSKIP_NOWPLAYING.md section 8.2 (c)).
public struct DetectionLimits: Equatable, Sendable {
    /// The intro is looked for in the first `introWindow` seconds, or the first quarter of the episode when that is shorter.
    public var introWindow: TimeInterval = 600
    public var introShare: Double = 0.25
    public var introLength: ClosedRange<TimeInterval> = 15...120
    /// The credits are looked for in the last `creditsWindow` seconds, or the last 40 % when that is shorter.
    public var creditsWindow: TimeInterval = 600
    public var creditsShare: Double = 0.4
    public var creditsLength: ClosedRange<TimeInterval> = 15...300
    /// Votes agree when start and end are each within this many seconds of the agreed value.
    public var agreement: TimeInterval = 1.0
    /// At most this many earlier episodes are compared with a new one (the newest first).
    public var maxPartners = 4
    /// Fingerprints of at most this many episodes are kept per season (the votes of older ones stay).
    public var keptFingerprints = 8

    public init() {}

    /// The stretch of a file of `duration` seconds that is fingerprinted for `kind` (file seconds).
    public func window(for kind: SegmentType, duration: TimeInterval) -> ClosedRange<TimeInterval>? {
        guard duration > 0, duration.isFinite else { return nil }
        switch kind {
        case .intro: return 0...min(introWindow, duration * introShare)
        case .credits: return max(0, duration - min(creditsWindow, duration * creditsShare))...duration
        case .recap: return nil   // no method better than guessing (section 6c)
        }
    }

    public func lengths(for kind: SegmentType) -> ClosedRange<TimeInterval> {
        kind == .credits ? creditsLength : introLength
    }
}

/// One episode's analysis: its file, its two fingerprints, and the votes the comparisons gave it.
public struct EpisodeAudioRecord: Equatable, Sendable, Codable {
    /// Path and size of the file (`FileIdentity`), so a replaced file starts again.
    public var file: FileIdentity
    public var intro: AudioFingerprint?
    public var credits: AudioFingerprint?
    public var introVotes: [DetectionVote] = []
    public var creditsVotes: [DetectionVote] = []

    public init(file: FileIdentity, intro: AudioFingerprint?, credits: AudioFingerprint?) {
        self.file = file
        self.intro = intro
        self.credits = credits
    }

    func fingerprint(_ kind: SegmentType) -> AudioFingerprint? { kind == .credits ? credits : intro }
    func votes(_ kind: SegmentType) -> [DetectionVote] { kind == .credits ? creditsVotes : introVotes }
    mutating func addVote(_ vote: DetectionVote, kind: SegmentType) {
        if kind == .credits {
            creditsVotes.removeAll { $0.partner == vote.partner }
            creditsVotes.append(vote)
        } else {
            introVotes.removeAll { $0.partner == vote.partner }
            introVotes.append(vote)
        }
    }
}

/// One comparison's answer for one episode: the shared stretch, and which episode it was shared with.
public struct DetectionVote: Equatable, Sendable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval
    /// The partner's file path.
    public var partner: String
}

/// The season: its episodes' records, newest last.
public struct SeasonSegmentMemory: Equatable, Sendable, Codable {
    public var records: [EpisodeAudioRecord] = []

    public init() {}

    /// The record of `file`, when this exact file was analysed.
    public func record(for file: FileIdentity) -> EpisodeAudioRecord? {
        records.first { $0.file.isSameFile(as: file) }
    }

    /// Adds (or replaces) an episode's fingerprints and compares them with up to `limits.maxPartners` earlier episodes.
    /// Each shared stretch gives a vote to both episodes.
    public mutating func add(_ record: EpisodeAudioRecord, limits: DetectionLimits = DetectionLimits()) {
        records.removeAll { $0.file.path == record.file.path }
        var new = record
        let partners = Array(records.indices.reversed().prefix(limits.maxPartners))
        for kind in [SegmentType.intro, .credits] {
            guard let mine = new.fingerprint(kind) else { continue }
            for index in partners {
                guard let theirs = records[index].fingerprint(kind),
                      let shared = SharedAudioFinder.longest(mine, theirs, lengths: limits.lengths(for: kind)) else { continue }
                new.addVote(DetectionVote(start: shared.startA, end: shared.endA, partner: records[index].file.path), kind: kind)
                records[index].addVote(DetectionVote(start: shared.startB, end: shared.endB, partner: new.file.path), kind: kind)
            }
        }
        records.append(new)
        // Old fingerprints are dropped to keep the store small; their votes stay.
        let keep = max(1, limits.keptFingerprints)
        if records.count > keep {
            for index in 0..<(records.count - keep) {
                records[index].intro = nil
                records[index].credits = nil
            }
        }
    }

    /// The segments detection gives for `file`: per kind, the value most votes agree on, with a confidence from the number
    /// of agreeing votes. One vote: 0.75 (the button shows, no automatic skip); two: 0.9; each further one adds 0.02, at
    /// most 0.98. Nothing when the file was not analysed or no comparison found anything.
    public func segments(for file: FileIdentity, limits: DetectionLimits = DetectionLimits()) -> [SkipSegment] {
        guard let record = record(for: file) else { return [] }
        var out: [SkipSegment] = []
        for kind in [SegmentType.intro, .credits] {
            guard let agreed = Self.agreement(record.votes(kind), within: limits.agreement) else { continue }
            out.append(SkipSegment(type: kind, start: agreed.start, end: agreed.end, source: .onDeviceDetection,
                                   confidence: Self.confidence(votes: agreed.count), file: file))
        }
        return out
    }

    public static func confidence(votes: Int) -> Double {
        switch votes {
        case ..<1: return 0
        case 1: return 0.75
        default: return min(0.98, 0.9 + 0.02 * Double(votes - 2))
        }
    }

    /// The largest group of votes whose starts and ends lie within `within` of the group's median; its median start and end.
    static func agreement(_ votes: [DetectionVote], within: TimeInterval) -> (start: TimeInterval, end: TimeInterval, count: Int)? {
        var best: (start: TimeInterval, end: TimeInterval, count: Int)?
        for anchor in votes {
            let group = votes.filter { abs($0.start - anchor.start) <= within && abs($0.end - anchor.end) <= within }
            guard group.count > (best?.count ?? 0) else { continue }
            best = (median(group.map(\.start)), median(group.map(\.end)), group.count)
        }
        return best
    }

    static func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
