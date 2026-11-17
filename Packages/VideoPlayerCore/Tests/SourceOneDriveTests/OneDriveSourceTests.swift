import XCTest
import VideoPlayerCore
@testable import SourceOneDrive

// Every response comes from OneDriveFixtures: hand-written from Microsoft's documentation,
// NOT recorded from the real service. Nothing here has run against OneDrive.
final class OneDriveSourceTests: XCTestCase {
    private static let graph = "https://graph.microsoft.com/v1.0"

    private func bearer(_ request: HTTPRequest) -> String? { request.headers["Authorization"] }

    // MARK: Registration gate

    func testWithoutClientIDEverythingIsNeedsAppRegistrationAndNothingIsSent() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{}") }
        let (source, _) = Support.make(clientID: nil, transport: transport)
        do { try await source.authenticate(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .needsAppRegistration) }
        do { _ = try await source.list("/"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .needsAppRegistration) }
        do { _ = try await source.beginSignIn(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .needsAppRegistration) }
        XCTAssertEqual(transport.requests.count, 0, "must not contact anything while unregistered")
    }

    func testKindAndCapabilities() {
        let (source, _) = Support.make(transport: ScriptedTransport { _, _ in Support.json("{}") })
        XCTAssertEqual(source.kind, .oneDrive)
        XCTAssertEqual(source.capabilities.authMethods, [.oauthDeviceCode])
        XCTAssertTrue(source.capabilities.byteRanges)
        XCTAssertTrue(source.capabilities.directPlaybackURL)
        XCTAssertTrue(source.capabilities.alwaysEncrypted)
        XCTAssertTrue(source.capabilities.changeSignals.contains(.serverToken))
    }

    func testSignInThroughTheSourceStoresTokens() async throws {
        let clock = TestClock(Support.t0)
        let transport = ScriptedTransport { _, index in
            Support.json(index == 0 ? OneDriveFixtures.deviceCode : OneDriveFixtures.tokens)
        }
        let (source, store) = Support.make(tokens: nil, transport: transport, sleeps: SleepLog(advancing: clock), clock: clock)
        let challenge = try await source.beginSignIn()
        XCTAssertEqual(challenge.userCode, "FJH2K9XQ")
        try await source.completeSignIn(challenge)
        let saved = await store.load()
        XCTAssertEqual(saved?.accessToken, "ACCESS-1")
        await source.signOut()
        let cleared = await store.load()
        XCTAssertNil(cleared)
    }

    // MARK: Tokens

    func testAuthenticateUsesBearerToken() async throws {
        let transport = ScriptedTransport { _, _ in Support.json(OneDriveFixtures.drive) }
        let (source, _) = Support.make(transport: transport)
        try await source.authenticate()
        XCTAssertEqual(transport.requests[0].url.absoluteString, "\(Self.graph)/me/drive")
        XCTAssertEqual(bearer(transport.requests[0]), "Bearer ACCESS-0")
    }

    func testNoTokensIsNotSignedIn() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{}") }
        let (source, _) = Support.make(tokens: nil, transport: transport)
        do { try await source.authenticate(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .notSignedIn) }
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testTokenNearExpiryIsRefreshedBeforeUse() async throws {
        // Expires in 60 s, skew is 120 s, so it counts as expired.
        let transport = ScriptedTransport { request, _ in
            request.url.path.hasSuffix("/token") ? Support.json(OneDriveFixtures.refreshedTokens) : Support.json(OneDriveFixtures.drive)
        }
        let (source, store) = Support.make(tokens: Support.goodTokens(expiresIn: 60), transport: transport)
        try await source.authenticate()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests[0].url.absoluteString.hasSuffix("/consumers/oauth2/v2.0/token"))
        XCTAssertTrue(Support.bodyText(transport.requests[0]).contains("refresh_token=REFRESH-0"))
        XCTAssertEqual(bearer(transport.requests[1]), "Bearer ACCESS-2")
        let saved = await store.load()
        XCTAssertEqual(saved?.refreshToken, "REFRESH-2")
        XCTAssertEqual(saved?.expiresAt, Support.t0.addingTimeInterval(3599))
    }

    func testFreshTokenIsNotRefreshed() async throws {
        let transport = ScriptedTransport { _, _ in Support.json(OneDriveFixtures.drive) }
        let (source, _) = Support.make(tokens: Support.goodTokens(expiresIn: 600), transport: transport)
        try await source.authenticate()
        try await source.authenticate()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests.allSatisfy { $0.url.host == "graph.microsoft.com" })
    }

    func test401RefreshesOnceThenRetries() async throws {
        let transport = ScriptedTransport { request, _ in
            if request.url.path.hasSuffix("/token") { return Support.json(OneDriveFixtures.refreshedTokens) }
            return bearerIs(request, "ACCESS-2") ? Support.json(OneDriveFixtures.drive) : Support.json("{}", status: 401)
        }
        let (source, _) = Support.make(transport: transport)
        try await source.authenticate()
        XCTAssertEqual(transport.requests.count, 3, "401, refresh, retry")
        XCTAssertEqual(bearer(transport.requests[0]), "Bearer ACCESS-0")
        XCTAssertEqual(bearer(transport.requests[2]), "Bearer ACCESS-2")
    }

    func testSecond401IsUnauthorizedAndDoesNotLoop() async throws {
        let transport = ScriptedTransport { request, _ in
            request.url.path.hasSuffix("/token") ? Support.json(OneDriveFixtures.refreshedTokens) : Support.json("{}", status: 401)
        }
        let (source, _) = Support.make(transport: transport)
        do { try await source.authenticate(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testRejectedRefreshTokenClearsStoreAndIsNotSignedIn() async throws {
        let transport = ScriptedTransport { request, _ in
            request.url.path.hasSuffix("/token")
                ? Support.json(OneDriveFixtures.error("invalid_grant"), status: 400) : Support.json("{}", status: 401)
        }
        let (source, store) = Support.make(transport: transport)
        do { try await source.authenticate(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .notSignedIn) }
        let left = await store.load()
        XCTAssertNil(left)
    }

    // MARK: Browsing

    private func browsingTransport() -> ScriptedTransport {
        ScriptedTransport { request, _ in
            switch request.url.absoluteString {
            case "\(Self.graph)/me/drive/root/children": return Support.json(OneDriveFixtures.rootChildrenPage1)
            case "\(Self.graph)/me/drive/root/children?$skiptoken=PAGE2": return Support.json(OneDriveFixtures.rootChildrenPage2)
            case "\(Self.graph)/me/drive/root:/Movies": return Support.json(OneDriveFixtures.moviesFolderItem)
            case "\(Self.graph)/me/drive/items/F-MOVIES/children": return Support.json(OneDriveFixtures.moviesChildren)
            case "\(Self.graph)/me/drive/root": return Support.json(OneDriveFixtures.rootItem)
            default: return Support.json("{}", status: 404)
            }
        }
    }

    func testListRootFollowsNextLinkAndMapsFacets() async throws {
        let transport = browsingTransport()
        let (source, _) = Support.make(transport: transport)
        let entries = try await source.list("/")

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertTrue(transport.requests.allSatisfy { bearer($0) == "Bearer ACCESS-0" })
        XCTAssertEqual(entries.map(\.name), ["Movies", "The Quiet Harbor (2019).mkv"])

        let folder = entries[0]
        XCTAssertTrue(folder.isDirectory)
        XCTAssertEqual(folder.path, "/Movies")
        XCTAssertNil(folder.size, "folders carry no size")
        XCTAssertNil(folder.contentType)
        XCTAssertEqual(folder.serverToken, "\"c:{M},3\"")

        let file = entries[1]
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.path, "/The Quiet Harbor (2019).mkv")
        XCTAssertEqual(file.size, 123_456_789)
        XCTAssertEqual(file.contentType, "video/x-matroska")
        XCTAssertEqual(file.etag, "\"{A},5\"")
        XCTAssertEqual(file.serverToken, "\"c:{A},7\"", "cTag is the content-change token")
        let modified = try XCTUnwrap(file.modified)
        XCTAssertEqual(modified.timeIntervalSince1970, 1_709_374_530.123, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(folder.modified).timeIntervalSince1970, 1_709_373_600, accuracy: 0.01)
    }

    func testListSubfolderResolvesPathToIDOnceAndCaches() async throws {
        let transport = browsingTransport()
        let (source, _) = Support.make(transport: transport)
        let first = try await source.list("/Movies/")
        XCTAssertEqual(first.map(\.path), ["/Movies/Episode 1.mp4", "/Movies/Season 1"])
        XCTAssertEqual(transport.requests.map(\.url.absoluteString), [
            "\(Self.graph)/me/drive/root:/Movies",
            "\(Self.graph)/me/drive/items/F-MOVIES/children"
        ])
        _ = try await source.list("Movies")
        XCTAssertEqual(transport.requests.count, 3, "second listing reuses the cached id")
    }

    func testInfoUsesPathAddressingWithEncodedSegments() async throws {
        let transport = ScriptedTransport { _, _ in Support.json(OneDriveFixtures.fileItem(downloadURL: "https://download.example.test/x")) }
        let (source, _) = Support.make(transport: transport)
        let entry = try await source.info("/Movies/My Film #1 (2020).mkv")
        XCTAssertEqual(transport.requests[0].url.absoluteString,
                       "\(Self.graph)/me/drive/root:/Movies/My%20Film%20%231%20%282020%29.mkv")
        XCTAssertEqual(entry.path, "/Movies/My Film #1 (2020).mkv")
        XCTAssertEqual(entry.size, 123_456_789)
        XCTAssertEqual(entry.version.serverToken, "\"c:{A},7\"")
        XCTAssertEqual(entry.version.etag, "\"{A},5\"")
    }

    func testInfoOfRootIsAFolder() async throws {
        let transport = browsingTransport()
        let (source, _) = Support.make(transport: transport)
        let root = try await source.info("/")
        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.path, "/")
        XCTAssertEqual(root.name, "/")
    }

    func testMissingItemIsNotFoundAndForbiddenIsForbidden() async throws {
        let transport = ScriptedTransport { request, _ in
            request.url.path.contains("Secret") ? Support.json("{}", status: 403) : Support.json("{}", status: 404)
        }
        let (source, _) = Support.make(transport: transport)
        do { _ = try await source.info("/nope"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
        do { _ = try await source.info("/Secret"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SourceError, .forbidden) }
    }

    func testMalformedListingIsMalformedResponse() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("not json") }
        let (source, _) = Support.make(transport: transport)
        do { _ = try await source.list("/"); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? SourceError, .malformedResponse) }
    }

    // MARK: Throttling

    func testRetryAfterIsHonouredThenSucceeds() async throws {
        let transport = ScriptedTransport { _, index in
            index < 2 ? Support.json("{}", status: 429, headers: ["Retry-After": "7"]) : Support.json(OneDriveFixtures.drive)
        }
        let sleeps = SleepLog()
        let (source, _) = Support.make(transport: transport, sleeps: sleeps)
        try await source.authenticate()
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(sleeps.values, [7, 7])
    }

    func test503WithoutRetryAfterBacksOffAndGivesUpWithTypedError() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{}", status: 503) }
        let sleeps = SleepLog()
        let (source, _) = Support.make(transport: transport, sleeps: sleeps, maxRetries: 3)
        do { try await source.authenticate(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .throttled(retryAfter: nil)) }
        XCTAssertEqual(transport.requests.count, 4, "first try plus three retries")
        XCTAssertEqual(sleeps.values, [1, 2, 4])
    }

    func testThrottledErrorCarriesRetryAfter() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{}", status: 429, headers: ["retry-after": "30"]) }
        let (source, _) = Support.make(transport: transport, maxRetries: 0)
        do { try await source.authenticate(); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? OneDriveError, .throttled(retryAfter: 30)) }
    }

    // MARK: Reads and playback

    private static let filePath = "/Movies/film.mkv"
    private static let fileMeta = "\(graph)/me/drive/root:/Movies/film.mkv"

    func testRangedReadUsesDownloadURLWithoutAuthorization() async throws {
        let payload = Data([1, 2, 3, 4, 5])
        let transport = ScriptedTransport { request, _ in
            if request.url.absoluteString == Self.fileMeta {
                return Support.json(OneDriveFixtures.fileItem(downloadURL: "https://download.example.test/film?tempauth=T1"))
            }
            return HTTPResponse(statusCode: 206, headers: ["Content-Range": "bytes 100-104/123456789"], body: payload)
        }
        let (source, _) = Support.make(transport: transport)
        let data = try await source.read(Self.filePath, range: ByteRange(offset: 100, length: 5))
        XCTAssertEqual(data, payload)

        let download = transport.requests[1]
        XCTAssertEqual(download.url.absoluteString, "https://download.example.test/film?tempauth=T1")
        XCTAssertEqual(download.headers["Range"], "bytes=100-104")
        XCTAssertNil(download.headers["Authorization"], "the download URL is pre-authenticated")
        XCTAssertEqual(bearer(transport.requests[0]), "Bearer ACCESS-0")

        // The URL is cached: a second read does not ask Graph again.
        _ = try await source.read(Self.filePath, range: ByteRange(offset: 0, length: 5))
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testReadOfZeroLengthSendsNothing() async throws {
        let transport = ScriptedTransport { _, _ in Support.json("{}") }
        let (source, _) = Support.make(transport: transport)
        let data = try await source.read(Self.filePath, range: ByteRange(offset: 0, length: 0))
        XCTAssertEqual(data.count, 0)
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testReadWhenServerIgnoresRangeAndWhenUnsatisfiable() async throws {
        for (status, expected) in [(200, SourceError.rangesNotSupported), (416, SourceError.rangeNotSatisfiable)] {
            let transport = ScriptedTransport { request, _ in
                request.url.host == "graph.microsoft.com"
                    ? Support.json(OneDriveFixtures.fileItem(downloadURL: "https://download.example.test/f"))
                    : HTTPResponse(statusCode: status, body: Data([9]))
            }
            let (source, _) = Support.make(transport: transport)
            do { _ = try await source.read(Self.filePath, range: ByteRange(offset: 0, length: 4)); XCTFail("\(status)") }
            catch { XCTAssertEqual(error as? SourceError, expected, "\(status)") }
        }
    }

    func testExpiredDownloadURLIsRefetchedOnceAndRetried() async throws {
        // First metadata call must hand out the OLD url; use a counter to switch.
        let counter = Counter()
        let scripted = ScriptedTransport { request, _ in
            if request.url.absoluteString == Self.fileMeta {
                let n = counter.next()
                return Support.json(OneDriveFixtures.fileItem(downloadURL: n == 0 ? "https://download.example.test/old" : "https://download.example.test/new"))
            }
            return request.url.absoluteString.hasSuffix("/new") ? HTTPResponse(statusCode: 206, body: Data([7, 7])) : HTTPResponse(statusCode: 403)
        }
        let (source, _) = Support.make(transport: scripted)
        let data = try await source.read(Self.filePath, range: ByteRange(offset: 0, length: 2))
        XCTAssertEqual(data, Data([7, 7]))
        XCTAssertEqual(scripted.requests.map(\.url.absoluteString), [
            Self.fileMeta, "https://download.example.test/old", Self.fileMeta, "https://download.example.test/new"
        ])
    }

    func testDownloadURLOlderThanItsLifetimeIsRefetched() async throws {
        let clock = TestClock(Support.t0)
        let transport = ScriptedTransport { request, _ in
            request.url.host == "graph.microsoft.com"
                ? Support.json(OneDriveFixtures.fileItem(downloadURL: "https://download.example.test/f"))
                : HTTPResponse(statusCode: 206, body: Data([1]))
        }
        let (source, _) = Support.make(tokens: Support.goodTokens(expiresIn: 100_000), transport: transport, clock: clock)
        _ = try await source.read(Self.filePath, range: ByteRange(offset: 0, length: 1))
        clock.advance(601)
        _ = try await source.read(Self.filePath, range: ByteRange(offset: 0, length: 1))
        XCTAssertEqual(transport.requests.filter { $0.url.host == "graph.microsoft.com" }.count, 2)
    }

    func testPlaybackAccessIsThePreAuthenticatedURLAndRefetchesEachTime() async throws {
        let counter = Counter()
        let transport = ScriptedTransport { _, _ in
            let n = counter.next()
            return Support.json(OneDriveFixtures.fileItem(downloadURL: "https://download.example.test/play\(n)"))
        }
        let (source, _) = Support.make(transport: transport)
        let first = try await source.playbackAccess(for: Self.filePath)
        XCTAssertEqual(first, .url(URL(string: "https://download.example.test/play0")!, headers: [:]))
        let second = try await source.playbackAccess(for: Self.filePath)
        XCTAssertEqual(second, .url(URL(string: "https://download.example.test/play1")!, headers: [:]))
    }

    func testPlaybackAccessForAFolderIsUnsupported() async throws {
        let transport = ScriptedTransport { _, _ in Support.json(OneDriveFixtures.moviesFolderItem) }
        let (source, _) = Support.make(transport: transport)
        do { _ = try await source.playbackAccess(for: "/Movies"); XCTFail("should throw") }
        catch {
            guard case SourceError.unsupported = error else { return XCTFail("got \(error)") }
        }
    }

    func testListingPrimesTheDownloadCache() async throws {
        let transport = ScriptedTransport { request, _ in
            switch request.url.absoluteString {
            case "\(Self.graph)/me/drive/root/children": return Support.json(OneDriveFixtures.rootChildrenPage2)
            default: return HTTPResponse(statusCode: 206, body: Data([4, 2]))
            }
        }
        let (source, _) = Support.make(transport: transport)
        _ = try await source.list("/")
        let data = try await source.read("/The Quiet Harbor (2019).mkv", range: ByteRange(offset: 0, length: 2))
        XCTAssertEqual(data, Data([4, 2]))
        XCTAssertEqual(transport.requests.count, 2, "listing, then the download; no extra metadata call")
        XCTAssertEqual(transport.requests[1].url.absoluteString, "https://download.example.test/film?tempauth=T1")
    }
}

private func bearerIs(_ request: HTTPRequest, _ token: String) -> Bool {
    request.headers["Authorization"] == "Bearer " + token
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; defer { value += 1 }; return value }
}
