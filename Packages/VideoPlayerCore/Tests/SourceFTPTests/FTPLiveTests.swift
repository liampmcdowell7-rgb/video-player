import XCTest
import VideoPlayerCore
@testable import SourceFTP

/// Runs against the rclone FTP server from `scripts/test-servers.sh` (plain FTP, read-only).
/// Use `bash scripts/test-live.sh ftp --filter SourceFTPTests`. Without the environment variables the
/// tests are reported as skipped, never as passed.
final class FTPLiveTests: XCTestCase {
    private struct Env { var host: String; var port: Int; var user: String; var pass: String }

    private func env() throws -> Env {
        let e = ProcessInfo.processInfo.environment
        guard let host = e["VP_FTP_HOST"], let portText = e["VP_FTP_PORT"], let port = Int(portText),
              let user = e["VP_TEST_USER"], let pass = e["VP_TEST_PASS"] else {
            throw XCTSkip("VP_FTP_* not set: run through scripts/test-live.sh")
        }
        return Env(host: host, port: port, user: user, pass: pass)
    }

    private func makeClient(password: String? = nil) throws -> FTPClient {
        let e = try env()
        return FTPClient(host: e.host, port: e.port, credentials: .init(username: e.user, password: password ?? e.pass), connector: makeDefaultFTPConnector())
    }

    private let movie = "/Movies/Test Movie (2020).mkv"

    func testAuthenticate() async throws {
        try await makeClient().authenticate()
    }

