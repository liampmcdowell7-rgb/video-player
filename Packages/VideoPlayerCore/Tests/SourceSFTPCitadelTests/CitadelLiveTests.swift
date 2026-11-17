import XCTest
import VideoPlayerCore
import SourceSFTP
@testable import SourceSFTPCitadel

/// Runs the Citadel backend, through `SFTPSource`, against real SFTP servers: the rclone server from
/// `scripts/test-servers.sh` (password only, read-only) and, for key authentication and the host-key tests, extra
/// rclone servers that `scripts/test-sftp.sh` starts. Run it with `bash scripts/test-sftp.sh`.
/// Without the VP_SFTP_* variables every test reports as skipped, never as passed.
final class CitadelLiveTests: XCTestCase {
    private struct Env { var host: String; var port: Int; var user: String; var pass: String }

    private func env() throws -> Env {
        let e = ProcessInfo.processInfo.environment
        guard let host = e["VP_SFTP_HOST"], let portText = e["VP_SFTP_PORT"], let port = Int(portText),
              let user = e["VP_TEST_USER"], let pass = e["VP_TEST_PASS"] else {
            throw XCTSkip("VP_SFTP_* not set: run `bash scripts/test-sftp.sh`")
        }
        return Env(host: host, port: port, user: user, pass: pass)
    }

