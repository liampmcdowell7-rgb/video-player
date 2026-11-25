import Foundation

// R471 (15), PROVISIONAL: Delete from Library. A file the user removed from the library stays on its source; this record
// keeps it out of the index on every later scan and on the user's other devices. One record per file, record type
// "libraryremoval", keyed like the file's edits (`UDEditKey.file`), synced and backed up like every other user record (an
// unregistered type merges field by field, later stamp wins). Restoring writes a deletion stamp.

public struct UDLibraryRemoval: Equatable, Hashable, Sendable {
    public var sourceID: String
    public var path: String
    public var title: String
    public var removedAt: Date

    public init(sourceID: String, path: String, title: String, removedAt: Date) {
        self.sourceID = sourceID; self.path = path; self.title = title; self.removedAt = removedAt
    }

    public static let type = "libraryremoval"

    public var key: UDEditKey { .file(sourceID: sourceID, path: path) }

    static func value(of r: UDRecord) -> UDLibraryRemoval? {
        guard r.type == type, !r.isDeleted, let s = r["sourceID"]?.asString, let p = r["path"]?.asString else { return nil }
        return UDLibraryRemoval(sourceID: s, path: p, title: r["title"]?.asString ?? "",
                                removedAt: Date(timeIntervalSince1970: r["removedAt"]?.asDouble ?? 0))
    }
}

public extension UserDataLedger {
    func removeFromLibrary(_ removal: UDLibraryRemoval, at date: Date? = nil) {
        let s = stamp(date)
        var r = UDRecord(type: UDLibraryRemoval.type, id: removal.key.recordID)
        r.set("sourceID", .string(removal.sourceID), at: s)
        r.set("path", .string(removal.path), at: s)
        r.set("title", .string(removal.title), at: s)
        r.set("removedAt", .double(removal.removedAt.timeIntervalSince1970), at: s)
        apply(r)
    }

    func restoreToLibrary(sourceID: String, path: String, at date: Date? = nil) {
        apply(UDRecord(type: UDLibraryRemoval.type, id: UDEditKey.file(sourceID: sourceID, path: path).recordID, fields: [:], deleted: stamp(date)))
    }

    /// Every file removed from the library, newest first.
    func libraryRemovals() -> [UDLibraryRemoval] {
        records(ofType: UDLibraryRemoval.type).compactMap(UDLibraryRemoval.value)
            .sorted { $0.removedAt != $1.removedAt ? $0.removedAt > $1.removedAt : $0.path < $1.path }
    }
}
