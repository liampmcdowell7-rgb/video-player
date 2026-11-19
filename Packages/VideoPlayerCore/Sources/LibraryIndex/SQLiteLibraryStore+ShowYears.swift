import Foundation

// Shows with the same name and different years (addendum #18 D, PROVISIONAL, OPEN_QUESTIONS R174, docs/SORTING.md).
//
// Rule: two shows stay apart when their names carry different years ("Sample Remake (2005)" and "Sample Remake (2019)");
// they are one show when at most one year is known or the years match. The scan first files every episode under the plain
// keys (`s|name`, `e|name|season|episode`), exactly as before; then, for each show name the change touched, this pass looks
// at the years of all its live files (`files.series_year`, schema 4):
//
// - fewer than two different years: every file stays in (or goes back to) the plain items, so a library without such a
//   pair keeps every key it had and loses no watch state;
// - two or more: each file with a year goes to `s|name|yYEAR` / `e|name|yYEAR|...`, titled "Name (YEAR)"; files with no
//   year stay in the plain show, because they cannot be told apart.
//
// The result depends only on which files are in the library, not on the order they were scanned, so two Apple TVs with the
// same files get the same keys. When a file moves to a new item, the new item starts with the watch state of the item it
// came from if the file was already there when that item was last played (before the split both shows' episodes were
// that one item, so this is what the user saw); a file that arrived later starts unwatched. A watch state saved in iCloud
// for the new key wins over both.
extension SQLiteLibraryStore {
    /// The base show key ("s|name") of an item's series key, with any "|yYEAR" removed.
    static func baseSeriesKey(_ key: String) -> String {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        return parts.count >= 2 ? parts[0] + "|" + parts[1] : key
    }

    static func yearedSeriesKey(_ base: String, year: Int) -> String { base + "|y\(year)" }

