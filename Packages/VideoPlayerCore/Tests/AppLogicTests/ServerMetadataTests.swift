import XCTest
import VideoPlayerCore
import LibraryIndex
import MetadataOnline
@testable import AppLogic

// FIXTURE: invented titles, a few invented picture bytes, fake server and online layers; nothing is contacted.

/// Stage 7 (R270, R307): Plex's own synopsis and poster come first for Plex files, TMDB fills the gaps; WebDAV, Jellyfin and
/// Emby keep exactly the order they had (details: Wikidata, then TMDB; artwork: the picture next to the file, then online).
final class ServerMetadataTests: XCTestCase {
    private final class FakeServer: ServerMetadataProviding, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var summaryAsked: [String] = []
        private(set) var posterAsked: [String] = []
        private(set) var fetches = 0
        func summary(for file: StoredFile) async -> String? {
            lock.withLock { summaryAsked.append(file.sourceID) }
            return "The server's synopsis."
        }
        func poster(for file: StoredFile) async -> ServerPicture? {
            lock.withLock { posterAsked.append(file.sourceID) }
            return ServerPicture(cacheKey: "plex|\(file.sourceID)|/library/metadata/1/thumb/1") { [self] _ in
                lock.withLock { fetches += 1 }
                return Data([9, 9, 9])
            }
        }
    }

    private struct TMDBDetails: TitleDetailsSource {
        func details(key: String) async -> TitleDetails? {
            TitleDetails(overview: "The online synopsis.", cast: [TitleDetails.CastMember(id: 1, name: "Ann Example", role: "Lead")])
        }
    }

    private final class Online: OnlineArtworkProviding, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var posterCalls = 0
        func posterURL(forItem item: LibraryItem, file: StoredFile?) async -> URL? {
            lock.withLock { posterCalls += 1 }
            return URL(string: "https://images.example.invalid/online.jpg")
        }
        func posterURL(forSeriesID tmdbID: Int) async -> URL? { nil }
        func imageURL(path: String) async -> URL? { nil }
    }

    private final class Reader: SidecarReading, @unchecked Sendable {
        var files: [String: Data] = [:]
        func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data {
            guard let data = files[path] else { throw SourceError.notFound }
            return data
        }
    }

    /// One movie per source kind, each with its own title (one item each).
    private let movies: [(id: String, kind: SourceKind, title: String)] = [
        ("dav", .webdav, "Arnvale"), ("jf", .jellyfin, "Brisken"), ("emby", .emby, "Corvath"), ("plex", .plex, "Dunmere"),
    ]

    private func library(sidecarOnPlex: Bool = false) async throws -> (SQLiteLibraryStore, [String: Int64]) {
        let store = try SQLiteLibraryStore(path: ":memory:")
        var ids: [String: Int64] = [:]
        for movie in movies {
            try await store.upsertSource(LibrarySourceRecord(id: movie.id, kind: movie.kind, name: movie.title, addedAt: epoch))
            let tree = TreeSource()
            tree.put("/Movies/\(movie.title) (2001)/\(movie.title) (2001).mkv")
            if sidecarOnPlex && movie.kind == .plex { tree.put("/Movies/\(movie.title) (2001)/poster.jpg", size: 3) }
            let summary = try await LibrarySyncer(store: store, source: tree, sourceID: movie.id, clock: { dayOffset(100) }).sync()
            XCTAssertEqual(summary.status, .completed)
            let file = try await store.storedFiles(sourceID: movie.id, folder: "/Movies/\(movie.title) (2001)").first { $0.name.hasSuffix(".mkv") }
            ids[movie.id] = try XCTUnwrap(file?.itemID)
        }
        return (store, ids)
    }

    func testDetailsTakePlexsSynopsisFirstAndTheOtherSourcesKeepTheirOrder() async throws {
        let (store, ids) = try await library()
        let server = FakeServer()
        let withServer = LayeredDetailsService.online(store: store, wikidata: nil, tmdb: TMDBDetails(), server: server)
        let without = LayeredDetailsService.online(store: store, wikidata: nil, tmdb: TMDBDetails())

        let plex = await withServer.details(key: "item-\(ids["plex"]!)")
        XCTAssertEqual(plex.details?.overview, "The server's synopsis.")
        XCTAssertEqual(plex.used, [.source, .tmdb], "TMDB fills only the gap (the cast)")
        XCTAssertEqual(plex.details?.cast.map(\.name), ["Ann Example"])

        for id in ["dav", "jf", "emby"] {
            let a = await withServer.details(key: "item-\(ids[id]!)")
            let b = await without.details(key: "item-\(ids[id]!)")
            XCTAssertEqual(a, b, "\(id): unchanged by the Plex layer")
            XCTAssertEqual(a.used, [.tmdb], id)
            XCTAssertEqual(a.details?.overview, "The online synopsis.", id)
        }
        XCTAssertEqual(server.summaryAsked, ["plex"], "the server is asked about Plex files only")
    }

    func testArtworkTakesPlexsPosterBeforeOnlineAndTheOtherSourcesKeepTheirOrder() async throws {
        let (store, ids) = try await library()
        let server = FakeServer(), online = Online()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("server-art-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = ArtworkEngine(store: store, cache: ArtworkDiskCache(directory: dir, maxBytes: 1_000_000), reader: Reader(),
                                   online: online, server: server)

        guard case .file(let url) = await engine.resolve(key: "item-\(ids["plex"]!)") else { return XCTFail("expected the server's poster") }
        XCTAssertEqual(try Data(contentsOf: url), Data([9, 9, 9]))
        XCTAssertEqual(online.posterCalls, 0, "online is not asked when Plex has a poster")

        for id in ["dav", "jf", "emby"] {
            let result = await engine.resolve(key: "item-\(ids[id]!)")
            XCTAssertEqual(result, .remote(URL(string: "https://images.example.invalid/online.jpg")!), id)
        }
        XCTAssertEqual(server.posterAsked, ["plex"], "the server is asked about Plex files only")

        // Shown again: the cached copy, no second read from the server.
        _ = await engine.resolve(key: "item-\(ids["plex"]!)")
        XCTAssertEqual(server.fetches, 1)
    }

    func testAPictureNextToThePlexFileStillComesFirst() async throws {
        let (store, ids) = try await library(sidecarOnPlex: true)
        let server = FakeServer(), reader = Reader()
        reader.files["/Movies/Dunmere (2001)/poster.jpg"] = Data([1, 2, 3])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("server-art-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = ArtworkEngine(store: store, cache: ArtworkDiskCache(directory: dir, maxBytes: 1_000_000), reader: reader,
                                   online: nil, server: server)
        guard case .file(let url) = await engine.resolve(key: "item-\(ids["plex"]!)") else { return XCTFail("expected the sidecar") }
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
        XCTAssertTrue(server.posterAsked.isEmpty)
    }

    func testShowPagesGetNothingFromTheServerLayer() async throws {
        let (store, _) = try await library()
        let layer = ServerDetailsLayer(store: store, server: FakeServer())
        let none = await layer.details(key: "series-1")
        XCTAssertNil(none)
    }
}
