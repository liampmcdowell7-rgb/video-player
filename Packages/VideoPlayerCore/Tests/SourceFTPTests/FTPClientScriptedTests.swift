import XCTest
import VideoPlayerCore
@testable import SourceFTP

final class FTPClientScriptedTests: XCTestCase {
    private func makeServer() -> FakeFTPServer {
        let s = FakeFTPServer()
        s.directories = ["/", "/Movies", "/Shows", "/Shows/Season 1"]
        s.files["/Movies/Test Movie.mkv"] = .init(content: patternBytes(offset: 0, count: 100_000))
        s.files["/notes.txt"] = .init(content: Data("hello".utf8))
        return s
    }

    private func client(_ server: FakeFTPServer, password: String = "secret", security: FTPSecurity = .none) -> FTPClient {
        FTPClient(host: "ftp.example", port: 21, credentials: .init(username: "tester", password: password), security: security, connector: server)
    }

    // MARK: Login

    func testLoginSequenceAndCapabilities() async throws {
        let server = makeServer()
        let c = client(server)
        try await c.authenticate()
        XCTAssertEqual(server.commands, ["USER tester", "PASS ****", "FEAT", "OPTS UTF8 ON", "TYPE I"])
        XCTAssertEqual(c.kind, .ftp)
        XCTAssertTrue(c.capabilities.byteRanges)
        XCTAssertFalse(c.capabilities.directPlaybackURL)
        let access = try await c.playbackAccess(for: "/notes.txt")
        XCTAssertEqual(access, .byteReader)
    }

    func testWrongPasswordIsUnauthorizedAndNotRetried() async {
        let server = makeServer()
        let c = client(server, password: "nope")
        do { try await c.authenticate(); XCTFail("expected unauthorized") }
        catch { XCTAssertEqual(error as? SourceError, .unauthorized) }
        XCTAssertEqual(server.controlConnections, 1)
    }

    // MARK: Listing

    func testListUsesMLSDAndOpensEPSVDataConnection() async throws {
        let server = makeServer()
        let c = client(server)
        let entries = try await c.list("/")
        XCTAssertEqual(entries.map(\.name).sorted(), ["Movies", "Shows", "notes.txt"])
        XCTAssertTrue(server.commands.contains("EPSV"))
        XCTAssertTrue(server.commands.contains("MLSD /"))
        let data = server.connections.last!
        XCTAssertEqual(data.host, "ftp.example", "the data connection dials the control host")
        XCTAssertFalse(data.tls)
    }

    func testListFallsBackToLISTWithoutMLST() async throws {
        let server = makeServer()
        server.supportsMLSD = false
        let c = client(server)
        let entries = try await c.list("/Movies")
        XCTAssertEqual(entries.map(\.name), ["Test Movie.mkv"])
        XCTAssertEqual(entries.first?.size, 100_000)
        XCTAssertTrue(server.commands.contains("LIST /Movies"))
        XCTAssertFalse(server.commands.contains { $0.hasPrefix("MLSD") })
    }

    func testListFallsBackWhenMLSDIsAdvertisedButRefused() async throws {
        let server = makeServer()
        server.features = ["MLST type*;", "EPSV"]
        server.supportsMLSD = true
        server.listFormat = .unix
        let c = FTPClient(host: "h", credentials: .init(username: "tester", password: "secret"), connector: server)
        // The server advertised MLST at login, then rejects MLSD (500) afterwards.
        try await c.authenticate()
        server.supportsMLSD = false
        let entries = try await c.list("/Movies")
        XCTAssertEqual(entries.map(\.name), ["Test Movie.mkv"])
        XCTAssertTrue(server.commands.contains("MLSD /Movies"))
        XCTAssertTrue(server.commands.contains("LIST /Movies"))
        // Later lists skip the failing MLSD.
        let before = server.commands.filter { $0.hasPrefix("MLSD") }.count
        _ = try await c.list("/Movies")
        XCTAssertEqual(server.commands.filter { $0.hasPrefix("MLSD") }.count, before)
    }

    func testListDOSFormat() async throws {
        let server = makeServer()
        server.supportsMLSD = false
        server.listFormat = .dos
        let entries = try await client(server).list("/")
        XCTAssertEqual(Set(entries.map(\.name)), ["Movies", "Shows", "notes.txt"])
        XCTAssertEqual(entries.first { $0.name == "notes.txt" }?.size, 5)
        XCTAssertTrue(entries.first { $0.name == "Movies" }!.isDirectory)
    }

