import Foundation

extension SQLiteLibraryStore {
    /// The item's stable key: the id of its watch record and the prefix of the ids of its user-marked segments. It is derived from the
    /// file name, so it is the same after an index rebuild and on every device (docs/STORAGE_MODEL.md, "Items are matched by items.key").
    /// Nil when the item does not exist.
    public func userDataKey(forItem id: Int64) throws -> String? {
        try itemKey(id)
    }
}
