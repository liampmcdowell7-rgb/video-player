import XCTest
import Foundation
import VideoPlayerCore
@testable import SourceUPnP

/// Runs against a real `rclone serve dlna`. Needs VP_DLNA_URL, which `bash scripts/test-live.sh upnp` sets.
/// Without it these tests are SKIPPED (and reported as skipped, never as passed).
final class UPnPLiveTests: XCTestCase {
    private func descriptionURL() throws -> URL {
        guard let base = ProcessInfo.processInfo.environment["VP_DLNA_URL"], !base.isEmpty else {
            throw XCTSkip("VP_DLNA_URL is not set; run through scripts/test-live.sh")
        }
        let root = base.hasSuffix("/") ? base : base + "/"
        return try XCTUnwrap(URL(string: root + "rootDesc.xml"))
    }

    private func client(pageSize: Int = 100) throws -> UPnPClient {
        let url = try descriptionURL()
        return UPnPClient(deviceURL: url, transport: URLSessionTransport())
    }

    /// The test servers' media bytes: byte k is (k * 7 + 3) % 251.
    private func expected(offset: Int64, count: Int) -> Data {
        Data((0..<count).map { UInt8(((offset + Int64($0)) * 7 + 3) % 251) })
    }

    func testAuthenticateReadsTheRealDescription() async throws {
        let c = try client()
        try await c.authenticate()
        let name = await c.friendlyName
        XCTAssertEqual(name, "VP Test Media")
    }

    func testRootListsTheTestFolders() async throws {
        let c = try client()
        let root = try await c.list("/")
        let folders = Set(root.filter(\.isDirectory).map(\.name))
        XCTAssertTrue(folders.isSuperset(of: ["Movies", "Shows", "Odd Names", "big"]), "\(folders)")
    }

    func testWalkFindsEveryVideoWithItsRealSize() async throws {
        let c = try client()
        let all = try await c.walk("/")
        let sizes = Dictionary(all.filter { !$0.isDirectory }.compactMap { e in e.size.map { (e.path, $0) } }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(sizes["/Movies/Test Movie (2020).mkv"], 3_145_728)
        XCTAssertEqual(sizes["/Shows/Test Show (2019)/Season 1/Test Show - S01E01 - Pilot.mkv"], 1_048_576)
        XCTAssertEqual(sizes["/Shows/Test Show (2019)/Season 1/Test Show - S01E02.mkv"], 1_048_576)
        XCTAssertEqual(sizes["/big/Large Sample.mkv"], 41_943_040)
        XCTAssertNotNil(all.first { $0.path == "/Movies/Test Movie (2020).en.srt" }, "the subtitle resource shows up as a sibling")
    }

    func testOddNamesSurvive() async throws {
        let c = try client()
        let entries = try await c.list("/Odd Names")
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.name, "Café – 100% [test] #1.mp4")
        XCTAssertEqual(entry.size, 4096)
        let bytes = try await c.read(entry.path, range: ByteRange(offset: 0, length: 64))
        XCTAssertEqual(bytes, expected(offset: 0, count: 64))
    }

    func testRangeReadsReturnTheRightBytes() async throws {
        let c = try client()
        let path = "/Movies/Test Movie (2020).mkv"
        let middle = try await c.read(path, range: ByteRange(offset: 1_000_000, length: 4096))
        XCTAssertEqual(middle, expected(offset: 1_000_000, count: 4096))
        let tail = try await c.read(path, range: ByteRange(offset: 3_145_728 - 100, length: 500))
        XCTAssertEqual(tail, expected(offset: 3_145_628, count: 100), "fewer bytes only at the end of the file")
    }

    func testReadBeyondTheEndIsNotSatisfiable() async throws {
        let c = try client()
        do {
            _ = try await c.read("/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 10_000_000, length: 10))
            XCTFail("expected a throw")
        } catch { XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable) }
    }

    func testPlaybackURLWorksWithARangeRequest() async throws {
        let c = try client()
        let access = try await c.playbackAccess(for: "/Shows/Test Show (2019)/Season 1/Test Show - S01E02.mkv")
        guard case .url(let url, let headers) = access else { return XCTFail("expected a URL") }
        let response = try await URLSessionTransport().send(
            HTTPRequest(url: url, method: "GET", headers: headers.merging(["Range": "bytes=100-131"]) { a, _ in a }))
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(response.body, expected(offset: 100, count: 32))
    }

    func testPagingOneAtATimeGivesTheSameListing() async throws {
        let whole = try await client().list("/")
        let url = try descriptionURL()
        let paged = try await UPnPClient(deviceURL: url, transport: URLSessionTransport(), pageSize: 1).list("/")
        XCTAssertEqual(paged, whole)
        XCTAssertGreaterThanOrEqual(whole.count, 4)
    }

    func testMissingFolderIsNotFound() async throws {
        let c = try client()
        do { _ = try await c.list("/does not exist"); XCTFail("expected a throw") } catch {
            XCTAssertEqual(error as? SourceError, .notFound)
        }
    }

    func testWrongAddressFailsWithATypedError() async throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:1/rootDesc.xml"))
        let c = UPnPClient(deviceURL: url, transport: URLSessionTransport(timeout: 3))
        do { try await c.authenticate(); XCTFail("expected a throw") } catch {
            guard case SourceError.transport = error else { return XCTFail("\(error)") }
        }
    }
}
