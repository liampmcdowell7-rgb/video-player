import XCTest
import VideoPlayerCore
import LibraryIndex
import AppLogic
@testable import SourcePlex

/// Stage 6 end to end (R306): the real scanner indexes the fake Plex server, the server's watch state is seeded once, and
/// not one request that could change the server is ever sent. No network.
final class PlexWatchSeedEndToEndTests: XCTestCase {
    func testIndexThenSeedOnceWithoutAnyServerWrite() async throws {
        let fake = try FakePlexServer()
        let plex = PlexClient(baseURL: URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!,
                              token: "server-token-placeholder",
                              identity: PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0"), transport: fake)
        let store = try SQLiteLibraryStore(path: ":memory:")
        try await store.upsertSource(LibrarySourceRecord(id: "plex-1", kind: .plex, name: "Home PC", addedAt: Date(timeIntervalSince1970: 0)))
        let summary = try await LibrarySyncer(store: store, source: plex, sourceID: "plex-1").sync()
        XCTAssertEqual(summary.status, .completed)

        // What the app does after the first scan of a Plex source (AppServices.seedPlexWatchState).
        let items = try await plex.serverItems()
        let states = items.mapValues {
            PlexWatchSeed.ServerState(positionSeconds: $0.viewOffsetSeconds, viewCount: $0.viewCount, lastViewedAt: $0.lastViewedAt,
                                      durationSeconds: $0.metadata.runtimeSeconds.map(Double.init))
        }
        let result = try await PlexWatchSeed(store: store, files: store).seed(sourceID: "plex-1", statesByPath: states)
        // Fixtures: "Second Test Movie" stopped at 600 s, S01E01 played once, S01E02 stopped at 120 s.
        XCTAssertEqual(result.markedWatched, 1)
        XCTAssertEqual(result.resumed, 2)

        let second = try await store.storedFiles(sourceID: "plex-1", folder: "/Movies")
            .first { $0.name == "Second Test Movie (2021).mkv" }
        let item = try await store.item(id: try XCTUnwrap(second?.itemID))
        XCTAssertEqual(item?.watch.position, 600)

        // A second run finds the app's own state and changes nothing.
        let again = try await PlexWatchSeed(store: store, files: store).seed(sourceID: "plex-1", statesByPath: states)
        XCTAssertEqual(again.keptLocal, 3)
        XCTAssertEqual(again.markedWatched + again.resumed, 0)

        // The whole run, playback access included, never asked the server to change anything.
        _ = try await plex.playbackAccess(for: "/Movies/Second Test Movie (2021).mkv")
        XCTAssertEqual(fake.serverWrites.map { "\($0.method) \($0.url.path)" }, [], "no write of any kind to the server")
        XCTAssertFalse(fake.requests.contains { ["/:/timeline", "/:/scrobble", "/:/unscrobble"].contains($0.url.path) })
    }
}

/// R385: this file imports AppLogic without `@testable`, as the app target does, so this only compiles while
/// `LayeredDetails.init(details:used:ratingLayer:)` is public (the app's compile check of ca23e66 failed on it).
final class LayeredDetailsPublicInitTests: XCTestCase {
    func testTheAppTargetCanBuildLayeredDetails() {
        let empty = LayeredDetails(used: [])
        XCTAssertNil(empty.details)
        XCTAssertEqual(empty.used, [])
        XCTAssertNil(empty.ratingLayer)
        let rated = LayeredDetails(details: nil, used: [.source], ratingLayer: .source)
        XCTAssertEqual(rated.used, [.source])
        XCTAssertEqual(rated.ratingLayer, .source)
    }
}
