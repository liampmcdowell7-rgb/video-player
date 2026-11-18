import Foundation

/// Whole-database copies for the iCloud backup (docs/BACKUP.md). The database is a rebuildable cache; what the user did
/// (watch state, favourites, saved views, Fix Match) is also in the user-data ledger, which is merged back after a
/// restore with the newest-edit-wins rule (docs/STORAGE_MODEL.md section 3).
extension SQLiteLibraryStore {
    /// The newest database schema this app opens; a backup with a larger number is not restored.
    public static var supportedSchemaVersion: Int { LibrarySchema.currentVersion }

    /// Writes a consistent copy of the database to `url` (replacing any file there).
    public func exportSnapshot(to url: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm", "-journal"] { try? fm.removeItem(atPath: url.path + suffix) }
        let target = try SQLiteDatabase(path: url.path)
        try db.copy(into: target)
    }

    /// Replaces the whole database with the copy at `url`, all or nothing. A copy from a newer schema, or one that fails
    /// SQLite's quick check, is refused and the current database is left as it was. An older copy is upgraded.
    public func importSnapshot(from url: URL) throws {
        let source = try SQLiteDatabase(path: url.path)
        let version = try source.scalarInt("PRAGMA user_version")
        if version > LibrarySchema.currentVersion {
            throw LibraryIndexError.newerSchema(found: version, supported: LibrarySchema.currentVersion)
        }
        let check = try source.first("PRAGMA quick_check", cached: false) { $0.text(0) } ?? ""
        guard check == "ok" else { throw LibraryIndexError.invalid("the restored library failed its check: \(check)") }
        try source.copy(into: db)
        try db.prepareLibrarySchema()
        pendingWatch = [:]
    }

    /// Every picture file the index knows on a source (kind image, not removed), with the size and date the artwork cache
    /// puts in its key. The backup's "Only artwork for items in your library" keeps only the cached pictures of these
    /// files, so old copies of replaced posters and pictures of removed sources are left out.
    public func indexedImageFiles() throws -> [IndexedImageFile] {
        try db.rows("SELECT source_id, path, parent, size, modified FROM files WHERE kind = 2 AND removed_at IS NULL", cached: false) {
            IndexedImageFile(sourceID: $0.text(0), path: $0.text(1), parent: $0.text(2), size: $0.optInt64(3), modified: $0.optDate(4))
        }
    }

    /// True when the index holds no film or episode.
    public func isEmptyLibrary() throws -> Bool {
        try db.scalarInt("SELECT COUNT(*) FROM items") == 0
    }
}

/// A picture file as the index stores it (for the backup's artwork filter and restore order).
public struct IndexedImageFile: Equatable, Sendable {
    public var sourceID: String
    public var path: String
    public var parent: String
    public var size: Int64?
    public var modified: Date?
    public init(sourceID: String, path: String, parent: String, size: Int64?, modified: Date?) {
        self.sourceID = sourceID
        self.path = path
        self.parent = parent
        self.size = size
        self.modified = modified
    }
}
