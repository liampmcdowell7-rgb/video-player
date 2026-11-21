import XCTest
import VideoPlayerCore
@testable import SourcePlex

/// Stage 1 (docs/PLEX_SOURCE.md section 8; R300): headers, the client identifier, JSON decoding of the hand-written fixtures,
/// the refusal of XML, token redaction, and the fake server itself. No network.
final class PlexBasicsTests: XCTestCase {
    let identity = PlexClientIdentity(clientIdentifier: "install-1234", version: "0.1.0")

    // MARK: Headers

    func testEveryRequestAsksForJSONAndNamesTheClient() {
        let headers = identity.headers(token: nil)
        XCTAssertEqual(headers["Accept"], "application/json")
        XCTAssertEqual(headers["X-Plex-Client-Identifier"], "install-1234")
        XCTAssertEqual(headers["X-Plex-Product"], "Video Player")
        XCTAssertEqual(headers["X-Plex-Version"], "0.1.0")
        XCTAssertEqual(headers["X-Plex-Platform"], "tvOS")
        XCTAssertEqual(headers["X-Plex-Device"], "Apple TV")
        XCTAssertNil(headers["X-Plex-Token"], "no token header without a token")
        XCTAssertEqual(identity.headers(token: "abcd1234")["X-Plex-Token"], "abcd1234")
        XCTAssertNil(identity.headers(token: "")["X-Plex-Token"])
    }

    func testTheProductNameIsNotAPlexProduct() {
        XCTAssertFalse(identity.product.lowercased().contains("plex"))
    }

    func testTheClientIdentifierIsTheOneGivenAndStable() {
        let a = PlexClientIdentity(clientIdentifier: "install-1234")
        let b = PlexClientIdentity(clientIdentifier: "install-1234")
        XCTAssertEqual(a.headers(token: nil)["X-Plex-Client-Identifier"], b.headers(token: nil)["X-Plex-Client-Identifier"])
        XCTAssertEqual(a.version, AppInfo.version)
    }

    // MARK: Decoding (hand-written fixtures)

    private func envelope(_ name: String) throws -> PlexMediaContainer {
        try JSONDecoder().decode(PlexEnvelope.self, from: Fixture.data(name)).container
    }

    func testSectionsDecodeWithTheirFolders() throws {
        let sections = try envelope("sections.json").directories
        XCTAssertEqual(sections.map(\.key), ["1", "2"])
        XCTAssertEqual(sections.map(\.type), ["movie", "show"])
        XCTAssertEqual(sections.map(\.title), ["Movies", "TV Shows"])
        XCTAssertEqual(sections[0].locations, ["D:\\Media\\Movies"])
    }

    func testMoviesDecodeWithMediaPartsAndIDs() throws {
        let container = try envelope("section-1-all.json")
        XCTAssertEqual(container.totalSize, 2)
        let movie = container.metadata[0]
        XCTAssertEqual(movie.ratingKey, "1001")
        XCTAssertEqual(movie.title, "Test Movie")
        XCTAssertEqual(movie.year, 2020)
        XCTAssertEqual(movie.tmdbID, 550)
        XCTAssertEqual(movie.imdbID, "tt0000001")
        XCTAssertEqual(movie.runtimeSeconds, 5400, "duration is milliseconds")
        XCTAssertEqual(movie.rating, 7.5)
        XCTAssertEqual(movie.contentRating, "PG-13")
        let media = try XCTUnwrap(movie.media.first)
        XCTAssertEqual(media.container, "mp4")
        XCTAssertEqual(media.videoCodec, "hevc")
        XCTAssertEqual(media.audioCodec, "eac3")
        XCTAssertEqual(media.width, 3840)
        let part = try XCTUnwrap(media.parts.first)
        XCTAssertEqual(part.id, "2001")
        XCTAssertEqual(part.key, "/library/parts/2001/1700000000/file.mp4")
        XCTAssertEqual(part.file, "D:\\Media\\Movies\\Test Movie (2020)\\Test Movie (2020).mp4")
        XCTAssertEqual(part.size, 1000)
        let second = container.metadata[1]
        XCTAssertEqual(second.viewOffset, 600_000)
        XCTAssertEqual(second.viewCount, 0)
        XCTAssertEqual(second.lastViewedAt, 1_763_600_000)
    }

    func testEpisodesDecodeWithSeasonAndEpisodeNumbers() throws {
        let episodes = try envelope("show-3001-leaves.json").metadata
        XCTAssertEqual(episodes.map(\.parentIndex), [1, 1])
        XCTAssertEqual(episodes.map(\.index), [1, 2])
        XCTAssertEqual(episodes.map(\.grandparentTitle), ["Test Show", "Test Show"])
        XCTAssertEqual(episodes[0].viewCount, 1)
    }

