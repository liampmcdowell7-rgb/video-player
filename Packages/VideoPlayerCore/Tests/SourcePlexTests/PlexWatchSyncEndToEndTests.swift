import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
import AppLogic
@testable import SourcePlex

/// Two-way watch state stage 2 end to end (R309): the real scanner indexes the fake Plex server, the store records through
/// the app's recorder, and the sync writes through the real Plex client. No network.
final class PlexWatchSyncEndToEndTests: XCTestCase {
    private let movie = "/Movies/Second Test Movie (2021).mkv"

    private struct Rig {
        let fake: FakePlexServer
        let store: SQLiteLibraryStore
        let sync: ServerWatchSync
        let runner: Task<Void, Never>
        let itemID: Int64
        let file: StoredFile
    }

    private func makeRig(switchOn: Bool) async throws -> Rig {
        let fake = try FakePlexServer()
        let plex = PlexClient(baseURL: URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!,
                              token: "server-token-placeholder",
                              identity: PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0"), transport: fake)
        let recorder = ServerWatchRecorder(wrapping: LedgerRecorder(ledger: UserDataLedger(deviceID: "device-a")))
        let store = try SQLiteLibraryStore(path: ":memory:", recorder: recorder)
        try await store.upsertSource(LibrarySourceRecord(id: "plex-1", kind: .plex, name: "Home PC", addedAt: Date(timeIntervalSince1970: 0)))
        let summary = try await LibrarySyncer(store: store, source: plex, sourceID: "plex-1").sync()
        XCTAssertEqual(summary.status, .completed)

        let definition = PlexWatchSyncOption.setting(switchOn, on: UDSourceDefinition(
            id: "plex-1", kind: "plex", name: "Home PC", path: "https://192-168-1-20.machine0001.plex.direct:32400", auth: "token",
            options: "machine=machine-0001"))
        let sync = ServerWatchSync(store: store, isOn: { $0 == definition.id && PlexWatchSyncOption.isOn(definition) },
                                   source: { $0 == "plex-1" ? plex : nil }, makeSessionID: { "session-1" })
        recorder.setHandler { sync.send(.changed($0)) }
        let runner = Task { await sync.run() }
        let movies = try await store.storedFiles(sourceID: "plex-1", folder: "/Movies")
        let file = try XCTUnwrap(movies.first { $0.path == movie })
        return Rig(fake: fake, store: store, sync: sync, runner: runner, itemID: try XCTUnwrap(file.itemID), file: file)
    }

    /// Everything a person can do with the item: play it, pause, stop, mark it watched and unwatched.
    private func useTheItem(_ rig: Rig) async throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        rig.sync.send(.started(itemID: rig.itemID, file: rig.file))
        rig.sync.send(.progress(state: .playing, position: 12.5, duration: 5_400, at: t0))
        rig.sync.send(.progress(state: .paused, position: 13, duration: 5_400, at: t0.addingTimeInterval(1)))
        try await rig.store.updateProgress(itemID: rig.itemID, position: 13, duration: 5_400, at: t0.addingTimeInterval(1))
        rig.sync.send(.stopped(position: 13, duration: 5_400, at: t0.addingTimeInterval(2)))
        try await rig.store.markWatched(itemIDs: [rig.itemID], watched: true, at: t0.addingTimeInterval(3))
        try await rig.store.markWatched(itemIDs: [rig.itemID], watched: false, at: t0.addingTimeInterval(4))
        await rig.sync.flush()
    }

    func testWithTheSwitchOffNoWriteRequestIsEverSent() async throws {
        let rig = try await makeRig(switchOn: false)
        try await useTheItem(rig)
        XCTAssertEqual(rig.fake.serverWrites.map { "\($0.method) \($0.url.path)" }, [], "no write of any kind to the server")
        XCTAssertFalse(rig.fake.requests.contains { $0.url.path == "/media/providers" }, "the write paths are not even looked up")
        let failures = await rig.sync.failures
        XCTAssertEqual(failures, 0)
    }

    func testWithTheSwitchOnTheServerGetsTheTimelineAndTheWatchedFlag() async throws {
        let rig = try await makeRig(switchOn: true)
        try await useTheItem(rig)
        let writes = rig.fake.serverWrites
        XCTAssertEqual(writes.map { "\($0.method) \($0.url.path)" }, [
            "POST /:/timeline", "POST /:/timeline", "POST /:/timeline", "PUT /:/scrobble", "PUT /:/unscrobble",
        ])
        func query(_ request: HTTPRequest) -> [String: String] {
            Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }
        XCTAssertEqual(writes.prefix(3).map { query($0)["state"] }, ["playing", "paused", "stopped"])
        XCTAssertEqual(query(writes[0])["ratingKey"], "1002")
        XCTAssertEqual(query(writes[0])["time"], "12500")
        XCTAssertEqual(query(writes[0])["duration"], "5400000")
        XCTAssertEqual(query(writes[2])["continuing"], "0")
        XCTAssertTrue(writes.prefix(3).allSatisfy { $0.headers["X-Plex-Session-Identifier"] == "session-1" })
        XCTAssertEqual(query(writes[3])["key"], "1002")
        XCTAssertEqual(query(writes[4])["key"], "1002")
        XCTAssertTrue(writes.allSatisfy { $0.headers["X-Plex-Token"] == "server-token-placeholder" && !$0.url.absoluteString.contains("server-token") })
        let failures = await rig.sync.failures
        XCTAssertEqual(failures, 0)
    }

    // MARK: Stage 3 (R310)

    func testWritesWhileTheServerIsOffAreReplayedWithOfflineAndUpdated() async throws {
        let rig = try await makeRig(switchOn: true)
        rig.fake.reachableHosts = []   // the server goes off after the scan
        try await useTheItem(rig)
        XCTAssertEqual(rig.fake.serverWrites.count, 0, "nothing arrived: the write paths could not even be looked up")
        let waiting = await rig.sync.waiting
        XCTAssertEqual(waiting.map(\.kind), [.position, .unplayed])
        rig.fake.reachableHosts = ["192-168-1-20.machine0001.plex.direct"]
        let before = rig.fake.serverWrites.count
        rig.sync.send(.replay(sourceID: "plex-1"))
        await rig.sync.flush()
        let replayed = Array(rig.fake.serverWrites.dropFirst(before))
        XCTAssertEqual(replayed.map { "\($0.method) \($0.url.path)" }, ["POST /:/timeline", "PUT /:/unscrobble"])
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: replayed[0].url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["state"], "stopped")
        XCTAssertEqual(query["time"], "13000")
        XCTAssertEqual(query["offline"], "1")
        XCTAssertEqual(query["updated"], "1800000002")
        let left = await rig.sync.waiting
        XCTAssertEqual(left, [])
    }

    func testTheMergeTakesTheServersStateWithoutWritingAnything() async throws {
        let rig = try await makeRig(switchOn: true)
        rig.sync.send(.merge(sourceID: "plex-1"))
        await rig.sync.flush()
        XCTAssertEqual(rig.fake.serverWrites.map { "\($0.method) \($0.url.path)" }, [], "the app had nothing newer to send")
        let item = try await rig.store.item(id: rig.itemID)
        XCTAssertEqual(item?.watch.position, 600, "the server's resume point (fixture: 600 s)")
    }
}
