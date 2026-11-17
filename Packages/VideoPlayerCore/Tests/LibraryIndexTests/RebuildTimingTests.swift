import XCTest
import VideoPlayerCore
import UserData
@testable import LibraryIndex

// How long the startup rebuild takes after the system has deleted the database (docs/STORAGE_MODEL.md, "Rebuild cost").
// Every item gets a user-data record, so this is the worst case: a library where the user touched every title.
//
// The cloud here is the in-memory fake, so the numbers are CPU time only. A real CloudKit round trip adds network time per
// request (about one request per 400 records to upload, one per page of changes to download), which is NOT measured.
//
// 1,000 items always run. 10,000 items are opt-in (VP_RUN_REBUILD_10K=1) because they take about half a minute in a debug build.
// Lines start with "PERF" and are appended to /tmp/library-index-perf.txt, like ScaleTests.

final class RebuildTimingTests: XCTestCase {
    func testRebuildTimings1000() async throws { try await measure(items: 1_000) }

    func testRebuildTimings10000() async throws {
        if ProcessInfo.processInfo.environment["VP_RUN_REBUILD_10K"] != "1" { throw XCTSkip("10,000-item rebuild timing is opt-in: set VP_RUN_REBUILD_10K=1") }
        try await measure(items: 10_000)
    }

    private func seconds(_ body: () async throws -> Void) async throws -> Double {
        try await milliseconds(body) / 1000
    }

    func measure(items n: Int) async throws {
        PerfLog.line("=== rebuild \(n) items === machine: \(PerfLog.machine())")
        let lib = GeneratedLibrary.generate(items: n)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sourceID = "rebuild"
        let scanClock = t0.addingTimeInterval(400 * 86_400)
        let cloud = InMemoryCloud(pageSize: 200)

        // ---- Run 1: scan from empty (no user data to restore), then touch every item, then back up.
        let dbPath1 = dir.appendingPathComponent("run1.sqlite").path
        let store1 = try SQLiteLibraryStore(path: dbPath1)
        try await store1.upsertSource(LibrarySourceRecord(id: sourceID, kind: .webdav, name: "R", addedAt: t0))
        let ledger1 = UserDataLedger(deviceID: "A", clock: { t0 })
        await store1.setRecorder(LedgerRecorder(ledger: ledger1))
        let syncer1 = LibrarySyncer(store: store1, source: lib.source, sourceID: sourceID, annotator: HashAnnotator(), clock: { scanClock })
        var scanReport: ScanSummary?
        let scanFromEmpty = try await seconds { scanReport = try await syncer1.sync() }
        XCTAssertEqual(scanReport?.status, .completed)
        try await expectEqual(try await store1.counts().items, n)
        PerfLog.line("\(n): scan from empty (nothing to restore): \(String(format: "%.2f", scanFromEmpty)) s")

        var ids: [Int64] = []
        var cursor: ItemCursor?
        repeat {
            let page = try await store1.page(ItemQuery(sort: ItemSort(key: .added)), limit: 2_000, after: cursor)
            ids += page.items.map(\.id)
            cursor = page.next
        } while cursor != nil
        XCTAssertEqual(ids.count, n)
        let touch = try await seconds {
            for (k, id) in ids.enumerated() {
                let when = t0.addingTimeInterval(Double(300 * 86_400 + k))
                switch k % 10 {
                case 0..<5: try await store1.markWatched(itemIDs: [id], watched: true, at: when)
                case 5..<9: try await store1.updateProgress(itemID: id, position: Double(100 + k % 5000), duration: 7200, at: when)
                default: try await store1.setFavorite(itemID: id, favorite: true)
                }
            }
        }
        XCTAssertEqual(ledger1.records(ofType: UDSchema.watch).count, n)
        PerfLog.line("\(n): \(n) user actions written through to the local copy: \(String(format: "%.2f", touch)) s (\(String(format: "%.2f", touch / Double(n) * 1000)) ms each)")

        let engine1 = UserDataSyncEngine(ledger: ledger1, cloud: cloud, sleep: { _ in })
        var uploadReport: UDSyncReport?
        let upload = try await seconds { uploadReport = await engine1.sync() }
        XCTAssertEqual(uploadReport?.status, .synced)
        XCTAssertEqual(uploadReport?.remainingDirty, 0)
        let uploadBytes = ledger1.allRecords().reduce(0) { $0 + $1.encodedByteCount }
        PerfLog.line("\(n): upload to the in-memory cloud: \(String(format: "%.2f", upload)) s, \(ledger1.count) records, \(uploadBytes / 1024) KB of record JSON, \(cloud.saveCalls) save requests (largest batch \(cloud.largestBatchSeen))")
        let before = try await store1.watchByKey()

        // ---- Purge: the database and the local copy are gone. Run 2 starts with nothing but the cloud.
        let dbPath2 = dir.appendingPathComponent("run2.sqlite").path
        let store2 = try SQLiteLibraryStore(path: dbPath2)
        try await store2.upsertSource(LibrarySourceRecord(id: sourceID, kind: .webdav, name: "R", addedAt: t0))
        let ledger2 = UserDataLedger(deviceID: "A", clock: { t0 })
        let engine2 = UserDataSyncEngine(ledger: ledger2, cloud: cloud, sleep: { _ in })
        await store2.setRecorder(LedgerRecorder(ledger: ledger2))
        let syncer2 = LibrarySyncer(store: store2, source: lib.source, sourceID: sourceID, annotator: HashAnnotator(), clock: { scanClock })

        // Phases timed one by one (the real startup runs the same steps in this order, `LibraryBootstrap`).
        await store2.closeWatchGate()
        var pullReport: UDSyncReport?
        let fetchesBefore = cloud.fetchCalls
        let pull = try await seconds { pullReport = await engine2.sync() }
        XCTAssertEqual(pullReport?.status, .synced)
        XCTAssertEqual(ledger2.records(ofType: UDSchema.watch).count, n)
        PerfLog.line("\(n): restore step 1, pull \(ledger2.count) records from the cloud into the local copy: \(String(format: "%.2f", pull)) s (\(cloud.fetchCalls - fetchesBefore) fetch requests of up to 200 records)")
        let apply = try await seconds {
            try await store2.restoreUserData(watch: ledger2.watchEntries(), views: ledger2.viewValues(), deletedViewUIDs: ledger2.deletedViewUIDs())
        }
        try await expectEqual(try await store2.pendingRestoreCount, n)
        PerfLog.line("\(n): restore step 2, hand \(n) watch states to the database (applied to items that exist, remembered for the ones the scan creates): \(String(format: "%.2f", apply)) s")
        let rescan = try await seconds { _ = try await syncer2.sync() }
        await store2.clearPendingRestore()
        await store2.openWatchGate()
        PerfLog.line("\(n): rescan that creates the items and applies the remembered watch state: \(String(format: "%.2f", rescan)) s (same scan without restore: \(String(format: "%.2f", scanFromEmpty)) s)")
        PerfLog.line("\(n): TOTAL rebuild (pull + hand over + rescan) = \(String(format: "%.2f", pull + apply + rescan)) s; the user data part alone (pull + hand over + the extra scan time) = \(String(format: "%.2f", pull + apply + max(0, rescan - scanFromEmpty))) s")

        let after = try await store2.watchByKey()
        let differing = before.keys.filter { before[$0] != after[$0] }
        XCTAssertEqual(differing.count, 0, "every item's watch state comes back exactly")
        XCTAssertEqual(after.count, before.count)
    }
}
