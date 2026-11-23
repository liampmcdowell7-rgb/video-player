import Foundation

/// R458 (Hide a source; PROVISIONAL) and R459 (Parental Controls): the ONE rule that decides which titles the library shows.
/// The store applies it inside every query that returns titles (grids, counts, letter index, Continue Watching, Next Up,
/// Recently Added, a show's episodes, one title by id), so no screen can read a title the rule hides. Nothing here is stored
/// in the library database: the app sets it at launch and whenever a setting changes.
public struct LibraryRestrictions: Equatable, Sendable {
    /// A title is hidden when every one of its files is in a hidden source.
    public var hiddenSourceIDs: Set<String> = []

    public init(hiddenSourceIDs: Set<String> = []) {
        self.hiddenSourceIDs = hiddenSourceIDs
    }

    public var isEmpty: Bool { hiddenSourceIDs.isEmpty }

    /// The SQL terms (joined with AND by the caller) and their arguments for items aliased `alias`.
    func terms(alias i: String = "i") -> (sql: [String], args: [SQLValue]) {
        var sql: [String] = []
        var args: [SQLValue] = []
        if !hiddenSourceIDs.isEmpty {
            let marks = Array(repeating: "?", count: hiddenSourceIDs.count).joined(separator: ",")
            sql.append("\(i).id IN (SELECT item_id FROM files WHERE removed_at IS NULL AND item_id IS NOT NULL AND source_id NOT IN (\(marks)))")
            args += hiddenSourceIDs.sorted().map { .text($0) }
        }
        return (sql, args)
    }
}
