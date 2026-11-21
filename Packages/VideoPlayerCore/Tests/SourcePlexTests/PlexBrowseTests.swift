import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// Stage 4 (docs/PLEX_SOURCE.md section 4; R304): sections, paged lists, shows to episodes, the tree built from the Parts'
/// server paths, ranged reads. Against the fake media server; no network.
final class PlexBrowseTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")
    let base = URL(string: "https://192-168-1-20.machine0001.plex.direct:32400")!

    private func client(_ fake: FakePlexServer, pageSize: Int = 200) -> PlexClient {
        PlexClient(baseURL: base, token: "server-token-placeholder", identity: identity, transport: fake, pageSize: pageSize)
    }

    func testTheSectionsAreTheTopFolders() async throws {
        let fake = try FakePlexServer()
        let top = try await client(fake).list("/")
        XCTAssertEqual(top.map(\.name), ["Movies", "TV Shows"])
        XCTAssertTrue(top.allSatisfy(\.isDirectory))
    }

    func testMoviesAppearUnderTheirServerFileNames() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        // The server's own folders stay: one movie sits in "Test Movie (2020)", the other directly in the section folder.
        let top = try await plex.list("/Movies")
        XCTAssertEqual(top.map(\.name), ["Second Test Movie (2021).mkv", "Test Movie (2020)"])
        XCTAssertEqual(top.map(\.isDirectory), [false, true])
        let inFolder = try await plex.list("/Movies/Test Movie (2020)")
        let movies = top.filter { !$0.isDirectory } + inFolder
        XCTAssertEqual(movies.count, 2)
        XCTAssertTrue(movies.allSatisfy { !$0.isDirectory && $0.serverItemType == .movie })
        let mp4 = try XCTUnwrap(movies.first { $0.name.hasSuffix(".mp4") })
        XCTAssertEqual(mp4.path, "/Movies/Test Movie (2020)/Test Movie (2020).mp4")
        XCTAssertEqual(mp4.contentType, "video/mp4")
        XCTAssertEqual(mp4.serverToken, "part-2001")
        let mkv = try XCTUnwrap(movies.first { $0.name.hasSuffix(".mkv") })
        XCTAssertEqual(mkv.contentType, "video/x-matroska")
    }

    func testShowsAreReadDownToTheirEpisodesWithAllLeaves() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        var episodes: [SourceEntry] = []
        var folders = ["/TV Shows"]
        while let folder = folders.popLast() {
            for entry in try await plex.list(folder) {
                if entry.isDirectory { folders.append(entry.path) } else { episodes.append(entry) }
            }
        }
        XCTAssertEqual(episodes.count, 2)
        XCTAssertTrue(episodes.allSatisfy { $0.serverItemType == .episode })
        XCTAssertTrue(fake.requests.contains { $0.url.path == "/library/metadata/3001/allLeaves" })
    }

    func testEveryListIsPagedWithBothHeaders() async throws {
        let fake = try FakePlexServer()
        fake.lists["/library/sections/1/all"] = (1...45).map { makeMovie($0) }
        let movies = try await client(fake, pageSize: 20).list("/Movies")
        XCTAssertEqual(movies.count, 45, "more than the 20 a list gives without paging headers")
        let pages = fake.requests.filter { $0.url.path == "/library/sections/1/all" }
        XCTAssertEqual(pages.map { $0.headers["X-Plex-Container-Start"] }, ["0", "20", "40"])
        XCTAssertTrue(pages.allSatisfy { $0.headers["X-Plex-Container-Size"] == "20" })
    }

    func testEveryRequestToTheServerIsAReadWithTheTokenInAHeader() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        _ = try await plex.list("/Movies")
        _ = try await plex.read(try await plex.list("/Movies")[0].path, range: ByteRange(offset: 0, length: 10))
        XCTAssertTrue(fake.serverWrites.isEmpty)
        for request in fake.requests where !FakePlexServer.isPlexTV(request.url) {
            XCTAssertEqual(request.method, "GET")
            XCTAssertEqual(request.headers["X-Plex-Token"], "server-token-placeholder")
            XCTAssertFalse(request.url.absoluteString.contains("server-token-placeholder"))
        }
    }

    func testRangedReadsReturnTheRightBytes() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        let path = try await plex.list("/Movies")[0].path
        let data = try await plex.read(path, range: ByteRange(offset: 100, length: 16))
        XCTAssertEqual([UInt8](data), FakePlexServer.bytes(100, 16))
        let request = try XCTUnwrap(fake.requests.last)
        XCTAssertEqual(request.headers["Range"], "bytes=100-115")
        XCTAssertTrue(request.url.path.hasPrefix("/library/parts/"))
    }

    func testAServerWithoutRangesAndAReadPastTheEndAreErrors() async throws {
        let fake = try FakePlexServer()
        let plex = client(fake)
        let path = try await plex.list("/Movies")[0].path
        do { _ = try await plex.read(path, range: ByteRange(offset: 5000, length: 10)); XCTFail("expected 416") }
        catch SourceError.rangeNotSatisfiable {}
        fake.rangesSupported = false
        do { _ = try await plex.read(path, range: ByteRange(offset: 0, length: 10)); XCTFail("expected no ranges") }
        catch SourceError.rangesNotSupported {}
    }

    func testAWrongTokenIsUnauthorized() async throws {
        let fake = try FakePlexServer()
        let plex = PlexClient(baseURL: base, token: "wrong", identity: identity, transport: fake)
        do { try await plex.authenticate(); XCTFail("expected unauthorized") } catch SourceError.unauthorized {}
    }

    func testAServerThatIsOffIsATransportErrorWithoutTheToken() async throws {
        let fake = try FakePlexServer()
        fake.reachableHosts = []
        do {
            _ = try await client(fake).list("/")
            XCTFail("expected a transport error")
        } catch SourceError.transport(let text) {
            XCTAssertFalse(text.contains("server-token-placeholder"))
        }
    }

    func testAnXMLServerIsRefused() async throws {
        let fake = try FakePlexServer()
        fake.answerWithXML = true
        do { _ = try await client(fake).list("/"); XCTFail("expected refusal") } catch PlexError.notJSON {}
    }

    func testWindowsPathsInAnyLetterCaseFindTheirSection() {
        let movie = PlexMetadata(ratingKey: "1", type: "movie", title: "A",
                                 media: [PlexMedia(container: "mkv", parts: [PlexPart(id: "9", key: "/library/parts/9/1/file.mkv",
                                                                                      file: "d:\\media\\movies\\A (2001)\\A (2001).mkv", size: 5, container: nil)])])
        let outside = PlexMetadata(ratingKey: "2", type: "movie", title: "B",
                                   media: [PlexMedia(container: "mkv", parts: [PlexPart(id: "8", key: "/library/parts/8/1/file.mkv",
                                                                                        file: "E:\\Elsewhere\\B.mkv", size: 5, container: nil)])])
        let tree = PlexTree.make(libraries: [PlexLibrary(title: "Movies", roots: [PlexTree.components(of: "D:\\Media\\Movies")])],
                                 items: [movie, outside])
        XCTAssertEqual(tree.children(of: "/Movies/A (2001)").map(\.path), ["/Movies/A (2001)/A (2001).mkv"])
        XCTAssertEqual(tree.skippedParts, 1)
    }
}
