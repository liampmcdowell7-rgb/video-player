import Foundation
import VideoPlayerCore
import UserData

/// Fraction of the runtime after which a stop counts as "watched" (Interpretation, PROVISIONAL).
public enum LibraryWatchRules {
    public static let watchedFraction = 0.95
}

/// The SQLite implementation of `LibraryStore` and `LibraryScanStore`.
///
/// Thread safety: this is an actor that owns the only connection to the database. Every call is serialized
/// on the actor, so callers on any thread or task can share one instance. Long reads (a page of a grid) take
/// a few milliseconds, so they never starve writes for long, but they do queue behind a folder being written.
public actor SQLiteLibraryStore: LibraryStore, LibraryScanStore {
    let db: SQLiteDatabase
    public nonisolated let path: String

    // User data that must survive a cleanup of Caches (docs/STORAGE_MODEL.md). Every watch-state and saved-view change is
    // written through to `recorder`; after a rebuild the restored state is loaded back (SQLiteLibraryStore+UserData.swift).
    var recorder: (any UserDataRecording)?
    /// While true every item reads as unwatched and the rows built on watch state are empty (a half-restored library must not show wrong marks).
    var watchGateClosed = false
    /// The time written on favourite, hidden and saved-view changes (a test sets a fake one).
    var clock: @Sendable () -> Date = { Date() }
    /// Restored watch state for items not scanned yet; applied when the item is created.
    var pendingWatch: [String: UDWatchValue] = [:]

    /// Opens or creates the database at `path` (":memory:" for a throwaway one) and upgrades its schema.
    /// `recorder` is where every watch-state and saved-view change is written through from the first call on. Passing it here
    /// (rather than calling `setRecorder` afterwards) is how a synchronous caller, such as the app's main-actor start-up, makes
    /// sure no change happens before the recorder is in place: `setRecorder` is actor-isolated and needs an `await`.
    public init(path: String, recorder: (any UserDataRecording)? = nil) throws {
        self.path = path
        self.recorder = recorder
        self.db = try SQLiteDatabase(path: path)
        try db.prepareLibrarySchema()
    }

    // MARK: Codes

    static func code(_ kind: FileKind) -> Int {
        switch kind {
        case .video: return 0
        case .subtitle: return 1
        case .image: return 2
        case .nfo: return 3
        case .other: return 4
        case .directory: return 5
        }
    }

    static func fileKind(_ code: Int) -> FileKind {
        switch code {
        case 0: return .video
        case 1: return .subtitle
        case 2: return .image
        case 3: return .nfo
        case 5: return .directory
        default: return .other
        }
    }

    static func code(_ kind: ItemKind) -> Int { kind == .movie ? 0 : 1 }

    static func hdrMask(_ set: Set<HDRFormat>) -> Int { set.reduce(0) { $0 | $1.bit } }
    static func hdrSet(_ mask: Int) -> Set<HDRFormat> { Set(HDRFormat.allCases.filter { mask & $0.bit != 0 }) }
    static func containerMask(_ set: Set<ContainerFormat>) -> Int { set.reduce(0) { $0 | $1.bit } }
    static func containerSet(_ mask: Int) -> Set<ContainerFormat> { Set(ContainerFormat.allCases.filter { mask & $0.bit != 0 }) }
    static func dvMask(_ profiles: Set<Int>) -> Int { profiles.reduce(0) { $0 | ((0...30).contains($1) ? (1 << $1) : 0) } }
    static func dvSet(_ mask: Int) -> Set<Int> { Set((0...30).filter { mask & (1 << $0) != 0 }) }

    // MARK: Sources

    public func upsertSource(_ source: LibrarySourceRecord) throws {
        try db.run(
            "INSERT INTO sources (id, kind, name, added_at) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET kind = excluded.kind, name = excluded.name",
            [.text(source.id), .text(source.kind.rawValue), .text(source.name), SQLValue(source.addedAt)]
        )
    }

    public func sources() throws -> [LibrarySourceRecord] {
        try db.rows("SELECT id, kind, name, added_at FROM sources ORDER BY added_at, id") { s in
            SourceKind(rawValue: s.text(1)).map { LibrarySourceRecord(id: s.text(0), kind: $0, name: s.text(2), addedAt: s.optDate(3) ?? Date(timeIntervalSince1970: 0)) }
        }.compactMap { $0 }
    }

    public func removeSource(id: String) throws {
        try db.transaction {
            let affected = try db.rows("SELECT DISTINCT item_id FROM files WHERE source_id = ? AND item_id IS NOT NULL", [.text(id)]) { $0.int64(0) }
            try db.run("DELETE FROM files WHERE source_id = ?", [.text(id)])
            try db.run("DELETE FROM folders WHERE source_id = ?", [.text(id)])
            try db.run("DELETE FROM scan_queue WHERE source_id = ?", [.text(id)])
            try db.run("DELETE FROM scans WHERE source_id = ?", [.text(id)])
            try db.run("DELETE FROM sources WHERE id = ?", [.text(id)])
            for item in affected { try refreshItem(item) }
            try deleteEmptyItems(among: affected, keepWatched: false)
        }
    }

    public func counts() throws -> LibraryCounts {
        LibraryCounts(
            items: try db.scalarInt("SELECT COUNT(*) FROM items WHERE version_count > 0 AND review = 0"),
            files: try db.scalarInt("SELECT COUNT(*) FROM files WHERE removed_at IS NULL"),
            folders: try db.scalarInt("SELECT COUNT(*) FROM folders WHERE removed_at IS NULL"),
            series: try db.scalarInt("SELECT COUNT(DISTINCT series_id) FROM items WHERE version_count > 0 AND series_id IS NOT NULL")
        )
    }

    // MARK: Item aggregates

    /// Recomputes what an item shows (best resolution, versions, formats...) from its live video files.
    func refreshItem(_ id: Int64) throws {
        struct Row { var id: Int64; var size: Int64; var res: Int; var hdr: Int; var dv: Int?; var channels: Int; var atmos: Bool; var container: Int?; var duration: Double; var firstSeen: Double }
        let rows = try db.rows(
            "SELECT id, size, res, hdr_mask, dv_profile, channels, atmos, container, duration, first_seen FROM files WHERE item_id = ? AND removed_at IS NULL AND kind = 0",
            [.int(id)]
        ) { s in
            Row(id: s.int64(0), size: s.optInt64(1) ?? 0, res: s.int(2), hdr: s.int(3), dv: s.optInt(4), channels: s.int(5), atmos: s.bool(6),
                container: s.optInt(7), duration: s.optDouble(8) ?? 0, firstSeen: s.double(9))
        }
        if rows.isEmpty {
            try db.run(
                "UPDATE items SET version_count = 0, effective_file_id = NULL, max_res = -1, hdr_mask = 0, dv_mask = 0, max_channels = 0, atmos = 0, container_mask = 0 WHERE id = ?",
                [.int(id)]
            )
            return
        }
        let best = rows.sorted { a, b in
            if a.res != b.res { return a.res > b.res }
            if a.size != b.size { return a.size > b.size }
            return a.id < b.id
        }
        let pref = try db.first("SELECT pref_file_id FROM items WHERE id = ?", [.int(id)]) { $0.optInt64(0) } ?? nil
        let effective = pref.flatMap { p in rows.contains { $0.id == p } ? p : nil } ?? best[0].id
        var hdr = 0, dv = 0, containers = 0
        for r in rows {
            hdr |= r.hdr
            if let p = r.dv, (0...30).contains(p) { dv |= 1 << p }
            if let c = r.container, c >= 0, c < 31 { containers |= 1 << c }
        }
        try db.run(
            """
            UPDATE items SET version_count = ?, effective_file_id = ?, max_res = ?, hdr_mask = ?, dv_mask = ?, max_channels = ?,
                atmos = ?, container_mask = ?, runtime = ?, added_at = ? WHERE id = ?
            """,
            [
                .int(Int64(rows.count)), .int(effective), .int(Int64(rows.map(\.res).max() ?? -1)), .int(Int64(hdr)), .int(Int64(dv)),
                .int(Int64(rows.map(\.channels).max() ?? 0)), SQLValue(rows.contains { $0.atmos }), .int(Int64(containers)),
                .double(rows.map(\.duration).max() ?? 0), .double(rows.map(\.firstSeen).min() ?? 0), .int(id),
            ]
        )
    }

    /// Deletes items that have no live files. With `keepWatched`, items with watch history stay so it survives
    /// a file being removed and coming back.
    func deleteEmptyItems(among ids: [Int64], keepWatched: Bool) throws {
        let guardSQL = keepWatched ? " AND play_count = 0 AND position = 0 AND favorite = 0 AND last_played = 0 AND watched = 0" : ""
        for id in ids {
            try db.run("DELETE FROM items WHERE id = ? AND version_count = 0\(guardSQL) AND NOT EXISTS (SELECT 1 FROM files WHERE item_id = ?)", [.int(id), .int(id)])
            try db.run("DELETE FROM item_genres WHERE item_id = ? AND NOT EXISTS (SELECT 1 FROM items WHERE id = ?)", [.int(id), .int(id)])
        }
    }

    // MARK: Versions and technical facts

    public func versions(of itemID: Int64) throws -> [StoredFile] {
        try db.rows(
            "\(Self.fileColumns) FROM files f WHERE f.item_id = ? AND f.removed_at IS NULL AND f.kind = 0 ORDER BY f.res DESC, f.size DESC, f.id",
            [.int(itemID)], Self.mapFile
        )
    }

    public func setPreferredVersion(itemID: Int64, fileID: Int64?) throws {
        try db.transaction {
            if let fileID {
                let owner = try db.first("SELECT item_id FROM files WHERE id = ? AND removed_at IS NULL", [.int(fileID)]) { $0.optInt64(0) } ?? nil
                guard owner == itemID else { throw LibraryIndexError.invalid("file \(fileID) is not a version of item \(itemID)") }
            }
            try db.run("UPDATE items SET pref_file_id = ? WHERE id = ?", [SQLValue(fileID), .int(itemID)])
            try refreshItem(itemID)
        }
    }

    public func setTechnicalInfo(fileID: Int64, _ info: FileTechnicalInfo) throws {
        try db.transaction {
            let owner = try db.first("SELECT item_id FROM files WHERE id = ?", [.int(fileID)]) { $0.optInt64(0) }
            guard let owner else { throw LibraryIndexError.notFound("file \(fileID)") }
            try db.run(
                """
                UPDATE files SET has_tech = 1, duration = ?, container = ?, width = ?, height = ?, res = ?, hdr_mask = ?, dv_profile = ?,
                    vcodec = ?, acodec = ?, channels = ?, atmos = ?, bitrate = ? WHERE id = ?
                """,
                Self.techArgs(info) + [.int(fileID)]
            )
            if let item = owner { try refreshItem(item) }
        }
    }

    static func techArgs(_ t: FileTechnicalInfo?) -> [SQLValue] {
        guard let t else {
            return [.null, .null, .null, .null, .int(-1), .int(0), .null, .null, .null, .int(0), .int(0), .null]
        }
        var hdr = hdrMask(t.hdrFormats)
        if t.dolbyVisionProfile != nil { hdr |= HDRFormat.dolbyVision.bit }
        return [
            SQLValue(t.duration), SQLValue(t.container?.rawValue), SQLValue(t.width), SQLValue(t.height),
            .int(Int64(t.resolution?.rawValue ?? -1)), .int(Int64(hdr)), SQLValue(t.dolbyVisionProfile),
            SQLValue(t.videoCodec), SQLValue(t.audioCodec), .int(Int64(t.audioChannels ?? 0)), SQLValue(t.hasAtmos), SQLValue(t.bitrate),
        ]
    }

    // MARK: Row mapping

    static let fileColumns = """
    SELECT f.id, f.source_id, f.path, f.name, f.parent, f.kind, f.size, f.modified, f.etag, f.token, f.item_id, f.first_seen, f.version_label,
           f.has_tech, f.duration, f.container, f.width, f.height, f.hdr_mask, f.dv_profile, f.vcodec, f.acodec, f.channels, f.atmos, f.bitrate,
           f.sort_signal, f.sort_note, f.sort_rev, f.sort_inputs, f.review
    """

    static func mapFile(_ s: SQLiteStatement) -> StoredFile {
        var tech: FileTechnicalInfo?
        if s.bool(13) {
            tech = FileTechnicalInfo(
                duration: s.optDouble(14), container: s.optInt(15).flatMap(ContainerFormat.init(rawValue:)),
                width: s.optInt(16), height: s.optInt(17), hdrFormats: hdrSet(s.int(18)), dolbyVisionProfile: s.optInt(19),
                videoCodec: s.optText(20), audioCodec: s.optText(21), audioChannels: s.int(22) > 0 ? s.int(22) : nil,
                hasAtmos: s.bool(23), bitrate: s.optInt64(24)
            )
        }
        return StoredFile(
            id: s.int64(0), sourceID: s.text(1), path: s.text(2), name: s.text(3), parentPath: s.text(4), kind: fileKind(s.int(5)),
            size: s.optInt64(6), modified: s.optDate(7), etag: s.optText(8), serverToken: s.optText(9), itemID: s.optInt64(10),
            technical: tech, firstSeen: s.optDate(11) ?? Date(timeIntervalSince1970: 0), versionLabel: s.optText(12),
            sort: s.optText(25).flatMap(SortSignal.init(rawValue:)).map {
                FileSortRecord(signal: $0, note: s.optText(26) ?? "", revision: s.int(27), inputs: s.optText(28) ?? "", needsReview: s.bool(29))
            }
        )
    }

    static let itemColumns = """
    i.id, i.kind, i.title, i.year, i.rating, i.series_id, i.series_title, i.season, i.episode, i.episode_end, i.tmdb_id, i.added_at,
    i.version_count, i.effective_file_id, i.max_res, i.hdr_mask, i.dv_mask, i.max_channels, i.atmos, i.container_mask, i.runtime,
    i.position, i.wduration, i.watched, i.play_count, i.last_played, i.favorite, i.hidden
    """

    static func mapItem(_ s: SQLiteStatement) -> LibraryItem {
        let year = s.int(3), rating = s.double(4), runtime = s.double(20), lastPlayed = s.double(25)
        return LibraryItem(
            id: s.int64(0), kind: s.int(1) == 0 ? .movie : .episode, title: s.text(2), year: year > 0 ? year : nil,
            rating: rating > 0 ? rating : nil, seriesID: s.optInt64(5), seriesTitle: s.optText(6), season: s.optInt(7),
            episode: s.optInt(8), episodeEnd: s.optInt(9), tmdbID: s.optInt(10), addedAt: s.optDate(11) ?? Date(timeIntervalSince1970: 0),
            versionCount: s.int(12), preferredFileID: s.optInt64(13), maxResolution: ResolutionClass(rawValue: s.int(14)),
            hdrFormats: hdrSet(s.int(15)), dolbyVisionProfiles: dvSet(s.int(16)), maxChannels: s.int(17) > 0 ? s.int(17) : nil,
            hasAtmos: s.bool(18), containers: containerSet(s.int(19)), runtime: runtime > 0 ? runtime : nil,
            watch: WatchState(
                position: s.double(21), duration: s.optDouble(22), watched: s.bool(23), playCount: s.int(24),
                lastPlayed: lastPlayed > 0 ? Date(timeIntervalSince1970: lastPlayed) : nil, favorite: s.bool(26), hiddenFromContinue: s.bool(27)
            )
        )
    }

    public func item(id: Int64) throws -> LibraryItem? {
        gated(try db.first("SELECT \(Self.itemColumns) FROM items i WHERE i.id = ?", [.int(id)], Self.mapItem))
    }

    // MARK: Metadata

    public func setMetadata(itemID: Int64, _ m: ItemMetadata) throws {
        try db.transaction {
            guard let current = try db.first("SELECT title, series_title, kind FROM items WHERE id = ?", [.int(itemID)], { ($0.text(0), $0.optText(1), $0.int(2)) }) else {
                throw LibraryIndexError.notFound("item \(itemID)")
            }
            if let title = m.title, !title.isEmpty {
                let search = LibraryText.normalize(title + " " + (current.1 ?? ""))
                if current.2 == 0 {
                    let sort = LibraryText.titleSortValue(title)
                    try db.run("UPDATE items SET title = ?, sort_title = ?, letter = ?, search = ? WHERE id = ?", [.text(title), .text(sort.value), .text(sort.letter), .text(search), .int(itemID)])
                } else {
                    try db.run("UPDATE items SET title = ?, search = ? WHERE id = ?", [.text(title), .text(search), .int(itemID)])
                }
            }
            if let y = m.year { try db.run("UPDATE items SET year = ? WHERE id = ?", [.int(Int64(max(0, y))), .int(itemID)]) }
            if let r = m.rating { try db.run("UPDATE items SET rating = ? WHERE id = ?", [.double(max(0, r)), .int(itemID)]) }
            if let t = m.tmdbID { try db.run("UPDATE items SET tmdb_id = ? WHERE id = ?", [.int(Int64(t)), .int(itemID)]) }
            if let genres = m.genres {
                try db.run("DELETE FROM item_genres WHERE item_id = ?", [.int(itemID)])
                for g in Set(genres.map { $0.trimmingCharacters(in: .whitespaces) }) where !g.isEmpty {
                    try db.run("INSERT OR IGNORE INTO item_genres (item_id, genre) VALUES (?, ?)", [.int(itemID), .text(g)])
                }
            }
        }
    }

    /// Many items in one transaction (what a metadata refresh over thousands of items uses).
    public func setMetadata(batch: [(itemID: Int64, metadata: ItemMetadata)]) throws {
        try db.transaction {
            for entry in batch { try setMetadata(itemID: entry.itemID, entry.metadata) }
        }
    }

    // MARK: Watch state

    public func updateProgress(itemID: Int64, position: Double, duration: Double?, at date: Date) throws {
        try db.transaction {
            guard let known = try db.first("SELECT wduration, watched, play_count FROM items WHERE id = ?", [.int(itemID)], { ($0.optDouble(0), $0.bool(1), $0.int(2)) }) else {
                throw LibraryIndexError.notFound("item \(itemID)")
            }
            let total = duration ?? known.0
            let t = date.timeIntervalSince1970
            if let total, total > 0, position >= total * LibraryWatchRules.watchedFraction {
                try db.run(
                    "UPDATE items SET watched = 1, position = 0, wduration = ?, play_count = ?, last_played = ?, hidden = 0 WHERE id = ?",
                    [SQLValue(total), .int(Int64(known.2 + 1)), .double(t), .int(itemID)]
                )
            } else {
                try db.run(
                    "UPDATE items SET watched = 0, position = ?, wduration = ?, last_played = ?, hidden = 0 WHERE id = ?",
                    [.double(max(0, position)), SQLValue(total), .double(t), .int(itemID)]
                )
            }
            try recordWatchChange(itemID, reset: false, at: date)
        }
    }

    public func markWatched(itemIDs: [Int64], watched: Bool, at date: Date) throws {
        try db.transaction {
            for id in itemIDs { try setWatched(id, watched, date) }
        }
    }

    func setWatched(_ id: Int64, _ watched: Bool, _ date: Date) throws {
        if watched {
            try db.run(
                "UPDATE items SET play_count = play_count + (CASE WHEN watched = 0 THEN 1 ELSE 0 END), watched = 1, position = 0, last_played = ?, hidden = 0 WHERE id = ?",
                [.double(date.timeIntervalSince1970), .int(id)]
            )
        } else {
            try db.run("UPDATE items SET watched = 0, position = 0, play_count = 0, last_played = 0, hidden = 0 WHERE id = ?", [.int(id)])
        }
        try recordWatchChange(id, reset: !watched, at: date)
    }

    public func markSeries(seriesID: Int64, season: Int?, watched: Bool, at date: Date) throws {
        try db.transaction {
            let ids: [Int64]
            if let season {
                ids = try db.rows("SELECT id FROM items WHERE series_id = ? AND season = ? AND version_count > 0", [.int(seriesID), .int(Int64(season))]) { $0.int64(0) }
            } else {
                ids = try db.rows("SELECT id FROM items WHERE series_id = ? AND version_count > 0", [.int(seriesID)]) { $0.int64(0) }
            }
            for id in ids { try setWatched(id, watched, date) }
        }
    }

    public func setFavorite(itemID: Int64, favorite: Bool) throws {
        try db.run("UPDATE items SET favorite = ? WHERE id = ?", [SQLValue(favorite), .int(itemID)])
        if let recorder, let key = try itemKey(itemID) { recorder.recordFavorite(key: key, favorite: favorite, at: clock()) }
    }

    public func hideFromContinue(itemID: Int64, hidden: Bool) throws {
        try db.run("UPDATE items SET hidden = ? WHERE id = ?", [SQLValue(hidden), .int(itemID)])
        if let recorder, let key = try itemKey(itemID) { recorder.recordHidden(key: key, hidden: hidden, at: clock()) }
    }

    // MARK: Saved views

    private static let viewColumns = "id, name, scope_kind, scope_source, scope_path, query, pinned, position, created_at"

    private static func mapView(_ s: SQLiteStatement) throws -> SavedView {
        let scope: ViewScope = s.int(2) == 0 ? .library : .folder(sourceID: s.text(3), path: s.text(4))
        let query = try JSONDecoder().decode(ItemQuery.self, from: Data(s.text(5).utf8))
        return SavedView(
            id: s.int64(0), name: s.text(1), scope: scope, query: query, pinned: s.bool(6), position: s.int(7),
            createdAt: s.optDate(8) ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func scopeArgs(_ scope: ViewScope) -> [SQLValue] {
        switch scope {
        case .library: return [.int(0), .text(""), .text("")]
        case let .folder(source, path): return [.int(1), .text(source), .text(path)]
        }
    }

    private static func encode(_ query: ItemQuery) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(query), as: UTF8.self)
    }

    public func saveView(name: String, scope: ViewScope, query: ItemQuery, pinned: Bool) throws -> SavedView {
        try db.transaction {
            let args = Self.scopeArgs(scope)
            let position = (try db.first("SELECT MAX(position) FROM views WHERE scope_kind = ? AND scope_source = ? AND scope_path = ?", args) { $0.optInt(0) } ?? nil).map { $0 + 1 } ?? 0
            let now = clock()
            let uid = UUID().uuidString.lowercased()
            try db.run(
                "INSERT INTO views (name, scope_kind, scope_source, scope_path, query, pinned, position, created_at, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [.text(name)] + args + [.text(try Self.encode(query)), SQLValue(pinned), .int(Int64(position)), SQLValue(now), .text(uid)]
            )
            let saved = SavedView(id: db.lastInsertRowID, name: name, scope: scope, query: query, pinned: pinned, position: position, createdAt: now)
            try recordView(saved, uid: uid, at: now)
            return saved
        }
    }

    public func updateView(_ view: SavedView) throws {
        let n = try db.run(
            "UPDATE views SET name = ?, scope_kind = ?, scope_source = ?, scope_path = ?, query = ?, pinned = ?, position = ? WHERE id = ?",
            [.text(view.name)] + Self.scopeArgs(view.scope) + [.text(try Self.encode(view.query)), SQLValue(view.pinned), .int(Int64(view.position)), .int(view.id)]
        )
        if n == 0 { throw LibraryIndexError.notFound("view \(view.id)") }
        if let uid = try db.first("SELECT uid FROM views WHERE id = ?", [.int(view.id)], { $0.optText(0) }) ?? nil {
            try recordView(view, uid: uid, at: clock())
        }
    }

    public func deleteView(id: Int64) throws {
        let uid = try db.first("SELECT uid FROM views WHERE id = ?", [.int(id)], { $0.optText(0) }) ?? nil
        try db.run("DELETE FROM views WHERE id = ?", [.int(id)])
        if let uid, let recorder { recorder.recordViewDeleted(uid: uid, at: clock()) }
    }

    public func views(scope: ViewScope) throws -> [SavedView] {
        try db.rows(
            "SELECT \(Self.viewColumns) FROM views WHERE scope_kind = ? AND scope_source = ? AND scope_path = ? ORDER BY position, id",
            Self.scopeArgs(scope), Self.mapView
        )
    }

    public func pinnedViews() throws -> [SavedView] {
        try db.rows("SELECT \(Self.viewColumns) FROM views WHERE pinned = 1 ORDER BY position, id", [], Self.mapView)
    }

    // MARK: Maintenance

    /// Folds the write-ahead log into the main file (so the file size on disk is the real size).
    public func checkpoint() throws {
        try db.exec("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    /// "ok" when SQLite finds nothing wrong.
    public func integrityCheck() throws -> String {
        try db.first("PRAGMA integrity_check") { $0.text(0) } ?? "no result"
    }

    public func schemaVersion() throws -> Int { try db.scalarInt("PRAGMA user_version") }
}
