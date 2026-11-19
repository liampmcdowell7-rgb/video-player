import XCTest
import Foundation
import VideoPlayerCore
@testable import SourceLinks

final class LinksMockTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [HTTPRequest] = []
    private let handler: @Sendable (HTTPRequest) throws -> HTTPResponse
    init(_ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) { self.handler = handler }
    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return log }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        // #23 D: withLock, not lock()/unlock(): NSLock.lock() is unavailable from async contexts (a warning in Swift 5 mode).
        lock.withLock { log.append(request) }
        return try handler(request)
    }
}

/// Behaviour with answers written by hand (no server): servers that refuse HEAD, ignore Range, answer with a web page, or want a sign-in.
/// The provider addresses are the documented formats; no provider was contacted.
final class LinksSourceMockTests: XCTestCase {
    private func source(_ links: [(String, String)], _ handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse)
        async throws -> (LinksSource, LinksMockTransport) {
        let transport = LinksMockTransport(handler)
        let source = LinksSource(transport: transport)
        for (title, address) in links { try await source.add(address, title: title) }
        return (source, transport)
    }

    private func page(_ status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "text/html; charset=utf-8"], body: Data("<html></html>".utf8))
    }

    func testListShowsLinksAsFilesInOneFolder() async throws {
        let (s, t) = try await source([("One.mkv", "https://a.example/1.mkv"), ("Two", "https://b.example/page")]) { _ in HTTPResponse(statusCode: 500) }
        let entries = try await s.list("/")
        XCTAssertEqual(entries.map(\.path), ["/One.mkv", "/Two"])
        XCTAssertTrue(entries.allSatisfy { !$0.isDirectory && $0.size == nil })
        XCTAssertTrue(t.requests.isEmpty, "listing never touches the network")
        do { _ = try await s.list("/One.mkv"); XCTFail("expected a throw") } catch {
            guard case SourceError.unsupported = error else { return XCTFail("\(error)") }
        }
        do { _ = try await s.list("/nothing"); XCTFail("expected a throw") } catch { XCTAssertEqual(error as? SourceError, .notFound) }
        try await s.authenticate()
    }

    func testInfoProbesWithHeadAndFillsTheEntry() async throws {
        let (s, t) = try await source([("One.mkv", "https://a.example/1.mkv")]) { request in
            HTTPResponse(statusCode: 200, headers: [
                "Content-Length": "5000", "Accept-Ranges": "bytes", "Content-Type": "video/x-matroska",
                "ETag": "\"abc\"", "Last-Modified": "Mon, 16 Nov 2026 10:00:00 GMT"
            ])
        }
        let info = try await s.info("/One.mkv")
        XCTAssertEqual(info.size, 5000)
        XCTAssertEqual(info.contentType, "video/x-matroska")
        XCTAssertEqual(info.etag, "\"abc\"")
        XCTAssertNotNil(info.modified)
        XCTAssertEqual(t.requests.map(\.method), ["HEAD"])
        let listed = try await s.list("/")
        XCTAssertEqual(listed.first?.size, 5000, "the probe result is kept for the list")
    }

    func testServerThatRefusesHeadGetsAOneByteRangedGet() async throws {
        let (s, t) = try await source([("One.mkv", "https://a.example/1.mkv")]) { request in
            if request.method == "HEAD" { return HTTPResponse(statusCode: 405) }
            XCTAssertEqual(request.headers["Range"], "bytes=0-0")
            return HTTPResponse(statusCode: 206, headers: ["Content-Range": "bytes 0-0/7777", "Content-Type": "video/mp4"], body: Data([1]))
        }
        let info = try await s.info("/One.mkv")
        XCTAssertEqual(info.size, 7777)
        XCTAssertEqual(t.requests.map(\.method), ["HEAD", "GET"])
    }

    func testUnadvertisedRangeSupportIsFoundByAskingForOneByte() async throws {
        let (s, _) = try await source([("One.mkv", "https://a.example/1.mkv")]) { request in
            if request.method == "HEAD" { return HTTPResponse(statusCode: 200, headers: ["Content-Length": "10"]) }
            return HTTPResponse(statusCode: 206, headers: ["Content-Range": "bytes 0-0/10"], body: Data([1]))
        }
        let probe = try await s.probe(URL(string: "https://a.example/1.mkv")!, provider: "x")
        XCTAssertTrue(probe.acceptsRanges)
        XCTAssertEqual(probe.size, 10)
    }

    func testServerThatIgnoresRangesIsReported() async throws {
        let (s, _) = try await source([("One.mkv", "https://a.example/1.mkv")]) { request in
            if request.method == "HEAD" { return HTTPResponse(statusCode: 200, headers: ["Content-Length": "10", "Accept-Ranges": "none"]) }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "video/mp4"], body: Data(repeating: 1, count: 10))
        }
        let probe = try await s.probe(URL(string: "https://a.example/1.mkv")!, provider: "x")
        XCTAssertFalse(probe.acceptsRanges)
        do { _ = try await s.read("/One.mkv", range: ByteRange(offset: 2, length: 4)); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? SourceError, .rangesNotSupported)
        }
    }

    func testWebPageIsATypedErrorNotPlayback() async throws {
        let (s, _) = try await source([("Share", "https://files.example/share/xyz")]) { _ in self.page() }
        do { _ = try await s.playbackAccess(for: "/Share"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .webPage(host: "files.example"))
            XCTAssertTrue((error as? LinkError)?.message.contains("web page") ?? false)
        }
        do { _ = try await s.info("/Share"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .webPage(host: "files.example"))
        }
    }

    func testWebPageOnReadIsRejectedToo() async throws {
        let (s, _) = try await source([("Share", "https://files.example/share/xyz.mkv")]) { _ in self.page(206) }
        do { _ = try await s.read("/Share", range: ByteRange(offset: 0, length: 4)); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .webPage(host: "files.example"))
        }
    }

    func testICloudAndFolderLinksNeverReachTheNetwork() async throws {
        let (s, t) = try await source([
            ("Cloud", "https://www.icloud.com/iclouddrive/0abc"),
            ("Folder", "https://www.dropbox.com/sh/abc/def?dl=0")
        ]) { _ in HTTPResponse(statusCode: 200) }
        do { _ = try await s.playbackAccess(for: "/Cloud"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .iCloudDriveShare)
        }
        do { _ = try await s.info("/Folder"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .folderLink(provider: "Dropbox"))
        }
        do { _ = try await s.read("/Cloud", range: ByteRange(offset: 0, length: 1)); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .iCloudDriveShare)
        }
        XCTAssertTrue(t.requests.isEmpty)
    }

    func testDropboxLinkIsConvertedBeforeProbing() async throws {
        let (s, t) = try await source([("Clip", "https://www.dropbox.com/s/abc/Clip.mp4?dl=0")]) { _ in
            HTTPResponse(statusCode: 200, headers: ["Accept-Ranges": "bytes", "Content-Length": "9", "Content-Type": "video/mp4"])
        }
        let access = try await s.playbackAccess(for: "/Clip")
        XCTAssertEqual(access, .url(URL(string: "https://www.dropbox.com/s/abc/Clip.mp4?dl=1")!, headers: [:]))
        XCTAssertEqual(t.requests.first?.url.absoluteString, "https://www.dropbox.com/s/abc/Clip.mp4?dl=1")
    }

    func testGoogleDriveAndOneDriveAreConvertedBeforeProbing() async throws {
        let (s, t) = try await source([
            ("G", "https://drive.google.com/file/d/ID123/view"),
            ("O", "https://1drv.ms/v/s!AbC")
        ]) { _ in HTTPResponse(statusCode: 200, headers: ["Accept-Ranges": "bytes", "Content-Type": "video/mp4"]) }
        _ = try await s.playbackAccess(for: "/G")
        _ = try await s.playbackAccess(for: "/O")
        let urls = t.requests.map(\.url.absoluteString)
        XCTAssertEqual(urls[0], "https://drive.google.com/uc?export=download&id=ID123")
        XCTAssertTrue(urls[1].hasPrefix("https://api.onedrive.com/v1.0/shares/u!"))
        XCTAssertTrue(urls[1].hasSuffix("/root/content"))
    }

    func testSignInResponsesAreNamedAfterTheProvider() async throws {
        let (s, _) = try await source([("O", "https://1drv.ms/v/s!AbC"), ("Plain", "https://host.example/x.mkv")]) { request in
            HTTPResponse(statusCode: request.url.host == "host.example" ? 403 : 401)
        }
        do { _ = try await s.info("/O"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .needsSignIn(provider: "OneDrive"))
        }
        do { _ = try await s.info("/Plain"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? LinkError, .needsSignIn(provider: "host.example"))
        }
    }

    func testStatusMapping() async throws {
        for (status, expected) in [(404, SourceError.notFound), (410, .notFound), (500, .httpStatus(500)), (503, .httpStatus(503))] {
            let (s, _) = try await source([("A", "https://a.example/a.mkv")]) { _ in HTTPResponse(statusCode: status) }
            do { _ = try await s.info("/A"); XCTFail("expected \(expected)") } catch { XCTAssertEqual(error as? SourceError, expected) }
        }
    }

    func testReadRangeMapping() async throws {
        for (status, expected) in [(416, SourceError.rangeNotSatisfiable), (404, .notFound), (500, .httpStatus(500))] {
            let (s, _) = try await source([("A", "https://a.example/a.mkv")]) { _ in HTTPResponse(statusCode: status) }
            do { _ = try await s.read("/A", range: ByteRange(offset: 0, length: 4)); XCTFail("expected \(expected)") } catch {
                XCTAssertEqual(error as? SourceError, expected)
            }
        }
        let (s, _) = try await source([("A", "https://a.example/a.mkv")]) { request in
            XCTAssertEqual(request.headers["Range"], "bytes=5-8")
            return HTTPResponse(statusCode: 206, headers: ["Content-Type": "video/mp4"], body: Data([1, 2, 3, 4, 5, 6]))
        }
        let data = try await s.read("/A", range: ByteRange(offset: 5, length: 4))
        XCTAssertEqual(data, Data([1, 2, 3, 4]))
        let none = try await s.read("/A", range: ByteRange(offset: 0, length: 0))
        XCTAssertTrue(none.isEmpty)
    }

    func testTransportFailureIsWrapped() async throws {
        struct Boom: Error {}
        let (s, _) = try await source([("A", "https://a.example/a.mkv")]) { _ in throw Boom() }
        do { _ = try await s.info("/A"); XCTFail("expected a throw") } catch {
            guard case SourceError.transport = error else { return XCTFail("\(error)") }
        }
    }

    func testProbeAllReportsEachFailureAndKeepsGoing() async throws {
        let (s, _) = try await source([("Good", "https://a.example/a.mkv"), ("Page", "https://b.example/p"), ("Cloud", "https://www.icloud.com/iclouddrive/x")]) { request in
            if request.url.host == "b.example" { return self.page() }
            return HTTPResponse(statusCode: 200, headers: ["Accept-Ranges": "bytes", "Content-Length": "3", "Content-Type": "video/mp4"])
        }
        let failures = await s.probeAll()
        XCTAssertEqual(failures.count, 2)
        let store = await s.currentStore
        XCTAssertEqual(failures[try XCTUnwrap(store.link(titled: "Page")?.id)] as? LinkError, .webPage(host: "b.example"))
        XCTAssertEqual(failures[try XCTUnwrap(store.link(titled: "Cloud")?.id)] as? LinkError, .iCloudDriveShare)
        let listed = try await s.list("/")
        XCTAssertEqual(listed.first { $0.name == "Good" }?.size, 3)
    }

    func testEditingTheListThroughTheSource() async throws {
        let (s, _) = try await source([("A", "https://a.example/a.mkv")]) { _ in HTTPResponse(statusCode: 200) }
        let b = try await s.add("https://a.example/b.mkv", title: "B")
        try await s.rename(id: b.id, to: "B2")
        var names = try await s.list("/").map(\.name)
        XCTAssertEqual(names, ["A", "B2"])
        await s.remove(id: b.id)
        names = try await s.list("/").map(\.name)
        XCTAssertEqual(names, ["A"])
        do { _ = try await s.info("/B2"); XCTFail("expected a throw") } catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testCapabilities() {
        let s = LinksSource(transport: LinksMockTransport { _ in HTTPResponse(statusCode: 200) })
        XCTAssertEqual(s.kind, .directLink)
        XCTAssertTrue(s.capabilities.directPlaybackURL)
        XCTAssertTrue(s.capabilities.byteRanges)
    }
}
