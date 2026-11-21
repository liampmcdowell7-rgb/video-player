import Foundation
import VideoPlayerCore

extension SQLiteLibraryStore {
    // MARK: Filters

    /// Builds the WHERE clause for a filter. Always includes "i.version_count > 0" so the partial indexes apply, and
    /// "i.review = 0": files in Needs Review never show in Movies, Shows, search or saved views (docs/SORTING.md).
    func whereClause(_ f: ItemFilter) -> (sql: String, args: [SQLValue]) {
        var terms = ["i.version_count > 0", "i.review = 0"]
        var args: [SQLValue] = []

        func list(_ column: String, _ values: [Int]) {
            terms.append("\(column) IN (\(values.map(String.init).joined(separator: ",")))")
        }
        if !f.kinds.isEmpty { list("i.kind", f.kinds.map { Self.code($0) }) }
        if !f.genres.isEmpty {
            let marks = Array(repeating: "?", count: f.genres.count).joined(separator: ",")
            terms.append("EXISTS (SELECT 1 FROM item_genres g WHERE g.item_id = i.id AND g.genre IN (\(marks)))")
            args += f.genres.sorted().map { .text($0) }
        }
        if let y = f.yearMin { terms.append("i.year >= ? AND i.year > 0"); args.append(.int(Int64(y))) }
        if let y = f.yearMax { terms.append("i.year <= ? AND i.year > 0"); args.append(.int(Int64(y))) }
        if let r = f.minRating { terms.append("i.rating >= ? AND i.rating > 0"); args.append(.double(r)) }
        switch f.watch {
        case .unwatched?: terms.append("i.watched = 0")
        case .watched?: terms.append("i.watched = 1")
        case .inProgress?: terms.append("i.watched = 0 AND i.position > 0")
        case nil: break
        }
        if !f.resolutions.isEmpty { list("i.max_res", f.resolutions.map(\.rawValue)) }
        if !f.hdrFormats.isEmpty { terms.append("(i.hdr_mask & \(Self.hdrMask(f.hdrFormats))) != 0") }
        if let dv = f.dolbyVision { terms.append(dv ? "(i.hdr_mask & \(HDRFormat.dolbyVision.bit)) != 0" : "(i.hdr_mask & \(HDRFormat.dolbyVision.bit)) = 0") }
        if !f.dolbyVisionProfiles.isEmpty { terms.append("(i.dv_mask & \(Self.dvMask(f.dolbyVisionProfiles))) != 0") }
        if let a = f.dolbyAtmos { terms.append("i.atmos = \(a ? 1 : 0)") }
        if let c = f.minChannels { terms.append("i.max_channels >= \(c)") }
        if !f.containers.isEmpty { terms.append("(i.container_mask & \(Self.containerMask(f.containers))) != 0") }
        if let d = f.addedAfter { terms.append("i.added_at >= ?"); args.append(SQLValue(d)) }
        if f.favoritesOnly { terms.append("i.favorite = 1") }
        if let s = f.seriesID { terms.append("i.series_id = ?"); args.append(.int(s)) }
        if let s = f.season { terms.append("i.season = ?"); args.append(.int(Int64(s))) }
        if let scope = f.folder {
            var inner = "SELECT item_id FROM files WHERE source_id = ? AND removed_at IS NULL AND item_id IS NOT NULL"
            args.append(.text(scope.sourceID))
            if scope.recursive {
                if let b = LibraryPath.descendantBounds(of: scope.path) {
                    inner += " AND (parent = ? OR (parent >= ? AND parent < ?))"
                    args += [.text(scope.path), .text(b.lower), .text(b.upper)]
                }
            } else {
                inner += " AND parent = ?"
                args.append(.text(scope.path))
            }
            terms.append("i.id IN (\(inner))")
        }
        if let s = f.sourceID {
            terms.append("i.id IN (SELECT item_id FROM files WHERE source_id = ? AND removed_at IS NULL AND item_id IS NOT NULL)")
            args.append(.text(s))
        }
        if let text = f.text {
            for word in LibraryText.normalize(text).split(separator: " ") {
                terms.append("i.search LIKE ?")
                args.append(.text("%\(word)%"))
            }
        }
        return (terms.joined(separator: " AND "), args)
    }

    static func sortColumn(_ key: ItemSortKey) -> String {
        switch key {
        case .title: return "i.sort_title"
        case .year: return "i.year"
        case .rating: return "i.rating"
        case .added: return "i.added_at"
        case .lastPlayed: return "i.last_played"
        case .runtime: return "i.runtime"
        }
    }

    // MARK: Grid pages

