import XCTest
@testable import UserData

final class TopShelfSnapshotTests: XCTestCase {
    private func folder() throws -> URL { try tempDir() }

    private func put(_ name: String, in dir: URL, bytes: Int = 10) throws {
        try Data(repeating: 1, count: bytes).write(to: dir.appendingPathComponent(name))
    }

    private func good(_ dir: URL) throws {
        try put("a.jpg", in: dir)
        try put("b.jpg", in: dir)
        try TopShelfSnapshotStore.write(TopShelfSnapshot(generatedAt: at(1), items: [
            .init(id: "a", title: "Hexfall", imageFile: "a.jpg", link: "videoplayer://item/a", progress: 0.4),
            .init(id: "b", title: "Show S01E02", subtitle: "Resume", imageFile: "b.jpg", link: "videoplayer://item/b"),
        ]), to: dir)
    }

    func testAGoodSnapshotGivesItsItemsWithArtwork() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        try good(dir)
        guard case let .items(items) = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected items") }
        XCTAssertEqual(items.map(\.item.id), ["a", "b"])
        XCTAssertEqual(items[0].imageURL.lastPathComponent, "a.jpg")
    }

    func testEveryKindOfMissingOrBadFileShowsNothingAndNeverCrashes() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(TopShelfSnapshotStore.fileName)
        func nothing(_ why: String, line: UInt = #line) {
            guard case let .nothing(reason) = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected nothing for \(why)", line: line) }
            XCTAssertFalse(reason.isEmpty, line: line)
        }
        nothing("empty folder")
        try Data().write(to: file); nothing("zero bytes")
        try Data("{ truncated".utf8).write(to: file); nothing("truncated json")
        try Data("[]".utf8).write(to: file); nothing("wrong shape")
        try Data(#"{"version":99,"generatedAt":1,"items":[]}"#.utf8).write(to: file); nothing("future version")
        try Data(repeating: 0x20, count: TopShelfSnapshotStore.maxBytes + 1).write(to: file); nothing("too large")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true); nothing("a folder where the file should be")
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(TopShelfSnapshotStore.read(from: dir.appendingPathComponent("does-not-exist")), .nothing(reason: "no snapshot file"))
    }

    func testItemsWithoutArtworkAreDroppedAndIfNoneIsLeftNothingShows() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        try good(dir)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.jpg"))
        guard case let .items(items) = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected one item") }
        XCTAssertEqual(items.map(\.item.id), ["b"])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("b.jpg"))
        XCTAssertEqual(TopShelfSnapshotStore.read(from: dir), .nothing(reason: "no item with artwork"))
    }

    func testAnEmptyOrFolderArtworkFileCountsAsMissing() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        try good(dir)
        try Data().write(to: dir.appendingPathComponent("a.jpg"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("b.jpg"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("b.jpg"), withIntermediateDirectories: true)
        XCTAssertEqual(TopShelfSnapshotStore.read(from: dir), .nothing(reason: "no item with artwork"))
    }

    func testImageNamesThatTryToLeaveTheFolderAreIgnored() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        try put("ok.jpg", in: dir)
        try TopShelfSnapshotStore.write(TopShelfSnapshot(generatedAt: at(1), items: [
            .init(id: "x", title: "Escape", imageFile: "../secret.jpg", link: "l"),
            .init(id: "y", title: "Slash", imageFile: "sub/ok.jpg", link: "l"),
            .init(id: "z", title: "", imageFile: "ok.jpg", link: "l"),
            .init(id: "w", title: "Fine", imageFile: "ok.jpg", link: "l"),
        ]), to: dir)
        guard case let .items(items) = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected one item") }
        XCTAssertEqual(items.map(\.item.id), ["w"])
    }

    func testOnlyTheFirstTwentyFourItemsAreUsed() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        try put("i.jpg", in: dir)
        let many = (0..<40).map { TopShelfSnapshot.Item(id: "\($0)", title: "T\($0)", imageFile: "i.jpg", link: "l") }
        try TopShelfSnapshotStore.write(TopShelfSnapshot(generatedAt: at(1), items: many), to: dir)
        guard case let .items(items) = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected items") }
        XCTAssertEqual(items.count, 24)
    }

    func testReadingAnUnreadableFileDoesNotCrash() throws {
        let dir = try folder(); defer { try? FileManager.default.removeItem(at: dir) }
        try good(dir)
        let file = dir.appendingPathComponent(TopShelfSnapshotStore.fileName)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        if getuid() == 0 { throw XCTSkip("running as root: file permissions do not block reads, so this case cannot be produced") }
        guard case .nothing = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected nothing") }
    }
}

