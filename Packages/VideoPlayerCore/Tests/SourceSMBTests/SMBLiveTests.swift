#if canImport(AMSMB2)
import XCTest
import VideoPlayerCore
@testable import SourceSMB

/// Runs against a real SMB server (impacket's smbserver, started by scripts/test-smb.sh) through AMSMB2.
/// Skipped (and reported as skipped) when VP_SMB_HOST is not set.
final class SMBLiveTests: XCTestCase {
    struct Env { var host: String; var port: Int; var share: String; var user: String; var pass: String }

    func env() throws -> Env {
        let e = ProcessInfo.processInfo.environment
        guard let host = e["VP_SMB_HOST"], let user = e["VP_SMB_USER"], let pass = e["VP_SMB_PASS"] else {
            throw XCTSkip("VP_SMB_HOST / VP_SMB_USER / VP_SMB_PASS not set (run scripts/test-smb.sh)")
        }
        return Env(host: host, port: Int(e["VP_SMB_PORT"] ?? "") ?? 445, share: e["VP_SMB_SHARE"] ?? "Media", user: user, pass: pass)
    }

    func client(password: String? = nil, user: String? = nil, guest: Bool = false) throws -> SMBClient {
        let env = try env()
        let configuration = SMBConfiguration(
            host: env.host, port: env.port,
            username: guest ? nil : (user ?? env.user), password: guest ? nil : (password ?? env.pass),
            timeout: 20
        )
        return SMBClient.amsmb2(configuration)
    }

    func expectedByte(_ offset: Int64) -> UInt8 { UInt8((offset * 7 + 3) % 251) }

    func assertPattern(_ data: Data, startingAt offset: Int64, file: StaticString = #filePath, line: UInt = #line) {
        for (i, byte) in data.enumerated() where byte != expectedByte(offset + Int64(i)) {
            XCTFail("byte \(offset + Int64(i)) is \(byte), expected \(expectedByte(offset + Int64(i)))", file: file, line: line)
            return
        }
    }

    func testAuthenticateAndListShares() async throws {
        let env = try env()
        let client = try client()
        try await client.authenticate()
        let shares = try await client.list("/")
        XCTAssertTrue(shares.contains { $0.name.caseInsensitiveCompare(env.share) == .orderedSame }, "shares: \(shares.map(\.name))")
        XCTAssertFalse(shares.contains { $0.name.hasSuffix("$") }, "admin shares are hidden")
    }

    func testListsTheTestLibrary() async throws {
        let env = try env()
        let client = try client()
        let top = try await client.list("/" + env.share)
        let names = Set(top.map(\.name))
        for expected in ["Movies", "Shows", "Odd Names", "big", "notes.txt"] {
            XCTAssertTrue(names.contains(expected), "\(expected) missing in \(names)")
        }
        let movies = try await client.list("/\(env.share)/Movies")
        XCTAssertTrue(movies.contains { $0.name == "Test Movie (2020).mkv" }, "\(movies.map(\.name))")
        let walked = try await client.walk("/" + env.share)
        XCTAssertTrue(walked.contains { $0.name == "Large Sample.mkv" })
        XCTAssertTrue(walked.contains { $0.path.hasSuffix("Season 1") && $0.isDirectory })
    }

