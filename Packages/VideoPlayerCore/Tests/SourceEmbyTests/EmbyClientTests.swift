import XCTest
import VideoPlayerCore
@testable import SourceEmby

/// Unit tests against recorded responses (no network). The live tests are in EmbyIntegrationTests.
final class EmbyClientTests: XCTestCase {
    private let base = URL(string: "http://server.test:8096")!

    private func client(
        _ server: FakeEmbyServer, credentials: EmbyCredentials = .token("good-token"),
        pageSize: Int = 500, scan: EmbyScanPolicy = .immediate, base: URL? = nil
    ) -> EmbyClient {
        EmbyClient(baseURL: base ?? self.base, credentials: credentials, transport: server, pageSize: pageSize, scanPolicy: scan)
    }

    // MARK: Tree from item paths

    func testBuildsTheFolderTreeFromRecordedItemPaths() async throws {
        let server = try FakeEmbyServer()
        let source = client(server)
        try await source.authenticate()
        let root = try await source.list("/")
        XCTAssertEqual(root.map(\.name), ["VPTest"])
        XCTAssertTrue(root[0].isDirectory)
        let library = try await source.list("/VPTest")
        // The recorded Emby server leaves out "big/Large Sample.mkv": Emby skips files named "sample".
        XCTAssertEqual(library.map(\.name), ["Movies", "Odd Names", "Shows"])
        XCTAssertTrue(library.allSatisfy(\.isDirectory))
        let episodes = try await source.list("/VPTest/Shows/Test Show (2019)/Season 1")
        XCTAssertEqual(episodes.map(\.name), ["Test Show - S01E01 - Pilot.mkv", "Test Show - S01E02.mkv"])
        XCTAssertTrue(episodes.allSatisfy { !$0.isDirectory })
    }

    func testNamesComeFromThePathNotFromTheServerTitle() async throws {
        let source = client(try FakeEmbyServer())
        let movies = try await source.list("/VPTest/Movies")
        // The recorded server titled this item "Movies"; we show the file name.
        XCTAssertEqual(movies.map(\.name), ["Test Movie (2020).mkv"])
        let entry = movies[0]
        XCTAssertEqual(entry.path, "/VPTest/Movies/Test Movie (2020).mkv")
        XCTAssertNil(entry.size, "the recorded Emby server lists size 0 (not measured), which is treated as unknown")
        XCTAssertEqual(entry.contentType, "video/x-matroska")
        XCTAssertNotNil(entry.serverToken)
    }

    func testSpecialCharactersSurvive() async throws {
        let source = client(try FakeEmbyServer())
        let odd = try await source.list("/VPTest/Odd Names")
        XCTAssertEqual(odd.map(\.name), ["Caf\u{00E9} \u{2013} 100% [test] #1.mp4"])
        let again = try await source.info(odd[0].path)
        XCTAssertEqual(again.path, odd[0].path)
        XCTAssertEqual(again.name, odd[0].name)
    }

