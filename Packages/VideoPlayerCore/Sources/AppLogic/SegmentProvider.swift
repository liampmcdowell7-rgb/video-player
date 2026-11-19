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

    /// - Parameters:
    ///   - itemKey: the library item's stable key (the key of its watch record), nil when unknown.
    ///   - openSource: the source with this id (`StoredFile.sourceID`), nil when it cannot be opened.
    public init(store: any LibraryStore, ledger: UserDataLedger?, itemKey: @escaping ItemKeyLookup, openSource: @escaping SourceOpener,
                collector: SegmentCollector = SegmentCollector(), online: OnlineTimings? = nil) {
        self.store = store
        self.ledger = ledger
        self.itemKey = itemKey
        self.openSource = openSource
        self.collector = collector
        self.online = online
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
        return await collector.collect(file: info, source: source, marks: marks, online: lookup)
    }

    public func segments(forItem itemID: Int64) async -> [SkipSegment] {
        await collection(forItem: itemID)?.segments ?? []
    }
}
