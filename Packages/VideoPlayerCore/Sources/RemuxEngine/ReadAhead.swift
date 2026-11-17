import Foundation

// Read-ahead planning with back-pressure. The planner is a pure value type: it is told what happened (segment
// requested by the player, bytes fetched in some time, a window finished) and answers which segments to fetch next.
// The session runs it; tests drive it with a fake clock and synthetic numbers.

public protocol EngineClock: Sendable {
    var now: Double { get }          // seconds, monotonic
}

public struct SystemEngineClock: EngineClock {
    public init() {}
    public var now: Double { ProcessInfo.processInfo.systemUptime }
}

public final class ManualEngineClock: EngineClock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double
    public init(_ start: Double = 0) { t = start }
    public var now: Double { lock.lock(); defer { lock.unlock() }; return t }
    public func advance(_ s: Double) { lock.lock(); t += s; lock.unlock() }
}

public struct ReadAheadPlanner: Sendable {
    public struct Config: Sendable {
        public var budget: EngineBudget
        /// Media bitrate in bits per second (file size / duration).
        public var bitrate: Double
        public var segmentSeconds: Double
        public var segmentCount: Int
        /// Fetching must stay this many times faster than playback to be called safe.
        public var safetyFactor: Double = 1.5
        public var maxAhead: Int = 4
        /// Segments requested more than this long ago and not followed by another request mean the player is paused
        /// or stalled: stop reading ahead beyond one segment.
        public var idleSeconds: Double = 30
        public init(budget: EngineBudget, bitrate: Double, segmentSeconds: Double, segmentCount: Int) {
            self.budget = budget; self.bitrate = bitrate; self.segmentSeconds = segmentSeconds; self.segmentCount = segmentCount
        }
    }

    public enum Health: Equatable, Sendable {
        /// Fetch speed is comfortably above the media bitrate.
        case healthy
        /// Fetch speed is below `safetyFactor` x bitrate but above the bitrate: little margin.
        case tight
        /// Fetch speed is below the bitrate: playback will stall sooner or later.
        case starved
        case unknown
    }

    public var config: Config
    /// Segment index the player asked for last, and when.
    public private(set) var playhead: Int?
    public private(set) var lastRequestTime: Double = 0
    /// Exponential moving average of fetch throughput in bytes per second.
    public private(set) var throughput: Double?
    /// Segments that are cached or being fetched.
    public private(set) var held: Set<Int> = []
    public private(set) var inFlight: Set<Int> = []

    public init(config: Config) { self.config = config }

    public var segmentBytes: Int64 { Int64(config.bitrate / 8 * config.segmentSeconds) }
    public var windowBytes: Int64 { config.budget.windowBytes(seconds: config.segmentSeconds, bitrate: config.bitrate) }

    /// How many windows the budget allows.
    public var capacity: Int {
        let overBudget = config.budget.isOverBudget(bitrate: config.bitrate)
        return overBudget ? 1 : min(config.maxAhead + 1, config.budget.windowsThatFit(windowBytes: windowBytes))
    }

    public var health: Health {
        guard let t = throughput, config.bitrate > 0 else { return .unknown }
        let ratio = t * 8 / config.bitrate
        if ratio < 1 { return .starved }
        if ratio < config.safetyFactor { return .tight }
        return .healthy
    }

    /// Number of segments to keep ahead of the playhead: enough that one fetch finishes before the buffer runs dry,
    /// limited by the memory budget.
    public func desiredAhead(now: Double) -> Int {
        let byBudget = max(0, capacity - 1)
        guard let t = throughput, t > 0 else { return min(1, byBudget) }
        // Time to fetch one segment vs time to play it.
        let fetchSeconds = Double(segmentBytes) / t
        let needed = Int((fetchSeconds * config.safetyFactor / config.segmentSeconds).rounded(.up)) + 1
        var ahead = min(max(1, needed), config.maxAhead)
        if now - lastRequestTime > config.idleSeconds { ahead = min(ahead, 1) }
        return min(ahead, byBudget)
    }

    /// The player asked for a segment. Returns the segments to fetch now (not held, not in flight), nearest first, and
    /// the segments that should be cancelled or dropped because the playhead moved away from them.
    public mutating func requested(_ index: Int, now: Double) -> (fetch: [Int], cancel: [Int]) {
        var cancel: [Int] = []
        if let p = playhead, index < p || index > p + capacity + 1 {
            // A seek: everything in flight that is not near the new playhead is wasted work.
            cancel = inFlight.filter { $0 < index || $0 > index + capacity }.sorted()
            for c in cancel { inFlight.remove(c) }
        }
        playhead = index
        lastRequestTime = now
        held.insert(index)
        var fetch: [Int] = []
        let ahead = desiredAhead(now: now)
        if ahead > 0 {
            for k in 1...ahead {
                let idx = index + k
                if idx >= config.segmentCount { break }
                if !held.contains(idx) && !inFlight.contains(idx) { fetch.append(idx) }
            }
        }
        // Drop held windows behind the playhead beyond what the budget keeps (one behind for re-requests).
        // One window behind the playhead (for a re-request) only if the budget has room for it next to the read-ahead.
        let behind = (ahead + 2 <= capacity) ? 1 : 0
        let keep = Set((index - behind)...(index + max(ahead, 1)))
        let drop = held.filter { !keep.contains($0) }
        for d in drop { held.remove(d) }
        return (fetch, cancel + drop.filter { inFlight.contains($0) }.sorted())
    }

    public mutating func started(_ index: Int) { inFlight.insert(index) }

    /// A window finished loading: `bytes` in `seconds` of wall time.
    public mutating func finished(_ index: Int, bytes: Int64, seconds: Double) {
        inFlight.remove(index)
        held.insert(index)
        guard seconds > 0, bytes > 0 else { return }
        let sample = Double(bytes) / seconds
        throughput = throughput.map { $0 * 0.7 + sample * 0.3 } ?? sample
    }

    public mutating func failed(_ index: Int) { inFlight.remove(index); held.remove(index) }
}
