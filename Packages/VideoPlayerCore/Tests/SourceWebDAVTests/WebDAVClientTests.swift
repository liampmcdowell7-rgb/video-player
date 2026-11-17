import XCTest
@testable import VideoPlayerCore
@testable import SourceWebDAV

final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest) -> HTTPResponse

    init(handler: @escaping @Sendable (HTTPRequest) -> HTTPResponse) { self.handler = handler }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return recorded }

    private func record(_ request: HTTPRequest) {
        lock.lock(); recorded.append(request); lock.unlock()
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        record(request)
        return handler(request)
    }
}

final class WebDAVClientTests: XCTestCase {
    static let listing = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response>
        <D:href>/dav/Movies/</D:href>
        <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype><D:displayname>Movies</D:displayname></D:prop>
        <D:status>HTTP/1.1 200 OK</D:status></D:propstat>
      </D:response>
      <D:response>
        <D:href>/dav/Movies/The%20Quiet%20Harbor%20(2019).mkv</D:href>
        <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>123456789</D:getcontentlength>
        <D:getlastmodified>Sat, 02 Mar 2024 10:00:00 GMT</D:getlastmodified>
        <D:getcontenttype>video/x-matroska</D:getcontenttype><D:getetag>"abc123"</D:getetag></D:prop>
        <D:status>HTTP/1.1 200 OK</D:status></D:propstat>
        <D:propstat><D:prop><D:displayname/></D:prop><D:status>HTTP/1.1 404 Not Found</D:status></D:propstat>
      </D:response>
      <D:response>
        <D:href>https://example.com/dav/Movies/Season%201/</D:href>
        <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
        <D:status>HTTP/1.1 200 OK</D:status></D:propstat>
      </D:response>
    </D:multistatus>
    """

    private func ok() -> HTTPResponse { HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
    private let base = URL(string: "https://example.com/dav")!
    private let creds = WebDAVCredentials(username: "user", password: "pass")

    func testListParsesEntriesAndBuildsRequest() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        let entries = try await client.list("/Movies")

        XCTAssertEqual(entries.count, 2)
        let file = try XCTUnwrap(entries.first { !$0.isDirectory })
        XCTAssertEqual(file.path, "/Movies/The Quiet Harbor (2019).mkv")
        XCTAssertEqual(file.name, "The Quiet Harbor (2019).mkv")
        XCTAssertEqual(file.size, 123_456_789)
        XCTAssertEqual(file.contentType, "video/x-matroska")
        XCTAssertEqual(file.etag, "abc123")
        XCTAssertNotNil(file.modified)
        let folder = try XCTUnwrap(entries.first { $0.isDirectory })
        XCTAssertEqual(folder.path, "/Movies/Season 1")
        XCTAssertEqual(folder.name, "Season 1")
        XCTAssertNil(folder.size)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "PROPFIND")
        XCTAssertEqual(request.url.absoluteString, "https://example.com/dav/Movies/")
        XCTAssertEqual(request.headers["Depth"], "1")
        XCTAssertTrue(String(decoding: request.body ?? Data(), as: UTF8.self).contains("propfind"))
    }

    func testParsesNamespacePrefixVariants() async throws {
        let xml = """
        <?xml version="1.0"?><multistatus xmlns="DAV:"><response><href>/a/</href><propstat><prop><resourcetype><collection/></resourcetype></prop><status>HTTP/1.1 200 OK</status></propstat></response>\
        <response><href>/a/clip.mp4</href><propstat><prop><getcontentlength>10</getcontentlength></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
        """
        let client = WebDAVClient(baseURL: URL(string: "https://example.com")!, credentials: nil,
                                  transport: MockTransport { _ in HTTPResponse(statusCode: 207, body: Data(xml.utf8)) })
        let entries = try await client.list("/a")
        XCTAssertEqual(entries.map(\.name), ["clip.mp4"])
        XCTAssertEqual(entries.first?.size, 10)
    }

    func testBasicAuthFlowAndPreemptiveReuse() async throws {
        let transport = MockTransport { request in
            if request.headers["Authorization"] == "Basic dXNlcjpwYXNz" { return HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
            return HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Basic realm="files""#])
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        _ = try await client.list("/Movies")
        XCTAssertEqual(transport.requests.count, 2)
        _ = try await client.list("/Movies")
        XCTAssertEqual(transport.requests.count, 3, "second listing must send credentials without a new 401")
    }

    func testBasicOverPlainHTTPIsRefusedUnlessAllowed() async throws {
        let handler: @Sendable (HTTPRequest) -> HTTPResponse = { request in
            if request.headers["Authorization"] != nil { return HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
            return HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Basic realm="x""#])
        }
        let http = URL(string: "http://nas.local/dav")!
        let strict = WebDAVClient(baseURL: http, credentials: creds, transport: MockTransport(handler: handler))
        do {
            _ = try await strict.list("/Movies")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SourceError, .insecureBasicAuthentication)
        }
        let allowed = WebDAVClient(baseURL: http, credentials: creds, transport: MockTransport(handler: handler), allowBasicOverHTTP: true)
        let entries = try await allowed.list("/Movies")
        XCTAssertEqual(entries.count, 2)
    }

    func testDigestFlowComputesCorrectResponseAndIncrementsNonceCount() async throws {
        let challenge = #"Digest realm="files", nonce="abc123", qop="auth", opaque="op""#
        let transport = MockTransport { request in
            if let h = request.headers["Authorization"], h.hasPrefix("Digest ") {
                return HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8))
            }
            return HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": challenge])
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport, cnonce: { "cafebabe" })
        _ = try await client.list("/Movies")
        _ = try await client.list("/Movies")
        let requests = transport.requests
        XCTAssertEqual(requests.count, 3)

        let ha1 = Digests.md5Hex("user:files:pass")
        let ha2 = Digests.md5Hex("PROPFIND:/dav/Movies/")
        let expected1 = Digests.md5Hex("\(ha1):abc123:00000001:cafebabe:auth:\(ha2)")
        let expected2 = Digests.md5Hex("\(ha1):abc123:00000002:cafebabe:auth:\(ha2)")
        let second = try XCTUnwrap(requests[1].headers["Authorization"])
        let third = try XCTUnwrap(requests[2].headers["Authorization"])
        XCTAssertTrue(second.contains(#"response="\#(expected1)""#), second)
        XCTAssertTrue(second.contains(#"uri="/dav/Movies/""#))
        XCTAssertTrue(second.contains(#"opaque="op""#))
        XCTAssertTrue(third.contains(#"response="\#(expected2)""#), third)
        XCTAssertTrue(third.contains("nc=00000002"))
    }

    func testDigestIsPreferredOverBasic() async throws {
        let header = #"Basic realm="a", Digest realm="a", nonce="n", qop="auth""#
        let transport = MockTransport { request in
            if request.headers["Authorization"] != nil { return HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
            return HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": header])
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        _ = try await client.list("/Movies")
        XCTAssertTrue(transport.requests[1].headers["Authorization"]?.hasPrefix("Digest ") == true)
    }

    func testStaleNonceIsRefreshedOnce() async throws {
        // Request 1: no auth -> 401 (nonce n1). Request 2: n1 -> OK.
        // Second listing: request 3 sends n1 preemptively -> 401 stale (nonce n2). Request 4: n2 -> OK.
        let counter = Counter()
        let transport = MockTransport { _ in
            switch counter.next() {
            case 1: return HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Digest realm="r", nonce="n1", qop="auth""#])
            case 3: return HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Digest realm="r", nonce="n2", qop="auth", stale=true"#])
            default: return HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8))
            }
        }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        _ = try await client.list("/Movies")
        _ = try await client.list("/Movies")
        let requests = transport.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests[2].headers["Authorization"]?.contains(#"nonce="n1""#) == true)
        XCTAssertTrue(requests[3].headers["Authorization"]?.contains(#"nonce="n2""#) == true)
        XCTAssertTrue(requests[3].headers["Authorization"]?.contains("nc=00000001") == true)
    }

    func testRepeated401ThrowsUnauthorized() async {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Basic realm="x""#]) }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        do { _ = try await client.list("/"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testNoCredentialsAnd401() async {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": #"Basic realm="x""#]) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        do { _ = try await client.list("/"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testUnsupportedAuthScheme() async {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 401, headers: ["WWW-Authenticate": "Negotiate"]) }
        let client = WebDAVClient(baseURL: base, credentials: creds, transport: transport)
        do { _ = try await client.list("/"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .unsupportedAuthentication) }
    }

    func testStatusMapping() async {
        for (status, expected) in [(404, SourceError.notFound), (403, .forbidden), (500, .httpStatus(500)), (200, .httpStatus(200))] {
            let client = WebDAVClient(baseURL: base, credentials: nil, transport: MockTransport { _ in HTTPResponse(statusCode: status) })
            do { _ = try await client.list("/"); XCTFail("expected error for \(status)") }
            catch { XCTAssertEqual(error as? SourceError, expected, "status \(status)") }
        }
    }

    func testGarbageBodyIsMalformed() async {
        let client = WebDAVClient(baseURL: base, credentials: nil,
                                  transport: MockTransport { _ in HTTPResponse(statusCode: 207, body: Data("not xml".utf8)) })
        do { _ = try await client.list("/"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .malformedResponse) }
    }

    func testEncodesSpecialCharactersInRequestURL() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        _ = try await client.list("/TV Shows/Harbor Lights (2015)")
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://example.com/dav/TV%20Shows/Harbor%20Lights%20(2015)/")
    }

    func testFileURLAndAuthorizationHeaderForPlayback() async throws {
        let transport = MockTransport { _ in HTTPResponse(statusCode: 207, body: Data(Self.listing.utf8)) }
        let client = WebDAVClient(baseURL: base, credentials: nil, transport: transport)
        let url = try await client.url(for: "/Movies/A B.mkv")
        XCTAssertEqual(url.absoluteString, "https://example.com/dav/Movies/A%20B.mkv")
        let header = await client.authorizationHeader(method: "GET", url: url)
        XCTAssertNil(header)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    /// Returns 1 on the first call, 2 on the second, and so on.
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
