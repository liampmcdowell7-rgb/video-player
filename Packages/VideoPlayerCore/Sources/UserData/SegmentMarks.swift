import Foundation

// User-marked positions: "this is where the intro / recap / credits of this title is". User data that cannot be
// recomputed, so it lives in the ledger (synced like watch state) and never only in the library index
// (docs/STORAGE_MODEL.md, docs/SEGMENTS.md).
//
// Record type `segment` (the string was reserved from the first version of the schema; no earlier version wrote it, so
// there is nothing to migrate). One record per (item, kind):
//   id      "<item key>|<kind>"   the item key is the library item's stable key (derived from the file name, the same
//                                  after an index rebuild and on every device), the kind is "recap", "intro" or "credits"
//   fields  kind (string), start, end (seconds), fileDuration (seconds, optional), createdAt (seconds since 1970, optional),
//           v (format version, optional, 1)
// Version safety:
//  - reading never needs a field beyond kind, start and end; the others are optional, so a record written by an older or a
//    newer app still reads;
//  - unknown fields are kept by the merge rules and ignored here;
//  - an unknown kind is skipped (a newer app may add kinds) and kept in the ledger.
// PROVISIONAL: a mark belongs to the item (one title), not to the series. Alternative (not built): "apply to the rest of
// this season", which would store one record per season and have the reader fall back to it.

/// One user mark, as stored. `kind` is the raw value of the playback logic's segment type ("recap", "intro", "credits").
public struct UDSegmentMark: Equatable, Sendable {
    public var itemKey: String
    public var kind: String
    public var start: Double
    public var end: Double
    /// Length of the file the user marked on. Used to drop the mark when the file is replaced by a different cut.
    public var fileDuration: Double?
    public var createdAt: Date?

    public init(itemKey: String, kind: String, start: Double, end: Double, fileDuration: Double? = nil, createdAt: Date? = nil) {
        self.itemKey = itemKey
        self.kind = kind
        self.start = start
        self.end = end
        self.fileDuration = fileDuration
        self.createdAt = createdAt
    }
}

public enum UDSegmentMarkRecord {
    public static let formatVersion = 1
    static let separator: Character = "|"

    public static func recordID(itemKey: String, kind: String) -> String { itemKey + String(separator) + kind }

    /// Splits a record id into item key and kind. The kind never contains the separator, the item key may.
    static func split(_ id: String) -> (itemKey: String, kind: String)? {
        guard let cut = id.lastIndex(of: separator) else { return nil }
        let key = String(id[id.startIndex..<cut]), kind = String(id[id.index(after: cut)...])
        return key.isEmpty || kind.isEmpty ? nil : (key, kind)
    }

    public static func patch(_ m: UDSegmentMark, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.segment, id: recordID(itemKey: m.itemKey, kind: m.kind))
        r.set("kind", .string(m.kind), at: stamp)
        r.set("start", .double(m.start), at: stamp)
        r.set("end", .double(m.end), at: stamp)
        r.set("fileDuration", m.fileDuration.map { .double($0) } ?? .null, at: stamp)
        r.set("createdAt", .double((m.createdAt ?? stamp.date).timeIntervalSince1970), at: stamp)
        r.set("v", .int(Int64(formatVersion)), at: stamp)
        return r
    }

    public static func tombstone(itemKey: String, kind: String, at stamp: UDStamp) -> UDRecord {
        UDRecord(type: UDSchema.segment, id: recordID(itemKey: itemKey, kind: kind), fields: [:], deleted: stamp)
    }

    /// nil for a deleted record or one that cannot be read as a range. Reads defensively.
    public static func value(of r: UDRecord) -> UDSegmentMark? {
        guard !r.isDeleted, r.type == UDSchema.segment, let ids = split(r.id) else { return nil }
        let kind = r["kind"]?.asString ?? ids.kind
        guard kind == ids.kind, let start = r["start"]?.asDouble, let end = r["end"]?.asDouble,
              start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
        let duration = r["fileDuration"]?.asDouble.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return UDSegmentMark(itemKey: ids.itemKey, kind: kind, start: start, end: end, fileDuration: duration,
                             createdAt: r["createdAt"]?.asDouble.map { Date(timeIntervalSince1970: $0) })
    }
}

extension UDStamp {
    var date: Date { Date(timeIntervalSince1970: time) }
}

public extension UserDataLedger {
    /// Every readable mark of one item, one per kind, in a stable order (by kind).
    func segmentMarks(forItemKey key: String) -> [UDSegmentMark] {
        records(ofType: UDSchema.segment)
            .filter { UDSegmentMarkRecord.split($0.id)?.itemKey == key }
            .compactMap { UDSegmentMarkRecord.value(of: $0) }
            .sorted { $0.kind < $1.kind }
    }

    /// Saves (or replaces) the mark of this item and kind. Returns false when nothing changed.
    @discardableResult
    func saveSegmentMark(_ mark: UDSegmentMark, at date: Date? = nil) -> Bool {
        apply(UDSegmentMarkRecord.patch(mark, at: stamp(date)))
    }

    /// Deletes the mark of this item and kind (a tombstone, so the deletion syncs; a later save brings it back).
    @discardableResult
    func deleteSegmentMark(itemKey: String, kind: String, at date: Date? = nil) -> Bool {
        apply(UDSegmentMarkRecord.tombstone(itemKey: itemKey, kind: kind, at: stamp(date)))
    }
}
