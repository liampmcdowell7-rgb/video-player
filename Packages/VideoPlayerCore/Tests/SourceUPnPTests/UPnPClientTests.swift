import XCTest
import Foundation
import VideoPlayerCore
@testable import SourceUPnP

/// Answers requests from a closure and remembers them. Tests below use real recorded rclone responses (Fixtures.swift)
/// or small hand-built ones for cases the test server cannot produce (paging, duplicate titles, odd servers).
final class MockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest) throws -> HTTPResponse

    init(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) { self.handler = handler }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return log }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock(); log.append(request); lock.unlock()
        return try handler(request)
    }
}

func soapBody(_ request: HTTPRequest) -> String { String(decoding: request.body ?? Data(), as: UTF8.self) }

func tag(_ name: String, in text: String) -> String? {
    guard let open = text.range(of: "<\(name)>"), let close = text.range(of: "</\(name)>") else { return nil }
    return String(text[open.upperBound..<close.lowerBound])
}

/// Wraps DIDL-Lite (already built as plain XML) in a BrowseResponse envelope, escaping it like real servers do.
func browseEnvelope(didlItems: String, returned: Int, total: Int) -> String {
    let didl = "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">\(didlItems)</DIDL-Lite>"
    let escaped = didl.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    return "<?xml version=\"1.0\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><u:BrowseResponse xmlns:u=\"urn:schemas-upnp-org:service:ContentDirectory:1\"><Result>\(escaped)</Result><NumberReturned>\(returned)</NumberReturned><TotalMatches>\(total)</TotalMatches><UpdateID>1</UpdateID></u:BrowseResponse></s:Body></s:Envelope>"
}

private func ok(_ text: String) -> HTTPResponse { HTTPResponse(statusCode: 200, body: Data(text.utf8)) }

/// Serves the recorded rclone description and Browse answers, picking by ObjectID.
private func recordedServer(files: @escaping @Sendable (HTTPRequest) -> HTTPResponse = { _ in HTTPResponse(statusCode: 404) }) -> MockTransport {
    MockTransport { request in
        if request.method == "GET", request.url.path == "/rootDesc.xml" { return ok(rcloneDeviceDescription) }
        guard request.method == "POST", request.url.path == "/ctl" else { return files(request) }
        switch tag("ObjectID", in: soapBody(request)) {
        case "0": return ok(rcloneBrowseRoot)
        case "%2FMovies": return ok(rcloneBrowseMovies)
        case "%2FShows": return ok(rcloneBrowseShows)
        case "%2FShows%2FTest+Show+%282019%29": return ok(rcloneBrowseShow)
        case "%2FShows%2FTest+Show+%282019%29%2FSeason+1": return ok(rcloneBrowseSeason1)
        default: return HTTPResponse(statusCode: 500, body: Data(rcloneBrowseMissingFault.utf8))
        }
    }
}

private let deviceURL = URL(string: "http://127.0.0.1:17879/rootDesc.xml")!

final class UPnPParserTests: XCTestCase {
    func testDeviceDescriptionFromRclone() throws {
        let description = try UPnPDeviceDescription.parse(Data(rcloneDeviceDescription.utf8))
        XCTAssertEqual(description.friendlyName, "VP Test Media")
        XCTAssertTrue(description.isMediaServer)
        XCTAssertEqual(description.contentDirectory?.controlURL, "/ctl")
        XCTAssertEqual(description.contentDirectory?.serviceType, "urn:schemas-upnp-org:service:ContentDirectory:1")
        XCTAssertEqual(description.services.count, 3)
    }

    func testNotADeviceDescription() {
        XCTAssertThrowsError(try UPnPDeviceDescription.parse(Data("<html><body>hi</body></html>".utf8))) {
            XCTAssertEqual($0 as? SourceError, .malformedResponse)
        }
    }

    func testRootBrowseFromRclone() throws {
        let response = try SOAPParser.parseBrowse(Data(rcloneBrowseRoot.utf8))
        let objects = try DIDLParser.parse(response.didl)
        XCTAssertEqual(response.numberReturned, objects.count)
        XCTAssertEqual(response.totalMatches, objects.count)
        XCTAssertTrue(objects.allSatisfy { $0.isContainer })
        XCTAssertEqual(Set(objects.map(\.title)), ["big", "Movies", "Odd Names", "Shows"])
        XCTAssertTrue(objects.contains { $0.id == "%2FOdd+Names" })
    }

