import XCTest
import Citadel
import NIOCore
import VideoPlayerCore
import SourceSFTP
@testable import SourceSFTPCitadel

/// Tests that need no server. The server-backed tests are in CitadelLiveTests.swift.
final class CitadelUnitTests: XCTestCase {

    // MARK: Host key fingerprint, compared with what the real `ssh-keygen -l -E sha256` printed for these keys.
    // The three keys were generated for this test with ssh-keygen (OpenSSH) in WSL; they are public keys only.

    private let ed25519Line = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDI0Ugb6ixyiCwLFy5FQeJxjAjnqhSD1ilXrJvZ45gaz vp-test-fixture"
    private let ed25519Fingerprint = "SHA256:nWLd/0pGHnfvLSsEl/VZ6y0vLO9xZr1sA1hWYtASpPs"
    private let rsaLine = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzhJ3ZeiIo/yqdj6+yg8vUgbGwgFouizn6Vm43fB8tUNLqPXU9MMG26Hc7ipDtPXFFEk0qTt+5M1xK7d1bs+Z8hDg7NCB4nZnPCRzE3SmVE0lEX2V15NK8hK7sY9Az1rNhnqMaJU+soYvJj1Ok4FXdQWA2lSnttFUTYg2fvqXDu5kQFiFTQS6YMqEpk4neLEPvB4TSlSsSJEsfEZPCcfCFcq98ziCrWaq9Awfsw6UTEByFIuMhf1J24NkoCDlnCqTcZkqJMhZEGmxojbxRSvWSC7+SnBKhkqf17hWlUBegAoZns4e0FxdZ93gm0YpARjuH2pMEfIjNSQ20J00/jDrl vp-test-fixture"
    private let rsaFingerprint = "SHA256:fMKBVns5Ah0rQ2xbclbSxceAvIU2k4PdrWq426ixT3E"
    private let ecdsaLine = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNKHGqLhYx5+aU+JNPkyjc5Q/xYiYOCybYVk3VqBlG6HwvOl7NUcgAhnsr4OOJWW3O8h/AapKs44OCVTFDsRWOA= vp-test-fixture"
    private let ecdsaFingerprint = "SHA256:1ECIdbn2s/QdvX40Mn5VCPZ0N6ZBI4dJ/la9DBjI0Ag"

    func testFingerprintMatchesSshKeygenForEd25519() {
        XCTAssertEqual(HostKeyFingerprint.sha256(openSSHPublicKeyLine: ed25519Line), ed25519Fingerprint)
    }

    func testFingerprintMatchesSshKeygenForRSA() {
        XCTAssertEqual(HostKeyFingerprint.sha256(openSSHPublicKeyLine: rsaLine), rsaFingerprint)
    }

    func testFingerprintMatchesSshKeygenForECDSA() {
        XCTAssertEqual(HostKeyFingerprint.sha256(openSSHPublicKeyLine: ecdsaLine), ecdsaFingerprint)
    }

    func testFingerprintIgnoresTheComment() {
        let bare = ed25519Line.replacingOccurrences(of: " vp-test-fixture", with: "")
        XCTAssertEqual(HostKeyFingerprint.sha256(openSSHPublicKeyLine: bare), ed25519Fingerprint)
    }

    func testFingerprintOfMalformedLinesIsNil() {
        XCTAssertNil(HostKeyFingerprint.sha256(openSSHPublicKeyLine: ""))
        XCTAssertNil(HostKeyFingerprint.sha256(openSSHPublicKeyLine: "ssh-ed25519"))
        XCTAssertNil(HostKeyFingerprint.sha256(openSSHPublicKeyLine: "ssh-ed25519 !!!not-base64!!!"))
    }

    func testFingerprintHasNoPaddingAndTheExpectedLength() throws {
        let f = try XCTUnwrap(HostKeyFingerprint.sha256(openSSHPublicKeyLine: rsaLine))
        XCTAssertTrue(f.hasPrefix("SHA256:"))
        XCTAssertEqual(f.count, 7 + 43)       // 32 bytes -> 44 base64 characters, one "=" removed
        XCTAssertFalse(f.contains("="))
    }

    // MARK: Attribute mapping

    func testDirectoryFileAndSymlinkAreTellApartByPermissionBits() {
        var dir = SFTPFileAttributes(); dir.permissions = 0o040755
        var file = SFTPFileAttributes(size: 1234); file.permissions = 0o100644
        var link = SFTPFileAttributes(); link.permissions = 0o120777
        XCTAssertTrue(CitadelSFTPBackend.attributes(from: dir).isDirectory)
        XCTAssertFalse(CitadelSFTPBackend.attributes(from: file).isDirectory)
        XCTAssertEqual(CitadelSFTPBackend.attributes(from: file).size, 1234)
        let l = CitadelSFTPBackend.attributes(from: link)
        XCTAssertTrue(l.isSymlink)
        XCTAssertFalse(l.isDirectory)
    }

    func testMissingPermissionsMeansAFile() {
        let a = CitadelSFTPBackend.attributes(from: SFTPFileAttributes(size: 9))
        XCTAssertFalse(a.isDirectory)
        XCTAssertFalse(a.isSymlink)
        XCTAssertEqual(a.size, 9)
        XCTAssertNil(a.modified)
    }

