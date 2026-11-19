import XCTest
import VideoPlayerCore
@testable import SourceJellyfin

/// Runs against a real Jellyfin server started by `scripts/test-mediaservers.sh start jellyfin`.
/// Needs VP_JELLYFIN_URL, VP_JELLYFIN_TOKEN, VP_TEST_USER and VP_TEST_PASS
/// (`eval "$(bash scripts/test-mediaservers.sh env jellyfin)"`). Without them every test here is
/// reported as skipped, never as passed.
final class JellyfinIntegrationTests: XCTestCase {
    private func env(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("\(name) not set; see scripts/test-mediaservers.sh env jellyfin")
        }
        return value
    }

    private func serverURL() throws -> URL {
        let text = try env("VP_JELLYFIN_URL")
        return try XCTUnwrap(URL(string: text))
    }

    private func tokenClient(token: String? = nil, transport: HTTPTransport = URLSessionTransport()) throws -> JellyfinClient {
        let url = try serverURL()
        let value = try token ?? env("VP_JELLYFIN_TOKEN")
        return JellyfinClient(baseURL: url, credentials: .token(value), transport: transport, deviceID: "vp-live-token")
    }

    private func passwordClient(
        password: String? = nil, deviceID: String = "vp-live-password", transport: HTTPTransport = URLSessionTransport()
    ) throws -> JellyfinClient {
        let url = try serverURL()
        let user = try env("VP_TEST_USER")
        let pass = try password ?? env("VP_TEST_PASS")
        return JellyfinClient(
            baseURL: url, credentials: .password(username: user, password: pass), transport: transport, deviceID: deviceID)
    }

    /// Test files hold byte (offset * 7 + 3) mod 251 at every offset.
    private func expected(offset: Int64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(((offset + Int64($0)) * 7 + 3) % 251) }
    }

    private let movie = "/VPTest/Movies/Test Movie (2020).mkv"

    func testBrowsesTheLibraryAsAFileTree() async throws {
        let source = try tokenClient()
        try await source.authenticate()
        let root = try await source.list("/")
        XCTAssertEqual(root.map(\.name), ["VPTest"])
        let library = try await source.list("/VPTest")
        XCTAssertEqual(library.map(\.name), ["big", "Movies", "Odd Names", "Shows"])
        let episodes = try await source.list("/VPTest/Shows/Test Show (2019)/Season 1")
        XCTAssertEqual(episodes.map(\.name), ["Test Show - S01E01 - Pilot.mkv", "Test Show - S01E02.mkv"])
        let settled = await source.scanSettled
        XCTAssertTrue(settled, "the item count must have stopped changing")
        let usedFolders = await source.usedLibraryFolders
        XCTAssertTrue(usedFolders)
    }

    func testEntriesCarrySizeAndVersionToken() async throws {
        let source = try tokenClient()
        let entry = try await source.info(movie)
        XCTAssertEqual(entry.size, 3_145_728)
        XCTAssertFalse(entry.isDirectory)
        XCTAssertEqual(entry.name, "Test Movie (2020).mkv")
        XCTAssertNotNil(entry.serverToken)
        let big = try await source.info("/VPTest/big/Large Sample.mkv")
        XCTAssertEqual(big.size, 41_943_040)
    }

    func testSpecialCharactersInNamesSurviveARoundTrip() async throws {
        let source = try tokenClient()
        let odd = try await source.list("/VPTest/Odd Names")
        let entry = try XCTUnwrap(odd.first)
        XCTAssertEqual(entry.name, "Caf\u{00E9} \u{2013} 100% [test] #1.mp4")
        XCTAssertEqual(entry.size, 4096)
        let data = try await source.read(entry.path, range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(Array(data), expected(offset: 0, count: 16))
    }

    func testRangedReadsAtArbitraryOffsetsHoldTheExpectedBytes() async throws {
        let source = try tokenClient()
        for (offset, length) in [(0, 64), (1_000, 500), (1_048_576, 4_096), (3_145_728 - 100, 100)] as [(Int64, Int)] {
            let data = try await source.read(movie, range: ByteRange(offset: offset, length: Int64(length)))
            XCTAssertEqual(Array(data), expected(offset: offset, count: length), "offset \(offset)")
        }
        let tail = try await source.read(movie, range: ByteRange(offset: 3_145_728 - 10, length: 100))
        XCTAssertEqual(tail.count, 10)
        let big = try await source.read("/VPTest/big/Large Sample.mkv", range: ByteRange(offset: 40_000_000, length: 2_000))
        XCTAssertEqual(Array(big), expected(offset: 40_000_000, count: 2_000))
    }

    func testSeekPastTheEndIsRangeNotSatisfiable() async throws {
        let source = try tokenClient()
        do {
            _ = try await source.read(movie, range: ByteRange(offset: 10_000_000, length: 10))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable)
        }
    }

    func testPlaybackAccessGivesADirectPlayURLThatPlaysWithTheTokenHeader() async throws {
        let source = try tokenClient()
        let access = try await source.playbackAccess(for: movie)
        guard case .url(let url, let headers) = access else { return XCTFail("expected a URL") }
        XCTAssertTrue((url.query ?? "").contains("static=true"))
        XCTAssertFalse(url.absoluteString.contains(try env("VP_JELLYFIN_TOKEN")), "the token must not be in the URL")

        let transport = URLSessionTransport()
        var request = HTTPRequest(url: url, method: "GET", headers: headers)
        request.headers["Range"] = "bytes=1000-1015"
        let response = try await transport.send(request)
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(Array(response.body), expected(offset: 1000, count: 16))
        XCTAssertEqual(response.header("content-range"), "bytes 1000-1015/3145728")
        // Observed: this Jellyfin version also serves a static stream without a token, so the
        // header is what we send, not something the server enforces on this endpoint.
    }

    func testWrongTokenIsRefused() async throws {
        let source = try tokenClient(token: "0123456789abcdef0123456789abcdef")
        do { try await source.authenticate(); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        do { _ = try await source.list("/"); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        do {
            _ = try await source.read(movie, range: ByteRange(offset: 0, length: 4))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SourceError, .unauthorized)
        }
    }

    func testWrongPasswordIsRefused() async throws {
        let source = try passwordClient(password: "definitely-not-the-password")
        do { try await source.authenticate(); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        do { _ = try await source.list("/"); XCTFail("expected error") } catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testPasswordSignInBrowsesAndReads() async throws {
        let source = try passwordClient()
        try await source.authenticate()
        let names = try await source.list("/VPTest").map(\.name)
        XCTAssertEqual(names, ["big", "Movies", "Odd Names", "Shows"])
        let data = try await source.read(movie, range: ByteRange(offset: 500, length: 32))
        XCTAssertEqual(Array(data), expected(offset: 500, count: 32))
    }

    /// The real server refuses a token it does not know (401); the client must sign in again and go on.
    func testReconnectsWhenTheServerRefusesTheToken() async throws {
        let transport = TokenTamperingTransport()
        let source = try passwordClient(deviceID: "vp-live-reconnect", transport: transport)
        try await source.authenticate()
        _ = try await source.list("/VPTest")
        XCTAssertEqual(transport.logins, 1)
        transport.breakTokenOnNextRequest()
        try await source.refresh()   // the next request carries a bad token
        let data = try await source.read(movie, range: ByteRange(offset: 0, length: 8))
        XCTAssertEqual(Array(data), expected(offset: 0, count: 8))
        XCTAssertEqual(transport.logins, 2, "signed in again once")
        XCTAssertTrue(transport.statuses.contains(401), "the server must have refused the bad token: \(transport.statuses)")
    }

    /// With a pasted token there is nothing to sign in with, so a refused token is reported.
    func testPastedTokenThatTheServerRefusesIsReportedNotRetried() async throws {
        let transport = TokenTamperingTransport()
        let source = try tokenClient(transport: transport)
        _ = try await source.list("/VPTest")
        transport.breakTokenOnNextRequest()
        do {
            try await source.refresh()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SourceError, .unauthorized)
        }
        XCTAssertEqual(transport.logins, 0)
    }
}

/// Passes requests on to the real server, remembers every status code and sign-in, and can
/// replace the token of the next request with one the server does not know.
final class TokenTamperingTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Int] = []
    private var loginCount = 0
    private var breakNext = false
    private let inner = URLSessionTransport()

    var statuses: [Int] { lock.lock(); defer { lock.unlock() }; return seen }
    var logins: Int { lock.lock(); defer { lock.unlock() }; return loginCount }
    func breakTokenOnNextRequest() { lock.lock(); breakNext = true; lock.unlock() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        // #23 D: withLock, not lock()/unlock(): NSLock.lock() is unavailable from async contexts (a warning in Swift 5 mode).
        var sent = request
        lock.withLock {
            if request.url.path.hasSuffix("/Users/AuthenticateByName") { loginCount += 1 }
            else if breakNext {
                breakNext = false
                if let value = sent.headers["Authorization"], let range = value.range(of: "Token=\"") {
                    sent.headers["Authorization"] = String(value[..<range.upperBound]) + "00000000000000000000000000000000\""
                }
            }
        }
        let response = try await inner.send(sent)
        lock.withLock { seen.append(response.statusCode) }
        return response
    }
}
