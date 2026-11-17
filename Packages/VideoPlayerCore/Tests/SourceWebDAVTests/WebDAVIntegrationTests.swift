import XCTest
@testable import VideoPlayerCore
@testable import SourceWebDAV

/// Runs against a real WebDAV server (rclone) started by `scripts/test-servers.sh`.
/// Skipped when the VP_* variables are absent, so plain `swift test` stays green everywhere.
/// Run with: bash scripts/test-integration.sh
final class WebDAVIntegrationTests: XCTestCase {
    private func env(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("\(name) not set; start the servers with scripts/test-servers.sh")
        }
        return value
    }

    // Read the variables first and on their own: XCTUnwrap would turn an XCTSkip thrown inside it into a failure.
    private func openClient() throws -> WebDAVClient {
        let text = try env("VP_WEBDAV_URL")
        let url = try XCTUnwrap(URL(string: text))
        return WebDAVClient(baseURL: url, credentials: nil, transport: URLSessionTransport())
    }

    private func basicClient(password: String? = nil, allowHTTP: Bool = true) throws -> WebDAVClient {
        let text = try env("VP_WEBDAV_BASIC_URL")
        let user = try env("VP_TEST_USER")
        let pass = try password ?? env("VP_TEST_PASS")
        let url = try XCTUnwrap(URL(string: text))
        return WebDAVClient(
            baseURL: url,
            credentials: WebDAVCredentials(username: user, password: pass),
            transport: URLSessionTransport(),
            allowBasicOverHTTP: allowHTTP)
    }

    /// Test files hold byte (offset * 7 + 3) mod 251 at every offset.
    private func expected(offset: Int64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8(((offset + Int64($0)) * 7 + 3) % 251) }
    }

    func testListsTheRootAndNestedFolders() async throws {
        let client = try openClient()
        try await client.authenticate()
        let root = try await client.list("/")
        XCTAssertTrue(Set(root.map(\.name)).isSuperset(of: ["Movies", "Shows", "Odd Names", "big", "notes.txt"]), "\(root.map(\.name))")
        let episodes = try await client.list("/Shows/Test Show (2019)/Season 1")
        XCTAssertEqual(episodes.map(\.name).sorted(), ["Test Show - S01E01 - Pilot.mkv", "Test Show - S01E02.mkv"])
    }

    func testSpecialCharactersInNamesSurviveARoundTrip() async throws {
        let client = try openClient()
        let odd = try await client.list("/Odd Names")
        let entry = try XCTUnwrap(odd.first)
        XCTAssertEqual(entry.name, "Caf\u{00E9} \u{2013} 100% [test] #1.mp4")
        let again = try await client.info(entry.path)
        XCTAssertEqual(again.size, 4096)
        let data = try await client.read(entry.path, range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(Array(data), expected(offset: 0, count: 16))
    }

    func testInfoAndRangedReadsAtArbitraryOffsets() async throws {
        let client = try openClient()
        let path = "/Movies/Test Movie (2020).mkv"
        let info = try await client.info(path)
        XCTAssertEqual(info.size, 3_145_728)
        XCTAssertFalse(info.isDirectory)

        for (offset, length) in [(0, 64), (1_000, 500), (1_048_576, 4_096), (3_145_728 - 100, 100)] as [(Int64, Int)] {
            let data = try await client.read(path, range: ByteRange(offset: offset, length: Int64(length)))
            XCTAssertEqual(Array(data), expected(offset: offset, count: length), "offset \(offset)")
        }
        // A range that runs past the end returns only what exists.
        let tail = try await client.read(path, range: ByteRange(offset: 3_145_728 - 10, length: 100))
        XCTAssertEqual(tail.count, 10)
    }

    func testSeekPastTheEndIsRangeNotSatisfiable() async throws {
        let client = try openClient()
        do {
            _ = try await client.read("/Movies/Test Movie (2020).mkv", range: ByteRange(offset: 10_000_000, length: 10))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable)
        }
    }

    func testMissingFileIsNotFound() async throws {
        let client = try openClient()
        do { _ = try await client.info("/nope.mkv"); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testSustainedSequentialReadOfALargeFile() async throws {
        let client = try openClient()
        let path = "/big/Large Sample.mkv"
        let size = try await client.info(path).size ?? 0
        XCTAssertEqual(size, 41_943_040)
        let chunk: Int64 = 1_048_576
        var offset: Int64 = 0
        let start = Date()
        while offset < size {
            let data = try await client.read(path, range: ByteRange(offset: offset, length: min(chunk, size - offset)))
            XCTAssertEqual(data.first, expected(offset: offset, count: 1)[0])
            offset += Int64(data.count)
            if data.isEmpty { break }
        }
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(offset, size)
        print("WebDAV loopback sequential read: \(size / 1_000_000) MB in \(String(format: "%.2f", seconds)) s (not a network measurement)")
    }

    func testBasicAuthentication() async throws {
        let good = try basicClient()
        try await good.authenticate()
        let entries = try await good.list("/")
        XCTAssertFalse(entries.isEmpty)

        let bad = try basicClient(password: "wrong")
        do { try await bad.authenticate(); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testBasicOverPlainHTTPIsRefusedByDefault() async throws {
        let client = try basicClient(allowHTTP: false)
        do { try await client.authenticate(); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .insecureBasicAuthentication) }
    }

    func testPlaybackAccessProducesAURLThatPlaysWithTheHeader() async throws {
        let client = try basicClient()
        let access = try await client.playbackAccess(for: "/Movies/Test Movie (2020).mkv")
        guard case let .url(url, headers) = access else { return XCTFail("expected a URL, got \(access)") }
        XCTAssertNotNil(headers["Authorization"])
        var request = HTTPRequest(url: url, method: "GET", headers: headers)
        request.headers["Range"] = "bytes=2000-2015"
        let response = try await URLSessionTransport().send(request)
        XCTAssertEqual(response.statusCode, 206)
        XCTAssertEqual(Array(response.body), expected(offset: 2000, count: 16))
        XCTAssertEqual(response.header("accept-ranges")?.lowercased(), "bytes")
    }

    func testChangeDetectionOnARealServer() async throws {
        let client = try openClient()
        let first = try await client.info("/Movies/Test Movie (2020).mkv")
        let second = try await client.info("/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(client.hasChanged(first.version, comparedTo: second), false)
        XCTAssertEqual(client.hasChanged(FileVersion(modified: Date(timeIntervalSince1970: 1), size: first.size), comparedTo: second), true)
    }
}
