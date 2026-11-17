import XCTest
import VideoPlayerCore
@testable import SourceNFS

final class NFSSourceTests: XCTestCase {
    private func make(_ backend: FakeNFSBackend = .standard(), chunk: Int = 4 * 1024 * 1024) -> (NFSSource, FakeNFSBackend) {
        let config = NFSConfiguration(host: "nas.local", exportPath: "/volume1/video", maxReadChunk: chunk)
        return (NFSSource(configuration: config, backend: backend), backend)
    }

    // MARK: Paths

    func testNormalizeCollapsesSlashesAndDots() throws {
        XCTAssertEqual(try NFSPath.normalize("/"), "/")
        XCTAssertEqual(try NFSPath.normalize(""), "/")
        XCTAssertEqual(try NFSPath.normalize("//a///b/./c/"), "/a/b/c")
        XCTAssertEqual(try NFSPath.normalize("a/b"), "/a/b")
    }

    func testNormalizeRefusesParentFolders() {
        XCTAssertThrowsError(try NFSPath.normalize("/a/../b")) { XCTAssertEqual($0 as? SourceError, .forbidden) }
        XCTAssertThrowsError(try NFSPath.normalize("..")) { XCTAssertEqual($0 as? SourceError, .forbidden) }
    }

    func testJoin() {
        XCTAssertEqual(NFSPath.join("/", "a"), "/a")
        XCTAssertEqual(NFSPath.join("/a", "b"), "/a/b")
    }

    // MARK: Contract

    func testCapabilitiesAreHonest() {
        let (source, _) = make()
        XCTAssertEqual(source.kind, .nfs)
        XCTAssertTrue(source.capabilities.byteRanges)
        XCTAssertFalse(source.capabilities.alwaysEncrypted, "NFSv3 AUTH_SYS has no encryption")
        XCTAssertFalse(source.capabilities.directPlaybackURL)
        XCTAssertFalse(source.capabilities.discovery)
        XCTAssertEqual(source.capabilities.authMethods, [.none])
        XCTAssertEqual(source.capabilities.changeSignals, [.modified, .size])
    }

    func testPlaybackAccessIsByteReader() async throws {
        let (source, _) = make()
        let access = try await source.playbackAccess(for: "/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(access, .byteReader)
    }

    func testAuthenticateMountsWithTheConfiguration() async throws {
        let (source, backend) = make()
        try await source.authenticate()
        XCTAssertEqual(backend.mountCalls, 1)
        XCTAssertEqual(backend.lastConfiguration?.host, "nas.local")
        XCTAssertEqual(backend.lastConfiguration?.exportPath, "/volume1/video")
    }

    func testAuthenticateReportsAccessDeniedAsForbidden() async {
        let backend = FakeNFSBackend.standard()
        backend.mountError = .accessDenied
        let (source, _) = make(backend)
        do { try await source.authenticate(); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .forbidden) }
    }

