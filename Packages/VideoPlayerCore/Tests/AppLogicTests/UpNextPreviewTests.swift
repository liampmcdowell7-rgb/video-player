import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

/// R383 (audit #11): the Up Next card's picture is the next episode's still when it is already cached, never the poster
/// (Apple's previewImage page), and nothing is read from a source or requested.
final class UpNextPreviewTests: XCTestCase {
    func testTheStillIsChosenAndThePosterNever() {
        XCTAssertEqual(UpNextPreview.choose(onHand: [.episodeStill]), .episodeStill)
        XCTAssertEqual(UpNextPreview.choose(onHand: [.episodeStill, .showPoster]), .episodeStill)
        XCTAssertNil(UpNextPreview.choose(onHand: [.showPoster]), "Apple: a frame from the proposed video, not the poster")
        XCTAssertNil(UpNextPreview.choose(onHand: []))
    }

    func testOnlyImageBytesWithinTheLimitAreUsable() {
        XCTAssertTrue(UpNextPreview.usable(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])))
        XCTAssertTrue(UpNextPreview.usable(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])))
        XCTAssertTrue(UpNextPreview.usable(Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))))
        XCTAssertTrue(UpNextPreview.usable(Data(Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBP".utf8))))
        XCTAssertFalse(UpNextPreview.usable(Data()))
        XCTAssertFalse(UpNextPreview.usable(Data("<html>".utf8)))
        XCTAssertFalse(UpNextPreview.usable(Data([0, 0, 0, 0x18] + Array("ftypisom".utf8))), "an MP4, not an image")
        XCTAssertFalse(UpNextPreview.usable(Data([0xFF, 0xD8, 0xFF] + [UInt8](repeating: 0, count: UpNextPreview.maxBytes))))
    }

    func testThePreviewKeyGivesAnItemIDOnly() {
        XCTAssertEqual(UpNextPreview.itemID(previewKey: "item-42"), 42)
        XCTAssertNil(UpNextPreview.itemID(previewKey: "series-7"))
        XCTAssertNil(UpNextPreview.itemID(previewKey: "remote:/a.jpg"))
        XCTAssertNil(UpNextPreview.itemID(previewKey: nil))
    }

    private func cacheDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upnext-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// The still next to the episode's file is used when it is in the artwork cache, and not otherwise.
    func testACachedSidecarStillIsFoundAndAnUncachedOneIsNot() async throws {
        let rig = try LibraryRig.make()
        let thumbPath = "/TV/Show One (2010)/Season 1/Show One - S01E02 - Ep 2-thumb.jpg"
        rig.source.put(thumbPath, size: 200, modified: dayOffset(30))
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        let second = try XCTUnwrap(episodes.first { $0.season == 1 && $0.episode == 2 })
        let third = try XCTUnwrap(episodes.first { $0.season == 1 && $0.episode == 3 })
        let cache = ArtworkDiskCache(directory: try cacheDir())

        let before = await UpNextPreview.cachedStill(itemID: second.id, store: rig.store, cache: cache, server: nil)
        XCTAssertNil(before, "not cached yet: nothing is read from the source")

        let key = ArtworkEngine.sidecarCacheKey(sourceID: LibraryRig.sourceID, path: thumbPath, size: 200, modified: dayOffset(30), etag: nil)
        let stored = try cache.store(Data([0xFF, 0xD8, 0xFF, 0xE0]), key: key)
        let found = await UpNextPreview.cachedStill(itemID: second.id, store: rig.store, cache: cache, server: nil)
        XCTAssertEqual(found?.lastPathComponent, stored.lastPathComponent)

        let other = await UpNextPreview.cachedStill(itemID: third.id, store: rig.store, cache: cache, server: nil)
        XCTAssertNil(other, "an episode without a still")
    }

    func testAFilmHasNoStill() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let movie = try await rig.movieID("Hexfall")
        let found = await UpNextPreview.cachedStill(itemID: movie, store: rig.store, cache: ArtworkDiskCache(directory: try cacheDir()),
                                                    server: nil)
        XCTAssertNil(found)
    }
}
