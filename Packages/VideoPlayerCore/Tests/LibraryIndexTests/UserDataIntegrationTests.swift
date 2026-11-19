import XCTest
import VideoPlayerCore
import UserData
@testable import LibraryIndex

// Watch state and saved views survive a purge of the database (docs/STORAGE_MODEL.md). The purge simulator below deletes the
// whole database and the local copy of user data between two runs of the app and checks the restored state matches exactly.

extension SQLiteLibraryStore {
    func allKeys() throws -> [String] { try db.rows("SELECT key FROM items ORDER BY key", [], cached: false) { $0.text(0) } }
    func id(ofKey key: String) throws -> Int64 {
        guard let id = try db.first("SELECT id FROM items WHERE key = ?", [.text(key)], { $0.int64(0) }) else { throw LibraryIndexError.notFound(key) }
        return id
    }
    func watchByKey() throws -> [String: WatchState] {
        let rows: [(String, WatchState)] = try db.rows(
            "SELECT key, position, wduration, watched, play_count, last_played, favorite, hidden FROM items", [], cached: false
        ) { s in
            let lp = s.double(5)
            return (s.text(0), WatchState(position: s.double(1), duration: s.optDouble(2), watched: s.bool(3), playCount: s.int(4),
                                          lastPlayed: lp > 0 ? Date(timeIntervalSince1970: lp) : nil, favorite: s.bool(6), hiddenFromContinue: s.bool(7)))
        }
        return Dictionary(uniqueKeysWithValues: rows)
    }
}

struct ViewSummary: Equatable, Comparable {
    var name: String, scope: ViewScope, query: ItemQuery, pinned: Bool, position: Int
    static func < (a: ViewSummary, b: ViewSummary) -> Bool { (a.name, a.position) < (b.name, b.position) }
}

func summaries(_ views: [SavedView]) -> [ViewSummary] {
    views.map { ViewSummary(name: $0.name, scope: $0.scope, query: $0.query, pinned: $0.pinned, position: $0.position) }.sorted()
}

final class LibraryUserDataTests: XCTestCase {
    private func recorded() async throws -> (Harness, UserDataLedger, SQLiteLibraryStore) {
        let h = try Harness.make()
        basicLibrary(h.source)
        try await h.registerSource()
        try await h.syncer.sync()
        let ledger = UserDataLedger(deviceID: "A", clock: { t0 })
        await h.store.setRecorder(LedgerRecorder(ledger: ledger))
        return (h, ledger, h.store)
    }

    private func hexfall(_ store: SQLiteLibraryStore) async throws -> (id: Int64, key: String) {
        let items = try await store.page(ItemQuery(), limit: 50, offset: 0)
        guard let item = items.first(where: { $0.title == "Hexfall" }) else { throw LibraryIndexError.notFound("Hexfall") }
        guard let key = try await store.itemKey(item.id) else { throw LibraryIndexError.notFound("key") }
        return (item.id, key)
    }

    // MARK: Write-through

    func testProgressWatchedUnwatchedFavoriteAndHiddenAreWrittenThrough() async throws {
        let (h, ledger, store) = try await recorded()
        defer { h.cleanup() }
        let (id, key) = try await hexfall(store)
        try await store.updateProgress(itemID: id, position: 1000, duration: 7200, at: day(10))
        var v = try XCTUnwrap(ledger.watchEntries().first { $0.key == key }?.value)
        XCTAssertEqual(v.position, 1000)
        XCTAssertEqual(v.duration, 7200)
        XCTAssertFalse(v.watched)
        XCTAssertEqual(v.lastPlayed, day(10))

        try await store.updateProgress(itemID: id, position: 7000, duration: 7200, at: day(11))
        v = try XCTUnwrap(ledger.watchEntries().first { $0.key == key }?.value)
        XCTAssertTrue(v.watched, "95% counts as watched")
        XCTAssertEqual(v.playCount, 1)
        XCTAssertEqual(v.position, 0)

        await store.setClock { day(12) }
        try await store.setFavorite(itemID: id, favorite: true)
        try await store.hideFromContinue(itemID: id, hidden: true)
        v = try XCTUnwrap(ledger.watchEntries().first { $0.key == key }?.value)
        XCTAssertTrue(v.favorite)
        XCTAssertTrue(v.hidden)

        try await store.markWatched(itemIDs: [id], watched: false, at: day(13))
        v = try XCTUnwrap(ledger.watchEntries().first { $0.key == key }?.value)
        XCTAssertFalse(v.watched)
        XCTAssertEqual(v.playCount, 0)
        XCTAssertNil(v.lastPlayed)
        XCTAssertTrue(v.favorite, "unwatching keeps the favourite")
        XCTAssertEqual(UDWatch.epoch(of: ledger.record(type: UDSchema.watch, id: key)), day(13).timeIntervalSince1970, "a new play-count epoch starts")
    }

