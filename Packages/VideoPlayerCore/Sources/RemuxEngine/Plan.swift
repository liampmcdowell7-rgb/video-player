import Foundation

// Segment planning: where to cut, how long segments are, which bytes belong to which segment, and how a seek time
// maps to a segment. All pure and synchronous; the session feeds it keyframes from Cues or from a cluster scan.

public struct VideoKeyframe: Equatable, Sendable {
    public var timeNs: Int64
    /// Absolute file offset of the cluster that holds the keyframe.
    public var clusterOffset: Int64
    public init(timeNs: Int64, clusterOffset: Int64) { self.timeNs = timeNs; self.clusterOffset = clusterOffset }
}

public struct SegmentSpec: Equatable, Sendable {
    public var index: Int
    /// Presentation time of the keyframe that starts the segment.
    public var startNs: Int64
    /// Presentation time of the keyframe that starts the next segment (the media end for the last segment).
    public var endNs: Int64
    /// Absolute offset of the cluster that holds the starting keyframe: where reading starts.
    public var clusterStart: Int64
    public var durationNs: Int64 { endNs - startNs }
    public var durationSeconds: Double { Double(endNs - startNs) / 1_000_000_000 }
}

public enum SegmentPlanner {
    /// Cuts the keyframe list into segments of about `targetNs`.
    ///
    /// Rules (all tested): the first segment starts at the first keyframe; a segment ends at the keyframe whose distance
    /// from the start is closest to the target, never before `minNs` unless the file ends; a GOP longer than the target
    /// cannot be split (a segment must start with a keyframe), so such a segment is longer than the target; with
    /// `maxNs` set, a keyframe is taken as soon as it passes `maxNs` even if an earlier one was closer to the target.
    public static func plan(keyframes input: [VideoKeyframe], mediaEndNs: Int64, targetNs: Int64, minNs: Int64? = nil) -> [SegmentSpec] {
        var kfs = input.sorted { $0.timeNs < $1.timeNs }
        // One entry per keyframe time.
        var seen = Set<Int64>()
        kfs = kfs.filter { seen.insert($0.timeNs).inserted }
        guard let first = kfs.first else { return [] }
        let minLen = minNs ?? targetNs / 2
        var cuts: [VideoKeyframe] = [first]
        var start = first.timeNs
        var i = 1
        while i < kfs.count {
            let d = kfs[i].timeNs - start
            if d >= targetNs {
                // Is the previous keyframe closer to the target than this one?
                var cut = i
                if i - 1 >= 1, kfs[i - 1].timeNs > start {
                    let dPrev = kfs[i - 1].timeNs - start
                    if dPrev >= minLen, targetNs - dPrev < d - targetNs { cut = i - 1 }
                }
                cuts.append(kfs[cut]); start = kfs[cut].timeNs
                i = cut + 1
                continue
            }
            i += 1
        }
        var specs: [SegmentSpec] = []
        for (n, c) in cuts.enumerated() {
            let end = n + 1 < cuts.count ? cuts[n + 1].timeNs : max(mediaEndNs, c.timeNs)
            specs.append(SegmentSpec(index: n, startNs: c.timeNs, endNs: end, clusterStart: c.clusterOffset))
        }
        return specs
    }
}

/// Maps playback time to a segment and back.
public struct SeekMap: Sendable {
    public let segments: [SegmentSpec]
    public init(_ segments: [SegmentSpec]) { self.segments = segments }

    public var isEmpty: Bool { segments.isEmpty }
    public var durationNs: Int64 { (segments.last?.endNs ?? 0) - (segments.first?.startNs ?? 0) }