    func testIdsAndFlagsAreAcceptedAsStringsOrNumbers() throws {
        let text = """
        {"MediaContainer": {"size": "1", "Metadata": [{"ratingKey": 77, "year": "1999", "duration": 1000.0, "rating": "6.5",
          "Media": [{"Part": [{"id": "9", "size": "123"}]}]}]}}
        """
        let item = try JSONDecoder().decode(PlexEnvelope.self, from: Data(text.utf8)).container.metadata[0]
        XCTAssertEqual(item.ratingKey, "77")
        XCTAssertEqual(item.year, 1999)
        XCTAssertEqual(item.duration, 1000)
        XCTAssertEqual(item.rating, 6.5)
        XCTAssertEqual(item.media.first?.parts.first?.size, 123)
        let connection = try JSONDecoder().decode(PlexConnection.self, from: Data(#"{"uri": "http://10.0.0.2:32400", "local": 1, "relay": 0}"#.utf8))
        XCTAssertTrue(connection.local)
        XCTAssertFalse(connection.relay)
        XCTAssertEqual(connection.scheme, "http")
    }

    func testAnItemWithoutARatingKeyIsDropped() {
        XCTAssertThrowsError(try JSONDecoder().decode(PlexMetadata.self, from: Data(#"{"title": "x"}"#.utf8)))
    }

    func testResourcesTellServersFromPlayers() throws {
        let resources = try JSONDecoder().decode([PlexResource].self, from: Fixture.data("resources.json"))
        XCTAssertEqual(resources.map(\.name), ["Home PC", "Living Room TV", "Friend's Server"])
        XCTAssertEqual(resources.map(\.isServer), [true, false, true])
        XCTAssertEqual(resources[0].connections.count, 4)
        XCTAssertEqual(resources[0].connections.filter(\.relay).count, 1)
        XCTAssertNil(resources[1].accessToken, "null token")
        // `provides` is UNVERIFIED: without it, a token and a connection make a server.
        let unnamed = try JSONDecoder().decode(PlexResource.self, from: Data(#"{"name": "X", "accessToken": "t0k3n", "connections": [{"uri": "http://10.0.0.2:32400"}]}"#.utf8))
        XCTAssertTrue(unnamed.isServer)
    }

    func testAPinDecodesWithoutAToken() throws {
        let pin = try JSONDecoder().decode(PlexPinResponse.self, from: Fixture.data("pin-created.json"))
        XCTAssertEqual(pin.id, "51234")
        XCTAssertEqual(pin.code, "WXYZ")
        XCTAssertNil(pin.authToken)
        XCTAssertEqual(pin.expiresIn, 900)
        let empty = try JSONDecoder().decode(PlexPinResponse.self, from: Data(#"{"id": 1, "code": "A", "authToken": ""}"#.utf8))
        XCTAssertNil(empty.authToken, "an empty token is no token")
    }

    // MARK: JSON only

    func testAnXMLAnswerIsRefused() {
        let xml = HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/xml;charset=utf-8"], body: Data("<MediaContainer/>".utf8))
        XCTAssertThrowsError(try PlexHTTP.decode(PlexEnvelope.self, from: xml)) { XCTAssertEqual($0 as? PlexError, .notJSON) }
        let unlabelled = HTTPResponse(statusCode: 200, body: Data("  <MediaContainer/>".utf8))
        XCTAssertThrowsError(try PlexHTTP.decode(PlexEnvelope.self, from: unlabelled)) { XCTAssertEqual($0 as? PlexError, .notJSON) }
    }

    func testStatusCodesMapToSourceErrors() {
        XCTAssertThrowsError(try PlexHTTP.check(HTTPResponse(statusCode: 401))) { XCTAssertEqual($0 as? SourceError, .unauthorized) }
        XCTAssertThrowsError(try PlexHTTP.check(HTTPResponse(statusCode: 404))) { XCTAssertEqual($0 as? SourceError, .notFound) }
        XCTAssertThrowsError(try PlexHTTP.check(HTTPResponse(statusCode: 500))) { XCTAssertEqual($0 as? SourceError, .httpStatus(500)) }
    }

    // MARK: Tokens never leak

    func testRedactionRemovesKnownTokensAndAnyQueryToken() {
        let text = "GET https://h:32400/library/parts/1/file.mkv?X-Plex-Token=secretvalue99&a=1 failed; header server-token-placeholder"
        let clean = PlexRedaction.redact(text, tokens: ["server-token-placeholder"])
        XCTAssertFalse(clean.contains("secretvalue99"))
        XCTAssertFalse(clean.contains("server-token-placeholder"))
        XCTAssertTrue(clean.contains("X-Plex-Token=<token>"))
    }

    func testATransportFailureNeverCarriesTheToken() async {
        struct Leaky: HTTPTransport {
            func send(_ request: HTTPRequest) async throws -> HTTPResponse {
                throw FakePlexServer.NetworkDown(url: request.url.absoluteString + "?X-Plex-Token=" + (request.headers["X-Plex-Token"] ?? ""))
            }
        }
        let http = PlexHTTP(identity: identity, transport: Leaky())
        do {
            _ = try await http.send(http.request("GET", URL(string: "http://10.0.0.2:32400/library/sections")!, token: "tok-SECRET-1"))
            XCTFail("expected a failure")
        } catch {
            XCTAssertFalse(String(describing: error).contains("tok-SECRET-1"), String(describing: error))
        }
    }

    // MARK: The fake server

    func testTheFakeServerAnswersIdentityWithoutATokenAndTheLibraryOnlyWithOne() async throws {
        let server = try FakePlexServer()
        let http = PlexHTTP(identity: identity, transport: server)
        let base = "https://192-168-1-20.machine0001.plex.direct:32400"
        let identityAnswer = try await http.send(http.request("GET", URL(string: base + "/identity")!, token: nil))
        XCTAssertEqual(try PlexHTTP.decode(PlexEnvelope.self, from: identityAnswer).container.machineIdentifier, "machine-0001")
        let refused = try await http.send(http.request("GET", URL(string: base + "/library/sections")!, token: nil))
        XCTAssertEqual(refused.statusCode, 401)
        let sections = try await http.send(http.request("GET", URL(string: base + "/library/sections")!, token: server.serverToken))
        XCTAssertEqual(try PlexHTTP.decode(PlexEnvelope.self, from: sections).container.directories.count, 2)
        do {
            _ = try await http.send(http.request("GET", URL(string: "https://198-51-100-40.machine0003.plex.direct:32400/identity")!, token: nil))
            XCTFail("an unreachable host must fail")
        } catch {
            guard case SourceError.transport = error else { return XCTFail("\(error)") }
        }
    }
}