    func testMarkingASeasonWatchedRecordsEveryEpisode() async throws {
        let (h, ledger, store) = try await recorded()
        defer { h.cleanup() }
        let items = try await store.page(ItemQuery(), limit: 50, offset: 0)
        let series = try XCTUnwrap(items.first { $0.seriesID != nil }?.seriesID)
        try await store.markSeries(seriesID: series, season: nil, watched: true, at: day(20))
        let watched = ledger.watchEntries().filter { $0.value.watched }
        let episodeCount = try await store.episodes(ofSeries: series).count
        XCTAssertEqual(watched.count, episodeCount)
    }

    func testSavedViewsAreWrittenThroughIncludingEditsAndDeletes() async throws {
        let (h, ledger, store) = try await recorded()
        defer { h.cleanup() }
        var f = ItemFilter(); f.kinds = [.movie]; f.minRating = 7
        let v1 = try await store.saveView(name: "Good movies", scope: .library, query: ItemQuery(filter: f, sort: ItemSort(key: .rating, ascending: false)), pinned: true)
        let v2 = try await store.saveView(name: "Folder view", scope: .folder(sourceID: Harness.sourceID, path: "/Movies"), query: ItemQuery(), pinned: false)
        XCTAssertEqual(ledger.viewValues().count, 2)
        var edited = v1; edited.name = "Better movies"; edited.pinned = false
        try await store.updateView(edited)
        XCTAssertEqual(Set(ledger.viewValues().map(\.name)), ["Better movies", "Folder view"])
        try await store.deleteView(id: v2.id)
        XCTAssertEqual(ledger.viewValues().map(\.name), ["Better movies"])
        XCTAssertEqual(ledger.deletedViewUIDs().count, 1)
    }

