import XCTest
import VideoPlayerCore
import SourceNFS

/// Runs against a real NFSv3 server through the real libnfs. Needs:
///   VP_NFS_HOST (and VP_NFS_PORT when the server is not on the portmapper), VP_NFS_EXPORT (default "/")
/// and a build with libnfs available (`bash scripts/test-nfs.sh` sets all of this up on Linux).
/// Without them every test here is reported as SKIPPED, never as passed.
/// Test data comes from scripts/test-servers.sh: byte at offset k = (k*7+3) % 251.
final class NFSLiveTests: XCTestCase {
    private static let notLinked = "libnfs is not linked in this build (no CLibnfs module); run bash scripts/test-nfs.sh"

    private func makeSource(export: String? = nil, backend: NFSBackend? = nil) throws -> NFSSource {
        let env = ProcessInfo.processInfo.environment
        guard let libnfs = backend ?? NFSBackends.libnfs() else { throw XCTSkip(Self.notLinked) }
        guard let host = env["VP_NFS_HOST"], !host.isEmpty else {
            throw XCTSkip("VP_NFS_HOST is not set; start a server with scripts/test-nfs.sh")
        }
        let config = NFSConfiguration(
            host: host,
            exportPath: export ?? env["VP_NFS_EXPORT"] ?? "/",
            port: env["VP_NFS_PORT"].flatMap { Int($0) },
            timeoutMilliseconds: 5_000
        )
        return NFSSource(configuration: config, backend: libnfs)
    }

    private static func pattern(_ offset: Int64, _ count: Int) -> [UInt8] {
        (0..<count).map { UInt8((((offset + Int64($0)) * 7) + 3) % 251) }
    }

    func testMountAndListRoot() async throws {
        let source = try makeSource()
        try await source.authenticate()
        let names = try await source.list("/").map(\.name)
        for expected in ["Movies", "Shows", "Odd Names", "big", "notes.txt"] {
            XCTAssertTrue(names.contains(expected), "\(expected) missing from \(names)")
        }
        XCTAssertFalse(names.contains("."))
        XCTAssertFalse(names.contains(".."))
    }

    func testNestedFolderWalk() async throws {
        let source = try makeSource()
        let all = try await source.walk("/")
        let paths = Set(all.map(\.path))
        XCTAssertTrue(paths.contains("/Shows/Test Show (2019)/Season 1/Test Show - S01E01 - Pilot.mkv"), "\(paths)")
        XCTAssertTrue(paths.contains("/Movies/Test Movie (2020).en.srt"))
        let folder = try XCTUnwrap(all.first { $0.path == "/Shows" })
        XCTAssertTrue(folder.isDirectory)
    }

    func testUnicodeAndPunctuationNames() async throws {
        let source = try makeSource()
        let entries = try await source.list("/Odd Names")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.name, "Café – 100% [test] #1.mp4")
        let again = try await source.info(entry.path)
        XCTAssertEqual(again.size, entry.size)
        let bytes = try await source.read(entry.path, range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(Array(bytes), Self.pattern(0, 16))
    }

    func testInfoGivesSizeAndModifiedTime() async throws {
        let source = try makeSource()
        let info = try await source.info("/big/Large Sample.mkv")
        XCTAssertEqual(info.size, 41_943_040)
        XCTAssertFalse(info.isDirectory)
        let modified = try XCTUnwrap(info.modified)
        XCTAssertGreaterThan(modified.timeIntervalSince1970, 1_500_000_000)
        let root = try await source.info("/")
        XCTAssertTrue(root.isDirectory)
    }

    func testRangedReadsMatchThePattern() async throws {
        let source = try makeSource()
        let path = "/big/Large Sample.mkv"
        for (offset, length) in [(0, 64), (1_000, 4_096), (1_048_593, 65_536), (20_000_001, 1_000_000), (41_943_040 - 64, 64)] as [(Int64, Int64)] {
            let data = try await source.read(path, range: ByteRange(offset: offset, length: length))
            XCTAssertEqual(Int64(data.count), length, "offset \(offset)")
            XCTAssertEqual(Array(data.prefix(64)), Self.pattern(offset, 64), "offset \(offset)")
            XCTAssertEqual(Array(data.suffix(64)), Self.pattern(offset + length - 64, 64), "tail at \(offset)")
        }
    }

    func testReadLargerThanOneChunkIsContinuous() async throws {
        let source = try makeSource()
        let length: Int64 = 9_000_000   // more than two 4 MiB pieces
        let data = try await source.read("/big/Large Sample.mkv", range: ByteRange(offset: 7, length: length))
        XCTAssertEqual(Int64(data.count), length)
        var mismatches = 0
        for k in stride(from: 0, to: data.count, by: 997) where data[k] != Self.pattern(7 + Int64(k), 1)[0] { mismatches += 1 }
        XCTAssertEqual(mismatches, 0)
    }

    func testReadAcrossEndOfFileIsShort() async throws {
        let source = try makeSource()
        let data = try await source.read("/big/Large Sample.mkv", range: ByteRange(offset: 41_943_040 - 10, length: 100))
        XCTAssertEqual(data.count, 10)
        XCTAssertEqual(Array(data), Self.pattern(41_943_040 - 10, 10))
        let past = try await source.read("/big/Large Sample.mkv", range: ByteRange(offset: 41_943_040, length: 10))
        XCTAssertTrue(past.isEmpty)
    }

    func testMissingFileIsNotFound() async throws {
        let source = try makeSource()
        do { _ = try await source.info("/does-not-exist.mkv"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
        do { _ = try await source.read("/does-not-exist.mkv", range: ByteRange(offset: 0, length: 4)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
        do { _ = try await source.list("/does-not-exist"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testUnknownExportIsRefused() async throws {
        let source = try makeSource(export: "/this-export-does-not-exist")
        do { try await source.authenticate(); XCTFail("mounting a missing export must fail") }
        catch { XCTAssertNotNil(error as? SourceError, "\(error)") }
    }

    func testDroppedConnectionReconnects() async throws {
        guard let backend = NFSBackends.libnfs() else { throw XCTSkip(Self.notLinked) }
        let source = try makeSource(backend: backend)
        let first = try await source.read("/big/Large Sample.mkv", range: ByteRange(offset: 0, length: 32))
        await backend.unmount()   // the connection is gone as far as the source can tell
        let second = try await source.read("/big/Large Sample.mkv", range: ByteRange(offset: 32, length: 32))
        XCTAssertEqual(Array(first), Self.pattern(0, 32))
        XCTAssertEqual(Array(second), Self.pattern(32, 32))
    }

    func testAuthenticateTwiceIsFine() async throws {
        let source = try makeSource()
        try await source.authenticate()
        try await source.authenticate()
        let names = try await source.list("/").map(\.name)
        XCTAssertTrue(names.contains("Movies"))
    }

    func testParallelReadsAreAllCorrect() async throws {
        let source = try makeSource()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for i in 0..<12 {
                group.addTask {
                    let offset = Int64(i) * 3_000_017
                    let data = try await source.read("/big/Large Sample.mkv", range: ByteRange(offset: offset, length: 8_192))
                    return Array(data.prefix(32)) == Self.pattern(offset, 32) && data.count == 8_192
                }
            }
            for try await ok in group { XCTAssertTrue(ok) }
        }
    }

    func testPlaybackAccessIsByteReader() async throws {
        let source = try makeSource()
        let access = try await source.playbackAccess(for: "/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(access, .byteReader)
    }
}
