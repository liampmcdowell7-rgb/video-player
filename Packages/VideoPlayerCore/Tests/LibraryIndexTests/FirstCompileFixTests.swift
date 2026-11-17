import XCTest
import VideoPlayerCore
import UserData
@testable import LibraryIndex

// Fixes from the first real compile (Xcode 27.2, 2026-11-17; OPEN_QUESTIONS R155).
// `UserData` is imported WITHOUT @testable here, so these lines compile only if the API is public, as the app needs it.
final class FirstCompileFixTests: XCTestCase {
    /// The app builds a failed report itself ("'UDSyncReport' initializer is inaccessible due to 'internal' protection level").
    func testSyncReportCanBeBuiltOutsideItsModuleWithTheSameDefaults() {
        var failed = UDSyncReport()
        failed.status = .failed("The start-up sync did not finish.")
        XCTAssertEqual(failed.status, .failed("The start-up sync did not finish."))
        let empty = UDSyncReport()
        XCTAssertEqual(empty.status, .synced)
        XCTAssertEqual([empty.pulled, empty.pushed, empty.conflictsMerged, empty.splits, empty.rateLimitWaits, empty.fullRefetches,
                        empty.remainingDirty], [0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(empty.oversize, [])
        XCTAssertEqual(UDSyncReport(status: .synced, pulled: 2, pushed: 1).pulled, 2)
    }

    /// The app's synchronous main-actor start-up cannot `await setRecorder`, so the store takes the recorder when it is opened.
    /// The very first change after opening must reach the ledger.
    func testStoreOpenedWithARecorderWritesTheFirstChangeThrough() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        let ledger = UserDataLedger(deviceID: "A", clock: { t0 })
        let recorder = LedgerRecorder(ledger: ledger)
        let store = try SQLiteLibraryStore(path: h.dir.appendingPathComponent("with-recorder.sqlite").path, recorder: recorder)
        let stored = await store.recorder
        XCTAssertTrue((stored as AnyObject) === recorder, "the recorder given to init is the one in place")

        basicLibrary(h.source)
        try await store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        try await h.syncer(store: store).sync()
        let items = try await store.page(ItemQuery(), limit: 50, offset: 0)
        let item = try XCTUnwrap(items.first)
        let maybeKey = try await store.itemKey(item.id)
        let key = try XCTUnwrap(maybeKey)
        try await store.updateProgress(itemID: item.id, position: 1000, duration: 7200, at: day(10))
        let value = try XCTUnwrap(ledger.watchEntries().first { $0.key == key }?.value)
        XCTAssertEqual(value.position, 1000)
    }

    /// Opening without a recorder still works as before (every existing caller).
    func testStoreOpenedWithoutARecorderHasNone() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        let stored = await store.recorder
        XCTAssertNil(stored)
    }
}