    func testNothingIsRecordedWithoutARecorderAndNothingBreaks() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.registerSource()
        try await h.syncer.sync()
        let (id, _) = try await hexfall(h.store)
        try await h.store.updateProgress(itemID: id, position: 10, duration: 100, at: day(1))
        try await h.store.setFavorite(itemID: id, favorite: true)
        _ = try await h.store.saveView(name: "x", scope: .library, query: ItemQuery(), pinned: false)
        try await expectEqual(try await h.store.item(id: id)?.watch.position, 10)
    }

    // MARK: Schema 1 -> 2

    func testAVersionOneDatabaseGetsViewUIDsWhenOpened() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("libidx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("v1.sqlite").path
        let queryJSON = try encodeQueryJSON(ItemQuery())
        do {
            let db = try SQLiteDatabase(path: path)
            try db.exec(LibrarySchema.pragmas)
            for sql in LibrarySchema.migrations[0] { try db.exec(sql) }
            try db.exec("PRAGMA user_version = 1")
            try db.exec("INSERT INTO views (name, scope_kind, scope_source, scope_path, query, pinned, position, created_at) VALUES ('Old A', 0, '', '', '\(queryJSON)', 1, 0, 1000)")
            try db.exec("INSERT INTO views (name, scope_kind, scope_source, scope_path, query, pinned, position, created_at) VALUES ('Old B', 0, '', '', '\(queryJSON)', 0, 1, 1001)")
        }
        let store = try SQLiteLibraryStore(path: path)
        try await expectEqual(try await store.schemaVersion(), LibrarySchema.currentVersion)
        let uids = try await store.rawUIDs()
        XCTAssertEqual(uids.count, 2)
        XCTAssertEqual(Set(uids).count, 2, "each view has its own uid")
        XCTAssertTrue(uids.allSatisfy { $0.count >= 16 })
        try await expectEqual(try await store.views(scope: .library).map(\.name), ["Old A", "Old B"])
        // The old views now reach the cloud when the store is reseeded.
        let patches = try await store.userDataPatches(device: "A")
        XCTAssertEqual(patches.filter { $0.type == UDSchema.view }.count, 2)
    }

    // MARK: The watch gate

    func testWhileTheGateIsClosedNothingShowsWatchStateAndOpeningItBringsItBack() async throws {
        let (h, _, store) = try await recorded()
        defer { h.cleanup() }
        let (id, _) = try await hexfall(store)
        try await store.updateProgress(itemID: id, position: 1000, duration: 7200, at: day(10))
        try await store.setFavorite(itemID: id, favorite: true)
        try await expectEqual(try await store.continueWatching(limit: 10, now: day(11), retentionDays: 365).count, 1)
        let itemCount = try await store.counts().items
        await store.closeWatchGate()
        try await expectEqual(try await store.item(id: id)?.watch, WatchState.none)
        try await expectEqual(try await store.continueWatching(limit: 10, now: day(11), retentionDays: 365).count, 0)
        try await expectEqual(try await store.nextUp(limit: 10, now: day(11), retentionDays: 365).count, 0)
        let page = try await store.page(ItemQuery(), limit: 50, offset: 0)
        XCTAssertTrue(page.allSatisfy { $0.watch == .none })
        let cursorPage = try await store.page(ItemQuery(), limit: 50, after: nil)
        XCTAssertTrue(cursorPage.items.allSatisfy { $0.watch == .none })
        let recent = try await store.recentlyAdded(limit: 10, kind: nil)
        XCTAssertTrue(recent.allSatisfy { $0.watch == .none })
        try await expectEqual(try await store.counts().items, itemCount, "everything else still works")
        await store.openWatchGate()
        try await expectEqual(try await store.item(id: id)?.watch.position, 1000)
        try await expectEqual(try await store.item(id: id)?.watch.favorite, true)
        try await expectEqual(try await store.continueWatching(limit: 10, now: day(11), retentionDays: 365).count, 1)
    }

    // MARK: Restore

    func testRestoredStateIsAppliedToItemsThatExistAndToItemsTheRescanCreatesLater() async throws {
        let (h, ledger, store) = try await recorded()
        defer { h.cleanup() }
        let (id, key) = try await hexfall(store)
        try await store.updateProgress(itemID: id, position: 1000, duration: 7200, at: day(10))
        let episodes = try await store.page(ItemQuery(), limit: 50, offset: 0).filter { $0.season == 1 && $0.episode == 1 }
        var episodeKey = ""
        if let e = episodes.first, let k = try await store.itemKey(e.id) { episodeKey = k }

        // A brand new, empty database.
        let h2 = try Harness.make()
        defer { h2.cleanup() }
        try await h2.registerSource()
        let ep = UDWatchValue(position: 0, duration: 3000, watched: true, playCount: 2, lastPlayed: day(12), favorite: true, hidden: false)
        try await h2.store.restoreUserData(watch: ledger.watchEntries() + (episodeKey.isEmpty ? [] : [(key: episodeKey, value: ep)]), views: [], deletedViewUIDs: [])
        try await expectEqual(try await h2.store.pendingRestoreCount, episodeKey.isEmpty ? 1 : 2)
        basicLibrary(h2.source)
        try await h2.syncer.sync()
        let restored = try await h2.store.watchByKey()
        XCTAssertEqual(restored[key]?.position, 1000)
        XCTAssertEqual(restored[key]?.lastPlayed, day(10))
        if !episodeKey.isEmpty {
            XCTAssertEqual(restored[episodeKey]?.playCount, 2)
            XCTAssertEqual(restored[episodeKey]?.favorite, true)
        }
        await h2.store.clearPendingRestore()
        try await expectEqual(try await h2.store.pendingRestoreCount, 0)
    }

    func testRestoringViewsCreatesMissingUpdatesChangedAndRemovesDeleted() async throws {
        let (h, _, store) = try await recorded()
        defer { h.cleanup() }
        let a = try await store.saveView(name: "A", scope: .library, query: ItemQuery(), pinned: false)
        let b = try await store.saveView(name: "B", scope: .library, query: ItemQuery(), pinned: false)
        let uidA = try await store.rawUIDs().first!
        let incoming = [
            UDViewValue(uid: uidA, name: "A renamed", scopeKind: 0, scopeSource: "", scopePath: "", query: try encodeQuery(ItemQuery()), pinned: true, position: 5, createdAt: day(1)),
            UDViewValue(uid: "brand-new", name: "C", scopeKind: 1, scopeSource: "src1", scopePath: "/Movies", query: try encodeQuery(ItemQuery()), pinned: false, position: 0, createdAt: day(2)),
        ]
        let uidB = try await store.rawUIDs().first { $0 != uidA }!
        try await store.restoreUserData(watch: [], views: incoming, deletedViewUIDs: [uidB])
        let all = try await store.views(scope: .library) + (try await store.views(scope: .folder(sourceID: "src1", path: "/Movies")))
        XCTAssertEqual(Set(all.map(\.name)), ["A renamed", "C"])
        XCTAssertEqual(all.first { $0.name == "A renamed" }?.id, a.id, "an existing view keeps its row")
        // (Not compared by row id: SQLite hands the freed row number to the next inserted view.)
        XCTAssertFalse(all.contains { $0.name == b.name })
    }

    private func encodeQuery(_ q: ItemQuery) throws -> String { try encodeQueryJSON(q) }
}

