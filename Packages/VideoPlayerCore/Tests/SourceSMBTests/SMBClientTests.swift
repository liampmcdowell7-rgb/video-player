import XCTest
import VideoPlayerCore
@testable import SourceSMB

/// A scripted SMB library: shares with files whose bytes follow the test pattern, and switches to inject failures.
actor FakeSMBBackend: SMBBackend {
    struct File { var data: Data; var modified: Date }
    var shares: [String: [String: File]] = [:]      // share -> share-relative file path -> file
    var folders: [String: Set<String>] = [:]        // share -> folder paths ("/a", "/a/b")
    var failNext: [SMBBackendError] = []            // consumed one per call, any call
    var connectError: SMBBackendError?
    private(set) var connects = 0
    private(set) var disconnects = 0
    private(set) var calls: [String] = []

    func setFailures(_ errors: [SMBBackendError]) { failNext = errors }
    func setConnectError(_ error: SMBBackendError?) { connectError = error }
    func add(share: String, files: [String: File], folders: Set<String> = []) {
        shares[share] = files
        self.folders[share] = folders
    }

    private var isDown = false
    private var deniedForMissing = false
    func dropConnection() { isDown = true }
    func setDeniedForMissing(_ value: Bool) { deniedForMissing = value }

    private func maybeFail(_ name: String) throws {
        calls.append(name)
        if isDown { throw SMBBackendError.connectionLost("connection dropped") }
        if !failNext.isEmpty { throw failNext.removeFirst() }
    }

    func connect(share: String?) async throws {
        connects += 1
        calls.append("connect")
        if let connectError { throw connectError }
        isDown = false
    }
    func listShares() async throws -> [String] {
        try maybeFail("listShares")
        return shares.keys.sorted()
    }
    func listDirectory(share: String, path: String) async throws -> [SMBItem] {
        try maybeFail("listDirectory")
        guard let files = shares[share] else { throw SMBBackendError.notFound }
        let prefix = path == "/" ? "/" : path + "/"
        var items: [SMBItem] = [SMBItem(name: ".", isDirectory: true), SMBItem(name: "..", isDirectory: true)]
        for (filePath, file) in files where filePath.hasPrefix(prefix) {
            let rest = filePath.dropFirst(prefix.count)
            if !rest.contains("/") {
                items.append(SMBItem(name: String(rest), isDirectory: false, size: Int64(file.data.count), modified: file.modified))
            }
        }
        for folder in folders[share] ?? [] where folder.hasPrefix(prefix) && !folder.dropFirst(prefix.count).contains("/") {
            items.append(SMBItem(name: String(folder.dropFirst(prefix.count)), isDirectory: true))
        }
        return items
    }
    func stat(share: String, path: String) async throws -> SMBItem {
        try maybeFail("stat")
        if let file = shares[share]?[path] {
            return SMBItem(name: String(path.split(separator: "/").last ?? ""), isDirectory: false,
                           size: Int64(file.data.count), modified: file.modified)
        }
        if folders[share]?.contains(path) == true {
            return SMBItem(name: String(path.split(separator: "/").last ?? ""), isDirectory: true)
        }
        throw deniedForMissing ? SMBBackendError.accessDenied : SMBBackendError.notFound
    }
    func read(share: String, path: String, offset: Int64, length: Int64) async throws -> Data {
        try maybeFail("read")
        guard let file = shares[share]?[path] else { throw SMBBackendError.notFound }
        let size = Int64(file.data.count)
        if offset >= size { return Data() }
        let end = min(size, offset + length)
        return file.data.subdata(in: Int(offset)..<Int(end))
    }
    func disconnect() async { disconnects += 1 }
}

func patternData(count: Int, from start: Int = 0) -> Data {
    Data((0..<count).map { UInt8(((start + $0) * 7 + 3) % 251) })
}