    public func page(_ query: ItemQuery, limit: Int, after: ItemCursor?) throws -> ItemPage {
        guard limit > 0 else { return ItemPage(items: [], next: nil) }
        let (whereSQL, whereArgs) = whereClause(query.filter)
        let col = Self.sortColumn(query.sort.key)
        let isText = query.sort.key == .title
        let dir = query.sort.ascending ? "ASC" : "DESC"
        var sql = "SELECT \(Self.itemColumns), \(col) FROM items i WHERE \(whereSQL)"
        var args = whereArgs
        if let c = after {
            sql += " AND (\(col), i.id) \(query.sort.ascending ? ">" : "<") (?, ?)"
            args.append(isText ? SQLValue(c.text) : SQLValue(c.number))
            args.append(.int(c.id))
        }
        sql += " ORDER BY \(col) \(dir), i.id \(dir) LIMIT ?"
        args.append(.int(Int64(limit + 1)))
        var rows: [(LibraryItem, ItemCursor)] = try db.rows(sql, args, cached: false) { s in
            let item = Self.mapItem(s)
            let cursor = isText ? ItemCursor(text: s.text(29), number: nil, id: item.id) : ItemCursor(text: nil, number: s.double(29), id: item.id)
            return (item, cursor)
        }
        var next: ItemCursor?
        if rows.count > limit {
            rows.removeLast()
            next = rows.last?.1
        }
        return ItemPage(items: gated(rows.map(\.0)), next: next)
    }

    public func page(_ query: ItemQuery, limit: Int, offset: Int) throws -> [LibraryItem] {
        guard limit > 0 else { return [] }
        let (whereSQL, whereArgs) = whereClause(query.filter)
        let col = Self.sortColumn(query.sort.key)
        let dir = query.sort.ascending ? "ASC" : "DESC"
        let sql = "SELECT \(Self.itemColumns) FROM items i WHERE \(whereSQL) ORDER BY \(col) \(dir), i.id \(dir) LIMIT ? OFFSET ?"
        return gated(try db.rows(sql, whereArgs + [.int(Int64(limit)), .int(Int64(max(0, offset)))], cached: false, Self.mapItem))
    }

    public func count(_ query: ItemQuery) throws -> Int {
        let (whereSQL, args) = whereClause(query.filter)
        return try db.first("SELECT COUNT(*) FROM items i WHERE \(whereSQL)", args, cached: false) { $0.int(0) } ?? 0
    }

    public func alphabetIndex(_ query: ItemQuery) throws -> [AlphabetEntry] {
        guard query.sort.key == .title else { return [] }
        let (whereSQL, args) = whereClause(query.filter)
        var groups = try db.rows("SELECT i.letter, COUNT(*) FROM items i WHERE \(whereSQL) GROUP BY i.letter", args, cached: false) { ($0.text(0), $0.int(1)) }
        groups.sort { $0.0 < $1.0 }   // "#" sorts before "A"
        if !query.sort.ascending { groups.reverse() }
        var offset = 0
        return groups.map { g in
            defer { offset += g.1 }
            return AlphabetEntry(letter: g.0, offset: offset, count: g.1)
        }
    }

    // MARK: Home rows

