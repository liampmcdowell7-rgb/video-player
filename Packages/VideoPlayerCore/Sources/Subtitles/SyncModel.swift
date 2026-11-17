import Foundation

/// Which player is producing the sound.
public enum PlaybackPath: String, Sendable, Codable, CaseIterable {
    /// AVPlayer / AVPlayerItem. The system schedules audio against the output device and applies the tvOS
    /// Wireless Audio Sync calibration itself.
    case avPlayer
    /// The app's own decoder and audio output.
    case fallbackEngine
}

/// Who applies the delay between "audio handed to the output" and "sound leaves the speakers".
public enum LatencyOwner: String, Sendable {
    case system
    case app
}

public struct SyncSettings: Equatable, Sendable {
    /// For the fallback engine: true when its audio goes through a renderer that the OS already keeps in step
    /// with the output device (for example AVSampleBufferRenderSynchronizer). Then the app must not add the
    /// output latency a second time. Default false: assume the app clocks the audio itself.
    /// UNVERIFIED on a device: which renderer the fallback engine uses decides this.
    public var fallbackOutputIsSystemSynchronised: Bool

    public init(fallbackOutputIsSystemSynchronised: Bool = false) {
        self.fallbackOutputIsSystemSynchronised = fallbackOutputIsSystemSynchronised
    }
}

/// The numbers the playback path must use.
///
/// Sign convention: positive means the audio is shifted later relative to the video.
public struct SyncPlan: Equatable, Sendable {
    public var path: PlaybackPath
    /// The user's per-file delay, clamped.
    public var userDelay: TimeInterval
    /// Who deals with the output latency on this path.
    public var outputLatencyOwner: LatencyOwner
    /// The output latency that exists (what the system reports), 0 when unknown. Information only.
    public var reportedOutputLatency: TimeInterval
    /// What the app itself adds to line the audio up with the output latency. 0 when the system owns it.
    /// Negative: the app sends audio earlier so it comes out on time.
    public var appCompensation: TimeInterval
    /// `userDelay + appCompensation`: the shift the player applies to the audio relative to the video clock.
    public var effectiveAudioDelay: TimeInterval

    /// The same shift expressed on the video side.
    public var equivalentVideoDelay: TimeInterval { -effectiveAudioDelay }
}

public enum SyncModel {

    /// The most the per-file delay can be set to, either way (Interpretation, PROVISIONAL).
    public static let maxUserDelay: TimeInterval = 5

    /// Largest output latency the model believes (AirPlay devices can report about 2 seconds).
    public static let maxPlausibleLatency: TimeInterval = 3

    /// Rounds to whole milliseconds, clamps to `maxUserDelay`, and maps NaN and infinity to 0.
    public static func clampedDelay(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return 0 }
        let rounded = (seconds * 1000).rounded() / 1000
        return max(-maxUserDelay, min(maxUserDelay, rounded))
    }

    public static func owner(for path: PlaybackPath, settings: SyncSettings = SyncSettings()) -> LatencyOwner {
        switch path {
        case .avPlayer: return .system
        case .fallbackEngine: return settings.fallbackOutputIsSystemSynchronised ? .system : .app
        }
    }

    /// - Parameters:
    ///   - userDelay: the per-file delay the user set (positive = audio later).
    ///   - systemOutputLatency: the output latency the system reports (`AVAudioSession.outputLatency` on tvOS), if known.
    public static func plan(
        path: PlaybackPath,
        userDelay: TimeInterval,
        systemOutputLatency: TimeInterval?,
        settings: SyncSettings = SyncSettings()
    ) -> SyncPlan {
        let delay = clampedDelay(userDelay)
        var latency = systemOutputLatency ?? 0
        if !latency.isFinite || latency < 0 { latency = 0 }
        latency = min(latency, maxPlausibleLatency)
        let who = owner(for: path, settings: settings)
        let compensation = who == .app ? -latency : 0
        return SyncPlan(
            path: path, userDelay: delay, outputLatencyOwner: who, reportedOutputLatency: latency,
            appCompensation: compensation, effectiveAudioDelay: delay + compensation
        )
    }
}

// MARK: Drift

/// Both clocks read at the same instant. `elapsed` is any monotonic time (seconds since playback started).
public struct ClockSample: Equatable, Sendable {
    public var elapsed: TimeInterval
    /// Media position according to the audio clock.
    public var audioClock: TimeInterval
    /// Media position according to the video clock.
    public var videoClock: TimeInterval

    public init(elapsed: TimeInterval, audioClock: TimeInterval, videoClock: TimeInterval) {
        self.elapsed = elapsed
        self.audioClock = audioClock
        self.videoClock = videoClock
    }

