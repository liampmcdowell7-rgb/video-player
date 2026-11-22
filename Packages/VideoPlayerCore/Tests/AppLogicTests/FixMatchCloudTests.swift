import XCTest
import Foundation
import MetadataOnline
import UserData
@testable import AppLogic

/// R381 (audit #14): Fix Match choices in the iCloud-synced ledger, matches.json as the cache. These tests cover the rules
/// and the local files only; that iCloud sync carries the records between devices can only be checked on a device.
final class FixMatchCopiesTests: XCTestCase {
    private func match(_ path: String, _ tmdbID: Int, at seconds: Double, scope: MatchScope = .file) -> StoredMatch {
        StoredMatch(scope: scope, path: path, tmdbID: tmdbID, kind: .movie, title: "Sample Movie \(tmdbID)", year: 2020,
                    createdAt: Date(timeIntervalSince1970: seconds))
    }

    func testNoCacheFileRebuildsItFromICloud() {
        let cloud = [match("/m/b.mkv", 2, at: 200), match("/m/a.mkv", 1, at: 100)]
        let outcome = FixMatchCopies.resolve(cache: nil, cloud: cloud, cloudRemoved: [:])
        XCTAssertEqual(outcome.matches.map(\.tmdbID), [1, 2], "oldest first")
        XCTAssertTrue(outcome.rewriteCache)
        XCTAssertEqual(outcome.upload, [])
    }

    func testNoCacheAndNothingInICloudWritesNoFile() {
        let outcome = FixMatchCopies.resolve(cache: nil, cloud: [], cloudRemoved: [:])
        XCTAssertEqual(outcome.matches, [])
        XCTAssertFalse(outcome.rewriteCache)
    }

    func testTheICloudCopyWinsForTheSameFile() {
        let local = match("/m/a.mkv", 1, at: 100)
        let other = match("/m/a.mkv", 9, at: 300)
        let outcome = FixMatchCopies.resolve(cache: [local], cloud: [other], cloudRemoved: [:])
        XCTAssertEqual(outcome.matches, [other])
        XCTAssertTrue(outcome.rewriteCache)
        XCTAssertEqual(outcome.upload, [])
    }

    func testACacheOnlyChoiceIsKeptAndSentToICloud() {
        let old = match("/m/a.mkv", 1, at: 100)
        let outcome = FixMatchCopies.resolve(cache: [old], cloud: [], cloudRemoved: [:])
        XCTAssertEqual(outcome.matches, [old])
        XCTAssertEqual(outcome.upload, [old])
        XCTAssertFalse(outcome.rewriteCache)
    }

    func testALaterRemovalInICloudDropsTheCacheOnlyChoice() {
        let old = match("/m/a.mkv", 1, at: 100)
        let removedLater = [FixMatchRecords.id(old): Date(timeIntervalSince1970: 150)]
        let outcome = FixMatchCopies.resolve(cache: [old], cloud: [], cloudRemoved: removedLater)
        XCTAssertEqual(outcome.matches, [])
        XCTAssertEqual(outcome.upload, [])
        XCTAssertTrue(outcome.rewriteCache)
    }

    func testAChoiceMadeAfterAnOlderRemovalStays() {
        let newer = match("/m/a.mkv", 1, at: 200)
        let outcome = FixMatchCopies.resolve(cache: [newer], cloud: [], cloudRemoved: [FixMatchRecords.id(newer): Date(timeIntervalSince1970: 150)])
        XCTAssertEqual(outcome.matches, [newer])
        XCTAssertEqual(outcome.upload, [newer])
    }

    func testEqualCopiesNeedNoWrite() {
        let both = [match("/m/a.mkv", 1, at: 100), match("/shows/x", 5, at: 120, scope: .season(2))]
        let outcome = FixMatchCopies.resolve(cache: both, cloud: both, cloudRemoved: [:])
        XCTAssertFalse(outcome.rewriteCache)
        XCTAssertEqual(outcome.upload, [])
    }
}

final class FixMatchRecordsTests: XCTestCase {
    func testAChoiceSurvivesTheRoundTripForEveryScope() throws {
        let device = UDStamp(time: 1_000, device: "test-device")
        for scope in [MatchScope.file, .season(3), .folder] {
            let original = StoredMatch(scope: scope, path: "/shows/Sample Show 1", fileSize: scope == .file ? 1234 : nil, tmdbID: 42,
                                       kind: .series, title: "Sample Show 1", year: nil, createdAt: Date(timeIntervalSince1970: 500))
            let back = try XCTUnwrap(FixMatchRecords.match(FixMatchRecords.record(original, stamp: device)))
            XCTAssertEqual(back, original, "\(scope)")
        }
    }