    func testListMissingFolderIsNotFound() async {
        let c = client(makeServer())
        do { _ = try await c.list("/nope"); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testPASVWhenEPSVIsUnsupportedUsesControlHostNotAnnouncedAddress() async throws {
        let server = makeServer()
        server.supportsEPSV = false
        let c = client(server)
        _ = try await c.list("/")
        XCTAssertTrue(server.commands.contains("EPSV"))
        XCTAssertTrue(server.commands.contains("PASV"))
        XCTAssertEqual(server.connections.last?.host, "ftp.example", "10.0.0.5 in the reply is ignored")
        // EPSV is not tried again on this server.
        _ = try await c.list("/")
        XCTAssertEqual(server.commands.filter { $0 == "EPSV" }.count, 1)
    }

    // MARK: Info

    func testInfoForFileViaMLST() async throws {
        let c = client(makeServer())
        let e = try await c.info("/Movies/Test Movie.mkv")
        XCTAssertEqual(e.name, "Test Movie.mkv")
        XCTAssertEqual(e.path, "/Movies/Test Movie.mkv")
        XCTAssertEqual(e.size, 100_000)
        XCTAssertFalse(e.isDirectory)
        XCTAssertNotNil(e.modified)
    }

    func testInfoForFolderAndRoot() async throws {
        let c = client(makeServer())
        let folder = try await c.info("/Movies")
        XCTAssertTrue(folder.isDirectory)
        let root = try await c.info("/")
        XCTAssertTrue(root.isDirectory)
        XCTAssertEqual(root.path, "/")
    }

    func testInfoWithoutMLSTUsesSIZEMDTMAndCWD() async throws {
        let server = makeServer()
        server.supportsMLSD = false
        server.features = ["SIZE", "MDTM"]
        let c = client(server)
        let file = try await c.info("/notes.txt")
        XCTAssertEqual(file.size, 5)
        XCTAssertNotNil(file.modified)
        let folder = try await c.info("/Shows")
        XCTAssertTrue(folder.isDirectory)
    }

    func testInfoMissingIsNotFound() async {
        let c = client(makeServer())
        do { _ = try await c.info("/ghost.mkv"); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    // MARK: Reads

    func testRangedReadSendsRESTAndAbortsTheTransferEarly() async throws {
        let server = makeServer()
        let c = client(server)
        let bytes = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 5000, length: 700))
        XCTAssertEqual(bytes, patternBytes(offset: 5000, count: 700))
        XCTAssertTrue(server.commands.contains("REST 5000"))
        XCTAssertTrue(server.commands.contains("RETR /Movies/Test Movie.mkv"))
        XCTAssertEqual(server.abortedTransfers, 1, "the data connection was closed before the end of the file")
        // The same control connection keeps working afterwards.
        let again = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 0, length: 10))
        XCTAssertEqual(again, patternBytes(offset: 0, count: 10))
        XCTAssertFalse(server.commands.contains("REST 0"), "offset 0 needs no REST")
        XCTAssertEqual(server.controlConnections, 1)
    }

