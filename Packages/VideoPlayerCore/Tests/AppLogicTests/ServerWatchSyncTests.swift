import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

/// R309, two-way watch state stage 2: the switch, the app's own changes, the player's reports and the same film on two
/// sources. A fake writer stands in for the server (the real Plex requests are tested in SourcePlexTests).
final class ServerWatchSyncTests: XCTestCase {
    /// Every call the sync made, in order. While `reachable` is false every call throws as a network failure would.
    final class FakeWriter: ServerWatchWriting, @unchecked Sendable {
        enum Call: Equatable { case played(String), unplayed(String), report(String, ServerPlaybackState, Double, String?) }
        private let lock = NSLock()
        private var made: [Call] = []
        private var offline: [Date?] = []
        private var up = true
        var calls: [Call] { lock.withLock { made } }
        /// `offlineUpdated` of each report, in order.
        var offlineTimes: [Date?] { lock.withLock { offline } }
        var reachable: Bool {
            get { lock.withLock { up } }
            set { lock.withLock { up = newValue } }
        }
        private func add(_ call: Call) throws {
            try lock.withLock {
                guard up else { throw SourceError.transport("no answer") }
                made.append(call)
            }
        }
        func report(_ r: ServerTimelineReport) async throws {
            try add(.report(r.itemKey, r.state, r.position, r.sessionIdentifier))
            lock.withLock { offline.append(r.offlineUpdated) }
        }
        func markPlayed(itemKey: String) async throws { try add(.played(itemKey)) }
        func markUnplayed(itemKey: String) async throws { try add(.unplayed(itemKey)) }
    }

    /// A server source: knows the server key and watch state of each file path; counts how often it was asked.
    final class FakeServerSource: ServerWatchSource, @unchecked Sendable {
        let writer = FakeWriter()
        let keys: [String: String]
        private let lock = NSLock()
        private var asked = 0
        private var known: [String: ServerWatchState] = [:]
        var askedCount: Int { lock.withLock { asked } }
        init(keys: [String: String]) { self.keys = keys }
        var watchWriter: any ServerWatchWriting { writer }
        /// The server's own state of a file (default: listed, never played).
        func setState(_ path: String, played: Bool = false, position: Double? = nil, at: Date? = nil) {
            lock.withLock { known[path] = ServerWatchState(itemKey: keys[path] ?? "", played: played, position: position, lastViewedAt: at, duration: 5_400) }
        }
        private func check() throws {
            lock.withLock { asked += 1 }
            guard writer.reachable else { throw SourceError.transport("no answer") }
        }
        func serverItemKey(at path: String) async throws -> String? { try check(); return keys[path] }
        func serverWatchState(at path: String) async throws -> ServerWatchState? {
            try check()
            guard let key = keys[path] else { return nil }
            return lock.withLock { known[path] } ?? ServerWatchState(itemKey: key, played: false, duration: 5_400)
        }
        func serverWatchStates() async throws -> [String: ServerWatchState] {
            try check()
            var out: [String: ServerWatchState] = [:]
            for path in keys.keys { out[path] = try await serverWatchState(at: path) }
            return out
        }
    }

    final class Switches: @unchecked Sendable {
        private let lock = NSLock()
        private var on: Set<String>
        init(_ on: Set<String>) { self.on = on }
        func isOn(_ id: String) -> Bool { lock.withLock { on.contains(id) } }
        func set(_ id: String, _ value: Bool) { lock.withLock { if value { on.insert(id) } else { on.remove(id) } } }
    }

    static let plexID = "plex1"
    static let otherID = "src1"
    static let hexfall = "/Movies/Hexfall (1995)/Hexfall (1995).mkv"
    static let aftlander = "/Movies/Aftlander (1979)/Aftlander (1979).mkv"

    /// The usual library on a non-Plex source (`src1`), plus a Plex source holding Hexfall and Aftlander under the same file
    /// names (so they are the same items). The store records through a `ServerWatchRecorder` wired to the sync.
    struct Rig {
        let store: SQLiteLibraryStore
        let ledger: UserDataLedger
        let recorder: ServerWatchRecorder
        let sync: ServerWatchSync
        let plex: FakeServerSource
        let switches: Switches
        let runner: Task<Void, Never>