    /// The segment that holds `timeNs`. Times before the first segment map to 0, times at or after the end to the last.
    public func index(containing timeNs: Int64) -> Int {
        guard !segments.isEmpty else { return 0 }
        var lo = 0, hi = segments.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if segments[mid].startNs <= timeNs { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    public func index(containingSeconds s: Double) -> Int { index(containing: Int64(s * 1_000_000_000)) }

    /// The EXT-X-TARGETDURATION value: the longest segment, rounded up to whole seconds.
    public var targetDurationSeconds: Int {
        Int((Double(segments.map { $0.durationNs }.max() ?? 0) / 1_000_000_000).rounded(.up))
    }
}

/// Estimates a byte offset for a time when no index covers it yet, from known (time, offset) anchor points.
/// The session uses it to jump near the target and then `MatroskaClusterScanner.resync` to land on a cluster start.
public struct ByteTimeEstimator: Sendable {
    public var anchors: [(timeNs: Int64, offset: Int64)]
    public var fileStart: Int64
    public var fileEnd: Int64
    public var durationNs: Int64

    public init(anchors: [(timeNs: Int64, offset: Int64)], fileStart: Int64, fileEnd: Int64, durationNs: Int64) {
        self.anchors = anchors.sorted { $0.timeNs < $1.timeNs }
        self.fileStart = fileStart; self.fileEnd = fileEnd; self.durationNs = durationNs
    }

    public func offset(forTimeNs t: Int64) -> Int64 {
        let pts = [(0 as Int64, fileStart)] + anchors + [(durationNs, fileEnd)]
        // Find the surrounding pair and interpolate.
        var lower = pts[0], upper = pts[pts.count - 1]
        for p in pts where p.0 <= t { lower = p }
        for p in pts.reversed() where p.0 >= t { upper = p }
        if upper.0 == lower.0 { return lower.1 }
        let f = Double(t - lower.0) / Double(upper.0 - lower.0)
        return lower.1 + Int64(Double(upper.1 - lower.1) * min(1, max(0, f)))
    }
}

/// The memory budget of the engine and the numbers derived from it.
///
/// ASSUMPTION (to be checked on a device, docs/DEVICE_TEST_CHECKLIST.md): the engine may use 192 MiB of the app's
/// memory. A segment window (the bytes of one segment plus the cluster after it, all tracks) is read, parsed and kept as
/// shared slices, so one window costs about `overreadFactor` times the segment bytes; the cache holds `windows` of them.
public struct EngineBudget: Equatable, Sendable {
    public var memoryBytes: Int64 = 192 * 1024 * 1024
    /// Windows the cache must be able to hold at the target segment length: the one being served and one read ahead.
    public var minimumWindows: Int = 2
    /// Window size relative to the segment bytes (the extra cluster read to reach the next keyframe).
    public var overreadFactor: Double = 1.5
    public var minSegmentSeconds: Double = 2
    public var maxSegmentSeconds: Double = 6

    public init() {}
    public init(memoryBytes: Int64) { self.memoryBytes = memoryBytes }

    /// Segment length that keeps `minimumWindows` windows inside the budget at `bitrate` (bits per second).
    public func targetSegmentSeconds(bitrate: Double) -> Double {
        guard bitrate > 0 else { return maxSegmentSeconds }
        let bytesPerSecond = bitrate / 8
        let fit = Double(memoryBytes) / (Double(minimumWindows) * overreadFactor * bytesPerSecond)
        return min(maxSegmentSeconds, max(minSegmentSeconds, fit))
    }

    /// Bytes of one window for a segment of `seconds` at `bitrate`.
    public func windowBytes(seconds: Double, bitrate: Double) -> Int64 {
        Int64(overreadFactor * seconds * bitrate / 8)
    }

    /// How many windows fit (at least 1).
    public func windowsThatFit(windowBytes: Int64) -> Int {
        guard windowBytes > 0 else { return 4 }
        return max(1, Int(memoryBytes / windowBytes))
    }

    /// True when even the minimum segment length cannot hold `minimumWindows` windows (very high bitrates): the
    /// session then runs with one window and no read-ahead, and reports a warning.
    public func isOverBudget(bitrate: Double) -> Bool {
        windowBytes(seconds: minSegmentSeconds, bitrate: bitrate) * Int64(minimumWindows) > memoryBytes
    }
}