// MARK: Bootstrap

final class FakeTarget: LibraryRestoreTarget, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [String] = []
    var watchGateClosedAtRestore: Bool?
    private var gateClosed = false
    var restoredWatch: [(key: String, value: UDWatchValue)] = []
    var restoredViews: [UDViewValue] = []
    var deletedViews: [String] = []
    var patches: [UDRecord] = []
    func log(_ e: String) { lock.withLock { events.append(e) } }
    func closeWatchGate() async { log("close"); gateClosed = true }
    func openWatchGate() async { log("open"); gateClosed = false }
    func restore(watch: [(key: String, value: UDWatchValue)], views: [UDViewValue], deletedViewUIDs: [String]) async throws {
        log("restore(\(watch.count),\(views.count))")
        watchGateClosedAtRestore = gateClosed
        restoredWatch = watch; restoredViews = views; deletedViews = deletedViewUIDs
    }
    func currentUserData() async throws -> [UDRecord] { log("current"); return patches }
    func rescan() async throws { log("rescan") }
}

final class BootstrapTests: XCTestCase {
    private func setup(account: UDAccountStatus = .available) -> (InMemoryCloud, UserDataLedger, UserDataSyncEngine, UDEssentialsStore, InMemoryCredentialStore, InMemoryKeyValueStore) {
        let cloud = InMemoryCloud()
        cloud.setAccount(account)
        let ledger = makeLedger("A")
        let kv = InMemoryKeyValueStore()
        return (cloud, ledger, makeEngine(ledger, cloud), UDEssentialsStore(store: kv), InMemoryCredentialStore(), kv)
    }

    private func seedCloud(_ cloud: InMemoryCloud, items: Int) async {
        let other = makeLedger("B")
        let rec = LedgerRecorder(ledger: other)
        for i in 0..<items { rec.recordProgress(key: "k\(i)", UDWatchValue(position: Double(i), duration: 100, lastPlayed: at(10)), at: at(10)) }
        rec.recordView(UDViewValue(uid: "v1", name: "Action", scopeKind: 0, scopeSource: "", scopePath: "", query: "{}", pinned: true, position: 0, createdAt: at(1)), at: at(1))
        rec.recordViewDeleted(uid: "v2", at: at(2))
        other.upsertSource(UDSourceDefinition(id: "s1", kind: "smb", name: "NAS", host: "nas", auth: "password"), at: at(1))
        _ = await makeEngine(other, cloud).sync()
    }