        func flush() async { await sync.flush() }
    }

    private func makeRig(switchOn: Bool = true, queue: ServerWatchQueue = ServerWatchQueue(storage: MemoryServerWatchQueueStorage())) async throws -> Rig {
        let ledger = UserDataLedger(deviceID: "device-a")
        let recorder = ServerWatchRecorder(wrapping: LedgerRecorder(ledger: ledger))
        let store = try SQLiteLibraryStore(path: ":memory:", recorder: recorder)
        let rig = LibraryRig(store: store, source: TreeSource())
        try await rig.fill()
        let plexTree = TreeSource()
        plexTree.put(Self.hexfall, size: 20_000, modified: dayOffset(4))
        plexTree.put(Self.aftlander, size: 20_000, modified: dayOffset(4))
        try await store.upsertSource(LibrarySourceRecord(id: Self.plexID, kind: .plex, name: "Plex", addedAt: epoch))
        let summary = try await LibrarySyncer(store: store, source: plexTree, sourceID: Self.plexID, clock: { dayOffset(100) }).sync()
        XCTAssertEqual(summary.status, .completed)

        let plex = FakeServerSource(keys: [Self.hexfall: "101", Self.aftlander: "102"])
        let switches = Switches(switchOn ? [Self.plexID] : [])
        let sync = ServerWatchSync(store: store, isOn: { switches.isOn($0) }, source: { $0 == Self.plexID ? plex : nil }, queue: queue,
                                   resetTime: { key in
                                       let e = UDWatch.epoch(of: ledger.record(type: UDSchema.watch, id: key))
                                       return e > 0 ? Date(timeIntervalSince1970: e) : nil
                                   },
                                   makeSessionID: { "session-1" }, now: { dayOffset(200) })
        recorder.setHandler { sync.send(.changed($0)) }
        let runner = Task { await sync.run() }
        return Rig(store: store, ledger: ledger, recorder: recorder, sync: sync, plex: plex, switches: switches, runner: runner)
    }

    private func file(_ rig: Rig, itemID: Int64, sourceID: String) async throws -> StoredFile {
        let files = try await rig.store.versions(of: itemID)
        return try XCTUnwrap(files.first { $0.sourceID == sourceID })
    }

    private func movieID(_ rig: Rig, _ title: String) async throws -> Int64 {
        try await LibraryRig(store: rig.store, source: TreeSource()).movieID(title)
    }

    // MARK: The switch

    func testTheSwitchIsOffByDefaultAndOnlyForPlex() {
        let plex = UDSourceDefinition(id: "p1", kind: "plex", name: "Home", path: "https://h:32400", auth: "token", options: "machine=m1")
        XCTAssertFalse(PlexWatchSyncOption.isOn(plex))
        let on = PlexWatchSyncOption.setting(true, on: plex)
        XCTAssertTrue(PlexWatchSyncOption.isOn(on))
        XCTAssertEqual(SourceOptions.parse(on.options)["machine"], "m1", "other options are kept")
        XCTAssertFalse(PlexWatchSyncOption.isOn(PlexWatchSyncOption.setting(false, on: on)))
        XCTAssertTrue(PlexWatchSyncOption.applies(toKind: "plex"))
        for kind in ["webdav", "smb", "jellyfin", "emby", "nfs"] { XCTAssertFalse(PlexWatchSyncOption.applies(toKind: kind), kind) }
        var webdav = plex
        webdav.kind = "webdav"
        webdav.options = "watchSync=1"
        XCTAssertFalse(PlexWatchSyncOption.isOn(webdav))
        XCTAssertEqual(PlexWatchSyncOption.title, "Sync Watched Status with Plex")
    }

