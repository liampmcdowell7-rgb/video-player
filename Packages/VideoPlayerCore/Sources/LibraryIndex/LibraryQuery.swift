import Foundation
import VideoPlayerCore

// MARK: Filters, sorts, saved views

public enum WatchFilter: String, Codable, Sendable { case unwatched, watched, inProgress }

public struct FolderScope: Codable, Equatable, Hashable, Sendable {
    public var sourceID: String
    /// "/" is the whole source. Items with a file in this folder (or below when `recursive`) match.
    public var path: String
    public var recursive: Bool
    public init(sourceID: String, path: String, recursive: Bool = true) {
        self.sourceID = sourceID
        self.path = path
        self.recursive = recursive
    }
}

/// Any number of these combine with AND. Inside one list (genres, resolutions...) the values combine with OR.
public struct ItemFilter: Codable, Equatable, Sendable {
    public var kinds: Set<ItemKind> = []
    public var genres: Set<String> = []
    public var yearMin: Int?
    public var yearMax: Int?
    public var minRating: Double?
    public var watch: WatchFilter?
    public var resolutions: Set<ResolutionClass> = []
    public var hdrFormats: Set<HDRFormat> = []
    /// Any Dolby Vision (true), or none (false).
    public var dolbyVision: Bool?
    public var dolbyVisionProfiles: Set<Int> = []
    public var dolbyAtmos: Bool?
    /// At least this many channels in the best audio track (2, 6 or 8).
    public var minChannels: Int?
    public var containers: Set<ContainerFormat> = []
    public var addedAfter: Date?
    public var favoritesOnly = false
    public var seriesID: Int64?
    public var season: Int?
    public var folder: FolderScope?
    public var sourceID: String?
    /// Every word must appear in the title or series title (case and accents ignored).
    public var text: String?

    public init() {}

    public var isEmpty: Bool { self == ItemFilter() }
}

public enum ItemSortKey: String, Codable, Sendable, CaseIterable {
    case title, year, rating, added, lastPlayed, runtime
}

public struct ItemSort: Codable, Equatable, Sendable {
    public var key: ItemSortKey
    public var ascending: Bool
    public init(key: ItemSortKey = .title, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }
}

public struct ItemQuery: Codable, Equatable, Sendable {
    public var filter: ItemFilter
    public var sort: ItemSort
    public init(filter: ItemFilter = ItemFilter(), sort: ItemSort = ItemSort()) {
        self.filter = filter
        self.sort = sort
    }
}

/// Keyset position: the sort value and id of the last row of the previous page.
public struct ItemCursor: Codable, Equatable, Sendable {
    var text: String?
    var number: Double?
    var id: Int64
}

public struct ItemPage: Sendable {
    public var items: [LibraryItem]
    /// nil when this was the last page.
    public var next: ItemCursor?
}

public struct AlphabetEntry: Equatable, Sendable {
    /// "#" for titles that do not start with a letter A to Z.
    public var letter: String
    /// Row number (0 based) of the first item with this letter in the current sort.
    public var offset: Int
    public var count: Int
}

public enum ViewScope: Codable, Equatable, Hashable, Sendable {
    case library
    case folder(sourceID: String, path: String)
    /// #21 F: the Shows grid's saved views (sort and watch filter over series), kept apart from the Movies views.
    case shows

    /// How the views table stores a scope (scope_kind, scope_source, scope_path).
    var stored: (kind: Int, source: String, path: String) {
        switch self {
        case .library: return (0, "", "")
        case let .folder(s, p): return (1, s, p)
        case .shows: return (2, "", "")
        }
    }

    init(storedKind kind: Int, source: String, path: String) {
        switch kind {
        case 0: self = .library
        case 2: self = .shows
        default: self = .folder(sourceID: source, path: path)
        }
    }
}

public struct SavedView: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var scope: ViewScope
    public var query: ItemQuery
    public var pinned: Bool
    public var position: Int
    public var createdAt: Date
}

// MARK: Rows for the home screen

public struct NextUpEntry: Equatable, Sendable {
    public var item: LibraryItem
    /// The episode that was watched last in this series.
    public var afterEpisodeID: Int64
}

public struct FolderChild: Equatable, Sendable {
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modified: Date?
    public var kind: FileKind
}

// MARK: The store

/// Everything the app reads and writes. Implemented over SQLite here; a SwiftData store could implement
/// the same protocol later (docs/LIBRARY_INDEX.md).
public protocol LibraryStore: Sendable {
    // Sources
    func upsertSource(_ source: LibrarySourceRecord) async throws
    func sources() async throws -> [LibrarySourceRecord]
    /// Removes the source and everything indexed from it (items left without files are removed too).
    func removeSource(id: String) async throws
    func counts() async throws -> LibraryCounts

    // Queries
    func page(_ query: ItemQuery, limit: Int, after: ItemCursor?) async throws -> ItemPage
    func page(_ query: ItemQuery, limit: Int, offset: Int) async throws -> [LibraryItem]
    func count(_ query: ItemQuery) async throws -> Int
    /// Letter jump positions for a title-sorted query. Empty for other sort keys.
    func alphabetIndex(_ query: ItemQuery) async throws -> [AlphabetEntry]
    func item(id: Int64) async throws -> LibraryItem?
    func versions(of itemID: Int64) async throws -> [StoredFile]
    func setPreferredVersion(itemID: Int64, fileID: Int64?) async throws
    func continueWatching(limit: Int, now: Date, retentionDays: Int) async throws -> [LibraryItem]
    func nextUp(limit: Int, now: Date, retentionDays: Int) async throws -> [NextUpEntry]
    func recentlyAdded(limit: Int, kind: ItemKind?) async throws -> [LibraryItem]
    func episodes(ofSeries seriesID: Int64) async throws -> [LibraryItem]
    func children(sourceID: String, folder: String, sort: FileSort, limit: Int, offset: Int) async throws -> [FolderChild]
    func sidecars(for fileID: Int64) async throws -> [StoredFile]

    // Metadata and technical facts
    func setMetadata(itemID: Int64, _ metadata: ItemMetadata) async throws
    func setTechnicalInfo(fileID: Int64, _ info: FileTechnicalInfo) async throws
    /// #21 C: the frame rate and tracks read from the file's header (nil when not read yet, or the file changed size).
    func trackDetails(fileID: Int64) async throws -> FileTrackDetails?
    func setTrackDetails(fileID: Int64, _ details: FileTrackDetails) async throws

    // Watch state
    func updateProgress(itemID: Int64, position: Double, duration: Double?, at date: Date) async throws
    func markWatched(itemIDs: [Int64], watched: Bool, at date: Date) async throws
    func markSeries(seriesID: Int64, season: Int?, watched: Bool, at date: Date) async throws
    func setFavorite(itemID: Int64, favorite: Bool) async throws
    func hideFromContinue(itemID: Int64, hidden: Bool) async throws

    // Saved views
    func saveView(name: String, scope: ViewScope, query: ItemQuery, pinned: Bool) async throws -> SavedView
    func updateView(_ view: SavedView) async throws
    func deleteView(id: Int64) async throws
    func views(scope: ViewScope) async throws -> [SavedView]
    func pinnedViews() async throws -> [SavedView]

    // Sorting (docs/SORTING.md)
    /// Files in Needs Review, newest first.
    func needsReview(limit: Int) async throws -> [ReviewEntry]
    func needsReviewCount() async throws -> Int
    /// How the item's playing file was sorted; nil when unknown.
    func sortInfo(itemID: Int64) async throws -> ItemSortInfo?
}
