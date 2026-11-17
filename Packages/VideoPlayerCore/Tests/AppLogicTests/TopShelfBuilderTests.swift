import XCTest
import VideoPlayerCore
import LibraryIndex
import UserData
@testable import AppLogic

final class TopShelfBuilderTests: XCTestCase {
    private let now = epoch.addingTimeInterval(100 * 86_400)

    func testAnEmptyLibraryGivesAnEmptySnapshot() async throws {
        let rig = try LibraryRig.make()
        let result = try await TopShelfBuilder(store: rig.store).build(now: now)
        XCTAssertTrue(result.snapshot.items.isEmpty)
        XCTAssertTrue(result.artwork.isEmpty)
        XCTAssertEqual(result.snapshot.version, TopShelfSnapshot.currentVersion)
    }

    func testContinueWatchingComesFirstThenNextUpWithLinksAndArtworkNames() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let heat = try await rig.movieID("Heat")
        try await rig.store.updateProgress(itemID: heat, position: 1_000, duration: 6_000, at: dayOffset(99))
        let firstCandidates = try await rig.episodes(ofSeriesTitle: "Show One")
        let first = try XCTUnwrap(firstCandidates.first { $0.season == 1 && $0.episode == 1 })
        try await rig.store.markWatched(itemIDs: [first.id], watched: true, at: dayOffset(99))

        let result = try await TopShelfBuilder(store: rig.store).build(now: now)
        let items = result.snapshot.items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, String(heat), "the movie in progress comes first")
        XCTAssertNotNil(items[0].progress)
        let secondCandidates = try await rig.episodes(ofSeriesTitle: "Show One")
        let second = try XCTUnwrap(secondCandidates.first { $0.season == 1 && $0.episode == 2 })
        XCTAssertEqual(items[1].id, String(second.id), "Next Up is the episode after the watched one")
        XCTAssertNil(items[1].progress, "Next Up shows no progress")
        for item in items {
            let id = try XCTUnwrap(Int64(item.id))
            XCTAssertEqual(DeepLink.parse(try XCTUnwrap(URL(string: item.link))), .item(id))
            XCTAssertEqual(item.imageFile, "item-\(id).jpg")
        }
        XCTAssertEqual(result.artwork.map(\.file), items.map(\.imageFile))
        XCTAssertEqual(result.artwork.map(\.key), items.map { "item-\($0.id)" })
    }

    func testAnItemInBothRowsAppearsOnce() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let firstCandidates = try await rig.episodes(ofSeriesTitle: "Show One")
        let first = try XCTUnwrap(firstCandidates.first { $0.season == 1 && $0.episode == 1 })
        let secondCandidates = try await rig.episodes(ofSeriesTitle: "Show One")
        let second = try XCTUnwrap(secondCandidates.first { $0.season == 1 && $0.episode == 2 })
        try await rig.store.markWatched(itemIDs: [first.id], watched: true, at: dayOffset(99))
        try await rig.store.updateProgress(itemID: second.id, position: 100, duration: 2_000, at: dayOffset(99))
        let ids = try await TopShelfBuilder(store: rig.store).build(now: now).snapshot.items.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "no duplicates: \(ids)")
        XCTAssertEqual(ids.filter { $0 == String(second.id) }.count, 1)
    }

    func testTheLimitIsRespectedAndClampedToTheStoreMaximum() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        for title in ["Heat", "Alien", "Zodiac"] {
            let id = try await rig.movieID(title)
            try await rig.store.updateProgress(itemID: id, position: 500, duration: 6_000, at: dayOffset(99))
        }
        let one = try await TopShelfBuilder(store: rig.store, limit: 1).build(now: now)
        XCTAssertEqual(one.snapshot.items.count, 1)
        XCTAssertEqual(TopShelfBuilder(store: rig.store, limit: 0).limit, 1)
        XCTAssertEqual(TopShelfBuilder(store: rig.store, limit: 10_000).limit, TopShelfSnapshotStore.maxItems)
        let all = try await TopShelfBuilder(store: rig.store, limit: 24).build(now: now)
        XCTAssertEqual(all.snapshot.items.count, 3)
    }

    func testTheSnapshotRoundTripsThroughTheFolderTheExtensionReads() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let heat = try await rig.movieID("Heat")
        try await rig.store.updateProgress(itemID: heat, position: 1_000, duration: 6_000, at: dayOffset(99))
        let result = try await TopShelfBuilder(store: rig.store).build(now: now)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vp-topshelf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try TopShelfSnapshotStore.write(result.snapshot, to: dir)
        // No artwork files were written yet, so the extension must show nothing rather than a half row.
        XCTAssertEqual(TopShelfSnapshotStore.read(from: dir), .nothing(reason: "no item with artwork"))
        for art in result.artwork { try Data([1, 2, 3]).write(to: dir.appendingPathComponent(art.file)) }
        guard case .items(let ready) = TopShelfSnapshotStore.read(from: dir) else { return XCTFail("expected items") }
        XCTAssertEqual(ready.map(\.item), result.snapshot.items)
    }
}