    func testWithTheSwitchOffNothingIsEverSentAndTheServerIsNotAsked() async throws {
        let rig = try await makeRig(switchOn: false)
        let hexfall = try await movieID(rig, "Hexfall")
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        try await rig.store.markWatched(itemIDs: [hexfall], watched: false, at: dayOffset(102))
        try await rig.store.updateProgress(itemID: hexfall, position: 5_300, duration: 5_400, at: dayOffset(103))
        rig.sync.send(.started(itemID: hexfall, file: try await file(rig, itemID: hexfall, sourceID: Self.plexID)))
        rig.sync.send(.progress(state: .playing, position: 10, duration: 5_400, at: dayOffset(104)))
        rig.sync.send(.stopped(position: 20, duration: 5_400, at: dayOffset(104)))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [])
        XCTAssertEqual(rig.plex.askedCount, 0, "a source with the switch off is not even asked for its server key")
        let watched = try await rig.store.item(id: hexfall)?.watch.watched
        XCTAssertEqual(watched, true, "the app's own watch state works as before")
    }

    // MARK: The app's own changes

    func testMarkWatchedAndUnwatchedAreSent() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall")
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        try await rig.store.markWatched(itemIDs: [hexfall], watched: false, at: dayOffset(102))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [.played("101"), .unplayed("101")])
    }

    func testThe95PercentRuleSendsWatchedOnceAndTheEndOfTheFilmDoesNotRepeatIt() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall")
        try await rig.store.updateProgress(itemID: hexfall, position: 600, duration: 5_400, at: dayOffset(101))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [], "a resume point alone is not a watched change")
        try await rig.store.updateProgress(itemID: hexfall, position: 5_200, duration: 5_400, at: dayOffset(101))
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [.played("101")])
    }

    func testAnItemOnlyOnAnotherSourceSendsNothing() async throws {
        let rig = try await makeRig()
        try await rig.store.markWatched(itemIDs: [try await movieID(rig, "Zornwick")], watched: true, at: dayOffset(101))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [])
    }

    func testTheSeedFromTheServerIsNotSentBack() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall")
        try await ServerWatchEcho.$suppressed.withValue(true) {
            _ = try await PlexWatchSeed(store: rig.store, files: rig.store).apply([hexfall: .init(positionSeconds: nil, viewCount: 1, lastViewedAt: dayOffset(90), durationSeconds: 5_400)])
        }
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [])
        let watched = try await rig.store.item(id: hexfall)?.watch.watched
        XCTAssertEqual(watched, true)
    }

    // MARK: The same film on two sources (owner's decision, 21 Nov 2026)

    func testTheSameFilmMarkedOrPlayedThroughAnotherSourceIsSentToItsPlexFile() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall")
        let versions = try await rig.store.versions(of: hexfall)
        XCTAssertEqual(versions.count, 2, "one item, a file on each source")
        let other = try await file(rig, itemID: hexfall, sourceID: Self.otherID)

        // Played through the other source: the Plex file gets the reports, and the 95 % rule marks it played there.
        rig.sync.send(.started(itemID: hexfall, file: other))
        rig.sync.send(.progress(state: .playing, position: 5_000, duration: 5_400, at: dayOffset(101)))
        try await rig.store.updateProgress(itemID: hexfall, position: 5_200, duration: 5_400, at: dayOffset(101))
        rig.sync.send(.stopped(position: 5_200, duration: 5_400, at: dayOffset(101)))
        // Marked unwatched (from any screen; the item is the same).
        try await rig.store.markWatched(itemIDs: [hexfall], watched: false, at: dayOffset(102))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [
            .report("101", .playing, 5_000, "session-1"), .played("101"), .report("101", .stopped, 5_200, "session-1"), .unplayed("101"),
        ])
    }

    // MARK: The player

    func testPlaybackReportsFollowTheRhythmAndEveryStateChange() async throws {
        let rig = try await makeRig()
        let aftlander = try await movieID(rig, "Aftlander")
        let plexFile = try await file(rig, itemID: aftlander, sourceID: Self.plexID)
        let t0 = dayOffset(101)
        rig.sync.send(.started(itemID: aftlander, file: plexFile))
        for second in 0...25 {   // a progress event every second, as the player sends them
            rig.sync.send(.progress(state: .playing, position: Double(second), duration: 6_000, at: t0.addingTimeInterval(Double(second))))
        }
        rig.sync.send(.progress(state: .paused, position: 25, duration: 6_000, at: t0.addingTimeInterval(25.5)))
        rig.sync.send(.progress(state: .paused, position: 25, duration: 6_000, at: t0.addingTimeInterval(30)))
        rig.sync.send(.progress(state: .paused, position: 25, duration: 6_000, at: t0.addingTimeInterval(36)))
        rig.sync.send(.stopped(position: 25, duration: 6_000, at: t0.addingTimeInterval(40)))
        rig.sync.send(.progress(state: .playing, position: 26, duration: 6_000, at: t0.addingTimeInterval(41)))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [
            .report("102", .playing, 0, "session-1"), .report("102", .playing, 10, "session-1"), .report("102", .playing, 20, "session-1"),
            .report("102", .paused, 25, "session-1"), .report("102", .paused, 25, "session-1"), .report("102", .stopped, 25, "session-1"),
        ], "every 10 seconds, at once on a change of state, and nothing after the stop")
    }

    func testTurningTheSwitchOffDuringPlaybackStopsTheReports() async throws {
        let rig = try await makeRig()
        let aftlander = try await movieID(rig, "Aftlander")
        rig.sync.send(.started(itemID: aftlander, file: try await file(rig, itemID: aftlander, sourceID: Self.plexID)))
        rig.sync.send(.progress(state: .playing, position: 1, duration: 6_000, at: dayOffset(101)))
        await rig.flush()
        rig.switches.set(Self.plexID, false)
        rig.sync.send(.progress(state: .paused, position: 2, duration: 6_000, at: dayOffset(101).addingTimeInterval(2)))
        rig.sync.send(.stopped(position: 2, duration: 6_000, at: dayOffset(101).addingTimeInterval(3)))
        try await rig.store.markWatched(itemIDs: [aftlander], watched: true, at: dayOffset(102))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [.report("102", .playing, 1, "session-1")])
    }

    func testARefusedRequestIsCountedNotKeptAndDoesNotStopTheRest() async throws {
        final class Refusing: ServerWatchWriting {
            func report(_ r: ServerTimelineReport) async throws { throw SourceError.httpStatus(500) }
            func markPlayed(itemKey: String) async throws { throw SourceError.httpStatus(500) }
            func markUnplayed(itemKey: String) async throws { throw SourceError.httpStatus(500) }
        }
        struct RefusingSource: ServerWatchSource {
            var watchWriter: any ServerWatchWriting { Refusing() }
            func serverItemKey(at path: String) async throws -> String? { "101" }
            func serverWatchState(at path: String) async throws -> ServerWatchState? { ServerWatchState(itemKey: "101", played: false) }
            func serverWatchStates() async throws -> [String: ServerWatchState] { [:] }
        }
        let store = try SQLiteLibraryStore(path: ":memory:")
        let rig = LibraryRig(store: store, source: TreeSource())
        try await rig.fill()
        let sync = ServerWatchSync(store: store, isOn: { _ in true }, source: { _ in RefusingSource() })
        let runner = Task { await sync.run() }
        let hexfall = try await rig.movieID("Hexfall")
        sync.send(.started(itemID: hexfall, file: nil))
        sync.send(.progress(state: .playing, position: 1, duration: nil, at: epoch))
        sync.send(.stopped(position: 1, duration: nil, at: epoch))
        await sync.flush()
        let failures = await sync.failures
        XCTAssertEqual(failures, 2)
        let waiting = await sync.waiting
        XCTAssertEqual(waiting, [], "a refused write is not kept for later")
        sync.finish()
        await runner.value
    }

    // MARK: Stage 3 (R310): the server cannot be reached

    func testWritesWhileTheServerIsUnreachableWaitAndAreReplayedWithOfflineAndUpdated() async throws {
        let storage = MemoryServerWatchQueueStorage()
        let rig = try await makeRig(queue: ServerWatchQueue(storage: storage))
        let aftlander = try await movieID(rig, "Aftlander")
        rig.plex.writer.reachable = false
        rig.sync.send(.started(itemID: aftlander, file: try await file(rig, itemID: aftlander, sourceID: Self.plexID)))
        rig.sync.send(.progress(state: .playing, position: 600, duration: 6_000, at: dayOffset(101)))
        rig.sync.send(.stopped(position: 700, duration: 6_000, at: dayOffset(101).addingTimeInterval(100)))
        try await rig.store.markWatched(itemIDs: [try await movieID(rig, "Hexfall")], watched: true, at: dayOffset(102))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [])
        let waiting = await rig.sync.waiting
        XCTAssertEqual(waiting.map(\.kind), [.position, .played], "the newest resume point and the flag")
        XCTAssertEqual(waiting.first?.position, 700)
        XCTAssertEqual(storage.load(), waiting, "kept across launches")

        // A new launch with the same saved queue: the next scan of the source finds the server again.
        let later = try await makeRig(queue: ServerWatchQueue(storage: storage))
        later.sync.send(.replay(sourceID: Self.plexID))
        await later.flush()
        XCTAssertEqual(later.plex.writer.calls.count, 2)
        XCTAssertEqual(later.plex.writer.calls.first, .report("102", .stopped, 700, "session-1"))
        XCTAssertEqual(later.plex.writer.offlineTimes, [dayOffset(101).addingTimeInterval(100)], "offline=1 with the time it happened")
        XCTAssertEqual(later.plex.writer.calls.last, .played("101"))
        let left = await later.sync.waiting
        XCTAssertEqual(left, [])
        XCTAssertEqual(storage.load(), [])
    }

    func testTheNextWriteThatReachesTheServerSendsWhatWaited() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall"), aftlander = try await movieID(rig, "Aftlander")
        rig.plex.writer.reachable = false
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        await rig.flush()
        rig.plex.writer.reachable = true
        try await rig.store.markWatched(itemIDs: [aftlander], watched: true, at: dayOffset(102))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [.played("102"), .played("101")])
        let left = await rig.sync.waiting
        XCTAssertEqual(left, [])
    }

    func testAWaitingChangeOlderThanTheServersLastViewIsDropped() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall")
        rig.plex.writer.reachable = false
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        await rig.flush()
        rig.plex.setState(Self.hexfall, played: false, position: 900, at: dayOffset(103))   // watched elsewhere since
        rig.plex.writer.reachable = true
        rig.sync.send(.replay(sourceID: Self.plexID))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [], "the server's newer change wins")
        let left = await rig.sync.waiting
        XCTAssertEqual(left, [])
    }

    func testWithTheSwitchTurnedOffWhatWaitedIsNeverSent() async throws {
        let rig = try await makeRig()
        rig.plex.writer.reachable = false
        try await rig.store.markWatched(itemIDs: [try await movieID(rig, "Hexfall")], watched: true, at: dayOffset(101))
        await rig.flush()
        rig.switches.set(Self.plexID, false)
        rig.plex.writer.reachable = true
        rig.sync.send(.replay(sourceID: Self.plexID))
        rig.sync.send(.merge(sourceID: Self.plexID))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [])
        let left = await rig.sync.waiting
        XCTAssertEqual(left, [])
    }

    // MARK: Stage 3 (R310): newer change wins

    func testTheDecisionTable() {
        typealias S = PlexWatchMerge.Side
        let t = dayOffset(10)
        let none = S(watched: false, position: 0, at: nil, known: false)
        XCTAssertEqual(PlexWatchMerge.decide(app: none, server: none), .same)
        XCTAssertEqual(PlexWatchMerge.decide(app: none, server: S(watched: true, position: 0, at: t, known: true)), .takeServer)
        XCTAssertEqual(PlexWatchMerge.decide(app: S(watched: false, position: 600, at: t, known: true), server: none), .sendApp)
        // Same state: nothing, whatever the times.
        XCTAssertEqual(PlexWatchMerge.decide(app: S(watched: true, position: 0, at: t, known: true),
                                             server: S(watched: true, position: 0, at: t.addingTimeInterval(500), known: true)), .same)
        XCTAssertEqual(PlexWatchMerge.decide(app: S(watched: false, position: 600, at: t, known: true),
                                             server: S(watched: false, position: 610, at: t.addingTimeInterval(-500), known: true)), .same)
        // Different: the newer side wins; one second apart counts as the same time.
        let app = S(watched: true, position: 0, at: t, known: true)
        XCTAssertEqual(PlexWatchMerge.decide(app: app, server: S(watched: false, position: 900, at: t.addingTimeInterval(60), known: true)), .takeServer)
        XCTAssertEqual(PlexWatchMerge.decide(app: app, server: S(watched: false, position: 900, at: t.addingTimeInterval(-60), known: true)), .sendApp)
        XCTAssertEqual(PlexWatchMerge.decide(app: app, server: S(watched: false, position: 900, at: t.addingTimeInterval(0.5), known: true)), .same)
        XCTAssertEqual(PlexWatchMerge.decide(app: app, server: S(watched: false, position: 900, at: nil, known: true)), .sendApp)
        // A rewatch in progress on the server counts as its resume point.
        let rewatch = S(server: ServerWatchState(itemKey: "1", played: true, position: 1_200, lastViewedAt: t))
        XCTAssertFalse(rewatch.watched)
        XCTAssertEqual(rewatch.position, 1_200)
    }

    func testAfterAScanTheNewerSideWinsAndNothingComesBack() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall"), aftlander = try await movieID(rig, "Aftlander")
        // Hexfall: watched in the app on day 101, then stopped partway in another Plex app on day 105 (server newer).
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        rig.plex.setState(Self.hexfall, played: false, position: 1_800, at: dayOffset(105))
        // Aftlander: the app's resume point (day 106) is newer than the server's watched mark (day 104).
        try await rig.store.updateProgress(itemID: aftlander, position: 2_400, duration: 6_000, at: dayOffset(106))
        rig.plex.setState(Self.aftlander, played: true, at: dayOffset(104))
        await rig.flush()
        let before = rig.plex.writer.calls.count

        rig.sync.send(.merge(sourceID: Self.plexID))
        await rig.flush()
        let taken = try await rig.store.item(id: hexfall)
        XCTAssertEqual(taken?.watch.watched, false)
        XCTAssertEqual(taken?.watch.position, 1_800, "the server's newer resume point")
        let merged = Array(rig.plex.writer.calls.dropFirst(before))
        XCTAssertEqual(merged, [.report("102", .stopped, 2_400, "session-1")], "only the app's newer change goes out; Hexfall is not sent back")
        XCTAssertEqual(rig.plex.writer.offlineTimes.last ?? nil, dayOffset(106))

        // A second merge finds both sides agreeing for Hexfall; Aftlander's server copy is still the old fake state, so it
        // is sent again (a real server would now report the new resume point).
        rig.plex.setState(Self.aftlander, played: false, position: 2_400, at: dayOffset(106))
        rig.sync.send(.merge(sourceID: Self.plexID))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls.count, before + 1, "nothing more once both sides agree")
    }

    func testAMarkAsUnwatchedNewerThanTheServersPlayIsSent() async throws {
        let rig = try await makeRig()
        let hexfall = try await movieID(rig, "Hexfall")
        rig.plex.writer.reachable = false   // the unwatch happens while the server is off; nothing waits for a flag the merge covers
        try await rig.store.markWatched(itemIDs: [hexfall], watched: true, at: dayOffset(101))
        try await rig.store.markWatched(itemIDs: [hexfall], watched: false, at: dayOffset(103))
        await rig.flush()
        rig.plex.setState(Self.hexfall, played: true, at: dayOffset(102))
        rig.plex.writer.reachable = true
        rig.sync.send(.merge(sourceID: Self.plexID))
        await rig.flush()
        XCTAssertEqual(rig.plex.writer.calls, [.unplayed("101")], "the kept unwatch is replayed; the merge then has nothing more to send")
        let watched = try await rig.store.item(id: hexfall)?.watch.watched
        XCTAssertEqual(watched, false)
    }

    func testTheQueueFileKeepsNoAddressOrToken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vp-watch-queue-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let storage = FileServerWatchQueueStorage(url: url)
        let entry = ServerWatchPending(sourceID: "plex1", path: Self.aftlander, kind: .position, position: 700, duration: 6_000, at: dayOffset(101))
        storage.save([entry])
        XCTAssertEqual(storage.load(), [entry])
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("http"))
        XCTAssertFalse(text.lowercased().contains("token"))
    }
}
