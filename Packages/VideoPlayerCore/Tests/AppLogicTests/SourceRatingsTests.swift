import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

// FIXTURE: hand-written NFO files, invented titles and ratings, a fake server and a fake file reader; nothing is contacted.

/// R374: the source's own content rating: a media server's (Plex `contentRating`, Jellyfin and Emby `OfficialRating`) first,
/// then the title's own NFO file, read once and kept in the library.
final class SourceRatingsTests: XCTestCase {
    private final class RatingServer: ServerMetadataProviding, @unchecked Sendable {
        private let lock = NSLock()
        var ratings: [String: String] = [:]
        private(set) var ratingAsked: [String] = []
        private(set) var summaryAsked: [String] = []
        func summary(for file: StoredFile) async -> String? {
            lock.withLock { summaryAsked.append(file.sourceID) }
            return nil
        }
        func poster(for file: StoredFile) async -> ServerPicture? { nil }
        func contentRating(for file: StoredFile) async -> String? {
            lock.withLock { ratingAsked.append(file.sourceID) }
            return ratings[file.sourceID]
        }
        /// R374: the single-item request's answer; nil: the server has none; `failing`: it cannot be asked now.
        var requested: String?
        var failing = false
        private(set) var requests = 0
        func requestContentRating(for file: StoredFile) async throws -> String? {
            lock.withLock { requests += 1 }
            if failing { throw SourceError.unsupported("offline") }
            return requested
        }
    }

    private final class Reader: SidecarReading, @unchecked Sendable {
        private let lock = NSLock()
        var files: [String: Data] = [:]
        private(set) var reads: [String] = []
        func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data {
            lock.withLock { reads.append(path) }
            guard let data = files[path] else { throw SourceError.notFound }
            return data
        }
    }

