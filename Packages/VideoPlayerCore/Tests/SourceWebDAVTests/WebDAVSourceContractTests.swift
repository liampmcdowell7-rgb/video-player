import XCTest
@testable import VideoPlayerCore
@testable import SourceWebDAV

/// WebDAV through the shared `MediaSource` contract (the same checks every source must pass).
final class WebDAVSourceContractTests: XCTestCase {
    private let base = URL(string: "https://example.com/dav")!
    private let creds = WebDAVCredentials(username: "user", password: "pass")

    private static func multistatus(_ body: String) -> HTTPResponse {
        HTTPResponse(statusCode: 207, body: Data("""
        <?xml version="1.0"?><D:multistatus xmlns:D="DAV:">\(body)</D:multistatus>
        """.utf8))
    }

    private static let fileResponse = """
    <D:response><D:href>/dav/Movies/Film.mkv</D:href><D:propstat><D:prop><D:resourcetype/>\
    <D:getcontentlength>5000</D:getcontentlength><D:getetag>"v1"</D:getetag>\
    <D:getlastmodified>Sat, 02 Mar 2024 10:00:00 GMT</D:getlastmodified></D:prop>\
    <D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
    """

    func testUsedThroughTheProtocol() async throws {
        let source: any MediaSource = WebDAVClient(
            baseURL: base, credentials: nil,
            transport: MockTransport { _ in Self.multistatus(Self.fileResponse) })
        XCTAssertEqual(source.kind, .webdav)
        XCTAssertTrue(source.capabilities.byteRanges)
        XCTAssertTrue(source.capabilities.authMethods.contains(.digest))
        XCTAssertTrue(source.capabilities.changeSignals.contains(.etag))
        try await source.authenticate()
        let entries = try await source.list("/Movies")
        XCTAssertEqual(entries.map(\.name), ["Film.mkv"])
    }

    func testInfoUsesDepthZeroAndReturnsTheEntry() async throws {
        let transport = MockTransport { _ in Self.multistatus(Self.fileResponse) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        let entry = try await client.info("/Movies/Film.mkv")
        XCTAssertEqual(entry.path, "/Movies/Film.mkv")
        XCTAssertEqual(entry.size, 5000)
        XCTAssertEqual(entry.etag, "v1")
        XCTAssertEqual(entry.version.etag, "v1")
        XCTAssertEqual(transport.requests[0].headers["Depth"], "0")
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://example.com/dav/Movies/Film.mkv")
    }

    func testInfoOnMissingEntryIsNotFound() async {
        let client = WebDAVClient(baseURL: base, credentials: nil,
                                  transport: MockTransport { _ in HTTPResponse(statusCode: 404) })
        do { _ = try await client.info("/nope"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testAuthenticateSurfacesBadCredentials() async {
        let transport = MockTransport { _ in
            HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Basic realm="x""#])
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        do { try await client.authenticate(); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testRangedReadSendsRangeHeaderAndReturnsBody() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 206, body: Data([1, 2, 3, 4])) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        let data = try await client.read("/Movies/A B.mkv", range: ByteRange(offset: 100, length: 4))
        XCTAssertEqual(Array(data), [1, 2, 3, 4])
        XCTAssertEqual(transport.requests[0].method, "GET")
        XCTAssertEqual(transport.requests[0].headers["Range"], "bytes=100-103")
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://example.com/dav/Movies/A%20B.mkv")
    }

    func testRangedReadTruncatesAnOverlongBody() async throws {
        let client = WebDAVClient(baseURL: base, credentials: nil,
                                  transport: MockTransport { _ in HTTPResponse(statusCode: 206, body: Data(repeating: 7, count: 10)) })
        let data = try await client.read("/f", range: ByteRange(offset: 0, length: 4))
        XCTAssertEqual(data.count, 4)
    }

    func testZeroLengthReadSendsNothing() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 500) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        let data = try await client.read("/f", range: ByteRange(offset: 5, length: 0))
        XCTAssertTrue(data.isEmpty)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testReadStatusMapping() async {
        let cases: [(Int, SourceError)] = [
            (200, .rangesNotSupported), (416, .rangeNotSatisfiable), (404, .notFound),
            (403, .forbidden), (500, .httpStatus(500))
        ]
        for (status, expected) in cases {
            let client = WebDAVClient(baseURL: base, credentials: nil,
                                      transport: MockTransport { _ in HTTPResponse(statusCode: status, body: Data([0])) })
            do { _ = try await client.read("/f", range: ByteRange(offset: 0, length: 1)); XCTFail("expected error") }
            catch { XCTAssertEqual(error as? SourceError, expected, "status \(status)") }
        }
    }

    func testPlaybackAccessWithoutCredentialsIsAPlainURL() async throws {
        let client = WebDAVClient(baseURL: base, credentials: nil,
                                  transport: MockTransport { _ in HTTPResponse(statusCode: 500) })
        let access = try await client.playbackAccess(for: "/Movies/Film.mkv")
        XCTAssertEqual(access, .url(URL(string: "https://example.com/dav/Movies/Film.mkv")!, headers: [:]))
    }

    func testPlaybackAccessWithBasicCarriesTheAuthorizationHeader() async throws {
        let transport = MockTransport { request in
            request.headers["Authorization"] == "Basic dXNlcjpwYXNz"
                ? Self.multistatus(Self.fileResponse)
                : HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Basic realm="x""#])
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        let access = try await client.playbackAccess(for: "/Movies/Film.mkv")
        XCTAssertEqual(access, .url(URL(string: "https://example.com/dav/Movies/Film.mkv")!,
                                    headers: ["Authorization": "Basic dXNlcjpwYXNz"]))
    }

    func testPlaybackAccessWithDigestFallsBackToTheByteReader() async throws {
        let transport = MockTransport { request in
            (request.headers["Authorization"] ?? "").hasPrefix("Digest ")
                ? Self.multistatus(Self.fileResponse)
                : HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Digest realm="r", nonce="n1", qop="auth", algorithm=MD5"#])
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        let access = try await client.playbackAccess(for: "/Movies/Film.mkv")
        XCTAssertEqual(access, .byteReader)
    }

    func testChangeDetectionThroughTheContract() async throws {
        let client = WebDAVClient(baseURL: base, credentials: nil,
                                  transport: MockTransport { _ in Self.multistatus(Self.fileResponse) })
        let entry = try await client.info("/Movies/Film.mkv")
        XCTAssertEqual(client.hasChanged(FileVersion(etag: "v1"), comparedTo: entry), false)
        XCTAssertEqual(client.hasChanged(FileVersion(etag: "v0"), comparedTo: entry), true)
        XCTAssertNil(client.hasChanged(FileVersion(), comparedTo: entry))
    }
}
