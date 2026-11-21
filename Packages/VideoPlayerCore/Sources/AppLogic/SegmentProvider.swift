import Foundation
import VideoPlayerCore
import LibraryIndex
import PlaybackLogic
import UserData

/// Segments for one library item: finds the file the player will open, asks the library for the facts `SegmentCollector` needs
/// (path, size, length, the item's stable key for the user marks) and returns the merged result. Never throws; an item or file the
/// library cannot find gives no segments.
///
/// The app's `SegmentService` (App/Support/SegmentService.swift) is a thin wrapper that supplies the two closures.
public struct SegmentProvider: Sendable {
    public typealias ItemKeyLookup = @Sendable (Int64) async -> String?
    public typealias SourceOpener = @Sendable (String) async -> (any MediaSource)?
    /// #26 5a: online timings for an item (IntroDB through `OnlineSegmentLookup`); nil when free data sources are off.
    public typealias OnlineTimings = @Sendable (LibraryItem, PlaybackLogic.FileIdentity) async -> OnlineSegmentResult

    private let store: any LibraryStore
    private let ledger: UserDataLedger?
    private let itemKey: ItemKeyLookup
    private let openSource: SourceOpener
    private let collector: SegmentCollector
    private let online: OnlineTimings?
    private let detection: SeasonDetectionStore?

    /// - Parameters:
    ///   - itemKey: the library item's stable key (the key of its watch record), nil when unknown.
    ///   - openSource: the source with this id (`StoredFile.sourceID`), nil when it cannot be opened.
    ///   - detection: R316: what this Apple TV learned from the audio of each season, nil to leave it out.
    public init(store: any LibraryStore, ledger: UserDataLedger?, itemKey: @escaping ItemKeyLookup, openSource: @escaping SourceOpener,
                collector: SegmentCollector = SegmentCollector(), online: OnlineTimings? = nil, detection: SeasonDetectionStore? = nil) {
        self.store = store
        self.ledger = ledger
        self.itemKey = itemKey
        self.openSource = openSource
        self.collector = collector
        self.online = online
        self.detection = detection
    }

    /// R316: the season an episode's audio is compared within, nil for a film or an episode without a season number.
    public static func detectionSeason(of item: LibraryItem) -> DetectionSeason? {
        guard item.kind == .episode, let series = item.seriesTitle, !series.isEmpty, let season = item.season else { return nil }
        return DetectionSeason(series: series, season: season)
    }

    /// The file `resolvePlayback` opens: the item's preferred version, else the first one.
    func playbackFile(of item: LibraryItem) async -> StoredFile? {
        guard let files = try? await store.versions(of: item.id) else { return nil }
        return files.first(where: { $0.id == item.preferredFileID }) ?? files.first
    }

    public func collection(forItem itemID: Int64) async -> SegmentCollection? {
        guard let item = try? await store.item(id: itemID), let file = await playbackFile(of: item) else { return nil }
        // PROVISIONAL: the length of the file the probe measured wins over the catalogue runtime, which can be a few minutes off.
        let duration = file.technical?.duration ?? item.runtime ?? item.watch.duration
        let info = SegmentFileInfo(path: file.path, size: file.size, duration: duration)
        let source = await openSource(file.sourceID)
        var marks: [UDSegmentMark] = []
        if let ledger, let key = await itemKey(itemID) { marks = ledger.segmentMarks(forItemKey: key) }
        let lookup: (@Sendable (PlaybackLogic.FileIdentity) async -> OnlineSegmentResult)? = online.map { online in { await online(item, $0) } }
        var detected: (@Sendable (PlaybackLogic.FileIdentity) async -> [SkipSegment])?
        if let detection, let season = Self.detectionSeason(of: item) {
            detected = { await detection.segments(for: $0, in: season) }
        }
        return await collector.collect(file: info, source: source, marks: marks, online: lookup,
                                       serverMarkers: ServerMarkerSegments.lookup(source: source, path: file.path), detected: detected)
    }

    /// R316: one episode whose audio the app should still analyse.
    public struct AnalysisTarget: Equatable, Sendable {
        public var file: PlaybackLogic.FileIdentity
        public var season: DetectionSeason
        public var sourceID: String
        /// The intro and credits windows to read, in file seconds.
        public var introWindow: ClosedRange<TimeInterval>?
        public var creditsWindow: ClosedRange<TimeInterval>?
    }

    /// The episode to analyse, nil when detection is off, the item is not an episode of a numbered season, its length is
    /// unknown, or it was analysed already.
    public func analysisTarget(forItem itemID: Int64, limits: DetectionLimits = DetectionLimits()) async -> AnalysisTarget? {
        guard let detection, let item = try? await store.item(id: itemID), let season = Self.detectionSeason(of: item),
              let file = await playbackFile(of: item) else { return nil }
        guard let duration = file.technical?.duration ?? item.runtime ?? item.watch.duration, duration > 0, duration.isFinite else { return nil }
        let identity = PlaybackLogic.FileIdentity(path: file.path, size: file.size ?? 0, duration: duration)
        guard await detection.needsAnalysis(identity, in: season) else { return nil }
        return AnalysisTarget(file: identity, season: season, sourceID: file.sourceID,
                              introWindow: limits.window(for: .intro, duration: duration),
                              creditsWindow: limits.window(for: .credits, duration: duration))
    }

    /// Stores what the app's audio reader measured for `target` and compares it with the season's other episodes.
    public func store(_ record: EpisodeAudioRecord, for target: AnalysisTarget) async {
        await detection?.add(record, in: target.season)
    }

    public func segments(forItem itemID: Int64) async -> [SkipSegment] {
        await collection(forItem: itemID)?.segments ?? []
    }
}
