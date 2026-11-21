import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

/// Stage 6 (R306): the server's watch state is copied once, only where the app has none, and never written back.
final class PlexWatchSeedTests: XCTestCase {
    private let hexfall = "/Movies/Hexfall (1995)/Hexfall (1995).mkv"
    private let aftlander = "/Movies/Aftlander (1979)/Aftlander (1979).mkv"
    private let zornwick = "/Movies/Zornwick (2007)/Zornwick (2007).mkv"
    private let episode = "/TV/Show One (2010)/Season 1/Show One - S01E01 - Ep 1.mkv"

    private func state(position: Double? = nil, count: Int? = nil, at: Date? = nil, duration: Double? = 5400) -> PlexWatchSeed.ServerState {
        PlexWatchSeed.ServerState(positionSeconds: position, viewCount: count, lastViewedAt: at, durationSeconds: duration)
    }

    func testPlayedItemsAreMarkedWatchedAndStoppedOnesResume() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let seed = PlexWatchSeed(store: rig.store, files: rig.store)
        let result = try await seed.seed(sourceID: LibraryRig.sourceID, statesByPath: [
            hexfall: state(count: 1, at: dayOffset(50)),
            aftlander: state(position: 600, count: 0, at: dayOffset(51)),
            zornwick: state(position: 12, count: 0),            // under 30 seconds: nothing to resume
            episode: state(position: 0, count: 0),               // never played
            "/Movies/Not Indexed (2000).mkv": state(count: 3),   // no such file: ignored
        ], now: dayOffset(60))
        XCTAssertEqual(result.markedWatched, 1)
        XCTAssertEqual(result.resumed, 1)
        XCTAssertEqual(result.keptLocal, 0)

        let watched = try await rig.store.item(id: try await rig.movieID("Hexfall"))
        XCTAssertEqual(watched?.watch.watched, true)
        XCTAssertEqual(watched?.watch.lastPlayed, dayOffset(50))
        let resumed = try await rig.store.item(id: try await rig.movieID("Aftlander"))
        XCTAssertEqual(resumed?.watch.position, 600)
        XCTAssertEqual(resumed?.watch.watched, false)
        let untouched = try await rig.store.item(id: try await rig.movieID("Zornwick"))
        XCTAssertTrue(PlexWatchSeed.hasNoLocalState(try XCTUnwrap(untouched).watch))
    }

    func testWhatTheAppAlreadyRecordedIsNeverOverwritten() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        try await rig.store.updateProgress(itemID: id, position: 1200, duration: 5400, at: dayOffset(40))
        let result = try await PlexWatchSeed(store: rig.store, files: rig.store)
            .seed(sourceID: LibraryRig.sourceID, statesByPath: [hexfall: state(count: 2, at: dayOffset(50))])
        XCTAssertEqual(result.keptLocal, 1)
        XCTAssertEqual(result.markedWatched, 0)
        let item = try await rig.store.item(id: id)
        XCTAssertEqual(item?.watch.position, 1200)
        XCTAssertEqual(item?.watch.watched, false)
    }

    func testTheSeedRunsOncePerPlexSource() {
        var plex = UDSourceDefinition(id: "p1", kind: "plex", name: "Home", path: "https://h:32400", auth: "token",
                                      options: "machine=m1&relay=off")
        XCTAssertTrue(PlexWatchSeed.isNeeded(for: plex))
        plex = PlexWatchSeed.markedDone(plex)
        XCTAssertFalse(PlexWatchSeed.isNeeded(for: plex))
        XCTAssertEqual(SourceOptions.parse(plex.options), ["machine": "m1", "relay": "off", "seeded": "done"], "other options kept")
        var webdav = plex
        webdav.kind = "webdav"
        webdav.options = ""
        XCTAssertFalse(PlexWatchSeed.isNeeded(for: webdav), "only Plex sources are seeded")
    }
}