    func testInfoForFolderRootAndMissingPath() async throws {
        let source = client(try FakeEmbyServer())
        let folder = try await source.info("/VPTest/Shows")
        XCTAssertTrue(folder.isDirectory)
        XCTAssertEqual(folder.name, "Shows")
        let root = try await source.info("/")
        XCTAssertTrue(root.isDirectory)
        do { _ = try await source.info("/VPTest/nope.mkv"); XCTFail("expected notFound") } catch { XCTAssertEqual(error as? SourceError, .notFound) }
        do { _ = try await source.list("/nope"); XCTFail("expected notFound") } catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testSeveralVersionsOfOneMovieAreSeveralFiles() async throws {
        let item = makeItem(id: "m1", sources: [
            (id: "s1", path: "/media/Movies/Film/Film - 1080p.mkv", size: 100),
            (id: "s2", path: "/media/Movies/Film/Film - 4K.mkv", size: 400),
        ])
        let server = try FakeEmbyServer(items: [item], folders: folders([("Movies", ["/media/Movies"])]))
        let source = client(server)
        let files = try await source.list("/Movies/Film")
        XCTAssertEqual(files.map(\.name), ["Film - 1080p.mkv", "Film - 4K.mkv"])
        XCTAssertEqual(files.map(\.size), [100, 400])
        _ = try await source.read("/Movies/Film/Film - 4K.mkv", range: ByteRange(offset: 0, length: 4))
        let stream = try XCTUnwrap(server.requests.last)
        XCTAssertTrue(stream.url.path.hasSuffix("/Videos/m1/stream"))
        XCTAssertTrue(stream.url.query?.contains("mediaSourceId=s2") ?? false, "\(stream.url)")
    }

    func testWindowsServerPathsAndLetterCase() async throws {
        let item = makeItem(id: "w1", sources: [(id: "w1", path: "d:\\media\\TV\\Show\\ep1.mkv", size: 10)])
        let server = try FakeEmbyServer(items: [item], folders: folders([("TV", ["D:\\Media\\TV"])]))
        let files = try await client(server).list("/TV/Show")
        XCTAssertEqual(files.map(\.name), ["ep1.mkv"])
    }

    func testFilesOutsideEveryLibraryFolderAreLeftOut() async throws {
        let inside = makeItem(id: "a", sources: [(id: "a", path: "/media/Movies/a.mkv", size: 1)])
        let outside = makeItem(id: "b", sources: [(id: "b", path: "/elsewhere/b.mkv", size: 1)])
        let server = try FakeEmbyServer(items: [inside, outside], folders: folders([("Movies", ["/media/Movies"])]))
        let source = client(server)
        let movies = try await source.list("/Movies")
        let top = try await source.list("/")
        XCTAssertEqual(movies.map(\.name), ["a.mkv"])
        XCTAssertEqual(top.map(\.name), ["Movies"])
    }

    func testTwoLibrariesWithOneNameStayApart() async throws {
        let a = makeItem(id: "a", sources: [(id: "a", path: "/one/a.mkv", size: 1)])
        let b = makeItem(id: "b", sources: [(id: "b", path: "/two/b.mkv", size: 1)])
        let server = try FakeEmbyServer(items: [a, b], folders: folders([("Films", ["/one"]), ("films", ["/two"])]))
        let top = try await client(server).list("/")
        XCTAssertEqual(top.map(\.name), ["Films", "films (2)"])
    }

    func testNonAdministratorFallsBackToOneLibraryAroundAllFiles() async throws {
        let a = makeItem(id: "a", sources: [(id: "a", path: "/media/Movies/a.mkv", size: 1)])
        let b = makeItem(id: "b", sources: [(id: "b", path: "/media/Shows/S/b.mkv", size: 1)])
        let server = try FakeEmbyServer(items: [a, b])
        server.foldersStatus = 403
        let source = client(server)
        let top = try await source.list("/")
        let inner = try await source.list("/Library")
        XCTAssertEqual(top.map(\.name), ["Library"])
        XCTAssertEqual(inner.map(\.name), ["Movies", "Shows"])
        let usedFolders = await source.usedLibraryFolders
        XCTAssertFalse(usedFolders)
    }

    // MARK: Scan polling and paging

    func testWaitsUntilTheItemCountStopsChanging() async throws {
        let server = try FakeEmbyServer()
        server.countSequence = [1, 3, 5, 5, 5]
        let source = client(server, scan: EmbyScanPolicy(pollInterval: 0, stableChecks: 3, timeout: 5))
        _ = try await source.list("/")
        let counts = server.requests.filter { $0.url.query?.contains("Limit=0") ?? false }
        XCTAssertEqual(counts.count, 5, "three equal counts in a row end the wait")
        let firstListing = try XCTUnwrap(server.requests.firstIndex { $0.url.query?.contains("Fields=") ?? false })
        let lastCount = try XCTUnwrap(server.requests.lastIndex { $0.url.query?.contains("Limit=0") ?? false })
        XCTAssertLessThan(lastCount, firstListing, "the item list is read only after the scan settled")
        XCTAssertTrue(server.requests[firstListing].url.query?.contains("Fields=Path%2CMediaSources%2CEtag") ?? false, "Emby only sends Etag when asked")
        let settled = await source.scanSettled
        XCTAssertTrue(settled)
    }

    func testGivesUpWaitingAfterTheTimeoutAndSaysSo() async throws {
        let server = try FakeEmbyServer()
        server.countSequence = Array(1...1000)
        let source = client(server, scan: EmbyScanPolicy(pollInterval: 0, stableChecks: 3, timeout: 0))
        let top = try await source.list("/")
        XCTAssertFalse(top.isEmpty)
        let settled = await source.scanSettled
        XCTAssertFalse(settled)
    }

    func testReadsAllPagesOfTheItemList() async throws {
        let server = try FakeEmbyServer()
        let source = client(server, pageSize: 2)
        let files = try await source.walk("/").filter { !$0.isDirectory }
        XCTAssertEqual(files.count, 4)
        let starts = server.requests.compactMap { request -> String? in
            guard let query = request.url.query, query.contains("Fields=") else { return nil }
            return query.components(separatedBy: "&").first { $0.hasPrefix("StartIndex=") }
        }
        XCTAssertEqual(starts, ["StartIndex=0", "StartIndex=2"])
    }

    // MARK: Reads and playback

    func testRangedReadAsksForTheFileAsItIsAndSendsTheToken() async throws {
        let server = try FakeEmbyServer()
        let source = client(server)
        let path = "/VPTest/Movies/Test Movie (2020).mkv"
        let data = try await source.read(path, range: ByteRange(offset: 100, length: 50))
        XCTAssertEqual(Array(data), FakeEmbyServer.bytes(100, 50))
        let request = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(request.headers["Range"], "bytes=100-149")
        XCTAssertEqual(request.url.path, "/emby/Videos/9/stream")
        XCTAssertTrue(request.url.query?.contains("static=true") ?? false)
        XCTAssertTrue(request.url.query?.contains("mediaSourceId=mediasource_9") ?? false)
        XCTAssertEqual(request.headers["X-Emby-Token"], "good-token")
    }

    func testReadAtTheEndReturnsOnlyWhatExistsAndPastTheEndFails() async throws {
        let server = try FakeEmbyServer()
        let source = client(server)
        let path = "/VPTest/Movies/Test Movie (2020).mkv"
        let tail = try await source.read(path, range: ByteRange(offset: 990, length: 100))
        XCTAssertEqual(tail.count, 10)
        do { _ = try await source.read(path, range: ByteRange(offset: 5000, length: 10)); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable) }
        let none = try await source.read(path, range: ByteRange(offset: 0, length: 0))
        XCTAssertEqual(none, Data())
    }

