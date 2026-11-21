import Foundation
import VideoPlayerCore
import PlaybackLogic

// R315 and R316 (owner's request of 21 Nov 2026): the two new segment inputs the collector takes.
//   - Server markers: the intro and credits a media server (Plex) detected itself, read once per playback.
//   - On-device detection: what this Apple TV learned by comparing the audio of the episodes of one season, kept in a small
//     JSON file per season in the app's own storage. Nothing about it is sent anywhere.

public enum ServerMarkerSegments {
    /// The markers as segment candidates for `file` (confidence 1: the server measured this very file).
    public static func candidates(_ markers: [ServerSegmentMarker], file: FileIdentity) -> [SkipSegment] {
        markers.compactMap { marker in
            guard let type = SegmentType(rawValue: marker.kind), type == .intro || type == .credits else { return nil }
            return SkipSegment(type: type, start: marker.start, end: marker.end, source: .serverMarkers, confidence: 1, file: file)
        }
    }

    /// The collector's lookup for a source that keeps markers, nil for every other source.
    public static func lookup(source: (any MediaSource)?, path: String) -> (@Sendable (FileIdentity) async -> OnlineSegmentResult)? {
        guard let server = source as? any ServerSegmentSource else { return nil }
        return { file in
            do {
                let found = candidates(try await server.serverMarkers(at: path), file: file)
                return OnlineSegmentResult(segments: found, note: "Server markers: \(found.count)")
            } catch {
                return OnlineSegmentResult(segments: [], note: "Server markers: could not be read (\(error))")
            }
        }
    }
}

/// Which season a file belongs to, for the detection memory. Episodes are compared only within one season of one show.
public struct DetectionSeason: Hashable, Sendable {
    public var series: String
    public var season: Int

    public init(series: String, season: Int) {
        self.series = series
        self.season = season
    }

    /// The file name of this season's memory: a stable hash, so no title ends up in a file name.
    var fileName: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(series.lowercased())\u{1F}\(season)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "season-" + String(hash, radix: 16) + ".json"
    }
}

/// The per-season memories, one JSON file each in `directory` (the app passes a folder in Application Support). Reads and
/// writes stay on this Apple TV.
public actor SeasonDetectionStore {
    private let directory: URL
    private let limits: DetectionLimits
    private var cache: [DetectionSeason: SeasonSegmentMemory] = [:]

    public init(directory: URL, limits: DetectionLimits = DetectionLimits()) {
        self.directory = directory
        self.limits = limits
    }

    /// What the season's memory says about `file` (empty until a second episode of the season was analysed).
    public func segments(for file: FileIdentity, in season: DetectionSeason) -> [SkipSegment] {
        memory(season).segments(for: file, limits: limits)
    }

    /// Whether `file` still needs its audio analysed (it has no record, or the file changed).
    public func needsAnalysis(_ file: FileIdentity, in season: DetectionSeason) -> Bool {
        memory(season).record(for: file) == nil
    }

    /// Adds one analysed episode, compares it with the others and saves the season.
    public func add(_ record: EpisodeAudioRecord, in season: DetectionSeason) {
        var updated = memory(season)
        updated.add(record, limits: limits)
        cache[season] = updated
        save(updated, season)
    }

    /// Forgets everything learned (Settings could offer this; also used by the tests).
    public func removeAll() {
        cache.removeAll()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix("season-") && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func memory(_ season: DetectionSeason) -> SeasonSegmentMemory {
        if let cached = cache[season] { return cached }
        let url = directory.appendingPathComponent(season.fileName)
        let loaded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SeasonSegmentMemory.self, from: $0) }
            ?? SeasonSegmentMemory()
        cache[season] = loaded
        return loaded
    }

    private func save(_ memory: SeasonSegmentMemory, _ season: DetectionSeason) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(memory) else { return }
        try? data.write(to: directory.appendingPathComponent(season.fileName), options: .atomic)
    }
}

/// What the app's audio reader must hand in for one episode: the mono samples of the intro window and of the credits
/// window (`DetectionLimits.window`). Building the record is pure, so the tests run it on synthetic audio.
public enum EpisodeAnalysis {
    public static func record(file: FileIdentity, intro: (samples: [Float], rate: Double, start: TimeInterval)?,
                              credits: (samples: [Float], rate: Double, start: TimeInterval)?) -> EpisodeAudioRecord {
        EpisodeAudioRecord(
            file: file,
            intro: intro.map { AudioFingerprinter.fingerprint(samples: $0.samples, sampleRate: $0.rate, startOffset: $0.start) },
            credits: credits.map { AudioFingerprinter.fingerprint(samples: $0.samples, sampleRate: $0.rate, startOffset: $0.start) })
    }
}