    /// "e|name|..." -> "e|name|yYEAR|..." (and back with `year` nil). Keys of other shapes are returned unchanged.
    static func episodeKey(_ key: String, year: Int?) -> String {
        var parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0] == "e" else { return key }
        if parts[2].hasPrefix("y"), Int(parts[2].dropFirst()) != nil { parts.remove(at: 2) }
        if let year { parts.insert("y\(year)", at: 2) }
        return parts.joined(separator: "|")
    }

    /// Series keys (base form) of the given items.
    func baseSeriesKeys(ofItems ids: Set<Int64>) throws -> Set<String> {
        var out = Set<String>()
        for id in ids {
            if let key = try db.first(
                "SELECT s.key FROM items i JOIN series s ON s.id = i.series_id WHERE i.id = ?", [.int(id)], { $0.text(0) }
            ) { out.insert(Self.baseSeriesKey(key)) }
        }
        return out
    }

    /// Applies the rule above to one show name. Returns every item whose files changed (old and new), for `refreshItem`.
    func reconcileShowYears(base: String) throws -> Set<Int64> {
        struct Row { var file: Int64; var item: Int64; var year: Int?; var key: String; var seriesTitle: String; var playedBefore: Bool }
        let rows = try db.rows(
            """
            SELECT f.id, f.item_id, f.series_year, i.key, COALESCE(i.series_title, ''),
                   (i.last_played > 0 AND f.first_seen <= i.last_played) FROM files f
            JOIN items i ON i.id = f.item_id JOIN series s ON s.id = i.series_id
            WHERE (s.key = ? OR substr(s.key, 1, ?) = ?) AND f.removed_at IS NULL AND f.kind = 0 AND f.review = 0
            """,
            [.text(base), .int(Int64(base.count + 1)), .text(base + "|")], cached: false
        ) { s in Row(file: s.int64(0), item: s.int64(1), year: s.optInt(2), key: s.text(3), seriesTitle: s.text(4), playedBefore: s.bool(5)) }
        let years = Set(rows.compactMap(\.year))
        let split = years.count >= 2
        var touched = Set<Int64>()
        var cache: [String: Int64] = [:]
        for row in rows {
            let year = split ? row.year : nil
            let target = Self.episodeKey(row.key, year: year)
            if target == row.key { continue }
            let plainTitle = Self.plainSeriesTitle(row.seriesTitle)
            let title = year.map { "\(plainTitle) (\($0))" } ?? plainTitle
            let seriesKey = year.map { Self.yearedSeriesKey(base, year: $0) } ?? base
            let id = try cache[target] ?? moveTarget(key: target, from: row.item, seriesKey: seriesKey, seriesTitle: title, year: year,
                                                     inheritWatch: row.playedBefore)
            cache[target] = id
            try db.run("UPDATE files SET item_id = ? WHERE id = ?", [.int(id), .int(row.file)])
            touched.insert(row.item)
            touched.insert(id)
        }
        return touched
    }

    /// "Name (2005)" -> "Name" when the suffix is a year this pass added.
    static func plainSeriesTitle(_ title: String) -> String {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "("), open > title.startIndex else { return title }
        let inside = title[title.index(after: open)..<title.index(before: title.endIndex)]
        guard inside.count == 4, Int(inside) != nil else { return title }
        return String(title[..<open]).trimmingCharacters(in: .whitespaces)
    }

    /// The item with `key`, created from `source` (same episode fields) when it does not exist yet. It takes the source's
    /// watch state only when `inheritWatch`: the file was in the library before the source item was last played, so it can
    /// have been the one watched; a file that arrived later starts unwatched.
    private func moveTarget(key: String, from source: Int64, seriesKey: String, seriesTitle: String, year: Int?, inheritWatch: Bool) throws -> Int64 {
        if let id = try db.first("SELECT id FROM items WHERE key = ?", [.text(key)], { $0.int64(0) }) { return id }
        var seriesID = try db.first("SELECT id FROM series WHERE key = ?", [.text(seriesKey)], { $0.int64(0) })
        if seriesID == nil {
            try db.run("INSERT INTO series (key, title) VALUES (?, ?)", [.text(seriesKey), .text(seriesTitle)])
            seriesID = db.lastInsertRowID
        }
        guard let s = try db.first("SELECT season, episode, title FROM items WHERE id = ?", [.int(source)], { ($0.optInt(0), $0.optInt(1), $0.text(2)) }) else {
            throw LibraryIndexError.notFound("item \(source)")
        }
        let base = LibraryText.titleSortValue(seriesTitle)
        let sortValue = base.value + " " + Self.pad4Key(s.0 ?? 0) + " " + Self.pad4Key(s.1 ?? 0)
        let search = LibraryText.normalize(s.2 + " " + seriesTitle)
        try db.run(
            """
            INSERT INTO items (key, kind, title, sort_title, letter, search, year, series_id, series_title, season, episode, episode_end,
                               tmdb_id, added_at, review, position, wduration, watched, play_count, last_played, favorite, hidden)
            SELECT ?, kind, title, ?, ?, ?, COALESCE(?, year), ?, ?, season, episode, episode_end, tmdb_id, added_at, review,
                   CASE WHEN ? THEN position ELSE 0 END, CASE WHEN ? THEN wduration ELSE NULL END, CASE WHEN ? THEN watched ELSE 0 END,
                   CASE WHEN ? THEN play_count ELSE 0 END, CASE WHEN ? THEN last_played ELSE 0 END, CASE WHEN ? THEN favorite ELSE 0 END,
                   CASE WHEN ? THEN hidden ELSE 0 END
            FROM items WHERE id = ?
            """,
            [.text(key), .text(sortValue), .text(base.letter), .text(search), SQLValue(year), SQLValue(seriesID), .text(seriesTitle)]
                + Array(repeating: SQLValue(inheritWatch), count: 7) + [.int(source)]
        )
        let id = db.lastInsertRowID
        try applyPendingWatch(itemID: id, key: key)
        return id
    }

    static func pad4Key(_ n: Int) -> String { String(repeating: "0", count: max(0, 4 - String(n).count)) + String(n) }
}
