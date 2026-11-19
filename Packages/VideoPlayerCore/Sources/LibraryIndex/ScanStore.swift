import Foundation
import VideoPlayerCore

// The primitives the sync engine needs from a store. Kept apart from `LibraryStore` so the app-facing
// protocol stays small. Every `apply` call is one atomic transaction, so a scan can be killed at any
// moment and resumed from the folder queue that is stored in the database.

public enum ScanStatus: String, Sendable { case running, completed, interrupted, cancelled }

public struct ScanOptions: Equatable, Sendable {
    /// Walk into sub folders. False refreshes only the given folders.
    public var recursive = true
    /// Skip sub folders whose own version (token, ETag, or date and size) did not change since they were last
    /// listed. Only sound for sources whose folder version also changes when something below it changes.
    public var trustFolderVersions = false
    public init(recursive: Bool = true, trustFolderVersions: Bool = false) {
        self.recursive = recursive
        self.trustFolderVersions = trustFolderVersions
    }
}

public struct ScanTicket: Equatable, Sendable {
    public var scanID: Int64
    /// True when an unfinished scan of this source was picked up where it stopped.
    public var resumed: Bool
    public var pendingFolders: Int
}

public struct ScanRecord: Equatable, Sendable {
    public var id: Int64
    public var sourceID: String
    public var status: ScanStatus
    public var startedAt: Date
    public var finishedAt: Date?
    public var foldersDone: Int
    public var foldersPending: Int
}

public struct PendingFolder: Equatable, Sendable {
    public var path: String
    /// The folder's own version as seen in its parent's listing (empty for scan roots).
    public var observed: FileVersion
    public var emptyStrikes: Int
    public var storedEntryCount: Int
}

/// What the grouping rules decided about a video file: which film or episode it is a version of.
public struct ItemSeed: Equatable, Sendable {
    public var key: String
    public var kind: ItemKind
    public var title: String
    public var year: Int?
    public var seriesKey: String?
    public var seriesTitle: String?
    public var season: Int?
    public var episode: Int?
    public var episodeEnd: Int?
    public var tmdbID: Int?
    /// Edition, resolution and source as parsed from the file name, shown in the version picker.
    public var versionLabel: String?
    /// A file in Needs Review (docs/SORTING.md): its own item, never shown in Movies, Shows, Home or Top Shelf.
    public var needsReview = false
}

/// How one file was sorted (docs/SORTING.md), stored with the file.
public struct FileSortRecord: Equatable, Sendable {
    public var signal: SortSignal
    public var note: String
    /// `MediaSorter.revision` at the time.
    public var revision: Int
    /// What decided besides the file itself (an override, a server type and the source setting), so a change there sorts
    /// the file again although the file did not change.
    public var inputs: String
    public var needsReview: Bool

    public init(signal: SortSignal, note: String, revision: Int = MediaSorter.revision, inputs: String = "", needsReview: Bool = false) {
        self.signal = signal
        self.note = note
        self.revision = revision
        self.inputs = inputs
        self.needsReview = needsReview
    }
}

public struct FileUpsert: Sendable {
    public var path: String
    public var name: String
    public var kind: FileKind
    public var size: Int64?
    public var modified: Date?
    public var etag: String?
    public var serverToken: String?
    public var technical: FileTechnicalInfo?
    public var seed: ItemSeed?
    public var sort: FileSortRecord? = nil
}

public struct ListedFolder: Equatable, Sendable {
    public var path: String
    public var name: String
    public var version: FileVersion
}

public struct FolderChange: Sendable {
    public var sourceID: String
    public var path: String
    /// The version recorded as "listed completely" for this folder.
    public var scannedVersion: FileVersion
    public var childFolders: [ListedFolder]
    public var upserts: [FileUpsert]
    public var removedFilePaths: [String]
    public var removedFolderPaths: [String]
    /// Removals are not applied (an empty listing of a folder that had content, seen for the first time).
    public var holdRemovals: Bool
    public var emptyStrikes: Int
    public var now: Date
}

public struct FolderApplyResult: Equatable, Sendable {
    public var added = 0
    public var changed = 0
    public var removed = 0
    public var queuedFolders = 0
}

public protocol LibraryScanStore: Sendable {
    /// Starts a scan of `roots`, or with `resume` picks up the unfinished full scan of this source when it has
    /// the same roots and options. Scans that cannot be resumed are closed as cancelled.
    func beginScan(sourceID: String, roots: [String], options: ScanOptions, resume: Bool, now: Date) async throws -> ScanTicket
    func scan(id: Int64) async throws -> ScanRecord?
    /// The next folder still to do, without removing it from the queue.
    func nextFolder(scanID: Int64) async throws -> PendingFolder?
    func storedFiles(sourceID: String, folder: String) async throws -> [StoredFile]
    /// Paths of the live sub folders stored for a folder.
    func storedChildFolders(sourceID: String, folder: String) async throws -> [String]
    /// Stores the result of listing one folder and marks it done, in one transaction.
    func apply(_ change: FolderChange, scanID: Int64) async throws -> FolderApplyResult
    /// Keeps all stored rows for the folder, records why it could not be read, and marks it done for this scan.
    func recordFailure(scanID: Int64, sourceID: String, folder: String, message: String, now: Date) async throws
    func finishScan(scanID: Int64, status: ScanStatus, now: Date) async throws
    /// Removes files and folders that were marked removed before `olderThan`, and items left without files
    /// that have no watch history.
    func purgeRemoved(olderThan: Date) async throws -> Int
}