    func testRebuildClosesTheGateRestoresOpensTheGateThenRescansInThatOrder() async throws {
        let (cloud, ledger, engine, essentials, creds, _) = setup()
        await seedCloud(cloud, items: 5)
        let target = FakeTarget()
        let states = StateLog()
        let boot = LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds, onState: { states.add($0) })
        let report = try await boot.run(health: .missing, ledgerWasLost: true, target: target)
        XCTAssertEqual(report.status, .synced)
        XCTAssertEqual(target.events, ["close", "restore(5,1)", "open", "rescan"])
        XCTAssertEqual(target.watchGateClosedAtRestore, true, "state is loaded while the gate is still closed")
        XCTAssertEqual(target.deletedViews, ["v2"])
        XCTAssertEqual(states.all, [.checking, .restoringUserData, .rescanning, .ready(note: .passwordsNeeded(sourceIDs: ["s1"]))])
        let final = await boot.state
        XCTAssertEqual(final, .ready(note: .passwordsNeeded(sourceIDs: ["s1"])), "the source came back but tvOS does not sync Keychain items")
    }

    func testEveryKindOfDamagedDatabaseTakesTheRebuildPath() async throws {
        for health: UDDatabaseHealth in [.missing, .empty, .corrupt("malformed")] {
            let (cloud, ledger, engine, essentials, creds, _) = setup()
            await seedCloud(cloud, items: 2)
            let target = FakeTarget()
            _ = try await LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds).run(health: health, ledgerWasLost: true, target: target)
            XCTAssertEqual(target.events.first, "close", "\(health)")
            XCTAssertTrue(target.events.contains("rescan"), "\(health)")
        }
    }

    func testSignedOutWithNothingLocalSaysHistoryCouldNotBeRestored() async throws {
        let (_, ledger, engine, essentials, creds, _) = setup(account: .noAccount)
        let target = FakeTarget()
        let boot = LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds)
        let report = try await boot.run(health: .missing, ledgerWasLost: true, target: target)
        XCTAssertEqual(report.status, .signedOut)
        let state = await boot.state
        XCTAssertEqual(state, .ready(note: .historyNotRestored))
        XCTAssertEqual(target.events, ["close", "restore(0,0)", "open", "rescan"], "the app still works, with no history")
    }

    func testSignedOutStillGetsSourcesAndSettingsBackFromTheEssentials() async throws {
        let (_, ledger, engine, essentials, creds, kv) = setup(account: .noAccount)
        let before = makeLedger("A")
        before.upsertSource(UDSourceDefinition(id: "s1", kind: "webdav", name: "NAS", auth: "none"), at: at(1))
        before.setSetting("nextEpisode", .string("credits"), at: at(2))
        try UDEssentialsStore(store: kv).save(from: before)
        let target = FakeTarget()
        let boot = LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds)
        _ = try await boot.run(health: .missing, ledgerWasLost: true, target: target)
        XCTAssertEqual(ledger.sourceDefinitions().map(\.id), ["s1"])
        XCTAssertEqual(ledger.settingValues()["nextEpisode"], .string("credits"))
        let state = await boot.state
        XCTAssertEqual(state, .ready(note: .historyNotRestored))
    }

    func testOfflineRestoreUsesWhatIsLocalAndSaysSo() async throws {
        let (cloud, ledger, engine, essentials, creds, _) = setup()
        cloud.setAccount(.unknown)
        let target = FakeTarget()
        let boot = LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds)
        _ = try await boot.run(health: .missing, ledgerWasLost: false, target: target)
        let state = await boot.state
        XCTAssertEqual(state, .ready(note: .restoredOffline))
    }

    func testAnIntactDatabaseWithALostLedgerRebuildsTheLedgerFromTheDatabaseFirst() async throws {
        let (cloud, ledger, engine, essentials, creds, _) = setup()
        let target = FakeTarget()
        target.patches = [UDWatch.progressPatch(key: "movie:a", UDWatchValue(position: 5, duration: 100, lastPlayed: at(9)), epoch: 0, at: stamp(9))]
        let boot = LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds)
        _ = try await boot.run(health: .ok, ledgerWasLost: true, target: target)
        XCTAssertEqual(target.events.first, "current")
        XCTAssertEqual(cloud.serverCount, 1, "and the cloud gets it too")
        XCTAssertFalse(target.events.contains("rescan"), "no rescan when the database is fine")
    }

    func testAnIntactDatabaseAndLedgerJustSyncs() async throws {
        let (cloud, ledger, engine, essentials, creds, _) = setup()
        await seedCloud(cloud, items: 3)
        let target = FakeTarget()
        _ = try await LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds).run(health: .ok, ledgerWasLost: false, target: target)
        XCTAssertFalse(target.events.contains("rescan"))
        XCTAssertEqual(target.restoredWatch.count, 3, "state another device wrote is loaded too")
    }

    func testICloudFullIsReportedAfterTheRestore() async throws {
        let (cloud, ledger, engine, essentials, creds, _) = setup()
        ledger.setSetting("a", .int(1))
        cloud.inject(.save(.quotaExceeded))
        let boot = LibraryBootstrap(ledger: ledger, engine: engine, essentials: essentials, credentials: creds)
        _ = try await boot.run(health: .missing, ledgerWasLost: false, target: FakeTarget())
        let state = await boot.state
        XCTAssertEqual(state, .ready(note: .iCloudFull))
    }
}

final class StateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [LibraryBootstrapState] = []
    func add(_ s: LibraryBootstrapState) { lock.withLock { values.append(s) } }
    var all: [LibraryBootstrapState] { lock.withLock { values } }
}
