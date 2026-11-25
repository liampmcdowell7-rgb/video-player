import Foundation

extension SQLiteLibraryStore {
    /// The item's stable key: the id of its watch record and the prefix of the ids of its user-marked segments. It is derived from the
    /// file name, so it is the same after an index rebuild and on every device (docs/STORAGE_MODEL.md, "Items are matched by items.key").
    /// Nil when the item does not exist.
    public func userDataKey(forItem id: Int64) throws -> String? {
        try itemKey(id)
    }
}

extension SQLiteLibraryStore {
    /// R471 (17): a show's stable key ("s|name", derived from the file names like an item's key), for the user's lists.
    public func seriesKey(forSeries id: Int64) throws -> String? {
        try db.first("SELECT key FROM series WHERE id = ?", [.int(id)]) { $0.text(0) }
    }

    /// The show a stable key belongs to on this device; nil when no show has it (yet).
    public func seriesID(forKey key: String) throws -> Int64? {
        try db.first("SELECT id FROM series WHERE key = ?", [.text(key)]) { $0.int64(0) }
    }
}
