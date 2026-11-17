import XCTest
import VideoPlayerCore
@testable import SourceFTP

final class FTPParserTests: XCTestCase {
    // MARK: Replies

    func testSingleLineReply() async throws {
        let ch = FTPControlChannel(stream: ChunkedStream([Data("220 Welcome\r\n".utf8)]))
        let r = try await ch.readReply()
        XCTAssertEqual(r.code, 220)
        XCTAssertEqual(r.text, "Welcome")
    }

    func testMultilineReplySplitIntoOneByteChunks() async throws {
        let text = "211-Features:\r\n MLST type*;size*;\r\n211-not the end\r\n REST STREAM\r\n211 End\r\n"
        let ch = FTPControlChannel(stream: ChunkedStream(text.utf8.map { Data([$0]) }))
        let r = try await ch.readReply()
        XCTAssertEqual(r.code, 211)
        XCTAssertEqual(r.lines.count, 5)
        XCTAssertEqual(r.lines[1], " MLST type*;size*;")
        XCTAssertEqual(r.lines.last, "211 End")
    }

    func testTwoRepliesInOnePacket() async throws {
        let ch = FTPControlChannel(stream: ChunkedStream([Data("150 Opening\r\n226 Done\r\n".utf8)]))
        let a = try await ch.readReply()
        let b = try await ch.readReply()
        XCTAssertEqual([a.code, b.code], [150, 226])
    }