    public func continueWatching(limit: Int, now: Date, retentionDays: Int) throws -> [LibraryItem] {
        if watchGateClosed { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return try db.rows(
            """
            SELECT \(Self.itemColumns) FROM items i
            WHERE i.version_count > 0 AND i.review = 0 AND i.watched = 0 AND i.position > 0 AND i.hidden = 0 AND i.last_played >= ?
            ORDER BY i.last_played DESC, i.id DESC LIMIT ?
            """,
            [SQLValue(cutoff), .int(Int64(limit))], Self.mapItem
        )
    }

    public func nextUp(limit: Int, now: Date, retentionDays: Int) throws -> [NextUpEntry] {
        if watchGateClosed { return [] }
        guard limit > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        struct Last { var series: Int64; var id: Int64; var season: Int; var episode: Int }
        let lasts: [Last] = try db.rows(
            """
            SELECT s.series_id, s.id, s.season, s.episode FROM items s
            WHERE s.kind = 1 AND s.watched = 1 AND s.season > 0 AND s.series_id IS NOT NULL AND s.last_played >= ?
              AND s.last_played = (SELECT MAX(w.last_played) FROM items w WHERE w.series_id = s.series_id AND w.kind = 1 AND w.watched = 1 AND w.season > 0)
            ORDER BY s.last_played DESC, s.id DESC
            """,
            [SQLValue(cutoff)]
        ) { Last(series: $0.int64(0), id: $0.int64(1), season: $0.int(2), episode: $0.int(3)) }

        var seen = Set<Int64>()
        var out: [NextUpEntry] = []
        for last in lasts where seen.insert(last.series).inserted {
            let inProgress = try db.first(
                "SELECT 1 FROM items WHERE series_id = ? AND watched = 0 AND position > 0 AND version_count > 0 LIMIT 1", [.int(last.series)]
            ) { $0.int(0) }
            if inProgress != nil { continue }
            let next = try db.first(
                """
                SELECT \(Self.itemColumns) FROM items i
                WHERE i.series_id = ? AND i.version_count > 0 AND i.watched = 0 AND i.season > 0 AND (i.season, i.episode) > (?, ?)
                ORDER BY i.season, i.episode, i.id LIMIT 1
                """,
                [.int(last.series), .int(Int64(last.season)), .int(Int64(last.episode))], Self.mapItem
            )
            if let next, !next.watch.hiddenFromContinue {
                out.append(NextUpEntry(item: next, afterEpisodeID: last.id))
                if out.count == limit { break }
            }
        }
        return out
    }

    public func recentlyAdded(limit: Int, kind: ItemKind?) throws -> [LibraryItem] {
        guard limit > 0 else { return [] }
        if let kind {
            return gated(try db.rows(
                "SELECT \(Self.itemColumns) FROM items i WHERE i.version_count > 0 AND i.review = 0 AND i.kind = ? ORDER BY i.added_at DESC, i.id DESC LIMIT ?",
                [.int(Int64(Self.code(kind))), .int(Int64(limit))], Self.mapItem
            ))
        }
        return gated(try db.rows(
            "SELECT \(Self.itemColumns) FROM items i WHERE i.version_count > 0 AND i.review = 0 ORDER BY i.added_at DESC, i.id DESC LIMIT ?",
            [.int(Int64(limit))], Self.mapItem
        ))
    }

    public func episodes(ofSeries seriesID: Int64) throws -> [LibraryItem] {
        gated(try db.rows(
            "SELECT \(Self.itemColumns) FROM items i WHERE i.series_id = ? AND i.version_count > 0 ORDER BY i.season, i.episode, i.id",
            [.int(seriesID)], Self.mapItem
        ))
    }

    // MARK: Direct file browsing

    public func children(sourceID: String, folder: String, sort: FileSort, limit: Int, offset: Int) throws -> [FolderChild] {
        guard limit > 0 else { return [] }
        let key: String
        switch sort.key {
        case .name: key = "name_key"
        case .dateModified: key = "modified"
        case .size: key = "size"
        case .kind: key = "kind"
        }
        let dir = sort.ascending ? "ASC" : "DESC"
        let sql = """
        SELECT path, name, isdir, size, modified, kind FROM (
            SELECT path, name, 1 AS isdir, NULL AS size, obs_modified AS modified, 5 AS kind, name_key FROM folders INDEXED BY idx_folders_parent
                WHERE source_id = ? AND parent = ? AND removed_at IS NULL
            UNION ALL
            SELECT path, name, 0, size, modified, kind, name_key FROM files
                WHERE source_id = ? AND parent = ? AND removed_at IS NULL
        ) ORDER BY isdir DESC, \(key) \(dir), name_key LIMIT ? OFFSET ?
        """
        let args: [SQLValue] = [.text(sourceID), .text(folder), .text(sourceID), .text(folder), .int(Int64(limit)), .int(Int64(max(0, offset)))]
        return try db.rows(sql, args, cached: false) { s in
            FolderChild(path: s.text(0), name: s.text(1), isDirectory: s.bool(2), size: s.optInt64(3), modified: s.optDate(4), kind: Self.fileKind(s.int(5)))
        }
    }

    /// Subtitles, artwork and NFO files that sit next to a video and start with its name.
    public func sidecars(for fileID: Int64) throws -> [StoredFile] {
        guard let video = try db.first("SELECT source_id, parent, name FROM files WHERE id = ?", [.int(fileID)], { ($0.text(0), $0.text(1), $0.text(2)) }) else {
            return []
        }
        let stem = LibraryPath.stem(video.2)
        return try db.rows(
            "\(Self.fileColumns) FROM files f WHERE f.source_id = ? AND f.parent = ? AND f.removed_at IS NULL AND f.kind IN (1, 2, 3) AND substr(f.name, 1, ?) = ? ORDER BY f.name_key",
            [.text(video.0), .text(video.1), .int(Int64(stem.count)), .text(stem)], Self.mapFile
        )
    }

    // MARK: Diagnostics

    /// The SQLite plan for a query string, for tests that check an index is used.
    func queryPlan(_ sql: String, _ args: [SQLValue] = []) throws -> [String] {
        try db.rows("EXPLAIN QUERY PLAN " + sql, args, cached: false) { $0.text(3) }
    }

    func gridPlan(_ query: ItemQuery) throws -> [String] {
        let (whereSQL, args) = whereClause(query.filter)
        let col = Self.sortColumn(query.sort.key)
        let dir = query.sort.ascending ? "ASC" : "DESC"
        return try queryPlan("SELECT \(Self.itemColumns) FROM items i WHERE \(whereSQL) ORDER BY \(col) \(dir), i.id \(dir) LIMIT 60", args)
    }
}