    func testServerThatIgnoresRangesIsReported() async throws {
        let ignoring = RangeIgnoringTransport(wrapping: try FakeEmbyServer())
        let source = EmbyClient(baseURL: base, credentials: .token("good-token"), transport: ignoring, scanPolicy: .immediate)
        do { _ = try await source.read("/VPTest/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 5, length: 5)); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .rangesNotSupported) }
    }

    func testReadingAFolderIsRefused() async throws {
        let source = client(try FakeEmbyServer())
        do { _ = try await source.read("/VPTest/Movies", range: ByteRange(offset: 0, length: 4)); XCTFail("expected error") }
        catch { guard case .unsupported = error as? SourceError else { return XCTFail("\(error)") } }
        do { _ = try await source.read("/VPTest/none.mkv", range: ByteRange(offset: 0, length: 4)); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testPlaybackAccessIsADirectPlayURLWithTheTokenInAHeader() async throws {
        let source = client(try FakeEmbyServer())
        let access = try await source.playbackAccess(for: "/VPTest/Movies/Test Movie (2020).mkv")
        guard case .url(let url, let headers) = access else { return XCTFail("expected a URL") }
        let query = url.query ?? ""
        XCTAssertTrue(query.contains("static=true"))
        XCTAssertFalse(query.lowercased().contains("transcod"))
        XCTAssertFalse(url.absoluteString.contains("good-token"), "the token must not be in the URL")
        XCTAssertEqual(headers, ["X-Emby-Token": "good-token"])
        XCTAssertEqual(url.path, "/emby/Videos/9/stream")
    }

    func testCapabilities() async throws {
        let source = client(try FakeEmbyServer())
        XCTAssertEqual(source.kind, .emby)
        XCTAssertTrue(source.capabilities.byteRanges)
        XCTAssertTrue(source.capabilities.directPlaybackURL)
        XCTAssertEqual(source.capabilities.authMethods, [.usernamePassword, .token])
    }

    func testPathPrefixOfTheServerAddressIsKept() async throws {
        // The address may or may not end with /emby; the API path is /emby/... either way, never /emby/emby.
        for text in ["http://server.test/emby/", "http://server.test/emby", "http://server.test"] {
            let server = try FakeEmbyServer()
            _ = try await client(server, base: URL(string: text)!).list("/")
            XCTAssertTrue(server.requests.allSatisfy { $0.url.path.hasPrefix("/emby/") && !$0.url.path.hasPrefix("/emby/emby") },
                          "\(text): \(server.requests.map(\.url))")
        }
        let server = try FakeEmbyServer()
        _ = try await client(server, base: URL(string: "http://server.test/proxy/emby")!).list("/")
        XCTAssertTrue(server.requests.allSatisfy { $0.url.path.hasPrefix("/proxy/emby/") })
    }

    func testSizeTheServerHasNotMeasuredIsReadFromAOneByteRangedRequest() async throws {
        let server = try FakeEmbyServer()
        let source = client(server)
        let path = "/VPTest/Movies/Test Movie (2020).mkv"
        let listed = try await source.list("/VPTest/Movies")
        XCTAssertNil(listed[0].size)
        let entry = try await source.info(path)
        XCTAssertEqual(entry.size, FakeEmbyServer.fileSize)
        XCTAssertEqual(server.requests.last?.headers["Range"], "bytes=0-0")
        let count = server.requests.count
        let again = try await source.list("/VPTest/Movies")
        XCTAssertEqual(again[0].size, FakeEmbyServer.fileSize, "remembered")
        _ = try await source.info(path)
        XCTAssertEqual(server.requests.count, count, "no second request for the same size")
    }

    // MARK: Authentication

    func testPasswordSignInSendsNoTokenAndUsesTheReturnedOne() async throws {
        let server = try FakeEmbyServer()
        let source = client(server, credentials: .password(username: "tester", password: "testpass-local"))
        try await source.authenticate()
        let login = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(login.method, "POST")
        XCTAssertTrue(login.url.path.hasSuffix("/Users/AuthenticateByName"))
        XCTAssertNil(login.headers["X-Emby-Token"])
        XCTAssertTrue(login.headers["X-Emby-Authorization"]?.hasPrefix("Emby Client=") ?? false)
        XCTAssertTrue(login.headers["X-Emby-Authorization"]?.contains("DeviceId=\"VideoPlayerCore\"") ?? false)
        _ = try await source.list("/")
        XCTAssertEqual(server.requests.last?.headers["X-Emby-Token"], "token-1")
    }

    func testWrongPasswordIsUnauthorized() async throws {
        let source = client(try FakeEmbyServer(), credentials: .password(username: "tester", password: "wrong"))
        do { try await source.authenticate(); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        do { _ = try await source.list("/"); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testWrongTokenIsUnauthorizedAndNeverSignsIn() async throws {
        let server = try FakeEmbyServer()
        let source = client(server, credentials: .token("not-the-token"))
        do { try await source.authenticate(); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        XCTAssertEqual(server.logins, 0)
    }

    func testSignsInAgainOnceWhenTheTokenStopsWorking() async throws {
        let server = try FakeEmbyServer()
        let source = client(server, credentials: .password(username: "tester", password: "testpass-local"))
        try await source.authenticate()
        let path = "/VPTest/Movies/Test Movie (2020).mkv"
        _ = try await source.read(path, range: ByteRange(offset: 0, length: 4))
        server.revokeToken()
        let data = try await source.read(path, range: ByteRange(offset: 0, length: 4))
        XCTAssertEqual(Array(data), FakeEmbyServer.bytes(0, 4))
        XCTAssertEqual(server.logins, 2, "one sign-in at the start, one after the 401")
    }

    func testAPastedTokenThatStopsWorkingIsNotRetried() async throws {
        let server = try FakeEmbyServer()
        let source = client(server)
        _ = try await source.list("/")
        server.revokeToken()
        do { _ = try await source.read("/VPTest/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 0, length: 4)); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        XCTAssertEqual(server.logins, 0)
    }

    func testNoSecretsInFixtures() throws {
        for name in ["authenticate.json", "items.json", "virtual-folders.json", "system-info-public.json", "items-count.json"] {
            let text = String(decoding: try Fixture.data(name), as: UTF8.self)
            XCTAssertFalse(text.contains("/home/"), name)
            if name == "authenticate.json" { XCTAssertTrue(text.contains("REDACTED-TOKEN")) }
        }
    }
}

/// Wraps a transport and answers a ranged GET with the whole file (status 200).
struct RangeIgnoringTransport: HTTPTransport {
    let wrapping: HTTPTransport
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var plain = request
        plain.headers["Range"] = nil
        return try await wrapping.send(plain)
    }
}
