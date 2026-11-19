import Foundation
import VideoPlayerCore

extension SQLiteLibraryStore {
    // MARK: Scan lifecycle

    public func beginScan(sourceID: String, roots: [String], options: ScanOptions, resume: Bool, now: Date) throws -> ScanTicket {
        try db.transaction {
            let rootsText = roots.sorted().joined(separator: "\n")
            struct Open { var id: Int64; var roots: String; var recursive: Bool; var trust: Bool }
            let open = try db.rows(
                """
                SELECT id, roots, recursive, trust FROM scans
                WHERE source_id = ? AND status != 'completed'
                  AND EXISTS (SELECT 1 FROM scan_queue q WHERE q.scan_id = scans.id AND q.done = 0)
                ORDER BY id DESC
                """,
                [.text(sourceID)]
            ) { Open(id: $0.int64(0), roots: $0.text(1), recursive: $0.bool(2), trust: $0.bool(3)) }
            let matching = open.filter { $0.roots == rootsText && $0.recursive == options.recursive && $0.trust == options.trustFolderVersions }

            if resume, let found = matching.first {
                try db.run("UPDATE scans SET status = 'running' WHERE id = ?", [.int(found.id)])
                return ScanTicket(scanID: found.id, resumed: true, pendingFolders: try pendingCount(found.id))
            }
            for stale in matching {
                try db.run("DELETE FROM scan_queue WHERE scan_id = ?", [.int(stale.id)])
                try db.run("UPDATE scans SET status = 'cancelled', finished_at = ? WHERE id = ?", [SQLValue(now), .int(stale.id)])
            }
            try db.run(
                "INSERT INTO scans (source_id, roots, recursive, trust, status, started_at) VALUES (?, ?, ?, ?, 'running', ?)",
                [.text(sourceID), .text(rootsText), SQLValue(options.recursive), SQLValue(options.trustFolderVersions), SQLValue(now)]
            )
            let id = db.lastInsertRowID
            for root in roots {
                try db.run("INSERT OR IGNORE INTO scan_queue (scan_id, source_id, path) VALUES (?, ?, ?)", [.int(id), .text(sourceID), .text(root)])
            }
            return ScanTicket(scanID: id, resumed: false, pendingFolders: try pendingCount(id))
        }
    }

    private func pendingCount(_ scanID: Int64) throws -> Int {
        try db.scalarInt("SELECT COUNT(*) FROM scan_queue WHERE scan_id = ? AND done = 0", [.int(scanID)])
    }

    public func scan(id: Int64) throws -> ScanRecord? {
        try db.first("SELECT id, source_id, status, started_at, finished_at, folders_done FROM scans WHERE id = ?", [.int(id)]) { s in
            ScanRecord(
                id: s.int64(0), sourceID: s.text(1), status: ScanStatus(rawValue: s.text(2)) ?? .interrupted,
                startedAt: s.optDate(3) ?? Date(timeIntervalSince1970: 0), finishedAt: s.optDate(4), foldersDone: s.int(5), foldersPending: 0
            )
        }.map { var r = $0; r.foldersPending = (try? pendingCount(id)) ?? 0; return r }
    }

    /// The most recent scan of a source that stopped before finishing its queue.
    public func unfinishedScan(sourceID: String) throws -> ScanRecord? {
        let id = try db.first(
            """
            SELECT id FROM scans WHERE source_id = ? AND status != 'completed'
              AND EXISTS (SELECT 1 FROM scan_queue q WHERE q.scan_id = scans.id AND q.done = 0) ORDER BY id DESC LIMIT 1
            """,
            [.text(sourceID)]
        ) { $0.int64(0) }
        guard let id else { return nil }
        return try scan(id: id)
    }

