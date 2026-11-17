import XCTest
import VideoPlayerCore
@testable import SourceSFTP

/// In-memory SFTP server stand-in. Records every call so tests can check chunking and reconnects.
actor FakeSFTPBackend: SFTPBackend {
    var files: [String: Data]
    var folders: Set<String>
    var fingerprint = "SHA256:fake-fingerprint"
    var failAuth = false
    var dropNextCalls = 0          // next N data calls throw connectionLost
    private(set) var connects = 0
    private(set) var readCalls: [(path: String, offset: UInt64, length: UInt32)] = []
    private(set) var lastUser: String?

    init(files: [String: Data], folders: Set<String>) {
        self.files = files
        self.folders = folders
    }

    func setDrops(_ n: Int) { dropNextCalls = n }
    func setFailAuth(_ v: Bool) { failAuth = v }
    func setFingerprint(_ f: String) { fingerprint = f }

    func connect(host: String, port: Int, credential: SFTPCredential,
                 acceptHostKey: @escaping @Sendable (String) async -> Bool) async throws {
        connects += 1
        guard await acceptHostKey(fingerprint) else { throw SFTPBackendError.hostKeyRejected(fingerprint: fingerprint) }
        if failAuth { throw SFTPBackendError.authenticationFailed }
        lastUser = credential.username
    }

    private func dropIfNeeded() throws {
        if dropNextCalls > 0 { dropNextCalls -= 1; throw SFTPBackendError.connectionLost("connection reset") }
    }

    func listDirectory(_ path: String) async throws -> [SFTPDirectoryEntry] {
        try dropIfNeeded()
        guard folders.contains(path) else { throw SFTPBackendError.noSuchFile }
        let prefix = path == "/" ? "/" : path + "/"
        var out: [SFTPDirectoryEntry] = [
            SFTPDirectoryEntry(name: ".", attributes: SFTPAttributes(isDirectory: true)),
            SFTPDirectoryEntry(name: "..", attributes: SFTPAttributes(isDirectory: true)),
        ]
        for f in folders where f != path && f.hasPrefix(prefix) && !f.dropFirst(prefix.count).contains("/") {
            out.append(SFTPDirectoryEntry(name: String(f.dropFirst(prefix.count)), attributes: SFTPAttributes(isDirectory: true)))
        }
        for (p, d) in files where p.hasPrefix(prefix) && !p.dropFirst(prefix.count).contains("/") {
            out.append(SFTPDirectoryEntry(
                name: String(p.dropFirst(prefix.count)),
                attributes: SFTPAttributes(size: Int64(d.count), modified: Date(timeIntervalSince1970: 1_700_000_000))
            ))
        }
        return out
    }

    func attributes(of path: String) async throws -> SFTPAttributes {
        try dropIfNeeded()
        if folders.contains(path) { return SFTPAttributes(isDirectory: true) }
        guard let d = files[path] else { throw SFTPBackendError.noSuchFile }
        return SFTPAttributes(size: Int64(d.count), modified: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func read(_ path: String, offset: UInt64, length: UInt32) async throws -> Data {
        try dropIfNeeded()
        readCalls.append((path, offset, length))
        guard let d = files[path] else { throw SFTPBackendError.noSuchFile }
        if offset >= UInt64(d.count) { return Data() }
        let end = min(d.count, Int(offset) + Int(length))
        return d.subdata(in: Int(offset)..<end)
    }

    func disconnect() async {}
}

actor MemoryKnownHosts: SFTPKnownHosts {
    var store: [String: String] = [:]
    func fingerprint(forHost host: String, port: Int) async -> String? { store["\(host):\(port)"] }
    func remember(fingerprint: String, forHost host: String, port: Int) async { store["\(host):\(port)"] = fingerprint }
}

final class SFTPSourceTests: XCTestCase {
    static func pattern(_ n: Int) -> Data { Data((0..<n).map { UInt8(($0 * 7 + 3) % 251) }) }

    func makeBackend() -> FakeSFTPBackend {
        FakeSFTPBackend(
            files: [
                "/movies/a.mkv": Self.pattern(100),
                "/movies/sub/b.mp4": Self.pattern(10),
                "/top.txt": Data("hi".utf8),
                "/data/movies/c.mkv": Self.pattern(20),
            ],
            folders: ["/", "/movies", "/movies/sub", "/data", "/data/movies"]
        )
    }

    func makeSource(_ backend: FakeSFTPBackend, root: String = "/", chunk: UInt32 = 32 * 1024,
                    policy: SFTPHostKeyPolicy = .acceptAnyForTesting,
                    credential: SFTPCredential = .password(username: "u", password: "p")) -> SFTPSource {
        SFTPSource(host: "h", credential: credential, hostKeyPolicy: policy, rootPath: root, backend: backend, maxChunk: chunk)
    }

    // MARK: browsing

    func testListRootHidesDotEntriesAndMapsTypes() async throws {
        let source = makeSource(makeBackend())
        let entries = try await source.list("/")
        XCTAssertEqual(entries.map(\.name), ["data", "movies", "top.txt"])
        XCTAssertEqual(entries.map(\.path), ["/data", "/movies", "/top.txt"])
        XCTAssertEqual(entries.map(\.isDirectory), [true, true, false])
        XCTAssertEqual(entries.last?.size, 2)
        XCTAssertNil(entries.first?.size)
    }

    func testListSubfolderAndInfo() async throws {
        let source = makeSource(makeBackend())
        let entries = try await source.list("/movies")
        XCTAssertEqual(entries.map(\.path), ["/movies/a.mkv", "/movies/sub"])
        let file = try await source.info("/movies/a.mkv")
        XCTAssertEqual(file.name, "a.mkv")
        XCTAssertEqual(file.size, 100)
        XCTAssertEqual(file.modified, Date(timeIntervalSince1970: 1_700_000_000))
        let dir = try await source.info("/movies/")
        XCTAssertEqual(dir.path, "/movies")
        XCTAssertTrue(dir.isDirectory)
        let root = try await source.info("/")
        XCTAssertEqual(root.name, "/")
    }

    func testRootPathIsPrefixedOnTheServerAndHiddenFromTheApp() async throws {
        let source = makeSource(makeBackend(), root: "/data")
        let entries = try await source.list("/")
        XCTAssertEqual(entries.map(\.path), ["/movies"])
        let inner = try await source.list("/movies")
        XCTAssertEqual(inner.map(\.path), ["/movies/c.mkv"])
        let bytes = try await source.read("/movies/c.mkv", range: ByteRange(offset: 0, length: 5))
        XCTAssertEqual(bytes, Self.pattern(20).prefix(5))
    }

    func testMissingPathIsNotFound() async {
        let source = makeSource(makeBackend())
        do { _ = try await source.info("/nope"); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testDotDotCannotEscapeTheRoot() async throws {
        let source = makeSource(makeBackend(), root: "/data")
        let entries = try await source.list("/../../")
        XCTAssertEqual(entries.map(\.path), ["/movies"])
        XCTAssertEqual(SFTPSource.normalize("/a/./b//c/../d/"), "/a/b/d")
        XCTAssertEqual(SFTPSource.normalize(""), "/")
        XCTAssertEqual(SFTPSource.normalize("../.."), "/")
    }

    // MARK: reading

    func testRangeReadMatchesPattern() async throws {
        let source = makeSource(makeBackend())
        let data = try await source.read("/movies/a.mkv", range: ByteRange(offset: 10, length: 30))
        XCTAssertEqual(data, Self.pattern(100).subdata(in: 10..<40))
    }

    func testLargeReadIsSplitIntoChunksOfTheMaximum() async throws {
        let backend = makeBackend()
        let source = makeSource(backend, chunk: 16)
        let data = try await source.read("/movies/a.mkv", range: ByteRange(offset: 0, length: 50))
        XCTAssertEqual(data, Self.pattern(100).prefix(50))
        let calls = await backend.readCalls
        XCTAssertEqual(calls.map(\.offset), [0, 16, 32, 48])
        XCTAssertEqual(calls.map(\.length), [16, 16, 16, 2])
    }

    func testReadStopsAtEndOfFile() async throws {
        let source = makeSource(makeBackend(), chunk: 16)
        let data = try await source.read("/movies/a.mkv", range: ByteRange(offset: 90, length: 1000))
        XCTAssertEqual(data, Self.pattern(100).suffix(10))
    }

    func testReadPastEndIsEmptyAndZeroLengthAsksNothing() async throws {
        let backend = makeBackend()
        let source = makeSource(backend)
        let past = try await source.read("/movies/a.mkv", range: ByteRange(offset: 500, length: 10))
        XCTAssertTrue(past.isEmpty)
        let before = await backend.readCalls.count
        let none = try await source.read("/movies/a.mkv", range: ByteRange(offset: 0, length: 0))
        XCTAssertTrue(none.isEmpty)
        let after = await backend.readCalls.count
        XCTAssertEqual(before, after)
    }

    func testPlaybackIsByteReaderAndCapabilitiesAreHonest() async throws {
        let source = makeSource(makeBackend())
        let access = try await source.playbackAccess(for: "/movies/a.mkv")
        XCTAssertEqual(access, .byteReader)
        XCTAssertEqual(source.kind, .sftp)
        XCTAssertTrue(source.capabilities.byteRanges)
        XCTAssertTrue(source.capabilities.alwaysEncrypted)
        XCTAssertFalse(source.capabilities.directPlaybackURL)
        XCTAssertEqual(source.capabilities.authMethods, [.usernamePassword, .publicKey])
    }

    func testChangeDetectionUsesModifiedAndSize() async throws {
        let source = makeSource(makeBackend())
        let a = try await source.info("/movies/a.mkv")
        var changed = a
        changed.size = 101
        XCTAssertEqual(source.hasChanged(a.version, comparedTo: changed), true)
        XCTAssertEqual(source.hasChanged(a.version, comparedTo: a), false)
    }

    // MARK: connection handling

    func testConnectsLazilyAndOnlyOnce() async throws {
        let backend = makeBackend()
        let source = makeSource(backend)
        _ = try await source.list("/")
        _ = try await source.list("/movies")
        let connects = await backend.connects
        XCTAssertEqual(connects, 1)
    }

    func testReconnectsOnceWhenTheConnectionDrops() async throws {
        let backend = makeBackend()
        let source = makeSource(backend)
        try await source.authenticate()
        await backend.setDrops(1)
        let data = try await source.read("/movies/a.mkv", range: ByteRange(offset: 0, length: 4))
        XCTAssertEqual(data, Self.pattern(100).prefix(4))
        let connects = await backend.connects
        XCTAssertEqual(connects, 2)
    }

    func testGivesUpAfterOneReconnect() async throws {
        let backend = makeBackend()
        let source = makeSource(backend)
        try await source.authenticate()
        await backend.setDrops(2)
        do { _ = try await source.list("/"); XCTFail("expected a transport error") }
        catch { XCTAssertEqual(error as? SourceError, .transport("connection reset")) }
    }

    func testWrongPasswordIsUnauthorized() async {
        let backend = makeBackend()
        await backend.setFailAuth(true)
        let source = makeSource(backend)
        do { try await source.authenticate(); XCTFail("expected unauthorized") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
    }

    func testPrivateKeyCredentialUsesItsUsername() async throws {
        let backend = makeBackend()
        let source = makeSource(backend, credential: .privateKey(username: "keyuser", pem: "PEM", passphrase: nil))
        try await source.authenticate()
        let user = await backend.lastUser
        XCTAssertEqual(user, "keyuser")
    }

    // MARK: host keys

    func testPinnedFingerprintAcceptsMatchAndRefusesMismatch() async throws {
        let backend = makeBackend()
        let ok = makeSource(backend, policy: .pinned("SHA256:fake-fingerprint"))
        try await ok.authenticate()
        let bad = makeSource(backend, policy: .pinned("SHA256:someone-else"))
        do { try await bad.authenticate(); XCTFail("expected refusal") }
        catch {
            guard case .transport(let message)? = error as? SourceError else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("host key"))
        }
    }

    func testTrustOnFirstUseRemembersThenRefusesAChangedKey() async throws {
        let backend = makeBackend()
        let hosts = MemoryKnownHosts()
        let first = makeSource(backend, policy: .trustOnFirstUse(hosts))
        try await first.authenticate()
        let stored = await hosts.fingerprint(forHost: "h", port: 22)
        XCTAssertEqual(stored, "SHA256:fake-fingerprint")

        await backend.setFingerprint("SHA256:attacker")
        let second = makeSource(backend, policy: .trustOnFirstUse(hosts))
        do { try await second.authenticate(); XCTFail("a changed key must be refused") }
        catch { XCTAssertNotNil(error as? SourceError) }
        let still = await hosts.fingerprint(forHost: "h", port: 22)
        XCTAssertEqual(still, "SHA256:fake-fingerprint", "a refused key must not overwrite the stored one")
    }
}