    func testInfoReportsSizeAndModifiedDate() async throws {
        let env = try env()
        let client = try client()
        let entry = try await client.info("/\(env.share)/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(entry.size, 3_145_728)
        XCTAssertFalse(entry.isDirectory)
        XCTAssertNotNil(entry.modified)
        let folder = try await client.info("/\(env.share)/Movies")
        XCTAssertTrue(folder.isDirectory)
        let share = try await client.info("/\(env.share)")
        XCTAssertTrue(share.isDirectory)
        do {
            _ = try await client.info("/\(env.share)/Movies/missing.mkv")
            XCTFail("expected notFound")
        } catch { XCTAssertEqual(error as? SourceError, .notFound, "\(error)") }
    }

    func testUnicodeAndSpecialCharactersInNames() async throws {
        let env = try env()
        let client = try client()
        let list = try await client.list("/\(env.share)/Odd Names")
        XCTAssertTrue(list.contains { $0.name == "Café – 100% [test] #1.mp4" }, "\(list.map(\.name))")
        let entry = try await client.info("/\(env.share)/Odd Names/Café – 100% [test] #1.mp4")
        XCTAssertGreaterThan(entry.size ?? 0, 0)
        let head = try await client.read(entry.path, range: ByteRange(offset: 0, length: 64))
        assertPattern(head, startingAt: 0)
    }

    func testRangedReadsMatchThePattern() async throws {
        let env = try env()
        let client = try client()
        let path = "/\(env.share)/Movies/Test Movie (2020).mkv"
        for (offset, length) in [(0, 1), (0, 4096), (1, 100), (65_535, 70_000), (1_000_000, 1_048_576), (3_145_000, 728)] as [(Int64, Int64)] {
            let data = try await client.read(path, range: ByteRange(offset: offset, length: length))
            XCTAssertEqual(Int64(data.count), length, "offset \(offset)")
            assertPattern(data, startingAt: offset)
        }
        let tail = try await client.read(path, range: ByteRange(offset: 3_145_700, length: 1000))
        XCTAssertEqual(tail.count, 28, "short only at the end of the file")
        assertPattern(tail, startingAt: 3_145_700)
    }

    func testSeekingPastTheEndIsRangeNotSatisfiable() async throws {
        let env = try env()
        let client = try client()
        let path = "/\(env.share)/Movies/Test Movie (2020).mkv"
        for offset: Int64 in [3_145_728, 10_000_000] {
            do {
                _ = try await client.read(path, range: ByteRange(offset: offset, length: 10))
                XCTFail("expected rangeNotSatisfiable at \(offset)")
            } catch { XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable, "\(error)") }
        }
    }

    func testWrongPasswordIsUnauthorized() async throws {
        let bad = try client(password: "definitely-wrong")
        do {
            try await bad.authenticate()
            XCTFail("expected unauthorized")
        } catch { XCTAssertEqual(error as? SourceError, .unauthorized, "\(error)") }
        let unknown = try client(password: "x", user: "nobody-here")
        do {
            _ = try await unknown.list("/")
            XCTFail("expected unauthorized")
        } catch { XCTAssertEqual(error as? SourceError, .unauthorized, "\(error)") }
    }

    func testGuestAccessIsRefusedByThisServer() async throws {
        // The test server only knows one user, so guest must be refused (not silently allowed).
        let guest = try client(guest: true)
        do {
            try await guest.authenticate()
            XCTFail("guest unexpectedly accepted")
        } catch { XCTAssertEqual(error as? SourceError, .unauthorized, "\(error)") }
    }

    func testReconnectAfterDisconnect() async throws {
        let env = try env()
        let client = try client()
        let path = "/\(env.share)/Movies/Test Movie (2020).mkv"
        let first = try await client.read(path, range: ByteRange(offset: 100, length: 50))
        await client.disconnect()
        let second = try await client.read(path, range: ByteRange(offset: 100, length: 50))
        XCTAssertEqual(first, second)
        assertPattern(second, startingAt: 100)
    }

    func testPlaybackAccessIsByteReader() async throws {
        let env = try env()
        let client = try client()
        let access = try await client.playbackAccess(for: "/\(env.share)/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(access, .byteReader)
    }

    func testReadsAFortyMegabyteFileSequentially() async throws {
        let env = try env()
        let client = try client()
        let path = "/\(env.share)/big/Large Sample.mkv"
        let size: Int64 = 41_943_040
        let entry = try await client.info(path)
        XCTAssertEqual(entry.size, size)
        var offset: Int64 = 0
        let chunk: Int64 = 1_048_576
        var total: Int64 = 0
        while offset < size {
            let data = try await client.read(path, range: ByteRange(offset: offset, length: chunk))
            XCTAssertEqual(Int64(data.count), min(chunk, size - offset), "chunk at \(offset)")
            assertPattern(data, startingAt: offset)
            total += Int64(data.count)
            offset += chunk
        }
        XCTAssertEqual(total, size)
    }
}
#endif