func encodeQueryJSON(_ q: ItemQuery) throws -> String {
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
    return String(decoding: try e.encode(q), as: UTF8.self)
}

extension SQLiteLibraryStore {
    func rawUIDs() throws -> [String] { try db.rows("SELECT uid FROM views WHERE uid IS NOT NULL ORDER BY id", [], cached: false) { $0.text(0) } }
}

// MARK: The purge simulator

final class PurgeSimulatorTests: XCTestCase {
    /// One run of the app: a database file, the local user-data file, the cloud and UserDefaults. `purge()` is what the
    /// system does when space is low and the app is not running: everything in Caches goes, the cloud and UserDefaults stay.
    final class Device {
        let dir: URL
        var dbURL: URL { dir.appendingPathComponent("library.sqlite") }
        var ledgerURL: URL { dir.appendingPathComponent("userdata-ledger.json") }
        let cloud: InMemoryCloud
        let defaults = InMemoryKeyValueStore()
        let source: FakeSource
        let tick = Locked(0.0)
        init(cloud: InMemoryCloud, source: FakeSource) throws {
            self.cloud = cloud
            self.source = source
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("purge-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        func now() -> Date { Date(timeIntervalSince1970: 1_800_000_000 + tick.with { $0 += 1; return $0 }) }
        func purge() {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbURL.path + suffix) }
            try? FileManager.default.removeItem(at: ledgerURL)
        }
        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    struct Run {
        var store: SQLiteLibraryStore
        var ledger: UserDataLedger
        var engine: UserDataSyncEngine
        var syncer: LibrarySyncer
    }