    func testItemWithTwoResourcesFromRclone() throws {
        let response = try SOAPParser.parseBrowse(Data(rcloneBrowseMovies.utf8))
        let objects = try DIDLParser.parse(response.didl)
        XCTAssertEqual(objects.count, 1)
        let item = try XCTUnwrap(objects.first)
        XCTAssertFalse(item.isContainer)
        XCTAssertEqual(item.resources.count, 2)
        XCTAssertEqual(item.resources[0].size, 3_145_728)
        XCTAssertEqual(item.resources[0].mimeType, "video/x-matroska")
        XCTAssertEqual(item.resources[0].url, "http://127.0.0.1:17879/r/Movies/Test%20Movie%20%282020%29.mkv")
        XCTAssertEqual(item.resources[1].mimeType, "application/x-subrip")
    }

    func testFaultFromRcloneMapsToNotFound() {
        XCTAssertThrowsError(try SOAPParser.parseBrowse(Data(rcloneBrowseMissingFault.utf8))) {
            XCTAssertEqual($0 as? SourceError, .notFound)
        }
    }

    func testOtherFaultCodeKeepsTheMessage() {
        let fault = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><detail><UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>720</errorCode><errorDescription>Cannot process the request</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>"
        XCTAssertThrowsError(try SOAPParser.parseBrowse(Data(fault.utf8))) {
            XCTAssertEqual($0 as? SourceError, .transport("UPnP error 720: Cannot process the request"))
        }
    }

    func testNonSoapBodyIsMalformed() {
        XCTAssertThrowsError(try SOAPParser.parseBrowse(Data("<html/>".utf8))) {
            XCTAssertEqual($0 as? SourceError, .malformedResponse)
        }
    }

    func testDidlDates() {
        XCTAssertNotNil(DIDLParser.parseDate("2026-11-16"))
        XCTAssertNotNil(DIDLParser.parseDate("2026-11-16T10:20:30"))
        XCTAssertNotNil(DIDLParser.parseDate("2026-11-16T10:20:30Z"))
        XCTAssertNil(DIDLParser.parseDate("yesterday"))
        XCTAssertNil(DIDLParser.parseDate(nil))
    }
}

final class SSDPTests: XCTestCase {
    func testSearchMessage() {
        let text = SSDP.mSearchMessage(mx: 9)
        XCTAssertTrue(text.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("HOST: 239.255.255.250:1900\r\n"))
        XCTAssertTrue(text.contains("MAN: \"ssdp:discover\"\r\n"))
        XCTAssertTrue(text.contains("MX: 5\r\n"), "MX is capped at 5")
        XCTAssertTrue(text.contains("ST: urn:schemas-upnp-org:device:MediaServer:1\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"))
    }

    // A typical answer from a home media server (shape taken from the UPnP Device Architecture spec, not recorded from a real device).
    private let answer = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nEXT:\r\nLOCATION: http://192.168.1.20:8200/rootDesc.xml\r\nSERVER: Linux/5.4 UPnP/1.0 MiniDLNA/1.3.0\r\nST: urn:schemas-upnp-org:device:MediaServer:1\r\nUSN: uuid:4d696e69-444c-164e-9d41-001132f4c0a1::urn:schemas-upnp-org:device:MediaServer:1\r\n\r\n"

    func testParseAnswer() throws {
        let response = try XCTUnwrap(SSDP.parseResponse(answer))
        XCTAssertEqual(response.location.absoluteString, "http://192.168.1.20:8200/rootDesc.xml")
        XCTAssertEqual(response.searchTarget, "urn:schemas-upnp-org:device:MediaServer:1")
        XCTAssertEqual(response.server, "Linux/5.4 UPnP/1.0 MiniDLNA/1.3.0")
        let found = SSDP.discoveredSource(from: response)
        XCTAssertEqual(found, DiscoveredSource(kind: .upnp, name: "Linux/5.4 UPnP/1.0 MiniDLNA/1.3.0", host: "192.168.1.20", port: 8200,
                                              address: "http://192.168.1.20:8200/rootDesc.xml"))
    }

    func testHeadersAreCaseInsensitiveAndNameComesFromDescription() throws {
        let lower = "HTTP/1.1 200 OK\r\nlocation: http://10.0.0.5/desc.xml\r\nst: upnp:rootdevice\r\n\r\n"
        let response = try XCTUnwrap(SSDP.parseResponse(lower))
        XCTAssertEqual(response.location.host, "10.0.0.5")
        let description = try UPnPDeviceDescription.parse(Data(rcloneDeviceDescription.utf8))
        let found = SSDP.discoveredSource(from: response, description: description)
        XCTAssertEqual(found.name, "VP Test Media")
        XCTAssertNil(found.port)
        XCTAssertEqual(SSDP.discoveredSource(from: response).name, "10.0.0.5")
    }

