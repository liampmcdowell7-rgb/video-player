import Foundation
import VideoPlayerCore
import UserData

// The part of the store that deals with user data (docs/STORAGE_MODEL.md): this SQLite file is a rebuildable cache that
// the system may delete, so watch state and saved views are written through to a recorder as they change, and restored
// from it after a rebuild. Items are matched by `items.key`, which is derived from the file name and stays the same when
// the index is rebuilt (integer ids do not).

extension SQLiteLibraryStore {
    // MARK: Wiring

    /// Starts writing every watch-state and saved-view change through to `recorder` (nil stops).
    public func setClock(_ clock: @escaping @Sendable () -> Date) { self.clock = clock }

    public func setRecorder(_ recorder: (any UserDataRecording)?) {
        self.recorder = recorder
    }

    /// Hides watch state until `openWatchGate()`. Every item reads as unwatched, Continue Watching and Next Up are empty.
    /// (Filters and sorts on watch state still read the database; the screens hide those controls while rebuilding.)
    public func closeWatchGate() { watchGateClosed = true }
    public func openWatchGate() { watchGateClosed = false }
    public var isWatchGateClosed: Bool { watchGateClosed }

    /// R458: the rule of which titles show (`LibraryRestrictions`); every query below reads it.
    public func setRestrictions(_ value: LibraryRestrictions) { restrictions = value }
    public var currentRestrictions: LibraryRestrictions { restrictions }

    /// R459: titles whose rating has not been read yet (nothing kept in the library), whatever the restrictions say: the reading
    /// pass needs the ones the rule hides. Not part of the library's lists; only the rating pass calls it.
    public func itemsWithoutRating(after id: Int64, limit: Int) throws -> [LibraryItem] {
        try db.rows("SELECT \(Self.itemColumns) FROM items i WHERE i.version_count > 0 AND i.review = 0 AND i.content_rating IS NULL AND i.id > ? ORDER BY i.id LIMIT ?",
                    [.int(id), .int(Int64(max(1, limit)))], Self.mapItem)
    }

    /// Items created from now on take their watch state from the restored data. Cleared when the rescan has finished.
    public func clearPendingRestore() { pendingWatch = [:] }
    public var pendingRestoreCount: Int { pendingWatch.count }

    func gated(_ items: [LibraryItem]) -> [LibraryItem] {
        guard watchGateClosed else { return items }
        return items.map { var i = $0; i.watch = .none; return i }
    }

    func gated(_ item: LibraryItem?) -> LibraryItem? {
        guard watchGateClosed, var i = item else { return item }
        i.watch = .none
        return i
    }

    // MARK: Write-through

    public func itemKey(_ id: Int64) throws -> String? {
        try db.first("SELECT key FROM items WHERE id = ?", [.int(id)]) { $0.text(0) }
    }

    /// The item a recorded key belongs to (the recorder only sees keys; R309 needs the item's files to reach the server).
    public func itemID(forKey key: String) throws -> Int64? {
        try db.first("SELECT id FROM items WHERE key = ?", [.text(key)]) { $0.int64(0) }
    }

    static func watchValue(_ s: SQLiteStatement, from index: Int32) -> UDWatchValue {
        let lastPlayed = s.double(index + 4)
        return UDWatchValue(
            position: s.double(index), duration: s.optDouble(index + 1), watched: s.bool(index + 2), playCount: s.int(index + 3),
            lastPlayed: lastPlayed > 0 ? Date(timeIntervalSince1970: lastPlayed) : nil, favorite: s.bool(index + 5), hidden: s.bool(index + 6)
        )
    }

    /// Reads the item as it is now and records it. `reset` marks an "unwatch" (a new play-count epoch).
    func recordWatchChange(_ id: Int64, reset: Bool, at date: Date) throws {
        guard let recorder else { return }
        let row = try db.first("SELECT key, position, wduration, watched, play_count, last_played, favorite, hidden FROM items WHERE id = ?", [.int(id)]) { s in
            (s.text(0), Self.watchValue(s, from: 1))
        }
        guard let (key, value) = row else { return }
        if reset { recorder.recordReset(key: key, duration: value.duration, at: date) } else { recorder.recordProgress(key: key, value, at: date) }
    }

    func recordView(_ view: SavedView, uid: String, at date: Date) throws {
        guard let recorder else { return }
        let (scopeKind, source, path) = view.scope.stored
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let query = String(decoding: try encoder.encode(view.query), as: UTF8.self)
        recorder.recordView(
            UDViewValue(uid: uid, name: view.name, scopeKind: scopeKind, scopeSource: source, scopePath: path, query: query,
                        pinned: view.pinned, position: view.position, createdAt: view.createdAt), at: date)
    }

    // MARK: Restore

