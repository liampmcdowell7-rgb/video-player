import XCTest
import VideoPlayerCore
import LibraryIndex
import PlaybackLogic
import MetadataOnline
@testable import AppLogic

// #29 (R226): the closures the app hands to the layered details service, the IMDb id resolver and the segment provider are
// built in AppLogic (OnlineComposition.swift), so these tests type-check and run them on Linux. FIXTURE: placeholder key text,
// a fake transport, synthetic titles; nothing is contacted.

private final class CompositionTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _paths: [String] = []
    private let body: String
    init(body: String) { self.body = body }
    var paths: [String] { lock.withLock { _paths } }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { _paths.append(request.url.path) }
        return HTTPResponse(statusCode: 200, body: Data(body.utf8))
    }
}

private struct FixedDetails: TitleDetailsSource {
    let value: TitleDetails?
    func details(key: String) async -> TitleDetails? { value }
}

final class OnlineCompositionTests: XCTestCase {
    private let full = TitleDetails(overview: "A synthetic synopsis.", cast: [.init(id: 1, name: "Sample Actor A", role: "Role A")])

    func testALayerThatIsOffIsNil() {
        XCTAssertNil(LayeredDetailsService.layer(nil))
        XCTAssertNotNil(LayeredDetailsService.layer(FixedDetails(value: nil)))
    }

    func testTheAppServiceWithNoKeyAndFreeSourcesOffGivesNothing() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        let service = LayeredDetailsService.online(store: store, wikidata: nil, tmdb: nil)
        let result = await service.details(key: "item-1")
        XCTAssertNil(result.details)
        XCTAssertEqual(result.used, [])
    }

    func testTheAppServiceUsesTheTMDBSourceItIsGiven() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        let service = LayeredDetailsService.online(store: store, wikidata: nil, tmdb: FixedDetails(value: full))
        let result = await service.details(key: "item-1")
        XCTAssertEqual(result.details, full)
        XCTAssertEqual(result.used, [.tmdb])
    }

    func testTMDBExternalIsNilWithoutAClientAndReadsTheIMDbIDWithOne() async throws {
        XCTAssertNil(IMDbIDResolver.tmdbExternal(nil))
        let transport = CompositionTransport(body: #"{"id":5,"imdb_id":"tt0000005","tvdb_id":null}"#)
        let client = TMDBClient(credentials: .apiKey("fixture-key"), transport: transport)
        let external = try XCTUnwrap(IMDbIDResolver.tmdbExternal(client))
        let id = try await external(.movie, 5)
        XCTAssertEqual(id, "tt0000005")
        XCTAssertEqual(transport.paths.last.map { $0.hasSuffix("/movie/5/external_ids") }, true)
    }

    func testOnlineTimingsAreNilWhenFreeSourcesAreOffAndAskTheLookupOtherwise() async throws {
        XCTAssertNil(SegmentProvider.onlineTimings(nil))
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let found: LibraryItem? = try await rig.store.item(id: id)
        let item = try XCTUnwrap(found)
        let lookup = OnlineSegmentLookup(resolver: IMDbIDResolver(tmdbExternal: nil, wikidata: nil), timings: { _ in nil })
        let timings = try XCTUnwrap(SegmentProvider.onlineTimings(lookup))
        let file = PlaybackLogic.FileIdentity(path: "/movies/Hexfall.mkv", size: 1, duration: 6000)
        let result = await timings(item, file)
        XCTAssertTrue(result.segments.isEmpty, "no IMDb id known: nothing asked, no segment")
        XCTAssertFalse(result.note.isEmpty)
    }
}