    func testReadShortAtEndOfFile() async throws {
        let c = client(makeServer())
        let bytes = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 99_990, length: 500))
        XCTAssertEqual(bytes, patternBytes(offset: 99_990, count: 10))
    }

    func testReadWholeSmallFile() async throws {
        let c = client(makeServer())
        let bytes = try await c.read("/notes.txt", range: ByteRange(offset: 0, length: 1000))
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "hello")
    }

    func testZeroLengthReadTouchesNoServer() async throws {
        let server = makeServer()
        let bytes = try await client(server).read("/notes.txt", range: ByteRange(offset: 0, length: 0))
        XCTAssertTrue(bytes.isEmpty)
        XCTAssertEqual(server.controlConnections, 0)
    }

    func testSeekPastEndIsRangeNotSatisfiable() async {
        let c = client(makeServer())
        do { _ = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 100_000_000, length: 10)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable) }
    }

    func testSeekToExactEndIsRangeNotSatisfiable() async {
        let c = client(makeServer())
        do { _ = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 100_000, length: 10)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .rangeNotSatisfiable) }
    }

    func testServerWithoutRESTIsRangesNotSupported() async throws {
        let server = makeServer()
        server.supportsREST = false
        let c = client(server)
        do { _ = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 10, length: 10)); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .rangesNotSupported) }
        // Offset 0 still works without REST.
        let head = try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: 0, length: 10))
        XCTAssertEqual(head, patternBytes(offset: 0, count: 10))
    }

    func testReadMissingFileIsNotFound() async {
        let c = client(makeServer())
        do { _ = try await c.read("/nope.mkv", range: ByteRange(offset: 0, length: 10)); XCTFail("expected notFound") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    // MARK: Reconnect and concurrency

    func testDroppedControlConnectionIsReestablishedAndTheCallRetried() async throws {
        let server = makeServer()
        let c = client(server)
        _ = try await c.list("/")
        XCTAssertEqual(server.controlConnections, 1)
        server.dropNextCommand = true
        let entries = try await c.list("/Movies")
        XCTAssertEqual(entries.map(\.name), ["Test Movie.mkv"])
        XCTAssertEqual(server.controlConnections, 2)
        XCTAssertEqual(server.commands.filter { $0 == "USER tester" }.count, 2, "logged in again")
    }

    func testAuthenticateAgainOpensAFreshConnection() async throws {
        let server = makeServer()
        let c = client(server)
        try await c.authenticate()
        try await c.authenticate()
        XCTAssertEqual(server.controlConnections, 2)
    }

    func testConcurrentReadsAreSerialisedAndCorrect() async throws {
        let server = makeServer()
        let c = client(server)
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for i in 0..<8 {
                group.addTask { (i, try await c.read("/Movies/Test Movie.mkv", range: ByteRange(offset: Int64(i * 9000), length: 1234))) }
            }
            for try await (i, data) in group {
                XCTAssertEqual(data, patternBytes(offset: i * 9000, count: 1234), "read \(i)")
            }
        }
        XCTAssertEqual(server.controlConnections, 1)
    }

    // MARK: FTPS sequencing

    func testExplicitTLSSequence() async throws {
        let server = makeServer()
        server.requireTLS = true
        let c = client(server, security: .explicitTLS)
        _ = try await c.list("/")
        XCTAssertEqual(Array(server.commands.prefix(6)), ["AUTH TLS", "USER tester", "PASS ****", "PBSZ 0", "PROT P", "FEAT"])
        XCTAssertEqual(server.tlsUpgrades, 1)
        let control = server.connections[0]
        XCTAssertFalse(control.tls)
        XCTAssertTrue(control.allowUpgrade, "explicit FTPS opens the control stream upgradable")
        let data = server.connections[1]
        XCTAssertTrue(data.tls, "PROT P means the data connection is protected")
        XCTAssertFalse(data.allowUpgrade)
    }

    func testExplicitTLSIsRefusedWhenTheServerHasNoAuthTLS() async {
        let server = makeServer()
        server.refuseAuthTLS = true
        let c = client(server, security: .explicitTLS)
        do { try await c.authenticate(); XCTFail("expected an error") }
        catch {
            guard case .unsupported? = error as? SourceError else { return XCTFail("got \(error)") }
        }
        XCTAssertFalse(server.commands.contains("USER tester"), "credentials are never sent unprotected")
    }

    func testImplicitTLSConnectsWithTLSImmediately() async throws {
        let server = makeServer()
        let c = client(server, security: .implicitTLS)
        _ = try await c.list("/")
        XCTAssertTrue(server.connections[0].tls)
        XCTAssertFalse(server.connections[0].allowUpgrade)
        XCTAssertEqual(server.tlsUpgrades, 0)
        XCTAssertEqual(Array(server.commands.prefix(5)), ["USER tester", "PASS ****", "PBSZ 0", "PROT P", "FEAT"])
        XCTAssertTrue(server.connections[1].tls)
    }

    func testPlainFTPNeverSendsPBSZ() async throws {
        let server = makeServer()
        _ = try await client(server).list("/")
        XCTAssertFalse(server.commands.contains("PBSZ 0"))
        XCTAssertFalse(server.commands.contains("AUTH TLS"))
    }

    func testTransportWithoutTLSIsReportedAsUnsupported() async {
        let c = FTPClient(host: "127.0.0.1", port: 1, credentials: .anonymous, security: .implicitTLS, connector: NoTLSConnector())
        do { try await c.authenticate(); XCTFail("expected an error") }
        catch { guard case .unsupported? = error as? SourceError else { return XCTFail("got \(error)") } }
    }

    // MARK: Safety

    func testPathWithLineBreakIsRejected() async {
        let c = client(makeServer())
        do { _ = try await c.list("/a\r\nDELE x"); XCTFail("expected an error") }
        catch { XCTAssertEqual(error as? SourceError, .invalidURL) }
    }
}

private struct NoTLSConnector: FTPConnector {
    func connect(host: String, port: Int, tls: Bool, allowUpgrade: Bool) async throws -> FTPStream {
        throw FTPStreamError.tlsUnavailable("no TLS here")
    }
}
