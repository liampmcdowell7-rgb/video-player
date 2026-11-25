import Foundation

// R471 (14), PROVISIONAL: Unmatch. A file the user unmatched is held unmatched: the automatic matcher leaves it alone until
// the user picks a match with Fix Match (a Fix Match choice still applies to it). One record per file, record type
// "unmatch", keyed like the file's edits (`UDEditKey.file`), synced and backed up like every other user record (an
// unregistered type merges field by field, later stamp wins, STORAGE_MODEL.md section 3). Releasing writes a deletion stamp.

public enum UDUnmatchHold {
    public static let type = "unmatch"
}

public extension UserDataLedger {
    func holdUnmatched(_ file: UDEditKey, at date: Date? = nil) {
        var r = UDRecord(type: UDUnmatchHold.type, id: file.recordID)
        r.set("held", .bool(true), at: stamp(date))
        apply(r)
    }

    func releaseUnmatched(_ file: UDEditKey, at date: Date? = nil) {
        apply(UDRecord(type: UDUnmatchHold.type, id: file.recordID, fields: [:], deleted: stamp(date)))
    }

    func isHeldUnmatched(_ file: UDEditKey) -> Bool {
        guard let r = record(type: UDUnmatchHold.type, id: file.recordID), !r.isDeleted else { return false }
        return r["held"]?.asBool ?? false
    }
}