final class SMBClientTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_600_000_000)

    func makeFake() async -> FakeSMBBackend {
        let fake = FakeSMBBackend()
        await fake.add(
            share: "Media",
            files: [
                "/notes.txt": .init(data: Data("hello".utf8), modified: date),
                "/Movies/Test Movie (2020).mkv": .init(data: patternData(count: 5000), modified: date),
                "/Odd Names/Café – 100% [test] #1.mp4": .init(data: patternData(count: 10), modified: date),
            ],
            folders: ["/Movies", "/Odd Names"]
        )
        await fake.add(share: "Backup", files: [:])
        await fake.add(share: "IPC$", files: [:])
        return fake
    }

    func makeClient(_ fake: FakeSMBBackend) -> SMBClient {
        SMBClient(configuration: SMBConfiguration(host: "server"), backend: fake)
    }

    // MARK: Path mapping

    func testLocationSplitsShareAndPath() {
        XCTAssertNil(SMBLocation("/")?.share)
        XCTAssertEqual(SMBLocation("")?.path, "/")
        XCTAssertEqual(SMBLocation("/Media")?.share, "Media")
        XCTAssertEqual(SMBLocation("/Media")?.path, "/")
        XCTAssertEqual(SMBLocation("/Media/Movies/a.mkv")?.path, "/Movies/a.mkv")
        XCTAssertEqual(SMBLocation("Media//Movies/")?.path, "/Movies")
        XCTAssertEqual(SMBLocation("/Media/./x")?.path, "/x")
        XCTAssertNil(SMBLocation("/Media/../x"))
        XCTAssertEqual(SMBLocation("/Media/Movies")?.child("a.mkv"), "/Media/Movies/a.mkv")
        XCTAssertEqual(SMBLocation("/Media")?.child("a"), "/Media/a")
        XCTAssertEqual(SMBLocation("/")?.child("Media"), "/Media")
    }

    func testCapabilitiesAndKind() async {
        let client = makeClient(await makeFake())
        XCTAssertEqual(client.kind, .smb)
        XCTAssertTrue(client.capabilities.byteRanges)
        XCTAssertFalse(client.capabilities.directPlaybackURL)
        XCTAssertEqual(client.capabilities.changeSignals, [.modified, .size])
        XCTAssertTrue(client.capabilities.authMethods.contains(.none))
        XCTAssertTrue(client.capabilities.authMethods.contains(.usernamePassword))
    }

    // MARK: Listing

    func testRootListsShares() async throws {
        let client = makeClient(await makeFake())
        let entries = try await client.list("/")
        XCTAssertEqual(entries.map(\.path), ["/Backup", "/Media"], "IPC$ and other admin shares are hidden")
        XCTAssertTrue(entries.allSatisfy { $0.isDirectory })
    }

    func testListingAFolderUsesTheShareAsFirstComponent() async throws {
        let client = makeClient(await makeFake())
        let top = try await client.list("/Media")
        XCTAssertEqual(Set(top.map(\.path)), ["/Media/notes.txt", "/Media/Movies", "/Media/Odd Names"])
        XCTAssertFalse(top.contains { $0.name == "." || $0.name == ".." })
        let notes = try XCTUnwrap(top.first { $0.name == "notes.txt" })
        XCTAssertEqual(notes.size, 5)
        XCTAssertEqual(notes.modified, date)
        XCTAssertFalse(notes.isDirectory)
        let movies = try await client.list("/Media/Movies")
        XCTAssertEqual(movies.map(\.path), ["/Media/Movies/Test Movie (2020).mkv"])
        let odd = try await client.list("/Media/Odd Names")
        XCTAssertEqual(odd.first?.name, "Café – 100% [test] #1.mp4")
    }

    func testInfoForRootShareFolderAndFile() async throws {
        let client = makeClient(await makeFake())
        let root = try await client.info("/")
        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.path, "/")
        let share = try await client.info("/Media")
        XCTAssertTrue(share.isDirectory)
        XCTAssertEqual(share.name, "Media")
        let folder = try await client.info("/Media/Movies")
        XCTAssertTrue(folder.isDirectory)
        let file = try await client.info("/Media/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(file.size, 5000)
        XCTAssertEqual(file.modified, date)
        XCTAssertEqual(file.name, "Test Movie (2020).mkv")
        XCTAssertEqual(file.version.size, 5000)
    }

    func testMissingPathsAreNotFound() async throws {
        let client = makeClient(await makeFake())
        await assertThrows(.notFound) { _ = try await client.info("/Media/nope.mkv") }
        await assertThrows(.notFound) { _ = try await client.list("/NoSuchShare") }
        await assertThrows(.notFound) { _ = try await client.list("/Media/../etc") }
        await assertThrows(.notFound) { _ = try await client.read("/", range: ByteRange(offset: 0, length: 1)) }
    }

    // MARK: Reading

    func testRangeReadsReturnTheRightBytes() async throws {
        let client = makeClient(await makeFake())
        let path = "/Media/Movies/Test Movie (2020).mkv"
        let head = try await client.read(path, range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(head, patternData(count: 16))
        let middle = try await client.read(path, range: ByteRange(offset: 1234, length: 100))
        XCTAssertEqual(middle, patternData(count: 100, from: 1234))
        let tail = try await client.read(path, range: ByteRange(offset: 4990, length: 100))
        XCTAssertEqual(tail, patternData(count: 10, from: 4990), "short at the end of the file")
        let empty = try await client.read(path, range: ByteRange(offset: 10, length: 0))
        XCTAssertTrue(empty.isEmpty)
    }

    func testSeekingPastTheEndIsRangeNotSatisfiable() async throws {
        let client = makeClient(await makeFake())
        let path = "/Media/Movies/Test Movie (2020).mkv"
        await assertThrows(.rangeNotSatisfiable) { _ = try await client.read(path, range: ByteRange(offset: 5000, length: 1)) }
        await assertThrows(.rangeNotSatisfiable) { _ = try await client.read(path, range: ByteRange(offset: 99_999, length: 10)) }
    }

    func testPlaybackAccessIsAByteReaderForFilesOnly() async throws {
        let client = makeClient(await makeFake())
        let access = try await client.playbackAccess(for: "/Media/notes.txt")
        XCTAssertEqual(access, .byteReader)
        await assertThrows(.unsupported("This is a folder, not a file.")) { _ = try await client.playbackAccess(for: "/Media/Movies") }
        await assertThrows(.notFound) { _ = try await client.playbackAccess(for: "/Media/missing.mkv") }
    }

    func testChangeDetectionUsesModifiedAndSize() async throws {
        let client = makeClient(await makeFake())
        let entry = try await client.info("/Media/notes.txt")
        XCTAssertEqual(client.hasChanged(entry.version, comparedTo: entry), false)
        var changed = entry.version
        changed.size = 6
        XCTAssertEqual(client.hasChanged(changed, comparedTo: entry), true)
        changed = entry.version
        changed.modified = date.addingTimeInterval(60)
        XCTAssertEqual(client.hasChanged(changed, comparedTo: entry), true)
    }

    // MARK: Authentication and errors

    func testWrongPasswordIsUnauthorized() async throws {
        let fake = await makeFake()
        await fake.setConnectError(.authenticationFailed)
        let client = makeClient(fake)
        await assertThrows(.unauthorized) { try await client.authenticate() }
        await assertThrows(.unauthorized) { _ = try await client.list("/") }
    }

    func testAccessDeniedAfterConnectingIsForbidden() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        try await client.authenticate()
        await fake.setFailures([.accessDenied])
        await assertThrows(.forbidden) { _ = try await client.list("/Media") }
    }

    func testAccessDeniedForAMissingFileBecomesNotFound() async throws {
        let fake = await makeFake()
        await fake.setDeniedForMissing(true)   // like impacket: "access denied" instead of "not found"
        let client = makeClient(fake)
        await assertThrows(.notFound) { _ = try await client.info("/Media/Movies/missing.mkv") }
        // A file that exists but really is denied stays "forbidden".
        await fake.setFailures([.accessDenied])
        await assertThrows(.forbidden) { _ = try await client.info("/Media/notes.txt") }
    }

    func testAuthenticateCanBeRepeatedAndFirstCallConnectsLazily() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        _ = try await client.list("/")
        try await client.authenticate()
        let connects = await fake.connects
        XCTAssertEqual(connects, 2)
    }

    // MARK: Reconnect

    func testReconnectsOnceWhenTheConnectionDrops() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        try await client.authenticate()
        await fake.setFailures([.connectionLost("reset")])
        let data = try await client.read("/Media/notes.txt", range: ByteRange(offset: 0, length: 5))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
        let connects = await fake.connects
        let disconnects = await fake.disconnects
        XCTAssertEqual(connects, 2)
        XCTAssertEqual(disconnects, 1)
    }

    func testGivesUpAfterOneReconnect() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        try await client.authenticate()
        await fake.setFailures([.connectionLost("first"), .connectionLost("second")])
        do {
            _ = try await client.list("/Media")
            XCTFail("expected failure")
        } catch let error as SourceError {
            XCTAssertEqual(error, .transport("second"))
        }
    }

    func testFailedReconnectReportsTheReason() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        try await client.authenticate()
        await fake.setFailures([.connectionLost("dropped")])
        await fake.setConnectError(.authenticationFailed)   // password changed while connected
        await assertThrows(.unauthorized) { _ = try await client.list("/Media") }
    }

    func testOtherErrorsAreNotRetried() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        try await client.authenticate()
        await fake.setFailures([.other("boom")])
        await assertThrows(.transport("boom")) { _ = try await client.list("/Media") }
        let connects = await fake.connects
        XCTAssertEqual(connects, 1)
    }

    func testManyParallelCallsAfterADropReconnectOnce() async throws {
        let fake = await makeFake()
        let client = SMBClient(configuration: SMBConfiguration(host: "server", defaultShare: "Media"), backend: fake)
        try await client.authenticate()
        await fake.dropConnection()   // every call fails until someone reconnects
        let counts = await withTaskGroup(of: Int?.self) { group -> [Int?] in
            for _ in 0..<5 {
                group.addTask { try? await client.list("/Media").count }
            }
            var all: [Int?] = []
            for await count in group { all.append(count) }
            return all
        }
        XCTAssertEqual(counts.compactMap { $0 }.count, 5, "every call gets its answer after the reconnect")
        let connects = await fake.connects
        XCTAssertEqual(connects, 2, "one connection at the start, one rebuild shared by all five calls")
    }

    func testDisconnectClosesAndLaterCallsConnectAgain() async throws {
        let fake = await makeFake()
        let client = makeClient(fake)
        try await client.authenticate()
        await client.disconnect()
        _ = try await client.list("/")
        let connects = await fake.connects
        let disconnects = await fake.disconnects
        XCTAssertEqual(connects, 2)
        XCTAssertEqual(disconnects, 1)
    }

    // MARK: Helper

    func assertThrows(_ expected: SourceError, file: StaticString = #filePath, line: UInt = #line,
                      _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SourceError, expected, "\(error)", file: file, line: line)
        }
    }
}
