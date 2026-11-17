import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

// FIXTURE: the "pictures" below are a few bytes of invented data and the online provider is a fake; no file server or service is contacted.

private func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-test-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class TickClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = 1_700_000_000.0
    func now() -> Date { lock.withLock { t += 1; return Date(timeIntervalSince1970: t) } }
}

final class ArtworkDiskCacheTests: XCTestCase {
    func testStoresAndFindsByKeyAndMissesOtherKeys() throws {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ArtworkDiskCache(directory: dir, maxBytes: 1_000)
        XCTAssertNil(cache.url(forKey: "a"))
        let url = try cache.store(Data(repeating: 1, count: 100), key: "a")
        XCTAssertEqual(cache.url(forKey: "a"), url)
        XCTAssertEqual(try Data(contentsOf: url).count, 100)
        XCTAssertNil(cache.url(forKey: "b"))
    }

    func testTheOldestUnusedFilesGoFirstAndTheFolderStaysUnderTheLimit() throws {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TickClock()
        let cache = ArtworkDiskCache(directory: dir, maxBytes: 300, now: { clock.now() })
        try cache.store(Data(repeating: 1, count: 100), key: "one")
        try cache.store(Data(repeating: 2, count: 100), key: "two")
        try cache.store(Data(repeating: 3, count: 100), key: "three")
        XCTAssertEqual(cache.totalBytes, 300)
        _ = cache.url(forKey: "one")   // using "one" makes "two" the least recently used
        try cache.store(Data(repeating: 4, count: 100), key: "four")
        XCTAssertLessThanOrEqual(cache.totalBytes, 300)
        XCTAssertNil(cache.url(forKey: "two"), "the least recently used file was removed")
        XCTAssertNotNil(cache.url(forKey: "one"))
        XCTAssertNotNil(cache.url(forKey: "four"), "the file just written is never the one removed")
        XCTAssertEqual(cache.fileCount, 3)
    }

    func testOnePictureLargerThanTheWholeCacheIsRefused() {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ArtworkDiskCache(directory: dir, maxBytes: 50)
        XCTAssertThrowsError(try cache.store(Data(repeating: 1, count: 51), key: "big")) { XCTAssertEqual($0 as? ArtworkDiskCache.CacheError, .tooLarge) }
        XCTAssertEqual(cache.fileCount, 0)
    }

    func testAShrunkLimitTrimsOnNextStartAndRemoveAllEmpties() throws {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TickClock()
        let big = ArtworkDiskCache(directory: dir, maxBytes: 1_000, now: { clock.now() })
        for i in 0..<5 { try big.store(Data(repeating: UInt8(i), count: 100), key: "k\(i)") }
        let small = ArtworkDiskCache(directory: dir, maxBytes: 250, now: { clock.now() })
        small.trim()
        XCTAssertLessThanOrEqual(small.totalBytes, 250)
        XCTAssertNotNil(small.url(forKey: "k4"))
        small.removeAll()
        XCTAssertEqual(small.fileCount, 0)
    }

    func testAnEmptyFileCountsAsMissing() throws {
        let dir = tempFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = ArtworkDiskCache(directory: dir, maxBytes: 100)
        let url = try cache.store(Data([1]), key: "x")
        try Data().write(to: url)
        XCTAssertNil(cache.url(forKey: "x"))
    }
}

private final class FakeReader: SidecarReading, @unchecked Sendable {
    private let lock = NSLock()
    var files: [String: Data] = [:]
    private(set) var reads: [String] = []
    func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data {
        lock.withLock { reads.append(path) }
        guard let d = lock.withLock({ files[path] }) else { throw SourceError.notFound }
        return d
    }
}

private final class FakeOnline: OnlineArtworkProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var itemCalls = 0
    private(set) var seriesCalls: [Int] = []
    var itemURL: URL? = URL(string: "https://images.example.invalid/item.jpg")
    var seriesURL: URL? = URL(string: "https://images.example.invalid/series.jpg")
    func posterURL(forItem item: LibraryItem, file: StoredFile?) async -> URL? { lock.withLock { itemCalls += 1 }; return itemURL }
    func posterURL(forSeriesID tmdbID: Int) async -> URL? { lock.withLock { seriesCalls.append(tmdbID) }; return seriesURL }
    func imageURL(path: String) async -> URL? { URL(string: "https://images.example.invalid/w500" + path) }
}

final class ArtworkEngineTests: XCTestCase {
    private struct Rig {
        let lib: LibraryRig
        let reader = FakeReader()
        let online = FakeOnline()
        let dir = tempFolder()
        func engine(withOnline: Bool = true, clock: @escaping @Sendable () -> Date = { Date() }) -> ArtworkEngine {
            ArtworkEngine(store: lib.store, cache: ArtworkDiskCache(directory: dir, maxBytes: 1_000_000), reader: reader, online: withOnline ? online : nil, now: clock)
        }
    }