    func testMalformedReplyThrows() async {
        let ch = FTPControlChannel(stream: ChunkedStream([Data("hello\r\n".utf8)]))
        do { _ = try await ch.readReply(); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .malformedResponse) }
    }

    func test421MeansConnectionClosed() async {
        let ch = FTPControlChannel(stream: ChunkedStream([Data("421 Timeout\r\n".utf8)]))
        do { _ = try await ch.readReply(); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? FTPStreamError, .closed) }
    }

    func testEndOfStreamThrowsClosed() async {
        let ch = FTPControlChannel(stream: ChunkedStream([]))
        do { _ = try await ch.readReply(); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? FTPStreamError, .closed) }
    }

    // MARK: Passive replies

    func testPASV() {
        let r = FTPParsers.parsePASV("Entering Passive Mode (192,168,1,20,195,80).")
        XCTAssertEqual(r?.host, "192.168.1.20")
        XCTAssertEqual(r?.port, 195 * 256 + 80)
        XCTAssertNil(FTPParsers.parsePASV("Entering Passive Mode (1,2,3)"))
        XCTAssertNil(FTPParsers.parsePASV("(1,2,3,4,300,5)"))
    }

    func testEPSV() {
        XCTAssertEqual(FTPParsers.parseEPSV("229 Entering Extended Passive Mode (|||6446|)"), 6446)
        XCTAssertEqual(FTPParsers.parseEPSV("229 ok (!!!2121!)"), 2121)
        XCTAssertNil(FTPParsers.parseEPSV("229 broken (|||0|)"))
        XCTAssertNil(FTPParsers.parseEPSV("229 broken"))
    }

    // MARK: Dates

    func testMDTM() {
        let d = FTPParsers.parseMDTM("20240102030405")!
        XCTAssertEqual(d.timeIntervalSince1970, 1_704_164_645)
        XCTAssertNotNil(FTPParsers.parseMDTM("20240102030405.123"))
        XCTAssertNil(FTPParsers.parseMDTM("2024"))
    }

    // MARK: MLSD

    func testMLSDSkipsCurrentAndParentDirectoriesAndReadsFacts() {
        let text = """
        type=cdir;modify=20240101000000; .\r
        type=pdir;modify=20240101000000; ..\r
        type=dir;modify=20240101000000; Season 1\r
        type=file;size=3145728;modify=20200102030405;perm=r; Test Movie (2020).mkv\r

        """
        let entries = FTPParsers.parseMLSD(text, parent: "/Movies")
        XCTAssertEqual(entries.map(\.name), ["Season 1", "Test Movie (2020).mkv"])
        XCTAssertEqual(entries[0].path, "/Movies/Season 1")
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertNil(entries[0].size)
        XCTAssertEqual(entries[1].size, 3_145_728)
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertNotNil(entries[1].modified)
    }

    func testMLSDNameWithSpacesAndUnicode() {
        let e = FTPParsers.parseMLSD("type=file;size=4096; Café – 100% [test] #1.mp4\r\n", parent: "/Odd Names")
        XCTAssertEqual(e.first?.name, "Café – 100% [test] #1.mp4")
        XCTAssertEqual(e.first?.path, "/Odd Names/Café – 100% [test] #1.mp4")
    }

    func testMLSDUppercaseFactNames() {
        let e = FTPParsers.parseMLSD("Type=File;Size=12;Modify=20240102030405; a.mkv\r\n", parent: "/")
        XCTAssertEqual(e.first?.size, 12)
        XCTAssertEqual(e.first?.path, "/a.mkv")
    }

    // MARK: LIST

    func testUnixList() {
        let now = Date(timeIntervalSince1970: 1_730_000_000)   // late Oct 2024
        let text = """
        total 12\r
        drwxr-xr-x    2 ftp      ftp          4096 Mar 02  2024 Movies\r
        -rw-r--r--    1 ftp      ftp       3145728 Oct 20 10:15 Test Movie (2020).mkv\r
        lrwxrwxrwx    1 ftp      ftp             7 Mar 02  2024 link -> Movies\r
        -rw-r--r--    1 ftp      ftp             5 Dec 25 10:15 future.txt\r
        drwxr-xr-x    2 ftp      ftp          4096 Mar 02  2024 .\r
        drwxr-xr-x    2 ftp      ftp          4096 Mar 02  2024 ..\r

        """
        let e = FTPParsers.parseList(text, parent: "/", now: now)
        XCTAssertEqual(e.map(\.name), ["Movies", "Test Movie (2020).mkv", "link", "future.txt"])
        XCTAssertTrue(e[0].isDirectory)
        XCTAssertEqual(e[1].size, 3_145_728)
        XCTAssertEqual(e[1].path, "/Test Movie (2020).mkv")
        let cal = Calendar(identifier: .gregorian)
        var utc = cal; utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.year, from: e[1].modified!), 2024)
        XCTAssertEqual(utc.component(.year, from: e[3].modified!), 2023, "a date in the future without a year means last year")
    }

    func testUnixListWithoutGroupColumn() {
        let e = FTPParsers.parseList("-rw-r--r-- 1 owner 1234 Jan  5  2023 no group.txt\r\n", parent: "/x")
        XCTAssertEqual(e.first?.name, "no group.txt")
        XCTAssertEqual(e.first?.size, 1234)
    }

    func testDOSList() {
        let text = "03-02-24  10:00AM       <DIR>          Shows\r\n03-02-2024 01:30PM 2048 Test Movie.srt\r\n"
        let e = FTPParsers.parseList(text, parent: "/")
        XCTAssertEqual(e.map(\.name), ["Shows", "Test Movie.srt"])
        XCTAssertTrue(e[0].isDirectory)
        XCTAssertEqual(e[1].size, 2048)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(utc.component(.hour, from: e[1].modified!), 13)
    }

    func testGarbageListLinesAreIgnored() {
        XCTAssertTrue(FTPParsers.parseList("what is this\r\n\r\n", parent: "/").isEmpty)
    }

    // MARK: Paths

    func testPathHelpers() {
        XCTAssertEqual(FTPParsers.parent(of: "/a/b/c"), "/a/b")
        XCTAssertEqual(FTPParsers.parent(of: "/a"), "/")
        XCTAssertEqual(FTPParsers.parent(of: "/"), "/")
        XCTAssertEqual(FTPParsers.join("/", "x"), "/x")
        XCTAssertEqual(FTPParsers.join("/a", "x"), "/a/x")
        XCTAssertEqual(FTPClient.normalize("a/b/"), "/a/b")
        XCTAssertEqual(FTPClient.normalize("/"), "/")
    }
}