    func testIgnoresThingsThatAreNotAnswers() {
        XCTAssertNil(SSDP.parseResponse("M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n\r\n"))
        XCTAssertNil(SSDP.parseResponse("NOTIFY * HTTP/1.1\r\nLOCATION: http://10.0.0.5/d.xml\r\n\r\n"))
        XCTAssertNil(SSDP.parseResponse("HTTP/1.1 200 OK\r\nST: x\r\n\r\n"), "no LOCATION")
        XCTAssertNil(SSDP.parseResponse("HTTP/1.1 200 OK\r\nLOCATION: file:///etc/passwd\r\n\r\n"), "only http(s)")
        XCTAssertNil(SSDP.parseResponse("HTTP/1.1 404 Not Found\r\nLOCATION: http://10.0.0.5/d.xml\r\n\r\n"))
        XCTAssertNil(SSDP.parseResponse(""))
    }
}

final class UPnPClientRecordedTests: XCTestCase {
    func testAuthenticateFindsControlURL() async throws {
        let transport = recordedServer()
        let client = UPnPClient(deviceURL: deviceURL, transport: transport)
        try await client.authenticate()
        let name = await client.friendlyName
        XCTAssertEqual(name, "VP Test Media")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testNoContentDirectoryIsUnsupported() async {
        let description = rcloneDeviceDescription.replacingOccurrences(of: "ContentDirectory", with: "SomethingElse")
        let client = UPnPClient(deviceURL: deviceURL, transport: MockTransport { _ in ok(description) })
        do { try await client.authenticate(); XCTFail("expected a throw") } catch {
            guard case SourceError.unsupported = error else { return XCTFail("\(error)") }
        }
    }

    func testListRootSendsARealBrowseRequest() async throws {
        let transport = recordedServer()
        let client = UPnPClient(deviceURL: deviceURL, transport: transport)
        let entries = try await client.list("/")
        XCTAssertEqual(entries.map(\.path).sorted(), ["/Movies", "/Odd Names", "/Shows", "/big"])
        XCTAssertTrue(entries.allSatisfy { $0.isDirectory })
        let post = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(post.method, "POST")
        XCTAssertEqual(post.url.absoluteString, "http://127.0.0.1:17879/ctl")
        XCTAssertEqual(post.headers["SOAPACTION"], "\"urn:schemas-upnp-org:service:ContentDirectory:1#Browse\"")
        let body = soapBody(post)
        XCTAssertEqual(tag("ObjectID", in: body), "0")
        XCTAssertEqual(tag("BrowseFlag", in: body), "BrowseDirectChildren")
        XCTAssertEqual(tag("StartingIndex", in: body), "0")
        XCTAssertEqual(tag("RequestedCount", in: body), "100")
    }

    func testNestedFoldersAndObjectIDMap() async throws {
        let client = UPnPClient(deviceURL: deviceURL, transport: recordedServer())
        let episodes = try await client.list("/Shows/Test Show (2019)/Season 1")
        XCTAssertEqual(episodes.map(\.name).sorted(), ["Test Show - S01E01 - Pilot.mkv", "Test Show - S01E02.mkv"])
        XCTAssertTrue(episodes.allSatisfy { $0.size == 1_048_576 && $0.contentType == "video/x-matroska" })
        let id = await client.path(forObjectID: "%2FShows")
        XCTAssertEqual(id, "/Shows")
    }

    func testItemNameGetsTheExtensionAndSubtitleIsASiblingEntry() async throws {
        let client = UPnPClient(deviceURL: deviceURL, transport: recordedServer())
        let entries = try await client.list("/Movies")
        XCTAssertEqual(entries.map(\.name), ["Test Movie (2020).mkv", "Test Movie (2020).en.srt"])
        XCTAssertEqual(entries[0].size, 3_145_728)
        XCTAssertNotNil(entries[0].modified)
        let info = try await client.info("/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(info, entries[0])
    }

    func testPlaybackAccessIsTheResourceURL() async throws {
        let client = UPnPClient(deviceURL: deviceURL, transport: recordedServer())
        let access = try await client.playbackAccess(for: "/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(access, .url(URL(string: "http://127.0.0.1:17879/r/Movies/Test%20Movie%20%282020%29.mkv")!, headers: [:]))
        let subtitle = try await client.playbackAccess(for: "/Movies/Test Movie (2020).en.srt")
        XCTAssertEqual(subtitle, .url(URL(string: "http://127.0.0.1:17879/r/Movies/Test%20Movie%20%282020%29.en.srt")!, headers: [:]))
    }

    func testFolderHasNothingToPlay() async throws {
        let client = UPnPClient(deviceURL: deviceURL, transport: recordedServer())
        do { _ = try await client.playbackAccess(for: "/Movies"); XCTFail("expected a throw") } catch {
            guard case SourceError.unsupported = error else { return XCTFail("\(error)") }
        }
    }

    func testMissingFolderIsNotFound() async throws {
        let client = UPnPClient(deviceURL: deviceURL, transport: recordedServer())
        do { _ = try await client.list("/nope"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? SourceError, .notFound)
        }
        // Real rclone answers an unknown object id with a 500 fault carrying UPnP error 701.
        let direct = MockTransport { request in
            request.method == "GET" ? ok(rcloneDeviceDescription) : HTTPResponse(statusCode: 500, body: Data(rcloneBrowseMissingFault.utf8))
        }
        let other = UPnPClient(deviceURL: deviceURL, transport: direct)
        do { _ = try await other.list("/"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? SourceError, .notFound)
        }
    }

    func testListingTwiceKeepsPathsStable() async throws {
        let client = UPnPClient(deviceURL: deviceURL, transport: recordedServer())
        let first = try await client.list("/Movies")
        let second = try await client.list("/Movies")
        XCTAssertEqual(first, second)
    }

    func testReadSendsRangeAndTrimsExtraBytes() async throws {
        let transport = recordedServer { request in
            XCTAssertEqual(request.headers["Range"], "bytes=10-19")
            XCTAssertEqual(request.url.path, "/r/Movies/Test%20Movie%20%282020%29.mkv".removingPercentEncoding)
            return HTTPResponse(statusCode: 206, body: Data(repeating: 7, count: 12))
        }
        let client = UPnPClient(deviceURL: deviceURL, transport: transport)
        let data = try await client.read("/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 10, length: 10))
        XCTAssertEqual(data.count, 10)
        let empty = try await client.read("/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 0, length: 0))
        XCTAssertTrue(empty.isEmpty)
    }

    func testReadStatusMapping() async throws {
        for (status, expected) in [(200, SourceError.rangesNotSupported), (416, .rangeNotSatisfiable), (404, .notFound), (500, .httpStatus(500))] {
            let transport = recordedServer { _ in HTTPResponse(statusCode: status) }
            let client = UPnPClient(deviceURL: deviceURL, transport: transport)
            do {
                _ = try await client.read("/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 0, length: 4))
                XCTFail("expected \(expected)")
            } catch { XCTAssertEqual(error as? SourceError, expected) }
        }
    }

    func testTransportFailureIsWrapped() async {
        struct Boom: Error {}
        let client = UPnPClient(deviceURL: deviceURL, transport: MockTransport { _ in throw Boom() })
        do { try await client.authenticate(); XCTFail("expected a throw") } catch {
            guard case SourceError.transport = error else { return XCTFail("\(error)") }
        }
    }
}

/// Hand-built answers for behaviour rclone cannot show: several pages, repeated titles, a relative res URL, a URLBase.
final class UPnPClientSyntheticTests: XCTestCase {
    private func item(_ n: Int, title: String? = nil) -> String {
        "<item id=\"i\(n)\" parentID=\"0\" restricted=\"1\"><dc:title>\(title ?? "Clip \(n)")</dc:title><upnp:class>object.item.videoItem</upnp:class><res protocolInfo=\"http-get:*:video/mp4:*\" size=\"\(100 * n)\">/media/\(n).mp4</res></item>"
    }

    func testPagingAsksForEveryPageAndStops() async throws {
        let transport = MockTransport { request in
            if request.method == "GET" { return ok(rcloneDeviceDescription) }
            let body = soapBody(request)
            let start = Int(tag("StartingIndex", in: body) ?? "") ?? -1
            let count = Int(tag("RequestedCount", in: body) ?? "") ?? -1
            XCTAssertEqual(count, 2)
            let slice = (start..<min(5, start + count)).map { self.item($0) }
            return ok(browseEnvelope(didlItems: slice.joined(), returned: slice.count, total: 5))
        }
        let client = UPnPClient(deviceURL: deviceURL, transport: transport, pageSize: 2)
        let entries = try await client.list("/")
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(entries.map(\.name), (0..<5).map { "Clip \($0).mp4" })
        let starts = transport.requests.filter { $0.method == "POST" }.compactMap { tag("StartingIndex", in: soapBody($0)) }
        XCTAssertEqual(starts, ["0", "2", "4"])
    }

    func testServerThatReportsNoTotalStopsOnAShortPage() async throws {
        let transport = MockTransport { request in
            if request.method == "GET" { return ok(rcloneDeviceDescription) }
            return ok(browseEnvelope(didlItems: self.item(1) + self.item(2), returned: 2, total: 0))
        }
        let client = UPnPClient(deviceURL: deviceURL, transport: transport, pageSize: 10)
        let entries = try await client.list("/")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(transport.requests.filter { $0.method == "POST" }.count, 1)
    }

    func testRepeatedTitlesGetUniquePathsAndRelativeURLsResolveAgainstTheDevice() async throws {
        let transport = MockTransport { request in
            if request.method == "GET" { return ok(rcloneDeviceDescription) }
            return ok(browseEnvelope(didlItems: self.item(1, title: "Same") + self.item(2, title: "Same") + self.item(3, title: "a/b"), returned: 3, total: 3))
        }
        let client = UPnPClient(deviceURL: deviceURL, transport: transport)
        let entries = try await client.list("/")
        XCTAssertEqual(entries.map(\.path), ["/Same.mp4", "/Same (2).mp4", "/a\u{2215}b.mp4"])
        let access = try await client.playbackAccess(for: "/Same (2).mp4")
        XCTAssertEqual(access, .url(URL(string: "http://127.0.0.1:17879/media/2.mp4")!, headers: [:]))
    }

    func testURLBaseAndRelativeControlURL() async throws {
        let description = rcloneDeviceDescription.replacingOccurrences(
            of: "<specVersion>", with: "<URLBase>http://10.1.2.3:9000/dev/</URLBase><specVersion>"
        ).replacingOccurrences(of: "<controlURL>/ctl</controlURL>", with: "<controlURL>control</controlURL>")
        XCTAssertTrue(description.contains("URLBase"), "fixture shape changed")
        let transport = MockTransport { request in
            if request.method == "GET" { return ok(description) }
            return ok(browseEnvelope(didlItems: "", returned: 0, total: 0))
        }
        let client = UPnPClient(deviceURL: deviceURL, transport: transport)
        _ = try await client.list("/")
        XCTAssertEqual(transport.requests.last?.url.absoluteString, "http://10.1.2.3:9000/dev/control")
    }

    func testObjectIDsAreXMLEscaped() {
        XCTAssertEqual(UPnPClient.xmlEscape("a&b<c>\"d"), "a&amp;b&lt;c&gt;&quot;d")
    }

    func testContainerWithQuotesAndAmpersandInTheTitle() async throws {
        let container = "<container id=\"c&amp;1\" parentID=\"0\" restricted=\"1\"><dc:title>Tom &amp; Jerry</dc:title><upnp:class>object.container</upnp:class></container>"
        let transport = MockTransport { request in
            if request.method == "GET" { return ok(rcloneDeviceDescription) }
            let id = tag("ObjectID", in: soapBody(request))
            if id == "0" { return ok(browseEnvelope(didlItems: container.replacingOccurrences(of: "&amp;", with: "&amp;"), returned: 1, total: 1)) }
            XCTAssertEqual(id, "c&amp;1", "the id must be escaped again inside the request")
            return ok(browseEnvelope(didlItems: "", returned: 0, total: 0))
        }
        let client = UPnPClient(deviceURL: deviceURL, transport: transport)
        let root = try await client.list("/")
        XCTAssertEqual(root.map(\.name), ["Tom & Jerry"])
        let inside = try await client.list("/Tom & Jerry")
        XCTAssertTrue(inside.isEmpty)
    }

    func testCapabilities() {
        let client = UPnPClient(deviceURL: deviceURL, transport: MockTransport { _ in ok("") })
        XCTAssertEqual(client.kind, .upnp)
        XCTAssertTrue(client.capabilities.byteRanges)
        XCTAssertTrue(client.capabilities.directPlaybackURL)
        XCTAssertEqual(client.capabilities.authMethods, [.none])
    }
}