    public func nextFolder(scanID: Int64) throws -> PendingFolder? {
        try db.first(
            """
            SELECT q.path, f.obs_etag, f.obs_modified, f.obs_size, f.obs_token, COALESCE(f.empty_strikes, 0),
                   (SELECT COUNT(*) FROM (SELECT 1 FROM files WHERE source_id = q.source_id AND parent = q.path AND removed_at IS NULL LIMIT 1))
                 + (SELECT COUNT(*) FROM (SELECT 1 FROM folders INDEXED BY idx_folders_parent WHERE source_id = q.source_id AND parent = q.path AND removed_at IS NULL LIMIT 1))
            FROM scan_queue q LEFT JOIN folders f ON f.source_id = q.source_id AND f.path = q.path
            WHERE q.scan_id = ? AND q.done = 0 ORDER BY q.id LIMIT 1
            """,
            [.int(scanID)]
        ) { s in
            PendingFolder(
                path: s.text(0), observed: FileVersion(etag: s.optText(1), modified: s.optDate(2), size: s.optInt64(3), serverToken: s.optText(4)),
                emptyStrikes: s.int(5), storedEntryCount: s.int(6)
            )
        }
    }

    public func storedFiles(sourceID: String, folder: String) throws -> [StoredFile] {
        try db.rows(
            "\(Self.fileColumns) FROM files f WHERE f.source_id = ? AND f.parent = ? AND f.removed_at IS NULL",
            [.text(sourceID), .text(folder)], cached: false, Self.mapFile
        )
    }

    public func storedChildFolders(sourceID: String, folder: String) throws -> [String] {
        try db.rows("SELECT path FROM folders INDEXED BY idx_folders_parent WHERE source_id = ? AND parent = ? AND removed_at IS NULL", [.text(sourceID), .text(folder)], cached: false) { $0.text(0) }
    }

    public func finishScan(scanID: Int64, status: ScanStatus, now: Date) throws {
        try db.transaction {
            try db.run("UPDATE scans SET status = ?, finished_at = ? WHERE id = ?", [.text(status.rawValue), SQLValue(now), .int(scanID)])
            if status == .completed { try db.run("DELETE FROM scan_queue WHERE scan_id = ?", [.int(scanID)]) }
        }
    }

    public func recordFailure(scanID: Int64, sourceID: String, folder: String, message: String, now: Date) throws {
        try db.transaction {
            let name = folder.split(separator: "/").last.map(String.init) ?? ""
            try db.run(
                """
                INSERT INTO folders (source_id, path, name, name_key, parent, last_error, last_scanned) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_id, path) DO UPDATE SET last_error = excluded.last_error, last_scanned = excluded.last_scanned
                """,
                [.text(sourceID), .text(folder), .text(name), .text(LibraryText.sortKey(name, dropArticle: false)), .text(LibraryPath.parent(of: folder)), .text(message), SQLValue(now)]
            )
            try db.run("UPDATE scan_queue SET done = 1 WHERE scan_id = ? AND path = ?", [.int(scanID), .text(folder)])
            try db.run("UPDATE scans SET folders_done = folders_done + 1 WHERE id = ?", [.int(scanID)])
        }
    }

    /// The error recorded the last time a folder could not be listed (nil when it listed fine).
    public func lastError(sourceID: String, folder: String) throws -> String? {
        (try db.first("SELECT last_error FROM folders WHERE source_id = ? AND path = ?", [.text(sourceID), .text(folder)]) { $0.optText(0) }) ?? nil
    }

    public func folderRecord(sourceID: String, path: String) throws -> StoredFolder? {
        try db.first(
            """
            SELECT obs_etag, obs_modified, obs_size, obs_token, scan_etag, scan_modified, scan_size, scan_token, scanned, empty_strikes, last_error, last_scanned
            FROM folders WHERE source_id = ? AND path = ? AND removed_at IS NULL
            """,
            [.text(sourceID), .text(path)]
        ) { s in
            StoredFolder(
                sourceID: sourceID, path: path,
                observed: FileVersion(etag: s.optText(0), modified: s.optDate(1), size: s.optInt64(2), serverToken: s.optText(3)),
                scanned: s.bool(8) ? FileVersion(etag: s.optText(4), modified: s.optDate(5), size: s.optInt64(6), serverToken: s.optText(7)) : nil,
                emptyStrikes: s.int(9), lastError: s.optText(10), lastScanned: s.optDate(11)
            )
        }
    }

    // MARK: Applying one folder

