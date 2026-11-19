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
    ///
    /// Addendum #19 C (PROVISIONAL, OPEN_QUESTIONS R174): while the name is split, a file with no year goes to Needs Review
    /// ("two shows share this name") instead of a third, plain show, unless a Move or the online check put it there. It
    /// keeps where it came from in `files.shared_name` and goes back by itself when fewer than two years are left.
    func reconcileShowYears(base: String) throws -> Set<Int64> {
        struct Row {
            var file: Int64; var item: Int64; var year: Int?; var key: String; var seriesTitle: String; var playedBefore: Bool
            var sourceID: String; var path: String; var signal: String?; var note: String
        }
        let rows = try db.rows(
            """
            SELECT f.id, f.item_id, f.series_year, i.key, COALESCE(i.series_title, ''),
                   (i.last_played > 0 AND f.first_seen <= i.last_played), f.source_id, f.path, f.sort_signal, COALESCE(f.sort_note, '') FROM files f
            JOIN items i ON i.id = f.item_id JOIN series s ON s.id = i.series_id
            WHERE (s.key = ? OR substr(s.key, 1, ?) = ?) AND f.removed_at IS NULL AND f.kind = 0 AND f.review = 0
            """,
            [.text(base), .int(Int64(base.count + 1)), .text(base + "|")], cached: false
        ) { s in
            Row(file: s.int64(0), item: s.int64(1), year: s.optInt(2), key: s.text(3), seriesTitle: s.text(4), playedBefore: s.bool(5),
                sourceID: s.text(6), path: s.text(7), signal: s.optText(8), note: s.text(9))
        }
        let years = Set(rows.compactMap(\.year))
        let split = years.count >= 2
        var touched = Set<Int64>()
        var cache: [String: Int64] = [:]
        let plainTitle = Self.plainSeriesTitle(rows.first(where: { $0.year == nil })?.seriesTitle ?? rows.first?.seriesTitle ?? "")
        for row in rows {
            if split, row.year == nil, !Self.placedByChoice(row.signal) {
                let waiting = try reviewItem(sourceID: row.sourceID, path: row.path, title: plainTitle, from: row.item)
                let shared = SharedName(key: row.key, signal: row.signal ?? SortSignal.episodePattern.rawValue, note: row.note)
                try db.run(
                    "UPDATE files SET item_id = ?, review = 1, sort_signal = ?, sort_note = ?, shared_name = ? WHERE id = ?",
                    [.int(waiting), .text(SortSignal.undecided.rawValue), .text(Self.sharedNameNote(plainTitle, years: years)),
                     .text(shared.encoded), .int(row.file)]
                )
                touched.insert(row.item)
                touched.insert(waiting)
                continue
            }
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
        if !split { touched.formUnion(try releaseWaitingFiles(base: base)) }
        return touched
    }

    /// Where a waiting file came from: its plain episode key, the signal and the note it had. Stored as one text value
    /// (unit separator between the parts; keys are normalised text and contain no control characters).
    struct SharedName: Equatable {
        var key: String
        var signal: String
        var note: String
        var encoded: String { [key, signal, note].joined(separator: "\u{1F}") }
        init(key: String, signal: String, note: String) { self.key = key; self.signal = signal; self.note = note }
        init?(encoded: String) {
            let parts = encoded.components(separatedBy: "\u{1F}")
            guard parts.count == 3, !parts[0].isEmpty else { return nil }
            self.init(key: parts[0], signal: parts[1], note: parts[2])
        }
    }

    /// A Move or the online check decided the file: it stays where it was put.
    static func placedByChoice(_ signal: String?) -> Bool {
        signal == SortSignal.manual.rawValue || signal == SortSignal.onlineLookup.rawValue
    }

    static func sharedNameNote(_ title: String, years: Set<Int>) -> String {
        let names = years.sorted().map { "\u{201C}\(title) (\($0))\u{201D}" }
        let list = names.count == 2 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        return "Two shows share this name: \(list). The file name has no year to tell which one."
    }

    /// Files of this show name waiting in Needs Review go back to the item they came from, with their signal and note.
    /// When that item no longer exists the file is marked for sorting again on the next scan.
    private func releaseWaitingFiles(base: String) throws -> Set<Int64> {
        let prefix = "e|" + base.dropFirst(2) + "|"
        let waiting = try db.rows(
            // Range on the partial index idx_files_shared_name: every value that starts with `prefix`.
            "SELECT id, item_id, shared_name FROM files WHERE shared_name IS NOT NULL AND shared_name >= ? AND shared_name < ? AND removed_at IS NULL",
            [.text(prefix), .text(String(prefix.dropLast()) + "}")], cached: false
        ) { s in (file: s.int64(0), item: s.optInt64(1), shared: s.text(2)) }
        var touched = Set<Int64>()
        for w in waiting {
            if let item = w.item { touched.insert(item) }
            guard let shared = SharedName(encoded: w.shared),
                  let target = try db.first("SELECT id FROM items WHERE key = ?", [.text(shared.key)], { $0.int64(0) }) else {
                try db.run("UPDATE files SET sort_rev = 0, shared_name = NULL WHERE id = ?", [.int(w.file)])
                continue
            }
            try db.run(
                "UPDATE files SET item_id = ?, review = 0, sort_signal = ?, sort_note = ?, shared_name = NULL WHERE id = ?",
                [.int(target), .text(shared.signal), .text(shared.note), .int(w.file)]
            )
            touched.insert(target)
        }
        return touched
    }

    /// The Needs Review item of one file ("r|source|path", as `ItemGrouping.reviewSeed` names it), made when missing.
    private func reviewItem(sourceID: String, path: String, title: String, from source: Int64) throws -> Int64 {
        let key = "r|\(sourceID)|\(path)"
        if let id = try db.first("SELECT id FROM items WHERE key = ?", [.text(key)], { $0.int64(0) }) {
            try db.run("UPDATE items SET review = 1 WHERE id = ?", [.int(id)])
            return id
        }
        let sort = LibraryText.titleSortValue(title)
        try db.run(
            """
            INSERT INTO items (key, kind, title, sort_title, letter, search, year, added_at, review)
            SELECT ?, ?, ?, ?, ?, ?, 0, added_at, 1 FROM items WHERE id = ?
            """,
            [.text(key), .int(Int64(Self.code(ItemKind.movie))), .text(title), .text(sort.value), .text(sort.letter),
             .text(LibraryText.normalize(title)), .int(source)]
        )
        return db.lastInsertRowID
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
