import XCTest
import VideoPlayerCore
@testable import MetadataOnline

final class CacheTests: XCTestCase {
    private func key(_ kind: String, _ id: String, _ variant: String = "en-US", provider: String = "tmdb") -> CacheKey {
        CacheKey(provider: provider, kind: kind, id: id, variant: variant)
    }

    private func caches() -> [(String, any MetadataCache, URL?)] {
        let dir = tempDirectory("cache")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return [("memory", InMemoryMetadataCache(), nil), ("file", JSONFileMetadataCache(directory: dir), dir)]
    }

    func testKeyTextIsProviderKindIdVariant() {
        XCTAssertEqual(key("movie", "603").description, "tmdb/movie/603/en-US")
        XCTAssertEqual(key("tv", "1399", "season-2/en-US").description, "tmdb/tv/1399/season-2/en-US")
    }

    func testStoreAndReadBackInBothImplementations() async {
        let date = Date(timeIntervalSince1970: 1_000_000)
        for (name, cache, _) in caches() {
            let k = key("movie", "603")
            let missing = await cache.entry(for: k)
            XCTAssertNil(missing, name)
            await cache.store(Data("hello".utf8), for: k, ttl: 60, at: date)
            let entry = await cache.entry(for: k)
            XCTAssertEqual(entry?.data, Data("hello".utf8), name)
            XCTAssertEqual(entry?.ttl, 60, name)
            XCTAssertEqual(entry?.storedAt.timeIntervalSince1970 ?? 0, 1_000_000, accuracy: 1, name)
        }
    }

    func testFreshnessFollowsTheTimeToLive() {
        let e = CacheEntry(storedAt: Date(timeIntervalSince1970: 100), ttl: 10, data: Data())
        XCTAssertTrue(e.isFresh(at: Date(timeIntervalSince1970: 105)))
        XCTAssertFalse(e.isFresh(at: Date(timeIntervalSince1970: 110)))
        XCTAssertFalse(e.isFresh(at: Date(timeIntervalSince1970: 500)))
    }

    func testStaleEntriesAreStillReturnedForOfflineUse() async {
        for (name, cache, _) in caches() {
            let k = key("movie", "1")
            await cache.store(Data("x".utf8), for: k, ttl: 1, at: Date(timeIntervalSince1970: 0))
            let entry = await cache.entry(for: k)
            XCTAssertNotNil(entry, name)
            XCTAssertFalse(entry?.isFresh(at: Date()) ?? true, name)
        }
    }

    func testStoringAgainReplaces() async {
        for (name, cache, _) in caches() {
            let k = key("movie", "1")
            await cache.store(Data("a".utf8), for: k, ttl: 1, at: Date())
            await cache.store(Data("b".utf8), for: k, ttl: 1, at: Date())
            let entry = await cache.entry(for: k)
            XCTAssertEqual(entry?.data, Data("b".utf8), name)
        }
    }

    func testRemoveByKeyAndByPrefix() async {
        for (name, cache, _) in caches() {
            for k in [key("movie", "603"), key("movie", "603", "de-DE"), key("movie", "6030"), key("tv", "603", "season-1/en-US"), key("movie", "604")] {
                await cache.store(Data("x".utf8), for: k, ttl: 1, at: Date())
            }
            let removed = await cache.remove(prefix: "tmdb/movie/603/")
            XCTAssertEqual(removed, 2, "\(name): 603/ must not catch 6030")
            let survivors = [("movie", "6030", "en-US"), ("tv", "603", "season-1/en-US"), ("movie", "604", "en-US")]
            for (kind, id, variant) in survivors {
                let e = await cache.entry(for: key(kind, id, variant))
                XCTAssertNotNil(e, "\(name) \(kind)/\(id)")
            }
            await cache.remove(key("movie", "604"))
            let gone = await cache.entry(for: key("movie", "604"))
            XCTAssertNil(gone, name)
        }
    }

    func testRemoveAll() async {
        for (name, cache, _) in caches() {
            await cache.store(Data("x".utf8), for: key("movie", "1"), ttl: 1, at: Date())
            await cache.store(Data("x".utf8), for: key("movie", "2", provider: "omdb"), ttl: 1, at: Date())
            await cache.removeAll()
            let a = await cache.entry(for: key("movie", "1"))
            let b = await cache.entry(for: key("movie", "2", provider: "omdb"))
            XCTAssertNil(a, name)
            XCTAssertNil(b, name)
        }
    }