    func launch(_ d: Device, device: String = "A") async throws -> (Run, UDDatabaseHealth, Bool) {
        let dbExisted = FileManager.default.fileExists(atPath: d.dbURL.path)
        let store = try SQLiteLibraryStore(path: d.dbURL.path)
        let existingItems = try await store.counts().items, existingSources = try await store.sources().count
        let health: UDDatabaseHealth = dbExisted ? (existingItems == 0 && existingSources == 0 ? .empty : .ok) : .missing
        let ledger = UserDataLedger(deviceID: device, clock: { Date() })
        let loaded = ledger.load(from: d.ledgerURL)
        let lost: Bool
        if case .loaded = loaded { lost = false } else { lost = true }
        let engine = UserDataSyncEngine(ledger: ledger, cloud: d.cloud, sleep: { _ in })
        let syncer = LibrarySyncer(store: store, source: d.source, sourceID: Harness.sourceID, annotator: FilenameAnnotator(), clock: { t0.addingTimeInterval(100 * 86_400) })
        await store.setRecorder(LedgerRecorder(ledger: ledger))
        let clockBox = d
        await store.setClock { clockBox.now() }
        return (Run(store: store, ledger: ledger, engine: engine, syncer: syncer), health, lost)
    }

    func bootstrap(_ run: Run, _ d: Device, health: UDDatabaseHealth, lost: Bool) async throws -> LibraryBootstrapState {
        let boot = LibraryBootstrap(ledger: run.ledger, engine: run.engine, essentials: UDEssentialsStore(store: d.defaults), credentials: InMemoryCredentialStore())
        let syncer = run.syncer
        let target = LibraryRestoreAdapter(store: run.store, deviceID: "A", scan: { try await syncer.sync() })
        _ = try await boot.run(health: health, ledgerWasLost: lost, target: target)
        return await boot.state
    }

    /// A deterministic burst of user actions on many items and views.
    func useTheApp(_ run: Run, _ d: Device, actions: Int, seed: UInt64) async throws {
        var rng = LCG(seed)
        let items = try await run.store.page(ItemQuery(), limit: 100_000, offset: 0)
        var views: [SavedView] = []
        for _ in 0..<actions {
            let item = items[rng.int(items.count)]
            switch rng.int(10) {
            case 0..<4:
                try await run.store.updateProgress(itemID: item.id, position: Double(rng.int(6000)), duration: 7200, at: d.now())
            case 4:
                try await run.store.updateProgress(itemID: item.id, position: 7100, duration: 7200, at: d.now())
            case 5:
                try await run.store.markWatched(itemIDs: [item.id], watched: rng.chance(60), at: d.now())
            case 6:
                try await run.store.setFavorite(itemID: item.id, favorite: rng.chance(60))
            case 7:
                try await run.store.hideFromContinue(itemID: item.id, hidden: rng.chance(50))
            case 8:
                var f = ItemFilter(); f.minRating = Double(rng.int(9)); f.kinds = rng.chance(50) ? [.movie] : []
                views.append(try await run.store.saveView(name: "View \(views.count)", scope: rng.chance(30) ? .folder(sourceID: Harness.sourceID, path: "/Movies") : .library,
                                                           query: ItemQuery(filter: f, sort: ItemSort(key: rng.chance(50) ? .rating : .title, ascending: rng.chance(50))), pinned: rng.chance(50)))
            default:
                guard !views.isEmpty else { continue }
                let i = rng.int(views.count)
                if rng.chance(40) {
                    try await run.store.deleteView(id: views[i].id)
                    views.remove(at: i)
                } else {
                    var v = views[i]; v.name += "!"; v.pinned.toggle()
                    try await run.store.updateView(v)
                    views[i] = v
                }
            }
        }
    }

    func capture(_ store: SQLiteLibraryStore) async throws -> (watch: [String: WatchState], views: [ViewSummary]) {
        let folder = ViewScope.folder(sourceID: Harness.sourceID, path: "/Movies")
        return (try await store.watchByKey(), summaries(try await store.views(scope: .library) + (try await store.views(scope: folder))))
    }