    private static let movieNFO = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
        <movie>
          <title>Arnvale</title>
          <year>2001</year>
          <mpaa>Rated PG-13</mpaa>
        </movie>
        """.utf8)

    private static let episodeNFO = Data("""
        <episodedetails>
          <title>Pilot</title>
          <season>1</season>
          <episode>1</episode>
          <certification>US:TV-14</certification>
        </episodedetails>
        """.utf8)

    private static let unratedNFO = Data("""
        <movie>
          <title>Arnvale</title>
          <mpaa>Not Rated</mpaa>
        </movie>
        """.utf8)

    func testTheNFOFileGivesTheRatingOfItsKindOfItem() {
        XCTAssertEqual(SourceRatings.nfoRating(Self.movieNFO, kind: .movie), "Rated PG-13")
        XCTAssertEqual(ContentRating.clean(SourceRatings.nfoRating(Self.movieNFO, kind: .movie)), "PG-13")
        XCTAssertEqual(ContentRating.clean(SourceRatings.nfoRating(Self.episodeNFO, kind: .episode)), "TV-14")
        XCTAssertEqual(SourceRatings.nfoRating(Self.episodeNFO, kind: .movie), "", "an episode's file says nothing about a film")
        XCTAssertEqual(SourceRatings.nfoRating(Self.unratedNFO, kind: .movie), "", "\"Not Rated\" is no rating")
        XCTAssertEqual(SourceRatings.nfoRating(Data("not xml".utf8), kind: .movie), "")
    }

    /// One movie with an NFO file next to it, on a source of the given kind.
    private func library(kind: SourceKind, nfo: Data?) async throws -> (SQLiteLibraryStore, Int64, Reader) {
        let store = try SQLiteLibraryStore(path: ":memory:")
        try await store.upsertSource(LibrarySourceRecord(id: "src", kind: kind, name: "Source", addedAt: epoch))
        let tree = TreeSource()
        tree.put("/Movies/Arnvale (2001)/Arnvale (2001).mkv")
        let reader = Reader()
        if let nfo {
            tree.put("/Movies/Arnvale (2001)/Arnvale (2001).nfo", size: Int64(nfo.count))
            reader.files["/Movies/Arnvale (2001)/Arnvale (2001).nfo"] = nfo
        }
        let summary = try await LibrarySyncer(store: store, source: tree, sourceID: "src", clock: { dayOffset(100) }).sync()
        XCTAssertEqual(summary.status, .completed)
        let file = try await store.storedFiles(sourceID: "src", folder: "/Movies/Arnvale (2001)").first { $0.name.hasSuffix(".mkv") }
        return (store, try XCTUnwrap(file?.itemID), reader)
    }

    func testTheNFORatingIsReadOnceAndKeptInTheLibrary() async throws {
        let (store, id, reader) = try await library(kind: .webdav, nfo: Self.movieNFO)
        let before = try await store.item(id: id)
        XCTAssertNil(before?.contentRating, "not read yet")

        let layer = SourceDetailsLayer(store: store, server: nil, reader: reader)
        let first = await layer.details(key: "item-\(id)")
        XCTAssertEqual(first?.contentRating, "PG-13")
        XCTAssertNil(first?.overview)
        let stored = try await store.item(id: id)
        XCTAssertEqual(stored?.contentRating, "Rated PG-13", "kept as the file writes it")

        let again = await layer.details(key: "item-\(id)")
        XCTAssertEqual(again?.contentRating, "PG-13")
        XCTAssertEqual(reader.reads.count, 1, "the file is not read a second time")
    }

    func testAFileWithoutARatingIsRecordedAndNotReadAgain() async throws {
        let (store, id, reader) = try await library(kind: .webdav, nfo: Self.unratedNFO)
        let layer = SourceDetailsLayer(store: store, server: nil, reader: reader)
        let first = await layer.details(key: "item-\(id)")
        let second = await layer.details(key: "item-\(id)")
        XCTAssertNil(first)
        XCTAssertNil(second)
        let stored = try await store.item(id: id)
        XCTAssertEqual(stored?.contentRating, "")
        XCTAssertEqual(reader.reads.count, 1)
    }

    func testNoNFOFileGivesNothingAndIsTriedAgainLater() async throws {
        let (store, id, reader) = try await library(kind: .webdav, nfo: nil)
        let layer = SourceDetailsLayer(store: store, server: nil, reader: reader)
        let none = await layer.details(key: "item-\(id)")
        XCTAssertNil(none)
        let stored = try await store.item(id: id)
        XCTAssertNil(stored?.contentRating, "nothing recorded")
        XCTAssertTrue(reader.reads.isEmpty, "no sidecar, nothing read")
    }

    func testTheServersRatingComesBeforeTheNFOFile() async throws {
        for kind in [SourceKind.jellyfin, .emby, .plex] {
            let (store, id, reader) = try await library(kind: kind, nfo: Self.movieNFO)
            let server = RatingServer()
            server.ratings["src"] = "R"
            let layer = SourceDetailsLayer(store: store, server: server, reader: reader)
            let details = await layer.details(key: "item-\(id)")
            XCTAssertEqual(details?.contentRating, "R", "\(kind)")
            XCTAssertTrue(reader.reads.isEmpty, "\(kind): the NFO file is not needed")
            XCTAssertEqual(server.ratingAsked, ["src"], "\(kind)")
            XCTAssertEqual(server.summaryAsked, kind == .plex ? ["src"] : [], "\(kind): only Plex gives its synopsis (R210)")
        }
    }

    func testTheNFOFileFillsInWhenTheServerHasNoRating() async throws {
        let (store, id, reader) = try await library(kind: .jellyfin, nfo: Self.movieNFO)
        let layer = SourceDetailsLayer(store: store, server: RatingServer(), reader: reader)
        let details = await layer.details(key: "item-\(id)")
        XCTAssertEqual(details?.contentRating, "PG-13")
    }

    func testAWebDAVSourceIsNeverAskedForAServerRating() async throws {
        let (store, id, _) = try await library(kind: .webdav, nfo: nil)
        let server = RatingServer()
        server.ratings["src"] = "R"
        let none = await ServerDetailsLayer(store: store, server: server).details(key: "item-\(id)")
        XCTAssertNil(none)
        XCTAssertTrue(server.ratingAsked.isEmpty)
        XCTAssertEqual(ServerMetadataKinds.rating, [.plex, .jellyfin, .emby])
        XCTAssertEqual(ServerMetadataKinds.used, [.plex], "the synopsis and pictures stay Plex only")
    }

    func testTheRatingLayerFeedsTheLayeredDetailsSourceFirst() async throws {
        let (store, id, reader) = try await library(kind: .webdav, nfo: Self.movieNFO)
        let service = LayeredDetailsService.online(store: store, wikidata: nil, tmdb: nil, reader: reader)
        let result = await service.details(key: "item-\(id)")
        XCTAssertEqual(result.details?.contentRating, "PG-13")
        XCTAssertEqual(result.used, [.source])
    }

    func testWhenTheListLacksItOneRequestIsMadeAndTheAnswerKept() async throws {
        for kind in [SourceKind.jellyfin, .emby] {
            let (store, id, reader) = try await library(kind: kind, nfo: Self.movieNFO)
            let server = RatingServer()
            server.requested = "TV-MA"
            let layer = SourceDetailsLayer(store: store, server: server, reader: reader)
            let first = await layer.details(key: "item-\(id)")
            XCTAssertEqual(first?.contentRating, "TV-MA", "\(kind): the server's answer before the NFO file")
            let stored = try await store.item(id: id)
            XCTAssertEqual(stored?.contentRating, "TV-MA", "\(kind)")
            let again = await layer.details(key: "item-\(id)")
            XCTAssertEqual(again?.contentRating, "TV-MA")
            XCTAssertEqual(server.requests, 1, "\(kind): asked once")
            XCTAssertTrue(reader.reads.isEmpty, "\(kind): the NFO file is not needed")
        }
    }

    func testAServerWithoutARatingIsRecordedAndTheNFOFileFillsIn() async throws {
        let (store, id, reader) = try await library(kind: .emby, nfo: Self.movieNFO)
        let server = RatingServer()
        let layer = SourceDetailsLayer(store: store, server: server, reader: reader)
        let first = await layer.details(key: "item-\(id)")
        XCTAssertEqual(first?.contentRating, "PG-13")
        let stored = try await store.item(id: id)
        XCTAssertEqual(stored?.contentRating, "Rated PG-13")
        _ = await layer.details(key: "item-\(id)")
        XCTAssertEqual(server.requests, 1)
        XCTAssertEqual(reader.reads.count, 1)
    }

    func testAServerWithoutARatingAndNoNFOIsRecordedAsNone() async throws {
        let (store, id, reader) = try await library(kind: .jellyfin, nfo: nil)
        let server = RatingServer()
        let layer = SourceDetailsLayer(store: store, server: server, reader: reader)
        let none = await layer.details(key: "item-\(id)")
        XCTAssertNil(none)
        let stored = try await store.item(id: id)
        XCTAssertEqual(stored?.contentRating, "", "the server answered: none")
        _ = await layer.details(key: "item-\(id)")
        XCTAssertEqual(server.requests, 1, "not asked again")
    }

    func testAFailedRequestIsNotKeptAndIsTriedAgain() async throws {
        let (store, id, reader) = try await library(kind: .jellyfin, nfo: nil)
        let server = RatingServer()
        server.failing = true
        let layer = SourceDetailsLayer(store: store, server: server, reader: reader)
        _ = await layer.details(key: "item-\(id)")
        let stored = try await store.item(id: id)
        XCTAssertNil(stored?.contentRating)
        server.failing = false
        server.requested = "PG"
        let later = await layer.details(key: "item-\(id)")
        XCTAssertEqual(later?.contentRating, "PG")
        XCTAssertEqual(server.requests, 2)
    }

    func testPlexAndWebDAVMakeNoSingleItemRequest() async throws {
        for kind in [SourceKind.plex, .webdav] {
            let (store, id, reader) = try await library(kind: kind, nfo: nil)
            let server = RatingServer()
            server.requested = "R"
            _ = await SourceDetailsLayer(store: store, server: server, reader: reader).details(key: "item-\(id)")
            XCTAssertEqual(server.requests, 0, "\(kind)")
        }
        XCTAssertEqual(ServerMetadataKinds.requested, [.jellyfin, .emby])
    }
}
