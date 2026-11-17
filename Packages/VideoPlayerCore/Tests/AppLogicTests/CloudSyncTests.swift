import XCTest
import UserData
@testable import AppLogic

// The scheduling around the ledger sync, against `InMemoryCloud` (a fake) and a fake clock. No real cloud is contacted.

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 1_700_000_000.0
    func now() -> Date { lock.withLock { Date(timeIntervalSince1970: t) } }
    func advance(_ s: Double) { lock.withLock { t += s } }
}

final class CloudSyncCoordinatorTests: XCTestCase {
    private struct Rig {
        let ledger = UserDataLedger(deviceID: "A")
        let cloud = InMemoryCloud()
        let clock = TestClock()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        let states = StateLog()
        let coordinator: CloudSyncCoordinator
        let engine: UserDataSyncEngine

        init() {
            let ledger = self.ledger, cloud = self.cloud, clock = self.clock, states = self.states
            engine = UserDataSyncEngine(ledger: ledger, cloud: cloud, sleep: { _ in })
            coordinator = CloudSyncCoordinator(ledger: ledger, engine: engine, ledgerFile: file, now: { clock.now() }, onState: { states.add($0) })
        }

        func edit(_ n: Int) { _ = ledger.apply(UDSettings.patch("k\(n)", .int(Int64(n)), at: ledger.stamp())) }
        func start() async { await coordinator.start(startupSync: { await self.engine.sync() }) }
    }