    var offset: TimeInterval { audioClock - videoClock }
}

public struct DriftReport: Equatable, Sendable {
    public var sampleCount: Int
    /// Time between the first and last sample.
    public var span: TimeInterval
    /// Slope of (audio clock - video clock) over elapsed time, in milliseconds per hour. Positive: the audio
    /// clock gains on the video clock (audio runs ahead).
    public var driftMillisecondsPerHour: Double
    /// Change of the offset from the first third of the samples to the last third, in milliseconds.
    public var offsetChangeMilliseconds: Double
    /// True when at least 3 samples span at least `minimumSpan`; below that the per-hour figure is only a rough guess.
    public var isReliable: Bool
    public var needsCorrection: Bool
    /// Seconds to add to the audio delay to cancel the change (audio ahead gives a positive value: delay it).
    public var suggestedAudioDelayChange: TimeInterval
}

public enum DriftCheck {

    /// Returns nil with fewer than 2 samples or samples that are not finite.
    /// - Parameters:
    ///   - thresholdMilliseconds: the offset change from which a correction is wanted. Default 45 ms, the
    ///     lower edge of what viewers notice when sound leads picture (ITU-R BT.1359 detectability figures
    ///     are about +45 ms audio early and -125 ms audio late; the smaller number is used).
    ///   - minimumSpan: seconds of data before the per-hour figure counts as reliable.
    public static func evaluate(_ samples: [ClockSample], thresholdMilliseconds: Double = 45, minimumSpan: TimeInterval = 30) -> DriftReport? {
        let usable = samples.filter { $0.elapsed.isFinite && $0.audioClock.isFinite && $0.videoClock.isFinite }.sorted { $0.elapsed < $1.elapsed }
        guard usable.count >= 2, let first = usable.first, let last = usable.last else { return nil }
        let n = Double(usable.count)
        let meanX = usable.reduce(0) { $0 + $1.elapsed } / n
        let meanY = usable.reduce(0) { $0 + $1.offset } / n
        var sxx = 0.0, sxy = 0.0
        for s in usable {
            let dx = s.elapsed - meanX
            sxx += dx * dx
            sxy += dx * (s.offset - meanY)
        }
        let slope = sxx > 1e-12 ? sxy / sxx : 0   // seconds of offset per second of time
        let third = max(1, usable.count / 3)
        let head = usable.prefix(third).reduce(0) { $0 + $1.offset } / Double(third)
        let tail = usable.suffix(third).reduce(0) { $0 + $1.offset } / Double(third)
        let change = tail - head
        let span = last.elapsed - first.elapsed
        return DriftReport(
            sampleCount: usable.count,
            span: span,
            driftMillisecondsPerHour: slope * 3600 * 1000,
            offsetChangeMilliseconds: change * 1000,
            isReliable: usable.count >= 3 && span >= minimumSpan,
            needsCorrection: abs(change * 1000) >= thresholdMilliseconds,
            suggestedAudioDelayChange: change
        )
    }
}

// MARK: Per-file delay storage

/// Identifies a file for the purpose of remembering its audio delay: where it lives plus its size, so a different
/// file saved under the same name does not inherit the delay.
public struct SyncFileKey: Hashable, Codable, Sendable {
    public var sourceID: String
    public var path: String
    public var size: Int64?

    public init(sourceID: String, path: String, size: Int64?) {
        self.sourceID = sourceID
        self.path = path
        self.size = size
    }

    var storageKey: String { "\(sourceID)\u{1F}\(path)\u{1F}\(size.map(String.init) ?? "-")" }
}

/// Remembered audio delays (seconds, positive = audio later). A value type: the app keeps one, mutates it and saves it.
public struct SyncDelayTable: Codable, Equatable, Sendable {
    private var entries: [String: Double] = [:]

    public init() {}

    public func delay(for key: SyncFileKey) -> TimeInterval { entries[key.storageKey] ?? 0 }

    /// Stores a clamped delay. Zero removes the entry.
    public mutating func setDelay(_ seconds: TimeInterval, for key: SyncFileKey) {
        let d = SyncModel.clampedDelay(seconds)
        if d == 0 { entries.removeValue(forKey: key.storageKey) } else { entries[key.storageKey] = d }
    }

    public var count: Int { entries.count }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(SyncDelayTable.self, from: data)
    }

    /// Reads a saved table; a missing or unreadable file gives an empty table.
    public static func load(from url: URL) -> SyncDelayTable {
        guard let data = try? Data(contentsOf: url), let table = try? SyncDelayTable(decoding: data) else { return SyncDelayTable() }
        return table
    }

    public func save(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }
}
