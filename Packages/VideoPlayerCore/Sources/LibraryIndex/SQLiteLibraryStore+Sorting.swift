import Foundation
import VideoPlayerCore

/// One file in Needs Review (docs/SORTING.md).
public struct ReviewEntry: Equatable, Sendable, Identifiable {
    /// The review item's id.
    public var id: Int64
    public var fileID: Int64
    public var sourceID: String
    public var path: String
    public var fileName: String
    /// The title read from the file name (or the file name itself).
    public var title: String
    public var year: Int?
    /// Why the file could not be sorted.
    public var note: String
    public var addedAt: Date

    public init(id: Int64, fileID: Int64, sourceID: String, path: String, fileName: String, title: String, year: Int?, note: String, addedAt: Date) {
        self.id = id; self.fileID = fileID; self.sourceID = sourceID; self.path = path; self.fileName = fileName
        self.title = title; self.year = year; self.note = note; self.addedAt = addedAt
    }
}

/// How an item's file was sorted, for the item info.
public struct ItemSortInfo: Equatable, Sendable {
    public var record: FileSortRecord
    public var sourceID: String
    public var path: String
    public var fileName: String
}

extension SQLiteLibraryStore {
    public func needsReview(limit: Int) throws -> [ReviewEntry] {
        guard limit > 0 else { return [] }
        return try db.rows(
            """
            SELECT i.id, f.id, f.source_id, f.path, f.name, i.title, i.year, f.sort_note, i.added_at
            FROM items i JOIN files f ON f.item_id = i.id AND f.removed_at IS NULL AND f.kind = 0
            WHERE i.review = 1 AND i.version_count > 0
            ORDER BY i.added_at DESC, i.id DESC LIMIT ?
            """,
            [.int(Int64(limit))], cached: false
        ) { s in
            ReviewEntry(
                id: s.int64(0), fileID: s.int64(1), sourceID: s.text(2), path: s.text(3), fileName: s.text(4), title: s.text(5),
                year: s.int(6) > 0 ? s.int(6) : nil, note: s.optText(7) ?? "", addedAt: s.optDate(8) ?? Date(timeIntervalSince1970: 0)
            )
        }
    }

    public func needsReviewCount() throws -> Int {
        try db.scalarInt("SELECT COUNT(*) FROM items WHERE review = 1 AND version_count > 0")
    }

    public func sortInfo(itemID: Int64) throws -> ItemSortInfo? {
        try db.first(
            """
            SELECT f.sort_signal, f.sort_note, f.sort_rev, f.sort_inputs, f.review, f.source_id, f.path, f.name
            FROM items i JOIN files f ON f.id = i.effective_file_id WHERE i.id = ?
            """,
            [.int(itemID)]
        ) { s -> ItemSortInfo? in
            guard let signal = s.optText(0).flatMap(SortSignal.init(rawValue:)) else { return nil }
            return ItemSortInfo(
                record: FileSortRecord(signal: signal, note: s.optText(1) ?? "", revision: s.int(2), inputs: s.optText(3) ?? "", needsReview: s.bool(4)),
                sourceID: s.text(5), path: s.text(6), fileName: s.text(7)
            )
        } ?? nil
    }
}