    final class StateLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _all: [CloudSyncState] = []
        func add(_ s: CloudSyncState) { lock.withLock { _all.append(s) } }
        var all: [CloudSyncState] { lock.withLock { _all } }
    }

    func testTheLaunchSyncUploadsWhatIsThereAndSavesTheLedgerFile() async throws {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        r.edit(1); r.edit(2)
        await r.start()
        let state = await r.coordinator.state
        XCTAssertEqual(state.status, .synced)
        XCTAssertNotNil(state.lastSynced)
        XCTAssertEqual(r.cloud.serverCount, 1, "both settings are fields of one record")
        let copy = UserDataLedger(deviceID: "A")
        XCTAssertEqual(copy.load(from: r.file), .loaded(records: 1), "the local copy was written")
        XCTAssertTrue(r.states.all.contains { $0.status == .syncing }, "the screen can show that it is syncing")
    }

    func testALocalChangeWaitsForThePauseThenGoesUpInOneRequest() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        await r.start()
        let before = r.cloud.saveCalls
        r.edit(1)
        await r.coordinator.request(.localChange)
        r.clock.advance(2)
        r.edit(2)
        var ran = await r.coordinator.tick()
        XCTAssertFalse(ran, "still inside the 5 second pause")
        XCTAssertEqual(r.cloud.saveCalls, before)
        r.clock.advance(4)
        ran = await r.coordinator.tick()
        XCTAssertTrue(ran)
        XCTAssertEqual(r.cloud.saveCalls, before + 1, "two edits, one upload")
        XCTAssertEqual(r.ledger.dirtyCount, 0)
    }

    func testChangesAreNoticedEvenWithoutAnExplicitRequest() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        await r.start()
        r.edit(1)
        _ = await r.coordinator.tick()      // notices the dirty record and starts the pause
        r.clock.advance(6)
        let ran = await r.coordinator.tick()
        XCTAssertTrue(ran)
        XCTAssertEqual(r.ledger.dirtyCount, 0)
    }

    func testSignedOutKeepsEditsAndDoesNotRetryUntilTheAccountChanges() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        r.cloud.setAccount(.noAccount)
        await r.start()
        var state = await r.coordinator.state
        XCTAssertEqual(state.status, .signedOut)
        r.edit(1)
        await r.coordinator.request(.localChange)
        r.clock.advance(30)
        let ran = await r.coordinator.tick()
        XCTAssertFalse(ran, "a signed-out device does not keep asking")
        XCTAssertEqual(r.cloud.saveCalls, 0)
        XCTAssertEqual(r.ledger.dirtyCount, 1)
        r.cloud.setAccount(.available)
        await r.coordinator.request(.accountChanged)
        let tk1 = await r.coordinator.tick()
        XCTAssertTrue(tk1)
        state = await r.coordinator.state
        XCTAssertEqual(state.status, .synced)
        XCTAssertEqual(r.ledger.dirtyCount, 0)
        XCTAssertEqual(r.cloud.serverCount, 1)
    }

    func testOfflineBacksOffAndDoublesTheWaitEachTime() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        r.cloud.setAccount(.unknown)
        await r.start()                                   // failure 1: waits 30 s
        var state = await r.coordinator.state
        XCTAssertEqual(state.status, .offline)
        r.edit(1)
        await r.coordinator.request(.localChange)
        r.clock.advance(10)
        var ran = await r.coordinator.tick()
        XCTAssertFalse(ran, "still backing off")
        r.clock.advance(25)
        ran = await r.coordinator.tick()                  // 35 s after the failure: tries (failure 2: waits 60 s)
        XCTAssertTrue(ran)
        r.clock.advance(35)
        r.edit(2)
        await r.coordinator.request(.localChange)
        ran = await r.coordinator.tick()
        XCTAssertFalse(ran, "the second wait is 60 s, not 30")
        r.cloud.setAccount(.available)
        r.clock.advance(30)
        ran = await r.coordinator.tick()
        XCTAssertTrue(ran)
        state = await r.coordinator.state
        XCTAssertEqual(state.status, .synced)
    }

    func testAnExplicitRequestOverridesTheBackOff() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        r.cloud.setAccount(.unknown)
        await r.start()
        r.cloud.setAccount(.available)
        r.edit(1)
        await r.coordinator.request(.manual)
        let tk2 = await r.coordinator.tick()
        XCTAssertTrue(tk2)
        XCTAssertEqual(r.ledger.dirtyCount, 0)
    }

    func testAFullCloudIsReportedAndNotRetriedByLocalEditsAlone() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        r.edit(1)
        r.cloud.inject(.save(.quotaExceeded))
        await r.start()
        let state = await r.coordinator.state
        XCTAssertEqual(state.status, .iCloudFull)
        XCTAssertEqual(state.pending, 1, "the edit stays queued")
        r.edit(2)
        await r.coordinator.request(.localChange)
        r.clock.advance(60)
        let tk3 = await r.coordinator.tick()
        XCTAssertFalse(tk3)
        XCTAssertTrue(CloudSyncText.line(state).contains("storage is full"))
    }

    func testThePeriodicPullBringsInAnotherDevicesEdits() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        await r.start()
        r.cloud.serverWrite(UDWatchlist.patch(UDWatchlistEntry(kind: "movie", tmdbID: 3, title: "From Elsewhere", addedAt: r.clock.now()), at: UDStamp(time: r.clock.now().timeIntervalSince1970 + 1, device: "B")))
        r.clock.advance(60)
        let tk4 = await r.coordinator.tick()
        XCTAssertFalse(tk4, "too early")
        r.clock.advance(15 * 60)
        let tk5 = await r.coordinator.tick()
        XCTAssertTrue(tk5)
        XCTAssertEqual(r.ledger.watchlist().map(\.title), ["From Elsewhere"])
    }

    func testBecomingActiveAndAnAccountChangeSyncAtOnce() async {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        await r.start()
        let calls = r.cloud.fetchCalls
        await r.coordinator.request(.becameActive)
        let tk6 = await r.coordinator.tick()
        XCTAssertTrue(tk6)
        XCTAssertGreaterThan(r.cloud.fetchCalls, calls)
    }

    func testTheLedgerFileIsRewrittenAtEveryTickThatFindsChanges() async throws {
        let r = Rig()
        defer { try? FileManager.default.removeItem(at: r.file) }
        r.cloud.setAccount(.noAccount)
        await r.start()
        r.edit(1)
        _ = await r.coordinator.tick()
        let copy = UserDataLedger(deviceID: "A")
        XCTAssertEqual(copy.load(from: r.file), .loaded(records: 1), "even signed out, the local copy is saved")
    }

    func testLoadingTheLedgerFileSaysWhetherItWasLost() throws {
        let ledger = UserDataLedger(deviceID: "A")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = UserDataSyncEngine(ledger: ledger, cloud: InMemoryCloud(), sleep: { _ in })
        let c = CloudSyncCoordinator(ledger: ledger, engine: engine, ledgerFile: file)
        XCTAssertTrue(c.loadLedgerFile(), "no file: lost")
        _ = ledger.apply(UDSettings.patch("a", .int(1), at: ledger.stamp()))
        try ledger.save(to: file)
        XCTAssertFalse(c.loadLedgerFile(), "a good file: not lost")
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(c.loadLedgerFile(), "a damaged file counts as lost")
    }

    func testTheStatusSentencesAreHonest() {
        var s = CloudSyncState()
        XCTAssertEqual(CloudSyncText.line(s), "iCloud sync has not started yet.")
        s.status = .synced; s.lastSynced = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(CloudSyncText.line(s, now: Date(timeIntervalSince1970: 1000 + 5 * 60)), "Last synced 5 minutes ago.")
        s.status = .signedOut; s.pending = 3
        XCTAssertTrue(CloudSyncText.line(s).contains("3 changes are waiting"))
        s.status = .offline; s.pending = 0
        XCTAssertTrue(CloudSyncText.line(s).contains("Nothing is waiting"))
    }
}