    func testFileCacheSurvivesANewInstanceAndUsesSafeFileNames() async throws {
        let dir = tempDirectory("cache-persist")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = JSONFileMetadataCache(directory: dir)
        let k = key("search-movie", "../etc/passwd|1999")
        await first.store(Data("payload".utf8), for: k, ttl: 100, at: Date())
        let second = JSONFileMetadataCache(directory: dir)
        let e = await second.entry(for: k)
        XCTAssertEqual(e?.data, Data("payload".utf8))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files[0].contains("/"))
        XCTAssertTrue(files[0].hasSuffix(".json"))
        // Nothing was written outside the folder.
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("etc").path))
    }

    func testFileCacheIgnoresUnreadableFilesAndReplacesThem() async throws {
        let dir = tempDirectory("cache-corrupt")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = JSONFileMetadataCache(directory: dir)
        let k = key("movie", "9")
        await cache.store(Data("good".utf8), for: k, ttl: 100, at: Date())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: dir.path).first)
        try Data("{ broken".utf8).write(to: dir.appendingPathComponent(file))
        let broken = await cache.entry(for: k)
        XCTAssertNil(broken)
        await cache.store(Data("again".utf8), for: k, ttl: 100, at: Date())
        let fixed = await cache.entry(for: k)
        XCTAssertEqual(fixed?.data, Data("again".utf8))
    }

    func testFilePrefixRemovalOnlyTouchesCacheFiles() async throws {
        let dir = tempDirectory("cache-prefix")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = JSONFileMetadataCache(directory: dir)
        await cache.store(Data("x".utf8), for: key("movie", "1"), ttl: 1, at: Date())
        try Data("keep".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        let n = await cache.remove(prefix: "")
        XCTAssertEqual(n, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
    }

    func testPolicyDefaults() {
        let p = CachePolicy.standard
        XCTAssertEqual(p.details, 14 * 86_400)
        XCTAssertEqual(p.season, 3 * 86_400)
        XCTAssertEqual(p.search, 86_400)
        XCTAssertEqual(p.configuration, 7 * 86_400)
        XCTAssertEqual(p.ratings, 7 * 86_400)
    }

    // MARK: Refresh Metadata

    private func filled() async -> InMemoryMetadataCache {
        let cache = InMemoryMetadataCache()
        let all = [
            key("movie", "603"), key("movie", "603", "de-DE"), key("movie", "604"),
            key("tv", "1396"), key("tv", "1396", "season-1/en-US"), key("tv", "1396", "season-2/en-US"), key("tv", "1399"),
            key("search-movie", "matrix|1999"), key("configuration", "-", ""),
            key("title", "tt0133093", "", provider: "omdb"), key("title", "tt0903747", "", provider: "omdb")
        ]
        for k in all { await cache.store(Data("x".utf8), for: k, ttl: 1, at: Date()) }
        return cache
    }

    func testRefreshOneMovieDropsAllItsLanguagesAndItsOMDbScores() async {
        let cache = await filled()
        let n = await MetadataRefresh.invalidate(.item(ProviderIDs(tmdb: 603, imdb: "tt0133093"), kind: .movie), in: cache)
        XCTAssertEqual(n, 3)
        let keys = await cache.keys
        XCTAssertFalse(keys.contains { $0.hasPrefix("tmdb/movie/603/") })
        XCTAssertFalse(keys.contains("omdb/title/tt0133093/"))
        XCTAssertTrue(keys.contains("tmdb/movie/604/en-US"))
        XCTAssertTrue(keys.contains("omdb/title/tt0903747/"))
    }

    func testRefreshOneSeriesDropsItsSeasonsAndEpisodes() async {
        let cache = await filled()
        let n = await MetadataRefresh.invalidate(.item(ProviderIDs(tmdb: 1396, imdb: "tt0903747"), kind: .series), in: cache)
        XCTAssertEqual(n, 4)
        let keys = await cache.keys
        XCTAssertFalse(keys.contains { $0.hasPrefix("tmdb/tv/1396/") })
        XCTAssertTrue(keys.contains("tmdb/tv/1399/en-US"))
    }

    func testRefreshFolderDropsEachListedItem() async {
        let cache = await filled()
        let n = await MetadataRefresh.invalidate(.folder([(ProviderIDs(tmdb: 603), .movie), (ProviderIDs(tmdb: 604), .movie), (ProviderIDs(tmdb: 1399), .series)]), in: cache)
        XCTAssertEqual(n, 4)
        let keys = await cache.keys
        XCTAssertTrue(keys.contains("tmdb/tv/1396/en-US"))
        XCTAssertTrue(keys.contains("tmdb/search-movie/matrix|1999/en-US"))
    }

    func testRefreshLibraryDropsEverythingThisTargetCached() async {
        let cache = await filled()
        let n = await MetadataRefresh.invalidate(.library, in: cache)
        XCTAssertEqual(n, 11)
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    func testRefreshedItemIsFetchedAgainOnNextRead() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let cache = InMemoryMetadataCache()
        let client = TMDBClient(credentials: .apiKey("k"), transport: transport, cache: cache, queueConfiguration: plainQueue(), clock: FakeClock())
        _ = try await client.movie(id: 603)
        _ = try await client.movie(id: 603)
        XCTAssertEqual(transport.count, 1)
        await MetadataRefresh.invalidate(.item(ProviderIDs(tmdb: 603), kind: .movie), in: cache)
        _ = try await client.movie(id: 603)
        XCTAssertEqual(transport.count, 2)
    }
}
