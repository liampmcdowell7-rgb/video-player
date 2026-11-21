import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

/// R309, two-way watch state stage 2: the switch, the app's own changes, the player's reports and the same film on two
/// sources. A fake writer stands in for the server (the real Plex requests are tested in SourcePlexTests).
final class ServerWatchSyncTests: XCTestCase {
    /// Every call the sync made, in order.
    final class FakeWriter: ServerWatchWriting, @unchecked Sendable {
        enum Call: Equatable { case played(String), unplayed(String), report(String, ServerPlaybackState, Double, String?) }
        private let lock = NSLock()
        private var made: [Call] = []
        var calls: [Call] { lock.withLock { made } }
        private func add(_ call: Call) { lock.withLock { made.append(call) } }
        func report(_ r: ServerTimelineReport) async throws { add(.report(r.itemKey, r.state, r.position, r.sessionIdentifier)) }
        func markPlayed(itemKey: String) async throws { add(.played(itemKey)) }
        func markUnplayed(itemKey: String) async throws { add(.unplayed(itemKey)) }
    }

    /// A server source: knows the server key of each file path; counts how often it was asked.
    final class FakeServerSource: ServerWatchSource, @unchecked Sendable {
        let writer = FakeWriter()
        let keys: [String: String]
        private let lock = NSLock()
        private var asked = 0
        var askedCount: Int { lock.withLock { asked } }
        init(keys: [String: String]) { self.keys = keys }
        var watchWriter: any ServerWatchWriting { writer }
        func serverItemKey(at path: String) async throws -> String? { lock.withLock { asked += 1 }; return keys[path] }
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

    private func makeRig(switchOn: Bool = true) async throws -> Rig {
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
        let sync = ServerWatchSync(store: store, isOn: { switches.isOn($0) },
                                   source: { $0 == Self.plexID ? plex : nil }, makeSessionID: { "session-1" })
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

    func testAFailedRequestIsCountedAndDoesNotStopTheRest() async throws {
        final class Refusing: ServerWatchWriting {
            func report(_ r: ServerTimelineReport) async throws { throw SourceError.transport("off") }
            func markPlayed(itemKey: String) async throws { throw SourceError.transport("off") }
            func markUnplayed(itemKey: String) async throws { throw SourceError.transport("off") }
        }
        struct RefusingSource: ServerWatchSource {
            var watchWriter: any ServerWatchWriting { Refusing() }
            func serverItemKey(at path: String) async throws -> String? { "101" }
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
        sync.finish()
        await runner.value
    }
}
