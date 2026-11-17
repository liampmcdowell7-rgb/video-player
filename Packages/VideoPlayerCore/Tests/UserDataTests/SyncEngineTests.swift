import XCTest
@testable import UserData

final class SyncEngineTests: XCTestCase {
    private func addWatch(_ ledger: UserDataLedger, count: Int, device: String = "A", playedAt: Double = 100) {
        let rec = LedgerRecorder(ledger: ledger)
        for i in 0..<count {
            rec.recordProgress(key: "item\(i)", UDWatchValue(position: Double(i), duration: 7200, watched: false, playCount: 0, lastPlayed: at(playedAt)), at: at(playedAt))
        }
    }

    // MARK: Basics

    func testFirstSyncPushesEverythingAndLeavesNothingDirty() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 10)
        ledger.setSetting("skipIntro", .bool(true))
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(report.pushed, 11)
        XCTAssertEqual(cloud.serverCount, 11)
        XCTAssertEqual(ledger.dirtyCount, 0)
        XCTAssertEqual(report.remainingDirty, 0)
        let again = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(again.pushed, 0, "nothing to send the second time")
    }

    func testAFreshDeviceGetsEverythingFromTheCloud() async throws {
        let cloud = InMemoryCloud()
        let a = makeLedger("A")
        addWatch(a, count: 25)
        _ = await makeEngine(a, cloud).sync()
        let b = makeLedger("B")
        let report = await makeEngine(b, cloud).sync()
        XCTAssertEqual(report.pulled, 25)
        XCTAssertEqual(b.watchEntries().count, 25)
        XCTAssertEqual(b.watchEntries().first { $0.key == "item7" }?.value.position, 7)
        XCTAssertEqual(b.dirtyCount, 0)
    }

    func testTwoDevicesConvergeToTheSameState() async throws {
        let cloud = InMemoryCloud()
        let a = makeLedger("A"), b = makeLedger("B")
        let ra = LedgerRecorder(ledger: a), rb = LedgerRecorder(ledger: b)
        ra.recordProgress(key: "m", UDWatchValue(position: 500, duration: 7200, lastPlayed: at(10)), at: at(10))
        rb.recordProgress(key: "m", UDWatchValue(position: 0, duration: 7200, watched: true, playCount: 1, lastPlayed: at(20)), at: at(20))
        ra.recordFavorite(key: "m", favorite: true, at: at(30))
        for _ in 0..<2 {
            _ = await makeEngine(a, cloud).sync()
            _ = await makeEngine(b, cloud).sync()
        }
        XCTAssertEqual(a.allRecords(), b.allRecords())
        XCTAssertEqual(cloud.serverRecords, a.allRecords())
        let v = try XCTUnwrap(a.watchEntries().first?.value)
        XCTAssertTrue(v.watched)
        XCTAssertTrue(v.favorite)
        XCTAssertEqual(v.lastPlayed, at(20))
    }

    // MARK: Conflicts

    func testAConflictIsMergedAndSavedAgainWithoutLosingEitherSide() async throws {
        let cloud = InMemoryCloud()
        let a = makeLedger("A")
        LedgerRecorder(ledger: a).recordProgress(key: "m", UDWatchValue(position: 100, duration: 7200, lastPlayed: at(10)), at: at(10))
        _ = await makeEngine(a, cloud).sync()
        // Device A edits again; before it uploads, another device writes a newer favourite straight into the cloud.
        LedgerRecorder(ledger: a).recordProgress(key: "m", UDWatchValue(position: 900, duration: 7200, lastPlayed: at(50)), at: at(50))
        var other = try XCTUnwrap(cloud.serverRecord("watch/m"))
        other.set("favorite", .bool(true), at: stamp(40, "B"))
        let otherCopy = other
        cloud.beforeSave { _ = cloud.serverWrite(otherCopy) }
        let report = await makeEngine(a, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(report.conflictsMerged, 1)
        let v = try XCTUnwrap(a.watchEntries().first?.value)
        XCTAssertEqual(v.position, 900)
        XCTAssertTrue(v.favorite)
        XCTAssertEqual(cloud.serverRecord("watch/m"), a.record(key: "watch/m"))
        XCTAssertEqual(a.dirtyCount, 0)
    }

    func testAnEditMadeWhileTheUploadWasInFlightStaysDirty() async throws {
        let ledger = makeLedger()
        let rec = LedgerRecorder(ledger: ledger)
        rec.recordFavorite(key: "m", favorite: true, at: at(1))
        let sent = ledger.dirtyEntries()[0].entry.record
        rec.recordHidden(key: "m", hidden: true, at: at(2))
        ledger.markSent(key: "watch/m", sent: sent, tag: "t1")
        XCTAssertEqual(ledger.dirtyCount, 1, "the record changed after it was sent")
        XCTAssertEqual(ledger.entry("watch/m")?.tag, "t1")
    }

    // MARK: Limits

    func testLargeBatchesAreSplitAtFourHundredRecords() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 1_000)
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(cloud.serverCount, 1_000)
        XCTAssertLessThanOrEqual(cloud.largestBatchSeen, 400)
        XCTAssertEqual(cloud.saveCalls, 3)
        XCTAssertEqual(report.splits, 0, "batched up front, no error needed")
    }

    func testBatchesAlsoRespectTwoMegabytes() {
        let big = (0..<10).map { i -> UDOutgoing in
            var r = UDRecord(type: "settings", id: "r\(i)")
            r.set("blob", .string(String(repeating: "x", count: 300_000)), at: stamp(1))
            return UDOutgoing(record: r, expectedTag: nil)
        }
        let batches = UserDataSyncEngine.batches(big, limits: .cloudKit)
        XCTAssertEqual(batches.map(\.count).reduce(0, +), 10)
        for b in batches { XCTAssertLessThanOrEqual(b.reduce(0) { $0 + $1.record.encodedByteCount }, 2_000_000) }
        XCTAssertGreaterThan(batches.count, 1)
    }

    func testALimitExceededErrorSplitsTheRequestInHalfAndRetriesBothHalves() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 40)
        cloud.inject(.save(.limitExceeded))
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(report.splits, 1)
        XCTAssertEqual(cloud.serverCount, 40)
        XCTAssertEqual(cloud.largestBatchSeen, 40, "the first try was the whole batch")
        XCTAssertEqual(cloud.saveCalls, 3)
        XCTAssertEqual(ledger.dirtyCount, 0)
    }

    func testRepeatedLimitErrorsKeepHalvingDownToOneRecordThenGiveUp() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 4)
        cloud.inject(.save(.limitExceeded), times: 100)
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .failed("request too large even for one record"))
        XCTAssertEqual(report.remainingDirty, 4, "nothing lost, everything still queued")
    }

    func testARecordOverTheOneMegabyteLimitIsReportedAndDoesNotBlockTheOthers() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 5)
        var huge = UDRecord(type: UDSchema.fixMatch, id: "huge")
        huge.set("title", .string(String(repeating: "y", count: 1_100_000)), at: stamp(1))
        ledger.apply(huge)
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(report.oversize, ["fixmatch/huge"])
        XCTAssertEqual(cloud.serverCount, 5)
        XCTAssertEqual(report.remainingDirty, 1)
    }

    // MARK: Errors

    func testARateLimitWaitsTheTimeTheServerGivesAndThenSucceeds() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger(), sleeps = Sleeps()
        addWatch(ledger, count: 3)
        cloud.inject(.save(.rateLimited(retryAfter: 7.5)))
        cloud.inject(.save(.rateLimited(retryAfter: nil)))
        let report = await makeEngine(ledger, cloud, sleeps: sleeps).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(sleeps.all, [7.5, 4.0], "server's number first, then the default back-off times the attempt")
        XCTAssertEqual(report.rateLimitWaits, 2)
        XCTAssertEqual(cloud.serverCount, 3)
    }

    func testEndlessRateLimitingEventuallyGivesUpAndKeepsTheEdits() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 3)
        cloud.inject(.save(.rateLimited(retryAfter: 1)), times: 50)
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .failed("rate limited, retry budget used up"))
        XCTAssertEqual(report.remainingDirty, 3)
    }

    func testAFullICloudKeepsEditsQueuedAndSaysSo() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 3)
        cloud.inject(.save(.quotaExceeded))
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .iCloudFull)
        XCTAssertEqual(report.remainingDirty, 3)
        let later = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(later.status, .synced, "after space is freed the same edits go up")
        XCTAssertEqual(cloud.serverCount, 3)
    }

    func testSignedOutDoesNothingAndKeepsLocalData() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        cloud.setAccount(.noAccount)
        addWatch(ledger, count: 3)
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .signedOut)
        XCTAssertEqual(cloud.saveCalls, 0)
        XCTAssertEqual(cloud.fetchCalls, 0)
        XCTAssertEqual(ledger.count, 3)
        XCTAssertEqual(report.remainingDirty, 3)
        cloud.setAccount(.restricted)
        let restricted = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(restricted.status, .signedOut)
        cloud.setAccount(.unknown)
        let unknown = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(unknown.status, .offline)
    }

    func testOfflineKeepsEditsAndTheNextSyncSendsThem() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 3)
        cloud.inject(.fetch(.networkUnavailable))
        let first = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(first.status, .offline)
        XCTAssertEqual(cloud.serverCount, 0)
        let second = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(second.status, .synced)
        XCTAssertEqual(cloud.serverCount, 3)
    }

    func testAnExpiredChangeTokenFetchesEverythingAgain() async throws {
        let cloud = InMemoryCloud()
        let a = makeLedger("A"), b = makeLedger("B")
        addWatch(a, count: 6)
        _ = await makeEngine(a, cloud).sync()
        _ = await makeEngine(b, cloud).sync()
        XCTAssertNotNil(b.changeToken)
        addWatch(a, count: 8, playedAt: 200)
        _ = await makeEngine(a, cloud).sync()
        cloud.expireTokens()
        let report = await makeEngine(b, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(report.fullRefetches, 1)
        XCTAssertEqual(b.watchEntries().count, 8)
    }

    func testLargeLibrariesArePulledInPages() async throws {
        let cloud = InMemoryCloud(pageSize: 100)
        let a = makeLedger("A"), b = makeLedger("B")
        addWatch(a, count: 750)
        _ = await makeEngine(a, cloud).sync()
        let report = await makeEngine(b, cloud).sync()
        XCTAssertEqual(report.pulled, 750)
        XCTAssertEqual(cloud.fetchCalls, 9, "8 pages for B (750 records, 100 per page) plus 1 for the first sync of A")
        XCTAssertEqual(b.watchEntries().count, 750)
    }

    func testTheCloudLosingARecordLetsTheNextSyncUploadItAgain() async throws {
        let cloud = InMemoryCloud(), ledger = makeLedger()
        addWatch(ledger, count: 3)
        _ = await makeEngine(ledger, cloud).sync()
        cloud.wipe()
        LedgerRecorder(ledger: ledger).recordFavorite(key: "item1", favorite: true, at: at(500))
        let report = await makeEngine(ledger, cloud).sync()
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(cloud.serverCount, 1, "only the edited record is dirty; the others are a known limitation of a wiped cloud")
    }
}