    private func rig(_ files: [(String, Int64)]) async throws -> Rig {
        let lib = try LibraryRig.make()
        try await lib.store.upsertSource(LibrarySourceRecord(id: LibraryRig.sourceID, kind: .webdav, name: "Test", addedAt: epoch))
        for (path, size) in files { lib.source.put(path, size: size, modified: dayOffset(1)) }
        let summary = try await LibrarySyncer(store: lib.store, source: lib.source, sourceID: LibraryRig.sourceID, clock: { epoch.addingTimeInterval(100 * 86_400) }).sync()
        XCTAssertEqual(summary.status, .completed)
        return Rig(lib: lib)
    }

    func testASidecarPosterWinsAndTheOnlineLookupIsNeverAsked() async throws {
        let r = try await rig([("/Movies/Heat (1995)/Heat (1995).mkv", 10_000), ("/Movies/Heat (1995)/poster.jpg", 5)])
        r.reader.files["/Movies/Heat (1995)/poster.jpg"] = Data([1, 2, 3, 4, 5])
        let id = try await r.lib.movieID("Heat")
        let result = await r.engine().resolve(key: "item-\(id)")
        guard case .file(let url) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(r.online.itemCalls, 0, "local pictures win over online ones")
    }

    func testWithoutASidecarTheMatchedOnlinePosterIsUsedAsAnAddress() async throws {
        let r = try await rig([("/Movies/Alien (1979)/Alien (1979).mkv", 9_000)])
        let id = try await r.lib.movieID("Alien")
        let result = await r.engine().resolve(key: "item-\(id)")
        XCTAssertEqual(result, .remote(URL(string: "https://images.example.invalid/item.jpg")!))
        XCTAssertTrue(r.reader.reads.isEmpty)
    }

    func testWithNoKeyAndNoSidecarThereIsNoPictureAndNothingIsAsked() async throws {
        let r = try await rig([("/Movies/Alien (1979)/Alien (1979).mkv", 9_000)])
        let id = try await r.lib.movieID("Alien")
        let result = await r.engine(withOnline: false).resolve(key: "item-\(id)")
        XCTAssertEqual(result, .none)
        XCTAssertEqual(r.online.itemCalls, 0)
    }

    func testAGenericPosterInAFolderWithTwoMoviesBelongsToNeither() async throws {
        let r = try await rig([("/Movies/Pair/First (2000).mkv", 1_000), ("/Movies/Pair/Second (2001).mkv", 1_000), ("/Movies/Pair/poster.jpg", 5),
                               ("/Movies/Pair/First (2000)-poster.jpg", 5)])
        r.reader.files["/Movies/Pair/poster.jpg"] = Data([9]); r.reader.files["/Movies/Pair/First (2000)-poster.jpg"] = Data([7])
        let first = try await r.lib.movieID("First")
        let second = try await r.lib.movieID("Second")
        let e = r.engine(withOnline: false)
        let a = await e.resolve(key: "item-\(first)")
        guard case .file(let url) = a else { return XCTFail("\(a)") }
        XCTAssertEqual(try Data(contentsOf: url), Data([7]), "the same-name poster is used")
        let b = await e.resolve(key: "item-\(second)")
        XCTAssertEqual(b, .none, "the folder-wide poster is not handed to a folder with several movies")
    }

    func testAnEpisodeUsesItsOwnStillThenTheShowPoster() async throws {
        let r = try await rig([("/TV/Show One (2010)/Season 1/Show One - S01E01 - A.mkv", 1_000), ("/TV/Show One (2010)/Season 1/Show One - S01E01 - A-thumb.jpg", 5),
                               ("/TV/Show One (2010)/Season 1/Show One - S01E02 - B.mkv", 1_000), ("/TV/Show One (2010)/poster.jpg", 5)])
        r.reader.files["/TV/Show One (2010)/Season 1/Show One - S01E01 - A-thumb.jpg"] = Data([1])
        r.reader.files["/TV/Show One (2010)/poster.jpg"] = Data([2])
        let eps = try await r.lib.episodes(ofSeriesTitle: "Show One")
        let e1 = try XCTUnwrap(eps.first { $0.episode == 1 }), e2 = try XCTUnwrap(eps.first { $0.episode == 2 })
        let engine = r.engine(withOnline: false)
        guard case .file(let u1) = await engine.resolve(key: "item-\(e1.id)"), case .file(let u2) = await engine.resolve(key: "item-\(e2.id)") else { return XCTFail("no files") }
        XCTAssertEqual(try Data(contentsOf: u1), Data([1]))
        XCTAssertEqual(try Data(contentsOf: u2), Data([2]), "no own picture: the show poster")
        guard case .file(let u3) = await engine.resolve(key: "series-\(try XCTUnwrap(e1.seriesID))") else { return XCTFail("series") }
        XCTAssertEqual(try Data(contentsOf: u3), Data([2]))
    }