    /// Puts restored user data into this database. Watch state is applied to items that exist and remembered for items the
    /// rescan creates later. Saved views are matched by uid: missing ones are created, changed ones updated, deleted ones removed.
    public func restoreUserData(watch: [(key: String, value: UDWatchValue)], views: [UDViewValue], deletedViewUIDs: [String]) throws {
        try db.transaction {
            for entry in watch {
                pendingWatch[entry.key] = entry.value
                try applyWatch(key: entry.key, entry.value)
            }
            for uid in deletedViewUIDs { try db.run("DELETE FROM views WHERE uid = ?", [.text(uid)]) }
            for v in views {
                let args: [SQLValue] = [.text(v.name), .int(Int64(v.scopeKind)), .text(v.scopeSource), .text(v.scopePath), .text(v.query), SQLValue(v.pinned), .int(Int64(v.position))]
                let changed = try db.run(
                    "UPDATE views SET name = ?, scope_kind = ?, scope_source = ?, scope_path = ?, query = ?, pinned = ?, position = ? WHERE uid = ?",
                    args + [.text(v.uid)]
                )
                if changed == 0 {
                    try db.run(
                        "INSERT INTO views (name, scope_kind, scope_source, scope_path, query, pinned, position, created_at, uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        args + [SQLValue(v.createdAt), .text(v.uid)]
                    )
                }
            }
        }
    }

    func applyWatch(key: String, _ w: UDWatchValue) throws {
        try db.run(
            "UPDATE items SET position = ?, wduration = ?, watched = ?, play_count = ?, last_played = ?, favorite = ?, hidden = ? WHERE key = ?",
            [.double(w.position), SQLValue(w.duration), SQLValue(w.watched), .int(Int64(w.playCount)), .double(w.lastPlayed?.timeIntervalSince1970 ?? 0),
             SQLValue(w.favorite), SQLValue(w.hidden), .text(key)]
        )
    }

    /// Applied by the scan when it creates an item whose key has restored state.
    func applyPendingWatch(itemID: Int64, key: String) throws {
        guard let w = pendingWatch[key] else { return }
        try db.run(
            "UPDATE items SET position = ?, wduration = ?, watched = ?, play_count = ?, last_played = ?, favorite = ?, hidden = ? WHERE id = ?",
            [.double(w.position), SQLValue(w.duration), SQLValue(w.watched), .int(Int64(w.playCount)), .double(w.lastPlayed?.timeIntervalSince1970 ?? 0),
             SQLValue(w.favorite), SQLValue(w.hidden), .int(itemID)]
        )
    }

    // MARK: Reseeding the ledger from the database

    /// Everything the user changed that this database still holds, as patches. Used when the local copy of user data was
    /// lost but this file survived. Stamps are the last-played time (or 1 second after 1970 for items with no play time, so
    /// anything the cloud holds wins over a guess).
    public func userDataPatches(device: String) throws -> [UDRecord] {
        var out: [UDRecord] = []
        let rows: [(String, UDWatchValue)] = try db.rows(
            """
            SELECT key, position, wduration, watched, play_count, last_played, favorite, hidden FROM items
            WHERE play_count > 0 OR position > 0 OR watched = 1 OR favorite = 1 OR hidden = 1 OR last_played > 0
            """, [], cached: false
        ) { s in (s.text(0), Self.watchValue(s, from: 1)) }
        for (key, value) in rows {
            let t = max(1, value.lastPlayed?.timeIntervalSince1970 ?? 1)
            let stamp = UDStamp(time: t, device: device)
            out.append(UDWatch.progressPatch(key: key, value, epoch: 0, at: stamp))
            if value.favorite { out.append(UDWatch.favoritePatch(key: key, favorite: true, at: stamp)) }
        }
        let views: [(String, SavedView)] = try db.rows(
            "SELECT uid, id, name, scope_kind, scope_source, scope_path, query, pinned, position, created_at FROM views WHERE uid IS NOT NULL", [], cached: false
        ) { s in
            let scope = ViewScope(storedKind: s.int(3), source: s.text(4), path: s.text(5))
            let query = try JSONDecoder().decode(ItemQuery.self, from: Data(s.text(6).utf8))
            return (s.text(0), SavedView(id: s.int64(1), name: s.text(2), scope: scope, query: query, pinned: s.bool(7), position: s.int(8), createdAt: s.optDate(9) ?? Date(timeIntervalSince1970: 1)))
        }
        for (uid, view) in views {
            let (scopeKind, source, path) = view.scope.stored
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let q = String(decoding: try encoder.encode(view.query), as: UTF8.self)
            let value = UDViewValue(uid: uid, name: view.name, scopeKind: scopeKind, scopeSource: source, scopePath: path, query: q, pinned: view.pinned, position: view.position, createdAt: view.createdAt)
            out.append(UDView.patch(value, at: UDStamp(time: max(1, view.createdAt.timeIntervalSince1970), device: device)))
        }
        return out
    }
}

/// Connects the store to the bootstrap. `rescan` is whatever starts the library scan for every source (the app passes it).
public struct LibraryRestoreAdapter: LibraryRestoreTarget {
    public let store: SQLiteLibraryStore
    public let deviceID: String
    public let scan: @Sendable () async throws -> Void

    public init(store: SQLiteLibraryStore, deviceID: String, scan: @escaping @Sendable () async throws -> Void) {
        self.store = store
        self.deviceID = deviceID
        self.scan = scan
    }

    public func closeWatchGate() async { await store.closeWatchGate() }
    public func openWatchGate() async { await store.openWatchGate() }

    public func restore(watch: [(key: String, value: UDWatchValue)], views: [UDViewValue], deletedViewUIDs: [String]) async throws {
        try await store.restoreUserData(watch: watch, views: views, deletedViewUIDs: deletedViewUIDs)
    }

    public func currentUserData() async throws -> [UDRecord] { try await store.userDataPatches(device: deviceID) }

    public func rescan() async throws {
        try await scan()
        await store.clearPendingRestore()
    }
}