    func testTheRecordIsKeyedByScopeAndPath() {
        XCTAssertEqual(FixMatchRecords.id(scope: .file, path: "/a/b.mkv"), "file:/a/b.mkv")
        XCTAssertEqual(FixMatchRecords.id(scope: .season(2), path: "/a"), "season2:/a")
        XCTAssertEqual(FixMatchRecords.id(scope: .folder, path: "/a"), "folder:/a")
        XCTAssertEqual(FixMatchRecords.type, "fixmatch", "the record type string is stored in the cloud and never renamed")
    }

    func testATombstoneHoldsNoChoice() {
        let gone = FixMatchRecords.tombstone(scope: .file, path: "/a/b.mkv", stamp: UDStamp(time: 1, device: "d"))
        XCTAssertNil(FixMatchRecords.match(gone))
    }

    func testTheDateIsKeptInWholeSecondsAsTheFileKeepsIt() throws {
        let original = StoredMatch(scope: .file, path: "/a.mkv", tmdbID: 1, kind: .movie, title: "T", year: 2000,
                                   createdAt: Date(timeIntervalSince1970: 500.75))
        let back = try XCTUnwrap(FixMatchRecords.match(FixMatchRecords.record(original, stamp: UDStamp(time: 1, device: "d"))))
        XCTAssertEqual(back.createdAt, Date(timeIntervalSince1970: 500))
    }
}

final class CloudMatchStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("fixmatch-cloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func choice(_ path: String, _ tmdbID: Int) -> StoredMatch {
        StoredMatch(scope: .file, path: path, tmdbID: tmdbID, kind: .movie, title: "Sample Movie \(tmdbID)", year: 2021,
                    createdAt: Date(timeIntervalSince1970: 1_000))
    }

    func testASaveGoesIntoTheFileAndTheLedger() async throws {
        let url = dir.appendingPathComponent("matches.json")
        let ledger = UserDataLedger(deviceID: "test-device")
        let store = CloudMatchStore(url: url, ledger: ledger)
        try await store.save(choice("/m/a.mkv", 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(ledger.records(ofType: FixMatchRecords.type).compactMap(FixMatchRecords.match).map(\.tmdbID), [1])
    }

    func testAMissingFileIsRebuiltFromTheLedger() async throws {
        let url = dir.appendingPathComponent("matches.json")
        let ledger = UserDataLedger(deviceID: "test-device")
        try await CloudMatchStore(url: url, ledger: ledger).save(choice("/m/a.mkv", 1))
        try FileManager.default.removeItem(at: url)
        let fresh = CloudMatchStore(url: url, ledger: ledger)
        let all = await fresh.all()
        XCTAssertEqual(all.map(\.tmdbID), [1])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the cache file is written again")
        let reread = await JSONFileMatchStore(url: url).all()
        XCTAssertEqual(reread.map(\.tmdbID), [1])
    }

    func testAChoiceFromBeforeTheLedgerIsSentToIt() async throws {
        let url = dir.appendingPathComponent("matches.json")
        try await JSONFileMatchStore(url: url).save(choice("/m/old.mkv", 7))
        let ledger = UserDataLedger(deviceID: "test-device")
        let all = await CloudMatchStore(url: url, ledger: ledger).all()
        XCTAssertEqual(all.map(\.tmdbID), [7])
        XCTAssertEqual(ledger.records(ofType: FixMatchRecords.type).count, 1)
    }

    func testRemovingAndUndoingReachTheLedger() async throws {
        let url = dir.appendingPathComponent("matches.json")
        let ledger = UserDataLedger(deviceID: "test-device")
        let store = CloudMatchStore(url: url, ledger: ledger)
        let first = choice("/m/a.mkv", 1)
        try await store.save(first)
        try await store.remove(id: first.id)
        XCTAssertTrue(ledger.records(ofType: FixMatchRecords.type).isEmpty, "the removal is a tombstone in the ledger")
        try await Task.sleep(nanoseconds: 2_000_000)
        try await store.save(first)
        XCTAssertEqual(ledger.records(ofType: FixMatchRecords.type).count, 1, "Undo (save the old choice again) brings it back")
    }

    func testAChoiceFromAnotherDeviceReachesTheCacheAfterTheRefreshInterval() async throws {
        let url = dir.appendingPathComponent("matches.json")
        let ledger = UserDataLedger(deviceID: "test-device")
        let now = Clock(Date(timeIntervalSince1970: 10_000))
        let store = CloudMatchStore(url: url, ledger: ledger, clock: { now.value })
        try await store.save(choice("/m/a.mkv", 1))
        // Another device's choice arrives through the sync (here applied straight into the ledger).
        ledger.apply(FixMatchRecords.record(choice("/m/b.mkv", 2), stamp: UDStamp(time: 20_000, device: "other-device")))
        let soon = await store.all()
        XCTAssertEqual(soon.map(\.tmdbID), [1], "within the interval the cache answers")
        now.value = now.value.addingTimeInterval(CloudMatchStore.refreshInterval)
        let later = await store.all()
        XCTAssertEqual(Set(later.map(\.tmdbID)), [1, 2])
    }
}

private final class Clock: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}
