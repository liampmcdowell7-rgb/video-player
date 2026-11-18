import Foundation
import UserData

/// The iCloud backup of what the library GENERATES (docs/BACKUP.md, OPEN_QUESTIONS R163). Never the media files, never
/// passwords, tokens or API keys. Everything here is PROVISIONAL until a CI compile and a device run (R163).

/// The two backed-up sets. Watch state, saved views, sources and settings are the third part of the screen, but they are
/// already synced record by record by `UserDataSyncEngine` (docs/STORAGE_MODEL.md section 3), so they are not copied again.
public enum BackupSet: String, Codable, CaseIterable, Sendable {
    /// The library index database, the online metadata answers and the Fix Match choices.
    case library
    /// Pictures read from the sources (posters, backdrops, stills, logos) in the artwork cache.
    case artwork
}

/// The format of a manifest. A manifest with a larger number was written by a newer app and is never restored.
public enum BackupFormat {
    public static let current = 1
    /// Chunk size before compression. 1 MiB: well under the CKAsset limits (docs/BACKUP.md), and SQLite changes pages in
    /// place, so an edit changes only the 1 MiB chunks that hold its pages (the incremental upload relies on this).
    public static let chunkSize = 1 << 20
}

/// The three switches (Settings > Backup). Stored in UserDefaults by the app.
public struct BackupSettings: Codable, Equatable, Sendable {
    public var library: Bool
    public var artwork: Bool
    /// Only pictures that belong to items in the library (a picture whose name is not claimed by an item is skipped).
    public var artworkLibraryOnly: Bool
    /// Watch state and settings: synced by the existing iCloud sync; this switch is shown on the same screen.
    public var userData: Bool

    public init(library: Bool = true, artwork: Bool = true, artworkLibraryOnly: Bool = false, userData: Bool = true) {
        self.library = library
        self.artwork = artwork
        self.artworkLibraryOnly = artworkLibraryOnly
        self.userData = userData
    }

    public func includes(_ set: BackupSet) -> Bool { set == .library ? library : artwork }
}

/// One file of a set as it is stored: its name inside the set, size, modification time and its chunks in order.
public struct BackupFileEntry: Codable, Equatable, Sendable {
    public var name: String
    public var size: Int
    public var modified: Date
    /// SHA-256 (hex) of each uncompressed chunk, in order.
    public var chunks: [String]
    /// SHA-256 of the whole file, checked after the chunks are joined.
    public var sha256: String

    public init(name: String, size: Int, modified: Date, chunks: [String], sha256: String) {
        self.name = name
        self.size = size
        self.modified = modified
        self.chunks = chunks
        self.sha256 = sha256
    }
}

/// A complete, self-consistent picture of one set. Chunks are content addressed and never changed after upload, so a
/// restore that reads one manifest can never mix two backups.
public struct BackupManifest: Codable, Equatable, Sendable {
    public var format: Int
    public var set: BackupSet
    /// 1, 2, 3, … per set. A restore remembers the generation it started with and refuses to continue on another one.
    public var generation: Int
    public var createdAt: Date
    /// The library database schema (`PRAGMA user_version`) of the database in this backup; 0 for artwork.
    public var librarySchema: Int
    public var files: [BackupFileEntry]
    /// Compressed size of each chunk this manifest uses (hash -> bytes): the "size in iCloud", measured at upload.
    public var storedBytes: [String: Int]
    /// The chunks of the generation before this one; kept until the next generation, so a restore that started on the
    /// previous manifest elsewhere can still finish.
    public var previousChunks: [String]
    /// Files left out on purpose (too large, or iCloud was full), with the reason. Shown on the screen.
    public var skipped: [BackupSkip]

    public init(format: Int = BackupFormat.current, set: BackupSet, generation: Int, createdAt: Date, librarySchema: Int,
                files: [BackupFileEntry], storedBytes: [String: Int], previousChunks: [String], skipped: [BackupSkip]) {
        self.format = format
        self.set = set
        self.generation = generation
        self.createdAt = createdAt
        self.librarySchema = librarySchema
        self.files = files
        self.storedBytes = storedBytes
        self.previousChunks = previousChunks
        self.skipped = skipped
    }

    public var chunkSet: Set<String> { Set(files.flatMap(\.chunks)) }
    public var totalStoredBytes: Int { storedBytes.values.reduce(0, +) }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(BackupManifest.self, from: data)
    }
}

public struct BackupSkip: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable { case tooLarge, iCloudFull, notInLibrary }
    public var name: String
    public var size: Int
    public var reason: Reason
    public init(name: String, size: Int, reason: Reason) {
        self.name = name
        self.size = size
        self.reason = reason
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case cloud(UDCloudError)
    /// A chunk's content did not match its name, even after downloading it again.
    case checksumMismatch(String)
    /// The backup was made by a newer version of the app (format or database schema): it is not restored.
    case newerBackup(format: Int, librarySchema: Int)
    /// A file about to be uploaded contains a password, token or API key: nothing is uploaded.
    case secretDetected(String)
    /// No backup of this set exists in iCloud.
    case nothingToRestore
    /// The backup changed while a restore was reading it (another Apple TV backed up): start the restore again.
    case backupChanged
    case local(String)
}

/// What the screen shows. Texts in `BackupStatusText`.
public enum BackupStatus: Equatable, Sendable {
    case idle
    case signedOut
    case iCloudFull
    case offline
    case newerBackup
    case backingUp(BackupProgress)
    case restoring(BackupProgress)
    case failed(String)
}

public struct BackupProgress: Equatable, Sendable {
    public var set: BackupSet
    public var done: Int
    public var total: Int
    public init(set: BackupSet, done: Int, total: Int) {
        self.set = set
        self.done = done
        self.total = total
    }
    public var fraction: Double { total == 0 ? 1 : Double(done) / Double(total) }
}

/// The result of one backup or restore pass.
public struct BackupReport: Equatable, Sendable {
    public var status: BackupStatus = .idle
    public var uploadedChunks = 0
    public var reusedChunks = 0
    public var downloadedChunks = 0
    public var resumedChunks = 0
    public var deletedChunks = 0
    public var restoredFiles = 0
    /// Files kept because the copy on this Apple TV is newer (the merge rule).
    public var keptNewerLocal = 0
    public var skipped: [BackupSkip] = []
    public var finishedAt: Date?
    public init() {}
}