    func testAfterAFullPurgeEveryWatchStateAndSavedViewComesBackExactly() async throws {
        let cloud = InMemoryCloud(pageSize: 50)
        let lib = GeneratedLibrary.generate(items: 400)
        let source = lib.source
        let d = try Device(cloud: cloud, source: source)
        defer { d.cleanup() }

        // Run 1: fresh install, scan, use the app, back up, quit.
        let (run1, health1, lost1) = try await launch(d)
        XCTAssertEqual(health1, .missing)
        try await run1.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(run1, d, health: health1, lost: lost1)
        try await expectEqual(try await run1.store.counts().items, lib.items)
        try await useTheApp(run1, d, actions: 600, seed: 99)
        let before = try await capture(run1.store)
        XCTAssertGreaterThan(before.watch.values.filter { $0.watched }.count, 20, "the scripted session really changed things")
        XCTAssertGreaterThan(before.watch.values.filter { $0.favorite }.count, 5)
        XCTAssertGreaterThan(before.views.count, 0)
        let report = await run1.engine.sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(report.remainingDirty, 0)
        try run1.ledger.save(to: d.ledgerURL)

        // The system frees space while the app is not running: the database and the local copy are gone.
        d.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.dbURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: d.ledgerURL.path))

        // Run 2: the app starts with nothing.
        let (run2, health2, lost2) = try await launch(d)
        XCTAssertEqual(health2, .missing)
        XCTAssertTrue(lost2)
        try await run2.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        let state = try await bootstrap(run2, d, health: health2, lost: lost2)
        XCTAssertEqual(state, .ready(note: nil))
        try await expectEqual(try await run2.store.counts().items, lib.items)
        try await expectEqual(try await run2.store.isWatchGateClosed, false)
        let after = try await capture(run2.store)
        let differing = before.watch.keys.filter { before.watch[$0] != after.watch[$0] }.sorted()
        XCTAssertEqual(differing.count, 0, "differs for \(differing.count) of \(before.watch.count) items; first: " + differing.prefix(3).map { "\($0) before=\(String(describing: before.watch[$0])) after=\(String(describing: after.watch[$0]))" }.joined(separator: " || "))
        XCTAssertEqual(Set(after.watch.keys), Set(before.watch.keys))
        XCTAssertEqual(after.views, before.views, "saved views are restored exactly")
        try await expectEqual(try await run2.store.pendingRestoreCount, 0)
    }

    func testAPurgeWhileSignedOutLosesHistoryAndSaysSoButTheLibraryRebuilds() async throws {
        let cloud = InMemoryCloud()
        cloud.setAccount(.noAccount)
        let source = FakeSource()
        basicLibrary(source)
        let d = try Device(cloud: cloud, source: source)
        defer { d.cleanup() }
        let (run1, h1, l1) = try await launch(d)
        try await run1.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(run1, d, health: h1, lost: l1)
        let key = try await run1.store.allKeys()[0]
        try await run1.store.updateProgress(itemID: try await run1.store.id(ofKey: key), position: 500, duration: 7200, at: d.now())
        let itemsBefore = try await run1.store.counts().items
        try run1.ledger.save(to: d.ledgerURL)
        // No purge yet: the local copy is what keeps the history.
        let (again, h, l) = try await launch(d)
        XCTAssertEqual(h, .ok)
        XCTAssertFalse(l)
        _ = try await bootstrap(again, d, health: h, lost: l)
        try await expectEqual(try await again.store.watchByKey()[key]?.position, 500)
        // Now the purge: without iCloud the history is gone and the app says so.
        d.purge()
        let (run2, h2, l2) = try await launch(d)
        try await run2.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        let state = try await bootstrap(run2, d, health: h2, lost: l2)
        XCTAssertEqual(state, .ready(note: .historyNotRestored))
        try await expectEqual(try await run2.store.counts().items, itemsBefore, "the library itself is rebuilt")
        try await expectEqual(try await run2.store.watchByKey()[key]?.position, 0)
    }

    func testAnExportedBackupBringsHistoryBackAfterAPurgeWithoutICloud() async throws {
        let cloud = InMemoryCloud()
        cloud.setAccount(.noAccount)
        let source = FakeSource()
        basicLibrary(source)
        let d = try Device(cloud: cloud, source: source)
        defer { d.cleanup() }
        let (run1, h1, l1) = try await launch(d)
        try await run1.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(run1, d, health: h1, lost: l1)
        let key = try await run1.store.allKeys()[0]
        try await run1.store.updateProgress(itemID: try await run1.store.id(ofKey: key), position: 500, duration: 7200, at: d.now())
        let backup = try UDExport.export(run1.ledger)
        d.purge()
        let (run2, h2, l2) = try await launch(d)
        try await run2.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        try UDExport.import(backup, into: run2.ledger)     // what Settings > Import does, before the rebuild
        _ = try await bootstrap(run2, d, health: h2, lost: l2)
        try await expectEqual(try await run2.store.watchByKey()[key]?.position, 500)
    }

    func testTheDatabaseSurvivingButTheLocalCopyBeingLostRebuildsTheCopyAndLosesNothing() async throws {
        let cloud = InMemoryCloud()
        let source = FakeSource()
        basicLibrary(source)
        let d = try Device(cloud: cloud, source: source)
        defer { d.cleanup() }
        let (run1, h1, l1) = try await launch(d)
        try await run1.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(run1, d, health: h1, lost: l1)
        let id = try await run1.store.id(ofKey: try await run1.store.allKeys()[0])
        try await run1.store.updateProgress(itemID: id, position: 700, duration: 7200, at: d.now())
        try await run1.store.setFavorite(itemID: id, favorite: true)
        try await run1.store.checkpoint()
        let before = try await capture(run1.store)
        // Only the ledger file disappears (and the cloud has never seen the changes).
        let (run2, h2, l2) = try await launch(d)
        XCTAssertEqual(h2, .ok)
        XCTAssertTrue(l2)
        _ = try await bootstrap(run2, d, health: h2, lost: l2)
        try await expectEqual(try await run2.store.watchByKey(), before.watch)
        XCTAssertGreaterThanOrEqual(cloud.serverCount, 1, "the reseeded records reached the cloud")
        // And a later purge now restores them.
        d.purge()
        let (run3, h3, l3) = try await launch(d)
        try await run3.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(run3, d, health: h3, lost: l3)
        let after = try await capture(run3.store)
        XCTAssertEqual(after.watch.filter { $0.value != .none }, before.watch.filter { $0.value != .none })
    }

    func testTwoDevicesEachPurgedStillConverge() async throws {
        let cloud = InMemoryCloud()
        let source = FakeSource()
        basicLibrary(source)
        let dA = try Device(cloud: cloud, source: source), dB = try Device(cloud: cloud, source: source)
        defer { dA.cleanup(); dB.cleanup() }
        let (a, ha, la) = try await launch(dA, device: "A")
        let (b, hb, lb) = try await launch(dB, device: "B")
        for (run, d) in [(a, dA), (b, dB)] { try await run.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0)); _ = d }
        _ = try await bootstrap(a, dA, health: ha, lost: la)
        _ = try await bootstrap(b, dB, health: hb, lost: lb)
        let keys = try await a.store.allKeys()
        let ida = try await a.store.id(ofKey: keys[0]), idb = try await b.store.id(ofKey: keys[1])
        try await a.store.updateProgress(itemID: ida, position: 100, duration: 7200, at: dA.now())
        try await b.store.updateProgress(itemID: idb, position: 200, duration: 7200, at: dB.now())
        _ = await a.engine.sync(); _ = await b.engine.sync(); _ = await a.engine.sync()
        dA.purge(); dB.purge()
        let (a2, ha2, la2) = try await launch(dA, device: "A")
        try await a2.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(a2, dA, health: ha2, lost: la2)
        let w = try await a2.store.watchByKey()
        XCTAssertEqual(w[keys[0]]?.position, 100)
        XCTAssertEqual(w[keys[1]]?.position, 200, "the other device's play is restored too")
    }
}
