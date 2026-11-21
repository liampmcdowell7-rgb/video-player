import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData

/// The one-time watch-state seed from a Plex server (docs/PLEX_SOURCE.md section 6; OPEN_QUESTIONS R272, R306).
///
/// After a Plex source's first complete scan, what the server knew (an item played to the end, or stopped partway) is
/// copied into the app's own watch state, ONLY for items the app has no watch state for yet. It runs once per source (the
/// source's `seeded` option is set afterwards) and never writes anything to the server: the app's watch state is the only
/// record from then on (two-way sync is an R272 alternative, not built). The server field names `viewOffset` (ms),
/// `viewCount` and `lastViewedAt` (seconds since 1970) are UNVERIFIED (not in the text of the PMS reference returned).
public struct PlexWatchSeed: Sendable {
    /// What the server knew about one file.
    public struct ServerState: Equatable, Sendable {
        public var positionSeconds: Double?
        public var viewCount: Int?
        public var lastViewedAt: Date?
        public var durationSeconds: Double?
        public init(positionSeconds: Double?, viewCount: Int?, lastViewedAt: Date?, durationSeconds: Double?) {
            self.positionSeconds = positionSeconds; self.viewCount = viewCount
            self.lastViewedAt = lastViewedAt; self.durationSeconds = durationSeconds
        }
    }

    public struct Result: Equatable, Sendable {
        public var markedWatched = 0
        public var resumed = 0
        /// Items the app already had a watch state for: left exactly as they were.
        public var keptLocal = 0
        public init() {}
    }

    /// A position under this many seconds is not worth resuming.
    public static let minimumResume: Double = 30
    /// The source option set once the seed ran ("done"); the seed never runs again for that source.
    public static let optionKey = "seeded"

    public let store: any LibraryStore
    public let files: any LibraryScanStore

    /// `store` and `files` are the same library database in the app (two protocols of it).
    public init(store: any LibraryStore, files: any LibraryScanStore) {
        self.store = store
        self.files = files
    }

    /// True for a Plex source whose seed has not run yet.
    public static func isNeeded(for definition: UDSourceDefinition) -> Bool {
        definition.kind == SourceKind.plex.rawValue && SourceOptions.parse(definition.options)[optionKey] != "done"
    }

    /// The definition with the seed recorded as done (saved by the caller, so it syncs like any other source change).
    public static func markedDone(_ definition: UDSourceDefinition) -> UDSourceDefinition {
        var options = SourceOptions.parse(definition.options)
        options[optionKey] = "done"
        var d = definition
        d.options = SourceOptions.format(options)
        return d
    }

    /// Seeds from the server's state per file path of the source, after a scan stored those files.
    public func seed(sourceID: String, statesByPath: [String: ServerState], now: Date = Date()) async throws -> Result {
        var byItem: [Int64: ServerState] = [:]
        let folders = Dictionary(grouping: statesByPath.keys, by: Self.folder(of:))
        for (folder, paths) in folders.sorted(by: { $0.key < $1.key }) {
            let stored = try await files.storedFiles(sourceID: sourceID, folder: folder)
            let wanted = Set(paths)
            for file in stored where wanted.contains(file.path) {
                guard let itemID = file.itemID, let state = statesByPath[file.path] else { continue }
                // Two files of one item (two versions): the one watched last decides.
                if let existing = byItem[itemID], (existing.lastViewedAt ?? .distantPast) >= (state.lastViewedAt ?? .distantPast) { continue }
                byItem[itemID] = state
            }
        }
        return try await apply(byItem, now: now)
    }

    /// - Parameters:
    ///   - states: server state by the item id the file was indexed under.
    ///   - now: the time recorded for an item the server marked watched without a date.
    public func apply(_ states: [Int64: ServerState], now: Date = Date()) async throws -> Result {
        var result = Result()
        for (itemID, state) in states.sorted(by: { $0.key < $1.key }) {
            guard let item = try await store.item(id: itemID) else { continue }
            let position = state.positionSeconds ?? 0
            let played = (state.viewCount ?? 0) > 0
            guard played || position >= Self.minimumResume else { continue }
            guard Self.hasNoLocalState(item.watch) else { result.keptLocal += 1; continue }
            if played && position < Self.minimumResume {
                try await store.markWatched(itemIDs: [itemID], watched: true, at: state.lastViewedAt ?? now)
                result.markedWatched += 1
            } else {
                // Stopped partway (a rewatch in progress counts as partway: the resume point is what is useful).
                try await store.updateProgress(itemID: itemID, position: position, duration: state.durationSeconds,
                                               at: state.lastViewedAt ?? now)
                result.resumed += 1
            }
        }
        return result
    }

    /// True when the app has never recorded anything for the item (so nothing of the owner's is overwritten).
    public static func hasNoLocalState(_ watch: WatchState) -> Bool {
        !watch.watched && watch.position == 0 && watch.playCount == 0 && watch.lastPlayed == nil
    }

    static func folder(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }
}