    func testModificationTimeIsCarriedOver() {
        let when = Date(timeIntervalSince1970: 1_600_000_000)
        let a = CitadelSFTPBackend.attributes(from: SFTPFileAttributes(
            size: 1,
            accessModificationTime: .init(accessTime: Date(timeIntervalSince1970: 1), modificationTime: when)))
        XCTAssertEqual(a.modified, when)
    }

    func testAnAbsurdlyLargeSizeDoesNotCrash() {
        let a = CitadelSFTPBackend.attributes(from: SFTPFileAttributes(size: UInt64.max))
        XCTAssertEqual(a.size, Int64.max)
    }

    // MARK: Authentication method

    func testPasswordCredentialBuildsAMethod() throws {
        _ = try CitadelSFTPBackend.authenticationMethod(for: .password(username: "u", password: "p"))
    }

    func testGarbageKeyIsRefusedWithAnExplainingError() {
        do {
            _ = try CitadelSFTPBackend.authenticationMethod(for: .privateKey(username: "u", pem: "this is not a key", passphrase: nil))
            XCTFail("expected an error")
        } catch let error as SFTPBackendError {
            guard case .other(let message) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertTrue(message.contains("supported"), message)
        } catch { XCTFail("wrong error type \(error)") }
    }

    // MARK: Error mapping

    func testBackendErrorsPassThrough() {
        XCTAssertEqual(CitadelSFTPBackend.map(SFTPBackendError.noSuchFile), .noSuchFile)
        XCTAssertEqual(CitadelSFTPBackend.map(SFTPBackendError.authenticationFailed), .authenticationFailed)
    }

    func testAuthenticationFailuresMapToAuthenticationFailed() {
        XCTAssertEqual(CitadelSFTPBackend.map(SSHClientError.allAuthenticationOptionsFailed), .authenticationFailed)
        XCTAssertEqual(CitadelSFTPBackend.map(SSHClientError.unsupportedPasswordAuthentication), .authenticationFailed)
    }

    func testClosedConnectionsMapToConnectionLost() {
        guard case .connectionLost = CitadelSFTPBackend.map(SFTPError.connectionClosed) else { return XCTFail() }
        guard case .connectionLost = CitadelSFTPBackend.map(SFTPError.missingResponse) else { return XCTFail() }
        guard case .connectionLost = CitadelSFTPBackend.map(ChannelError.ioOnClosedChannel) else { return XCTFail() }
    }

    func testProtocolErrorsAreReportedAsOther() {
        guard case .other = CitadelSFTPBackend.map(SFTPError.invalidResponse) else { return XCTFail() }
        guard case .other = CitadelSFTPBackend.map(CancellationError()) else { return XCTFail() }
    }

    func testBackendErrorsReachTheSourceAsTheRightSourceErrors() async {
        let unauthorized = await sourceError(for: .authenticationFailed)
        let hostKey = await sourceError(for: .hostKeyRejected(fingerprint: "SHA256:x"))
        XCTAssertEqual(unauthorized as? SourceError, .unauthorized)
        guard case .transport(let message)? = hostKey as? SourceError else { return XCTFail("wrong error \(String(describing: hostKey))") }
        XCTAssertTrue(message.contains("host key"), message)
    }

    /// What `SFTPSource.authenticate()` throws when the backend fails with `error`.
    private func sourceError(for error: SFTPBackendError) async -> Error? {
        let source = SFTPSource(
            host: "h", credential: .password(username: "u", password: "p"),
            hostKeyPolicy: .acceptAnyForTesting, backend: ThrowingBackend(error: error))
        do { try await source.authenticate(); return nil } catch let e { return e }
    }

    // MARK: Behaviour without a server

    func testUsingTheBackendBeforeConnectingReportsAConnectionProblem() async {
        let backend = CitadelSFTPBackend()
        do { _ = try await backend.listDirectory("/"); XCTFail("expected an error") }
        catch { guard case .connectionLost = error as? SFTPBackendError else { return XCTFail("\(error)") } }
        do { _ = try await backend.read("/x", offset: 0, length: 10); XCTFail("expected an error") }
        catch { guard case .connectionLost = error as? SFTPBackendError else { return XCTFail("\(error)") } }
        await backend.disconnect()   // must be harmless when nothing is open
    }

    func testConnectingToAClosedPortFailsQuicklyAsATransportError() async {
        let source = SFTPSource(
            host: "127.0.0.1", port: 1,
            credential: .password(username: "u", password: "p"),
            hostKeyPolicy: .acceptAnyForTesting,
            backend: CitadelSFTPBackend(connectTimeoutSeconds: 5))
        let started = Date()
        do { try await source.authenticate(); XCTFail("expected an error") }
        catch {
            guard case .transport = error as? SourceError else { return XCTFail("wrong error \(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}

private struct ThrowingBackend: SFTPBackend {
    let error: SFTPBackendError
    func connect(host: String, port: Int, credential: SFTPCredential, acceptHostKey: @escaping @Sendable (String) async -> Bool) async throws { throw error }
    func listDirectory(_ path: String) async throws -> [SFTPDirectoryEntry] { throw error }
    func attributes(of path: String) async throws -> SFTPAttributes { throw error }
    func read(_ path: String, offset: UInt64, length: UInt32) async throws -> Data { throw error }
    func disconnect() async {}
}