    func testAuthenticateReportsMissingExportAsNotFound() async {
        let backend = FakeNFSBackend.standard()
        backend.mountError = .notFound
        let (source, _) = make(backend)
        do { try await source.authenticate(); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testFirstUseMountsLazilyAndOnlyOnce() async throws {
        let (source, backend) = make()
        _ = try await source.list("/")
        _ = try await source.list("/Movies")
        XCTAssertEqual(backend.mountCalls, 1)
    }

    // MARK: Listing

    func testListRootSkipsDotEntriesPipesAndDeadLinks() async throws {
        let (source, _) = make()
        let names = try await source.list("/").map(\.name)
        XCTAssertEqual(names, ["big.mkv", "link-to-file", "link-to-movies", "Movies", "notes.txt", "Odd Names"])
        XCTAssertFalse(names.contains("."))
        XCTAssertFalse(names.contains(".."))
        XCTAssertFalse(names.contains("pipe"))
        XCTAssertFalse(names.contains("dead-link"))
    }

    func testListFollowsSymlinksToFoldersAndFiles() async throws {
        let (source, _) = make()
        let entries = try await source.list("/")
        let folderLink = try XCTUnwrap(entries.first { $0.name == "link-to-movies" })
        XCTAssertTrue(folderLink.isDirectory)
        XCTAssertNil(folderLink.size)
        let fileLink = try XCTUnwrap(entries.first { $0.name == "link-to-file" })
        XCTAssertFalse(fileLink.isDirectory)
        XCTAssertEqual(fileLink.size, 12)
    }

    func testListFolderGivesFullPathsSizesAndDates() async throws {
        let (source, _) = make()
        let entries = try await source.list("/Movies")
        XCTAssertEqual(entries.map(\.path), ["/Movies/Test Movie (2020).en.srt", "/Movies/Test Movie (2020).mkv"])
        let movie = try XCTUnwrap(entries.last)
        XCTAssertEqual(movie.size, 10_000)
        XCTAssertFalse(movie.isDirectory)
        XCTAssertEqual(movie.modified, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testListKeepsUnicodeAndPunctuationInNames() async throws {
        let (source, _) = make()
        let entries = try await source.list("/Odd Names")
        XCTAssertEqual(entries.first?.name, "Café – 100% [test] #1.mp4")
        XCTAssertEqual(entries.first?.path, "/Odd Names/Café – 100% [test] #1.mp4")
    }

    func testListIgnoresNamesThatCouldEscape() async throws {
        // Hostile server: names with slashes must never become paths.
        final class Hostile: NFSBackend, @unchecked Sendable {
            func mount(_ c: NFSConfiguration) async throws {}
            func unmount() async {}
            func readDirectory(_ p: String) async throws -> [NFSDirectoryEntry] {
                [NFSDirectoryEntry(name: "../etc", kind: .directory, size: 0),
                 NFSDirectoryEntry(name: "a/b", kind: .file, size: 1),
                 NFSDirectoryEntry(name: "ok.mkv", kind: .file, size: 2)]
            }
            func status(_ p: String) async throws -> NFSFileStatus { NFSFileStatus(kind: .file, size: 1) }
            func read(_ p: String, offset: UInt64, count: Int) async throws -> Data { Data() }
        }
        let source = NFSSource(configuration: NFSConfiguration(host: "h"), backend: Hostile())
        let names = try await source.list("/").map(\.name)
        XCTAssertEqual(names, ["ok.mkv"])
    }

    func testListMissingFolderIsNotFound() async {
        let (source, _) = make()
        do { _ = try await source.list("/Nope"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testListOfAFileIsNotFound() async {
        let (source, _) = make()
        do { _ = try await source.list("/notes.txt"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testListRefusesParentTraversal() async {
        let (source, _) = make()
        do { _ = try await source.list("/Movies/../.."); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .forbidden) }
    }

    // MARK: Info

    func testInfoForFileFolderAndRoot() async throws {
        let (source, _) = make()
        let file = try await source.info("/Movies/Test Movie (2020).mkv")
        XCTAssertEqual(file.name, "Test Movie (2020).mkv")
        XCTAssertEqual(file.size, 10_000)
        XCTAssertFalse(file.isDirectory)
        let folder = try await source.info("/Movies/")
        XCTAssertEqual(folder.path, "/Movies")
        XCTAssertTrue(folder.isDirectory)
        XCTAssertNil(folder.size)
        let root = try await source.info("/")
        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.path, "/")
    }

    func testInfoMissingIsNotFoundAndSpecialFileIsNotFound() async {
        let (source, _) = make()
        do { _ = try await source.info("/missing"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
        do { _ = try await source.info("/pipe"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testInfoGivesAComparableVersion() async throws {
        let (source, _) = make()
        let a = try await source.info("/notes.txt").version
        let b = try await source.info("/notes.txt").version
        XCTAssertEqual(a.isSame(as: b), true)
    }

    // MARK: Reading

    func testReadReturnsExactRange() async throws {
        let (source, _) = make()
        let data = try await source.read("/big.mkv", range: ByteRange(offset: 1_000, length: 64))
        XCTAssertEqual(data.count, 64)
        XCTAssertEqual(Array(data), (0..<64).map { FakeNFSBackend.byte(at: 1_000 + UInt64($0)) })
    }

    func testReadLoopsOverShortReads() async throws {
        let backend = FakeNFSBackend.standard()
        backend.maxBytesPerRead = 100
        let (source, _) = make(backend)
        let data = try await source.read("/big.mkv", range: ByteRange(offset: 5, length: 1_000))
        XCTAssertEqual(data.count, 1_000)
        XCTAssertEqual(Array(data), (0..<1_000).map { FakeNFSBackend.byte(at: 5 + UInt64($0)) })
        XCTAssertEqual(backend.readCalls.count, 10)
        XCTAssertEqual(backend.readCalls.map(\.offset), (0..<10).map { 5 + UInt64($0) * 100 })
    }

    func testReadIsSplitIntoChunks() async throws {
        let (source, backend) = make(chunk: 4096)
        let data = try await source.read("/big.mkv", range: ByteRange(offset: 0, length: 10_000))
        XCTAssertEqual(data.count, 10_000)
        XCTAssertEqual(backend.readCalls.map(\.count), [4096, 4096, 1808])
    }

    func testReadAcrossEndOfFileIsShort() async throws {
        let (source, _) = make()
        let data = try await source.read("/notes.txt", range: ByteRange(offset: 2, length: 100))
        XCTAssertEqual(data.count, 10)
    }

    func testReadPastEndIsEmpty() async throws {
        let (source, _) = make()
        let data = try await source.read("/notes.txt", range: ByteRange(offset: 500, length: 10))
        XCTAssertTrue(data.isEmpty)
    }

    func testReadOfZeroLengthDoesNotTouchTheServer() async throws {
        let (source, backend) = make()
        let data = try await source.read("/notes.txt", range: ByteRange(offset: 0, length: 0))
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(backend.mountCalls, 0)
        XCTAssertTrue(backend.readCalls.isEmpty)
    }

    func testReadMissingFileIsNotFoundAndFolderIsUnsupported() async {
        let (source, _) = make()
        do { _ = try await source.read("/missing", range: ByteRange(offset: 0, length: 4)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
        do { _ = try await source.read("/Movies", range: ByteRange(offset: 0, length: 4)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .unsupported("This path is a folder, not a file")) }
    }

    func testReadAtVeryLargeOffsetKeepsFullPrecision() async throws {
        let (source, backend) = make()
        _ = try? await source.read("/big.mkv", range: ByteRange(offset: 5_000_000_000, length: 10))
        XCTAssertEqual(backend.readCalls.first?.offset, 5_000_000_000)
    }

    // MARK: Reconnect

    func testDroppedConnectionIsRemountedAndTheReadRetriedOnce() async throws {
        let (source, backend) = make()
        _ = try await source.list("/")                    // mount #1
        backend.failNext = [.connection("reset by peer")] // next call fails once
        let data = try await source.read("/big.mkv", range: ByteRange(offset: 0, length: 16))
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(backend.mountCalls, 2, "one remount after the drop")
    }

    func testSecondFailureIsReportedAsTransport() async throws {
        let (source, backend) = make()
        _ = try await source.list("/")
        backend.failNext = [.connection("reset"), .connection("still down")]  // read fails, then the remount fails
        do {
            _ = try await source.read("/big.mkv", range: ByteRange(offset: 0, length: 16))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SourceError, .transport("still down"))
        }
        // The next call tries to mount again from scratch and works.
        let data = try await source.read("/big.mkv", range: ByteRange(offset: 0, length: 4))
        XCTAssertEqual(data.count, 4)
    }

    func testMountFailureOnFirstUseIsRetriedOnce() async throws {
        let backend = FakeNFSBackend.standard()
        backend.failNext = [.connection("refused")]
        let (source, _) = make(backend)
        let names = try await source.list("/").map(\.name)
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(backend.mountCalls, 2)
    }

    func testAccessDeniedIsNotRetried() async throws {
        let (source, backend) = make()
        _ = try await source.list("/")
        backend.failNext = [.accessDenied]
        do { _ = try await source.list("/"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .forbidden) }
        XCTAssertEqual(backend.mountCalls, 1)
    }

    func testAuthenticateAgainReconnects() async throws {
        let (source, backend) = make()
        try await source.authenticate()
        try await source.authenticate()
        XCTAssertEqual(backend.mountCalls, 2)
    }

    func testDefaultsMatchTheDocumentedDecisions() {
        let c = NFSConfiguration(host: "h")
        XCTAssertEqual(c.exportPath, "/")
        XCTAssertNil(c.port, "real servers use the portmapper")
        XCTAssertEqual(c.timeoutMilliseconds, 10_000)
        XCTAssertEqual(NFSConfiguration(host: "h", exportPath: "").exportPath, "/")
        XCTAssertGreaterThanOrEqual(NFSConfiguration(host: "h", maxReadChunk: 1).maxReadChunk, 4096)
    }
}
