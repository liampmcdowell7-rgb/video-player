import XCTest
import Foundation
import VideoPlayerCore
@testable import SourceLinks

/// Runs against a real `rclone serve http`. Needs VP_HTTP_URL, which `bash scripts/test-live.sh links` sets.
/// Without it these tests are SKIPPED (and reported as skipped, never as passed).
final class LinksLiveTests: XCTestCase {
    private func base() throws -> String {
        guard let value = ProcessInfo.processInfo.environment["VP_HTTP_URL"], !value.isEmpty else {
            throw XCTSkip("VP_HTTP_URL is not set; run through scripts/test-live.sh")
        }
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    private func source(_ links: [(String, String)]) async throws -> LinksSource {
        let s = LinksSource(transport: URLSessionTransport())
        let root = try base()
        for (title, path) in links { try await s.add(root + path, title: title) }
        return s
    }

    /// The test servers' media bytes: byte k is (k * 7 + 3) % 251.
    private func expected(offset: Int64, count: Int) -> Data {
        Data((0..<count).map { UInt8(((offset + Int64($0)) * 7 + 3) % 251) })
    }

    private let movie = "/Movies/Test%20Movie%20(2020).mkv"

    func testProbeOfARealFile() async throws {
        let s = try await source([("Movie", movie)])
        let info = try await s.info("/Movie")
        XCTAssertEqual(info.size, 3_145_728)
        XCTAssertNotNil(info.modified)
        XCTAssertNotNil(info.contentType)
        let probe = try await s.probe(URL(string: try base() + movie)!, provider: "test")
        XCTAssertTrue(probe.acceptsRanges, "rclone serve http supports byte ranges")
        XCTAssertEqual(probe.size, 3_145_728)
    }

    func testRangeReads() async throws {
        let s = try await source([("Movie", movie)])
        let middle = try await s.read("/Movie", range: ByteRange(offset: 1_000_000, length: 4096))
        XCTAssertEqual(middle, expected(offset: 1_000_000, count: 4096))
        let tail = try await s.read("/Movie", range: ByteRange(offset: 3_145_728 - 100, length: 500))
        XCTAssertEqual(tail, expected(offset: 3_145_628, count: 100))
    }

    func testReadBeyondTheEnd() async throws {
        let s = try await source([("Movie", movie)])
        do { _ = try await s.read("/Movie", range: ByteRange(offset: 99_000_000, length: 10)); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable)
        }
    }

    func testPlaybackAccessGivesAWorkingURL() async throws {
        let s = try await source([("Movie", movie)])
        let access = try await s.playbackAccess(for: "/Movie")
        guard case .url(let url, let headers) = access else { return XCTFail("expected a URL") }
        let response = try await URLSessionTransport().send(HTTPRequest(url: url, method: "GET", headers: ["Range": "bytes=10-41"].merging(headers) { a, _ in a }))
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.body, expected(offset: 10, count: 32))
    }

    func testOddNameAndAFileWithoutAMediaExtension() async throws {
        let s = try await source([("Odd", "/Odd%20Names/Caf%C3%A9%20%E2%80%93%20100%25%20%5Btest%5D%20%231.mp4"), ("Notes", "/notes.txt")])
        let odd = try await s.info("/Odd")
        XCTAssertEqual(odd.size, 4096)
        let bytes = try await s.read("/Odd", range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(bytes, expected(offset: 0, count: 16))
        let notes = try await s.info("/Notes")   // kind .unknown: only the probe tells it serves bytes
        XCTAssertNotNil(notes.size)
    }

    func testFolderAddressIsAWebPage() async throws {
        let s = try await source([("Folder", "/Movies/")])
        do { _ = try await s.playbackAccess(for: "/Folder"); XCTFail("expected a throw") } catch {
            guard case LinkError.webPage = error else { return XCTFail("\(error)") }
        }
    }

    func testMissingFileIsNotFound() async throws {
        let s = try await source([("Gone", "/Movies/missing.mkv")])
        do { _ = try await s.info("/Gone"); XCTFail("expected a throw") } catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testProbeAllWithGoodAndBadLinks() async throws {
        let s = try await source([("Movie", movie), ("Gone", "/nope.mkv"), ("Folder", "/Shows/")])
        let failures = await s.probeAll()
        XCTAssertEqual(failures.count, 2)
        let listed = try await s.list("/")
        XCTAssertEqual(listed.first { $0.name == "Movie" }?.size, 3_145_728)
    }

    func testNothingListeningIsATransportError() async throws {
        let s = LinksSource(transport: URLSessionTransport(timeout: 3))
        try await s.add("http://127.0.0.1:1/a.mkv", title: "A")
        do { _ = try await s.info("/A"); XCTFail("expected a throw") } catch {
            guard case SourceError.transport = error else { return XCTFail("\(error)") }
        }
    }
}