    func testWrongPasswordIsUnauthorized() async throws {
        let c = try makeClient(password: "definitely-wrong")
        do { try await c.authenticate(); XCTFail("expected unauthorized") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testListRootAndFolders() async throws {
        let c = try makeClient()
        let root = try await c.list("/")
        let names = Set(root.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["Movies", "Shows", "Odd Names", "big", "notes.txt"]), "got \(names)")
        XCTAssertTrue(root.first { $0.name == "Movies" }!.isDirectory)
        XCTAssertEqual(root.first { $0.name == "notes.txt" }?.isDirectory, false)

        let movies = try await c.list("/Movies")
        XCTAssertEqual(Set(movies.map(\.name)), ["Test Movie (2020).mkv", "Test Movie (2020).en.srt"])
        XCTAssertEqual(movies.first { $0.name == "Test Movie (2020).mkv" }?.size, 3_145_728)
        XCTAssertEqual(movies.first { $0.name == "Test Movie (2020).en.srt" }?.size, 2048)

        let season = try await c.list("/Shows/Test Show (2019)/Season 1")
        XCTAssertEqual(season.count, 2)
        XCTAssertTrue(season.allSatisfy { $0.size == 1_048_576 })
    }

    func testWalkFindsEveryFile() async throws {
        let all = try await makeClient().walk("/")
        let files = all.filter { !$0.isDirectory }.map(\.name)
        XCTAssertTrue(files.contains("Large Sample.mkv"))
        XCTAssertTrue(files.contains("Test Show - S01E02.mkv"))
        XCTAssertTrue(files.contains("Café – 100% [test] #1.mp4"))
    }

    func testInfoForFileFolderAndMissing() async throws {
        let c = try makeClient()
        let file = try await c.info(movie)
        XCTAssertEqual(file.size, 3_145_728)
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.name, "Test Movie (2020).mkv")
        XCTAssertNotNil(file.modified)
        let folder = try await c.info("/Movies")
        XCTAssertTrue(folder.isDirectory)
        do { _ = try await c.info("/Movies/ghost.mkv"); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testUnicodeAndSpecialCharacterNames() async throws {
        let c = try makeClient()
        let entry = try await c.info("/Odd Names/Café – 100% [test] #1.mp4")
        XCTAssertEqual(entry.size, 4096)
        let bytes = try await c.read(entry.path, range: ByteRange(offset: 100, length: 64))
        XCTAssertEqual(bytes, patternBytes(offset: 100, count: 64))
    }

    func testRangedReadsReturnThePatternAtEveryOffset() async throws {
        let c = try makeClient()
        for (offset, length) in [(0, 1), (0, 4096), (1, 1000), (999, 2), (65_535, 65_537), (1_000_003, 777), (3_145_728 - 100, 100)] {
            let bytes = try await c.read(movie, range: ByteRange(offset: Int64(offset), length: Int64(length)))
            XCTAssertEqual(bytes.count, length, "offset \(offset)")
            XCTAssertEqual(bytes, patternBytes(offset: offset, count: length), "offset \(offset)")
        }
    }

    func testReadShortAtTheEnd() async throws {
        let c = try makeClient()
        let bytes = try await c.read(movie, range: ByteRange(offset: 3_145_728 - 10, length: 1000))
        XCTAssertEqual(bytes, patternBytes(offset: 3_145_728 - 10, count: 10))
    }

    func testSeekPastTheEnd() async throws {
        let c = try makeClient()
        do { _ = try await c.read(movie, range: ByteRange(offset: 3_145_728 + 5000, length: 100)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable) }
        // The connection is still usable afterwards.
        let ok = try await c.read(movie, range: ByteRange(offset: 10, length: 10))
        XCTAssertEqual(ok, patternBytes(offset: 10, count: 10))
    }

    func testReadMissingFileIsNotFound() async throws {
        let c = try makeClient()
        do { _ = try await c.read("/Movies/ghost.mkv", range: ByteRange(offset: 0, length: 10)); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testManySeeksOnOneConnection() async throws {
        let c = try makeClient()
        var offset = 17
        for _ in 0..<30 {
            offset = (offset * 31 + 7) % 3_000_000
            let bytes = try await c.read(movie, range: ByteRange(offset: Int64(offset), length: 2048))
            XCTAssertEqual(bytes, patternBytes(offset: offset, count: 2048), "offset \(offset)")
        }
    }

    func testConcurrentReads() async throws {
        let c = try makeClient()
        let path = movie
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<6 {
                group.addTask {
                    let offset = i * 400_000 + 13
                    let bytes = try await c.read(path, range: ByteRange(offset: Int64(offset), length: 5000))
                    XCTAssertEqual(bytes, patternBytes(offset: offset, count: 5000), "task \(i)")
                }
            }
            try await group.waitForAll()
        }
    }

    func testSequentialReadOfTheFortyMegabyteFile() async throws {
        let c = try makeClient()
        let path = "/big/Large Sample.mkv"
        let size: Int64 = 41_943_040
        let info = try await c.info(path)
        XCTAssertEqual(info.size, size)
        let chunk: Int64 = 4 * 1024 * 1024
        var offset: Int64 = 0
        var total: Int64 = 0
        var readSeconds = 0.0
        while offset < size {
            let started = Date()
            let bytes = try await c.read(path, range: ByteRange(offset: offset, length: chunk))
            readSeconds += Date().timeIntervalSince(started)
            XCTAssertEqual(Int64(bytes.count), min(chunk, size - offset), "chunk at \(offset)")
            // Verify the whole chunk, not a sample.
            XCTAssertEqual(bytes, patternBytes(offset: Int(offset), count: bytes.count), "pattern at \(offset)")
            offset += Int64(bytes.count)
            total += Int64(bytes.count)
        }
        XCTAssertEqual(total, size)
        print("FTP sequential read: \(size) bytes, time spent inside read(): \(String(format: "%.2f", readSeconds)) s (debug build; pattern checking excluded)")
    }

    func testReconnectsAfterTheServerSideConnectionIsGone() async throws {
        let c = try makeClient()
        try await c.authenticate()
        // authenticate() again replaces the connection; reads work on the new one.
        try await c.authenticate()
        let bytes = try await c.read(movie, range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(bytes, patternBytes(offset: 0, count: 16))
    }
}