    func testASeriesWithoutASidecarAsksOnlineByTheMostCommonID() async throws {
        let r = try await rig([("/TV/Show One (2010)/Season 1/Show One - S01E01 - A.mkv", 1_000), ("/TV/Show One (2010)/Season 1/Show One - S01E02 - B.mkv", 1_000),
                               ("/TV/Show One (2010)/Season 1/Show One - S01E03 - C.mkv", 1_000)])
        let eps = try await r.lib.episodes(ofSeriesTitle: "Show One")
        for (i, e) in eps.enumerated() { try await r.lib.store.setMetadata(itemID: e.id, ItemMetadata(tmdbID: i == 0 ? 5 : 7)) }
        let result = await r.engine().resolve(key: "series-\(try XCTUnwrap(eps.first?.seriesID))")
        XCTAssertEqual(result, .remote(URL(string: "https://images.example.invalid/series.jpg")!))
        XCTAssertEqual(r.online.seriesCalls, [7])
    }

    func testAPictureIsReadOnceThenServedFromTheCache() async throws {
        let r = try await rig([("/Movies/Heat (1995)/Heat (1995).mkv", 10_000), ("/Movies/Heat (1995)/poster.jpg", 5)])
        r.reader.files["/Movies/Heat (1995)/poster.jpg"] = Data([1, 2, 3, 4, 5])
        let id = try await r.lib.movieID("Heat")
        let e = r.engine()
        _ = await e.resolve(key: "item-\(id)")
        _ = await e.resolve(key: "item-\(id)")
        XCTAssertEqual(r.reader.reads.count, 1)
    }

    func testAnUnreadableOrOversizedPictureFallsBackToOnline() async throws {
        let r = try await rig([("/Movies/Heat (1995)/Heat (1995).mkv", 10_000), ("/Movies/Heat (1995)/poster.jpg", Int64(ArtworkEngine.maxSidecarBytes) + 1),
                               ("/Movies/Alien (1979)/Alien (1979).mkv", 9_000), ("/Movies/Alien (1979)/poster.jpg", 5)])
        // Heat's poster is over the size limit (40 MB since the quality re-check); Alien's cannot be read (not in the fake reader).
        let heat = try await r.lib.movieID("Heat"), alien = try await r.lib.movieID("Alien")
        let e = r.engine()
        let a = await e.resolve(key: "item-\(heat)"), b = await e.resolve(key: "item-\(alien)")
        guard case .remote = a, case .remote = b else { return XCTFail("\(a) \(b)") }
        XCTAssertFalse(r.reader.reads.contains("/Movies/Heat (1995)/poster.jpg"), "an oversized file is not even downloaded")
    }

    func testANothingAnswerIsRememberedForAWhileThenAskedAgain() async throws {
        let r = try await rig([("/Movies/Alien (1979)/Alien (1979).mkv", 9_000)])
        r.online.itemURL = nil
        let id = try await r.lib.movieID("Alien")
        let clock = TickClock()
        final class Box: @unchecked Sendable { var offset = 0.0 }
        let box = Box()
        let e = r.engine(clock: { clock.now().addingTimeInterval(box.offset) })
        _ = await e.resolve(key: "item-\(id)")
        _ = await e.resolve(key: "item-\(id)")
        XCTAssertEqual(r.online.itemCalls, 1, "scrolling past again does not repeat the lookup")
        box.offset = ArtworkEngine.missMemory + 10
        _ = await e.resolve(key: "item-\(id)")
        XCTAssertEqual(r.online.itemCalls, 2)
    }

    func testRemoteKeysAndUnknownKeys() async throws {
        let r = try await rig([("/Movies/Alien (1979)/Alien (1979).mkv", 9_000)])
        let e = r.engine()
        let remote = await e.resolve(key: "remote:/abc.jpg")
        XCTAssertEqual(remote, .remote(URL(string: "https://images.example.invalid/w500/abc.jpg")!))
        for bad in ["", "remote:", "remote:abc", "item-x", "item-999999", "series-999999", "folder-1"] {
            let result = await e.resolve(key: bad)
            XCTAssertEqual(result, .none, bad)
        }
        let none = await r.engine(withOnline: false).resolve(key: "remote:/abc.jpg")
        XCTAssertEqual(none, .none, "no key, no address")
    }

    func testKeysParse() {
        XCTAssertEqual(ArtworkKey("item-42"), .item(42))
        XCTAssertEqual(ArtworkKey("series-7"), .series(7))
        XCTAssertEqual(ArtworkKey("remote:/p.jpg"), .remote("/p.jpg"))
        XCTAssertNil(ArtworkKey("item-"))
    }
}