    /// Variables only `scripts/test-sftp.sh` sets (extra servers, generated keys, a real rclone binary).
    private func extra(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("\(name) not set: run `bash scripts/test-sftp.sh`")
        }
        return value
    }

    private func makeSource(
        port: Int? = nil,
        credential: SFTPCredential? = nil,
        policy: SFTPHostKeyPolicy = .acceptAnyForTesting
    ) throws -> SFTPSource {
        let e = try env()
        return SFTPSource(
            host: e.host, port: port ?? e.port,
            credential: credential ?? .password(username: e.user, password: e.pass),
            hostKeyPolicy: policy,
            backend: CitadelSFTPBackend(connectTimeoutSeconds: 10))
    }

    private let movie = "/Movies/Test Movie (2020).mkv"
    private let movieSize = 3_145_728

    /// Byte k of every test file is (k*7+3) mod 251.
    private func pattern(offset: Int, count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: ((offset + $0) * 7 + 3) % 251) })
    }

    // MARK: Password authentication

    func testAuthenticateWithPassword() async throws {
        try await makeSource().authenticate()
    }

    func testWrongPasswordIsRefusedAsUnauthorized() async throws {
        let e = try env()
        let source = try makeSource(credential: .password(username: e.user, password: "definitely-wrong"))
        do { try await source.authenticate(); XCTFail("expected unauthorized") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testWrongUserIsRefusedAsUnauthorized() async throws {
        let e = try env()
        let source = try makeSource(credential: .password(username: "nobody", password: e.pass))
        do { try await source.authenticate(); XCTFail("expected unauthorized") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    // MARK: Listing and info

    func testListRoot() async throws {
        let source = try makeSource()
        let root = try await source.list("/")
        let names = Set(root.map(\.name))
        XCTAssertTrue(names.isSuperset(of: ["Movies", "Shows", "Odd Names", "big", "notes.txt"]), "got \(names)")
        XCTAssertEqual(root.first { $0.name == "Movies" }?.isDirectory, true)
        XCTAssertEqual(root.first { $0.name == "notes.txt" }?.isDirectory, false)
        XCTAssertEqual(root.first { $0.name == "notes.txt" }?.size, 12)
    }

    func testListFoldersWithSizesAndDates() async throws {
        let source = try makeSource()
        let movies = try await source.list("/Movies")
        XCTAssertEqual(Set(movies.map(\.name)), ["Test Movie (2020).mkv", "Test Movie (2020).en.srt"])
        XCTAssertEqual(movies.first { $0.name == "Test Movie (2020).mkv" }?.size, Int64(movieSize))
        XCTAssertEqual(movies.first { $0.name == "Test Movie (2020).en.srt" }?.size, 2048)
        XCTAssertNotNil(movies.first?.modified)

        let season = try await source.list("/Shows/Test Show (2019)/Season 1")
        XCTAssertEqual(season.count, 2)
        XCTAssertTrue(season.allSatisfy { $0.size == 1_048_576 })
    }

    func testListFolderWithUnicodeAndSpecialCharacters() async throws {
        let source = try makeSource()
        let odd = try await source.list("/Odd Names")
        XCTAssertEqual(odd.map(\.name), ["Café – 100% [test] #1.mp4"])
        let bytes = try await source.read(odd[0].path, range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(bytes, pattern(offset: 0, count: 16))
    }

    func testInfoForFileFolderAndMissing() async throws {
        let source = try makeSource()
        let file = try await source.info(movie)
        XCTAssertEqual(file.size, Int64(movieSize))
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.name, "Test Movie (2020).mkv")
        XCTAssertNotNil(file.modified)
        let folder = try await source.info("/Movies")
        XCTAssertTrue(folder.isDirectory)
        do { _ = try await source.info("/Movies/ghost.mkv"); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testListingAMissingFolderIsNotFound() async throws {
        let source = try makeSource()
        do { _ = try await source.list("/no such folder"); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    // MARK: Ranged reads

    func testRangedReadAtOffset1000Returns64Bytes() async throws {
        let source = try makeSource()
        let bytes = try await source.read(movie, range: ByteRange(offset: 1000, length: 64))
        XCTAssertEqual(bytes, pattern(offset: 1000, count: 64))
    }

    func testReadsAtManyOffsetsAndSizesMatchThePattern() async throws {
        let source = try makeSource()
        // Sizes cross the 32 KiB request size so SFTPSource has to chunk, and offsets are not aligned.
        for (offset, length) in [(0, 1), (7, 100), (4095, 4097), (32_767, 32_769), (100_001, 100_000), (1_000_000, 70_000)] {
            let bytes = try await source.read(movie, range: ByteRange(offset: Int64(offset), length: Int64(length)))
            XCTAssertEqual(bytes.count, length, "offset \(offset)")
            XCTAssertEqual(bytes, pattern(offset: offset, count: length), "offset \(offset)")
        }
    }

    func testReadCrossingTheEndReturnsOnlyWhatExists() async throws {
        let source = try makeSource()
        let bytes = try await source.read(movie, range: ByteRange(offset: Int64(movieSize - 10), length: 1000))
        XCTAssertEqual(bytes, pattern(offset: movieSize - 10, count: 10))
    }

    func testReadPastTheEndReturnsZeroBytes() async throws {
        let source = try makeSource()
        let exactlyAtEnd = try await source.read(movie, range: ByteRange(offset: Int64(movieSize), length: 100))
        XCTAssertEqual(exactlyAtEnd.count, 0)
        let wellPast = try await source.read(movie, range: ByteRange(offset: Int64(movieSize + 5000), length: 100))
        XCTAssertEqual(wellPast.count, 0)
        // The connection is still good afterwards.
        let ok = try await source.read(movie, range: ByteRange(offset: 10, length: 10))
        XCTAssertEqual(ok, pattern(offset: 10, count: 10))
    }

    func testReadingAMissingFileIsNotFound() async throws {
        let source = try makeSource()
        do { _ = try await source.read("/Movies/ghost.mkv", range: ByteRange(offset: 0, length: 10)); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testAlternatingBetweenFilesKeepsReadsCorrect() async throws {
        let source = try makeSource()
        let other = "/Shows/Test Show (2019)/Season 1/Test Show - S01E02.mkv"
        for i in 0..<6 {
            let a = try await source.read(movie, range: ByteRange(offset: Int64(i * 5000), length: 300))
            XCTAssertEqual(a, pattern(offset: i * 5000, count: 300))
            let b = try await source.read(other, range: ByteRange(offset: Int64(i * 777), length: 300))
            XCTAssertEqual(b, pattern(offset: i * 777, count: 300))
        }
    }

    func testSequentialReadOfEightMebibytesIsCorrectAndReportsSpeed() async throws {
        let source = try makeSource()
        let big = "/big/Large Sample.mkv"
        let chunk = 1 << 20
        let started = Date()
        for i in 0..<8 {
            let bytes = try await source.read(big, range: ByteRange(offset: Int64(i * chunk), length: Int64(chunk)))
            XCTAssertEqual(bytes.count, chunk)
            // Check the first and last 64 bytes of each chunk (the whole chunk would only slow the test).
            XCTAssertEqual(bytes.prefix(64), pattern(offset: i * chunk, count: 64))
            XCTAssertEqual(bytes.suffix(64), pattern(offset: (i + 1) * chunk - 64, count: 64))
        }
        let seconds = Date().timeIntervalSince(started)
        print("SFTP (Citadel, loopback, 32 KiB requests, one at a time): 8 MiB in \(String(format: "%.2f", seconds)) s = \(String(format: "%.1f", 8 / seconds)) MiB/s")
        XCTAssertLessThan(seconds, 120)
    }

    func testReadsRecoverAfterTheBackendIsDisconnected() async throws {
        let e = try env()
        let backend = CitadelSFTPBackend(connectTimeoutSeconds: 10)
        let source = SFTPSource(host: e.host, port: e.port, credential: .password(username: e.user, password: e.pass),
                                hostKeyPolicy: .acceptAnyForTesting, backend: backend)
        let first = try await source.read(movie, range: ByteRange(offset: 0, length: 32))
        XCTAssertEqual(first, pattern(offset: 0, count: 32))
        await backend.disconnect()      // simulates the connection dropping between two reads
        let second = try await source.read(movie, range: ByteRange(offset: 64, length: 32))
        XCTAssertEqual(second, pattern(offset: 64, count: 32))
    }

    // MARK: Host key policy

    func testFirstConnectionRecordsTheFingerprintAndTheSecondOneMatches() async throws {
        let port = Int(try extra("VP_SFTP_KEY_PORT"))!
        let expected = try extra("VP_SFTP_HOSTKEY_FINGERPRINT")      // what `ssh-keygen -l` says about the server's key
        let store = MemoryKnownHosts()

        let first = try makeSource(port: port, policy: .trustOnFirstUse(store))
        try await first.authenticate()
        let recorded = await store.fingerprint(forHost: "127.0.0.1", port: port)
        XCTAssertEqual(recorded, expected, "the fingerprint computed from the SSH handshake must equal ssh-keygen's")
        let count = await store.count
        XCTAssertEqual(count, 1)

        let second = try makeSource(port: port, policy: .trustOnFirstUse(store))
        try await second.authenticate()
        let entries = await store.count
        XCTAssertEqual(entries, 1, "a matching second connection records nothing new")
        let list = try await second.list("/")
        XCTAssertFalse(list.isEmpty)
    }

    func testPinnedFingerprintIsAcceptedAndAWrongPinIsRefused() async throws {
        let port = Int(try extra("VP_SFTP_KEY_PORT"))!
        let expected = try extra("VP_SFTP_HOSTKEY_FINGERPRINT")
        try await makeSource(port: port, policy: .pinned(expected)).authenticate()

        let wrong = "SHA256:" + String(repeating: "A", count: 43)
        let refused = try makeSource(port: port, policy: .pinned(wrong))
        do { try await refused.authenticate(); XCTFail("expected a host key refusal") }
        catch {
            guard case .transport(let message)? = error as? SourceError else { return XCTFail("wrong error \(error)") }
            XCTAssertTrue(message.contains("host key"), message)
            XCTAssertTrue(message.contains(expected), "the refusal names the key the server really presented: \(message)")
        }
    }

    func testAChangedHostKeyIsRefusedAfterTheFirstConnection() async throws {
        let rclone = try extra("VP_RCLONE")
        let data = try extra("VP_SFTP_DATA")
        let keyA = try extra("VP_SFTP_HOSTKEY_A"), keyB = try extra("VP_SFTP_HOSTKEY_B")
        let port = Int(try extra("VP_SFTP_CHANGE_PORT"))!
        let e = try env()
        let store = MemoryKnownHosts()

        let serverA = try RcloneSFTPServer(rclone: rclone, data: data, port: port, hostKey: keyA, user: e.user, pass: e.pass)
        defer { serverA.stop() }
        try await Self.waitUntilAccepting(makeSource(port: port, policy: .acceptAnyForTesting))
        let firstTime = try makeSource(port: port, policy: .trustOnFirstUse(store))
        try await firstTime.authenticate()
        let afterFirst = await store.fingerprint(forHost: "127.0.0.1", port: port)
        XCTAssertNotNil(afterFirst)
        serverA.stop()

        // The same address now presents a different key (what a man-in-the-middle, or a reinstalled server, looks like).
        let serverB = try RcloneSFTPServer(rclone: rclone, data: data, port: port, hostKey: keyB, user: e.user, pass: e.pass)
        defer { serverB.stop() }
        try await Self.waitUntilAccepting(makeSource(port: port, policy: .acceptAnyForTesting))
        let again = try makeSource(port: port, policy: .trustOnFirstUse(store))
        do { try await again.authenticate(); XCTFail("the changed key must be refused") }
        catch {
            guard case .transport(let message)? = error as? SourceError else { return XCTFail("wrong error \(error)") }
            XCTAssertTrue(message.contains("host key"), message)
            XCTAssertFalse(message.contains(afterFirst ?? "?"), "the message names the NEW key, not the remembered one")
        }
        let stillRemembered = await store.fingerprint(forHost: "127.0.0.1", port: port)
        XCTAssertEqual(stillRemembered, afterFirst, "a refused key must not overwrite the remembered one")
    }

    // MARK: Key authentication

    func testEd25519KeyAuthentication() async throws {
        let port = Int(try extra("VP_SFTP_KEY_PORT"))!
        let pem = try String(contentsOfFile: try extra("VP_SFTP_KEY_ED25519"), encoding: .utf8)
        let e = try env()
        let source = try makeSource(port: port, credential: .privateKey(username: e.user, pem: pem, passphrase: nil))
        try await source.authenticate()
        let bytes = try await source.read(movie, range: ByteRange(offset: 1000, length: 64))
        XCTAssertEqual(bytes, pattern(offset: 1000, count: 64))
    }

    func testPassphraseProtectedEd25519KeyAuthentication() async throws {
        let port = Int(try extra("VP_SFTP_KEY_PORT"))!
        let pem = try String(contentsOfFile: try extra("VP_SFTP_KEY_ED25519_PASSPHRASED"), encoding: .utf8)
        let passphrase = try extra("VP_SFTP_KEY_PASSPHRASE")
        let e = try env()
        try await makeSource(port: port, credential: .privateKey(username: e.user, pem: pem, passphrase: passphrase)).authenticate()

        let wrong = try makeSource(port: port, credential: .privateKey(username: e.user, pem: pem, passphrase: "wrong-passphrase"))
        do { try await wrong.authenticate(); XCTFail("a wrong passphrase must fail") }
        catch { guard case .transport = error as? SourceError else { return XCTFail("wrong error \(error)") } }
    }

    func testRSAKeyAuthentication() async throws {
        let port = Int(try extra("VP_SFTP_KEY_PORT"))!
        let pem = try String(contentsOfFile: try extra("VP_SFTP_KEY_RSA"), encoding: .utf8)
        let e = try env()
        try await makeSource(port: port, credential: .privateKey(username: e.user, pem: pem, passphrase: nil)).authenticate()
    }

    func testAKeyTheServerDoesNotKnowIsRefused() async throws {
        let port = Int(try extra("VP_SFTP_KEY_PORT"))!
        let pem = try String(contentsOfFile: try extra("VP_SFTP_KEY_UNKNOWN"), encoding: .utf8)
        let e = try env()
        let source = try makeSource(port: port, credential: .privateKey(username: e.user, pem: pem, passphrase: nil))
        do { try await source.authenticate(); XCTFail("expected unauthorized") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    // MARK: Helpers

    /// Polls until the server answers a handshake (a freshly started rclone needs a moment).
    private static func waitUntilAccepting(_ source: SFTPSource) async throws {
        for _ in 0..<40 {
            do { try await source.authenticate(); return } catch { try await Task.sleep(nanoseconds: 250_000_000) }
        }
        throw XCTSkip("the extra rclone SFTP server did not start in 10 s")
    }
}

/// In-memory known-hosts store (the app keeps its own, persistent one).
actor MemoryKnownHosts: SFTPKnownHosts {
    private var entries: [String: String] = [:]
    var count: Int { entries.count }
    func fingerprint(forHost host: String, port: Int) async -> String? { entries["\(host):\(port)"] }
    func remember(fingerprint: String, forHost host: String, port: Int) async { entries["\(host):\(port)"] = fingerprint }
}

/// An rclone SFTP server this test starts and stops itself, to be able to change the host key between two connections.
final class RcloneSFTPServer {
    private let process = Process()

    init(rclone: String, data: String, port: Int, hostKey: String, user: String, pass: String) throws {
        process.executableURL = URL(fileURLWithPath: rclone)
        process.arguments = ["serve", "sftp", data, "--addr", "127.0.0.1:\(port)", "--read-only",
                             "--user", user, "--pass", pass, "--key", hostKey]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    deinit { stop() }
}