    public func apply(_ c: FolderChange, scanID: Int64) throws -> FolderApplyResult {
        try db.transaction {
            guard let scan = try db.first("SELECT recursive, trust FROM scans WHERE id = ?", [.int(scanID)], { ($0.bool(0), $0.bool(1)) }) else {
                throw LibraryIndexError.notFound("scan \(scanID)")
            }
            var result = FolderApplyResult()
            var touched = Set<Int64>()
            let nowT = c.now.timeIntervalSince1970
            let v = c.scannedVersion

            let selfName = c.path.split(separator: "/").last.map(String.init) ?? ""
            try db.run(
                """
                INSERT INTO folders (source_id, path, name, name_key, parent, obs_etag, obs_modified, obs_size, obs_token,
                                     scan_etag, scan_modified, scan_size, scan_token, scanned, empty_strikes, last_error, last_scanned)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, NULL, ?)
                ON CONFLICT(source_id, path) DO UPDATE SET
                    scan_etag = excluded.scan_etag, scan_modified = excluded.scan_modified, scan_size = excluded.scan_size, scan_token = excluded.scan_token,
                    scanned = 1, empty_strikes = excluded.empty_strikes, last_error = NULL, last_scanned = excluded.last_scanned, removed_at = NULL
                """,
                [.text(c.sourceID), .text(c.path), .text(selfName), .text(LibraryText.sortKey(selfName, dropArticle: false)), .text(LibraryPath.parent(of: c.path))]
                    + Self.versionArgs(v) + Self.versionArgs(v) + [.int(Int64(c.emptyStrikes)), .double(nowT)]
            )

            if !c.holdRemovals {
                for path in c.removedFilePaths {
                    if try tombstoneFile(c.sourceID, path, nowT, &touched) { result.removed += 1 }
                }
                for path in c.removedFolderPaths {
                    let (n, ids) = try tombstoneFolderTree(c.sourceID, path, nowT)
                    touched.formUnion(ids)
                    result.removed += n
                }
            }

            for child in c.childFolders {
                let existing = try db.first(
                    "SELECT scan_etag, scan_modified, scan_size, scan_token, scanned, last_error, removed_at FROM folders WHERE source_id = ? AND path = ?",
                    [.text(c.sourceID), .text(child.path)]
                ) { s in
                    (scanned: s.bool(4) ? FileVersion(etag: s.optText(0), modified: s.optDate(1), size: s.optInt64(2), serverToken: s.optText(3)) : nil,
                     failed: !s.isNull(5), removed: !s.isNull(6))
                }
                try db.run(
                    """
                    INSERT INTO folders (source_id, path, name, name_key, parent, obs_etag, obs_modified, obs_size, obs_token) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(source_id, path) DO UPDATE SET
                        name = excluded.name, name_key = excluded.name_key, parent = excluded.parent,
                        obs_etag = excluded.obs_etag, obs_modified = excluded.obs_modified, obs_size = excluded.obs_size, obs_token = excluded.obs_token, removed_at = NULL
                    """,
                    [.text(c.sourceID), .text(child.path), .text(child.name), .text(LibraryText.sortKey(child.name, dropArticle: false)), .text(c.path)] + Self.versionArgs(child.version)
                )
                guard scan.0 else { continue }
                var enqueue = true
                if scan.1, let existing, !existing.failed, !existing.removed, let scanned = existing.scanned {
                    enqueue = child.version.isSame(as: scanned) != true
                }
                if enqueue {
                    result.queuedFolders += try db.run("INSERT OR IGNORE INTO scan_queue (scan_id, source_id, path) VALUES (?, ?, ?)", [.int(scanID), .text(c.sourceID), .text(child.path)])
                }
            }

            var itemCache: [String: Int64] = [:]
            for u in c.upserts {
                let existing = try db.first("SELECT id, item_id, removed_at FROM files WHERE source_id = ? AND path = ?", [.text(c.sourceID), .text(u.path)]) {
                    (id: $0.int64(0), item: $0.optInt64(1), removed: !$0.isNull(2))
                }
                var itemID: Int64?
                if let seed = u.seed { itemID = try findOrCreateItem(seed, firstSeen: min(nowT, u.modified?.timeIntervalSince1970 ?? nowT), cache: &itemCache) }
                let name = u.name
                let common: [SQLValue] = [
                    .text(name), .text(LibraryText.sortKey(name, dropArticle: false)), .text(LibraryPath.parent(of: u.path)),
                    .int(Int64(Self.code(u.kind))), SQLValue(u.size), SQLValue(u.modified), SQLValue(u.etag), SQLValue(u.serverToken),
                    SQLValue(itemID), SQLValue(u.seed?.versionLabel), SQLValue(u.technical != nil),
                ] + Self.techArgs(u.technical) + Self.sortArgs(u.sort) + [SQLValue(u.seed?.seriesYear)]
                if let existing {
                    try db.run(
                        """
                        UPDATE files SET name = ?, name_key = ?, parent = ?, kind = ?, size = ?, modified = ?, etag = ?, token = ?, item_id = ?, version_label = ?,
                            has_tech = ?, duration = ?, container = ?, width = ?, height = ?, res = ?, hdr_mask = ?, dv_profile = ?, vcodec = ?, acodec = ?,
                            channels = ?, atmos = ?, bitrate = ?, sort_signal = ?, sort_note = ?, sort_rev = ?, sort_inputs = ?, review = ?,
                            series_year = ?, shared_name = NULL, removed_at = NULL WHERE id = ?
                        """,
                        common + [.int(existing.id)]
                    )
                    if let old = existing.item { touched.insert(old) }
                    if existing.removed { result.added += 1 } else { result.changed += 1 }
                } else {
                    try db.run(
                        """
                        INSERT INTO files (name, name_key, parent, kind, size, modified, etag, token, item_id, version_label,
                            has_tech, duration, container, width, height, res, hdr_mask, dv_profile, vcodec, acodec, channels, atmos, bitrate,
                            sort_signal, sort_note, sort_rev, sort_inputs, review, series_year,
                            source_id, path, first_seen)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        common + [.text(c.sourceID), .text(u.path), .double(min(nowT, u.modified?.timeIntervalSince1970 ?? nowT))]
                    )
                    result.added += 1
                }
                if let itemID { touched.insert(itemID) }
            }
            // Same show name, different years (addendum #18 D): settle every show this change touched.
            for base in try baseSeriesKeys(ofItems: touched) { touched.formUnion(try reconcileShowYears(base: base)) }
            for id in touched { try refreshItem(id) }

            try db.run("UPDATE scan_queue SET done = 1 WHERE scan_id = ? AND path = ?", [.int(scanID), .text(c.path)])
            try db.run("UPDATE scans SET folders_done = folders_done + 1 WHERE id = ?", [.int(scanID)])
            return result
        }
    }

    static func sortArgs(_ s: FileSortRecord?) -> [SQLValue] {
        guard let s else { return [.null, .null, .int(0), .text(""), .int(0)] }
        return [.text(s.signal.rawValue), .text(s.note), .int(Int64(s.revision)), .text(s.inputs), SQLValue(s.needsReview)]
    }

    static func versionArgs(_ v: FileVersion) -> [SQLValue] {
        [SQLValue(v.etag), SQLValue(v.modified), SQLValue(v.size), SQLValue(v.serverToken)]
    }

    /// Marks one file removed. Returns false when there was no live file at that path.
    private func tombstoneFile(_ source: String, _ path: String, _ now: Double, _ touched: inout Set<Int64>) throws -> Bool {
        let row = try db.first("SELECT item_id FROM files WHERE source_id = ? AND path = ? AND removed_at IS NULL", [.text(source), .text(path)]) { $0.optInt64(0) }
        guard let row else { return false }
        if let item = row { touched.insert(item) }
        try db.run("UPDATE files SET removed_at = ? WHERE source_id = ? AND path = ? AND removed_at IS NULL", [.double(now), .text(source), .text(path)])
        return true
    }

    /// Marks a folder and everything below it as removed. Returns the number of files and folders removed and the items touched.
    private func tombstoneFolderTree(_ source: String, _ path: String, _ now: Double) throws -> (Int, [Int64]) {
        guard let b = LibraryPath.descendantBounds(of: path) else { return (0, []) }
        var removed = 0
        let items = try db.rows(
            "SELECT DISTINCT item_id FROM files WHERE source_id = ? AND removed_at IS NULL AND item_id IS NOT NULL AND (parent = ? OR (parent >= ? AND parent < ?))",
            [.text(source), .text(path), .text(b.lower), .text(b.upper)]
        ) { $0.int64(0) }
        removed += try db.run(
            "UPDATE files SET removed_at = ? WHERE source_id = ? AND removed_at IS NULL AND (parent = ? OR (parent >= ? AND parent < ?))",
            [.double(now), .text(source), .text(path), .text(b.lower), .text(b.upper)]
        )
        removed += try db.run(
            "UPDATE folders SET removed_at = ? WHERE source_id = ? AND removed_at IS NULL AND (path = ? OR (path >= ? AND path < ?))",
            [.double(now), .text(source), .text(path), .text(b.lower), .text(b.upper)]
        )
        return (removed, items)
    }

    // MARK: Items and series

    private func findOrCreateItem(_ seed: ItemSeed, firstSeen: Double, cache: inout [String: Int64]) throws -> Int64 {
        if let id = cache[seed.key] { return id }
        if let id = try db.first("SELECT id FROM items WHERE key = ?", [.text(seed.key)], { $0.int64(0) }) {
            cache[seed.key] = id
            return id
        }
        var seriesID: Int64?
        if let key = seed.seriesKey, let title = seed.seriesTitle {
            seriesID = try db.first("SELECT id FROM series WHERE key = ?", [.text(key)], { $0.int64(0) })
            if seriesID == nil {
                try db.run("INSERT INTO series (key, title) VALUES (?, ?)", [.text(key), .text(title)])
                seriesID = db.lastInsertRowID
            }
        }
        let title: String
        let sort: (value: String, letter: String)
        if seed.kind == .episode {
            title = seed.title.isEmpty ? "S\(Self.pad2(seed.season ?? 0))E\(Self.pad2(seed.episode ?? 0))" : seed.title
            let base = LibraryText.titleSortValue(seed.seriesTitle ?? title)
            sort = (base.value + " " + Self.pad4(seed.season ?? 0) + " " + Self.pad4(seed.episode ?? 0), base.letter)
        } else {
            title = seed.title
            sort = LibraryText.titleSortValue(title)
        }
        let search = LibraryText.normalize(title + " " + (seed.seriesTitle ?? ""))
        try db.run(
            """
            INSERT INTO items (key, kind, title, sort_title, letter, search, year, series_id, series_title, season, episode, episode_end, tmdb_id, added_at, review)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(seed.key), .int(Int64(Self.code(seed.kind))), .text(title), .text(sort.value), .text(sort.letter), .text(search),
                .int(Int64(seed.year ?? 0)), SQLValue(seriesID), SQLValue(seed.seriesTitle), SQLValue(seed.season), SQLValue(seed.episode),
                SQLValue(seed.episodeEnd), SQLValue(seed.tmdbID), .double(firstSeen), SQLValue(seed.needsReview),
            ]
        )
        let id = db.lastInsertRowID
        try applyPendingWatch(itemID: id, key: seed.key)
        cache[seed.key] = id
        return id
    }

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    private static func pad4(_ n: Int) -> String { String(repeating: "0", count: max(0, 4 - String(n).count)) + String(n) }

    // MARK: Purging

    public func purgeRemoved(olderThan: Date) throws -> Int {
        try db.transaction {
            let cutoff = SQLValue(olderThan)
            let items = try db.rows("SELECT DISTINCT item_id FROM files WHERE removed_at IS NOT NULL AND removed_at < ? AND item_id IS NOT NULL", [cutoff]) { $0.int64(0) }
            var n = try db.run("DELETE FROM files WHERE removed_at IS NOT NULL AND removed_at < ?", [cutoff])
            n += try db.run("DELETE FROM folders WHERE removed_at IS NOT NULL AND removed_at < ?", [cutoff])
            try deleteEmptyItems(among: items, keepWatched: true)
            return n
        }
    }
}
