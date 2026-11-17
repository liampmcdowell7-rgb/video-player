import XCTest
import VideoPlayerCore
@testable import SourceSFTP

// Host key trust, as the app wires it: PinningSFTPBackend + CertificatePin around the fake backend (FIXTURE: no real server).
final class PinningSFTPBackendTests: XCTestCase {
    private func source(backend: FakeSFTPBackend, pin: CertificatePin) -> TrustGuardedSource {
        let sftp = SFTPSource(host: "nas.local", credential: .password(username: "me", password: "pw"),
                              hostKeyPolicy: .pinned(""), backend: PinningSFTPBackend(backend, pin: pin))
        return TrustGuardedSource(sftp, pin: pin)
    }

    private let files: [String: Data] = ["/a.mkv": Data([1, 2, 3])]

    func testWithNothingApprovedTheKeyIsRefusedAndReportedAsFirstUse() async throws {
        let backend = FakeSFTPBackend(files: files, folders: ["/"])
        let pin = CertificatePin(kind: .sshHostKey, host: "nas.local", trusted: nil)
        let guarded = source(backend: backend, pin: pin)
        do { try await guarded.authenticate(); XCTFail("must not connect without approval") }
        catch let error as TrustRefusedError {
            XCTAssertNil(error.refusal.expected)
            XCTAssertFalse(error.refusal.isChange)
            XCTAssertEqual(error.refusal.presented, "SHA256:fake-fingerprint")
            XCTAssertEqual(error.refusal.kind, .sshHostKey)
        }
    }

    func testTheApprovedKeyConnectsAndListsEveryTime() async throws {
        let backend = FakeSFTPBackend(files: files, folders: ["/"])
        let pin = CertificatePin(kind: .sshHostKey, host: "nas.local", trusted: "SHA256:fake-fingerprint")
        let guarded = source(backend: backend, pin: pin)
        try await guarded.authenticate()
        let names = try await guarded.list("/").map(\.name)
        XCTAssertEqual(names, ["a.mkv"])
        let bytes = try await guarded.read("/a.mkv", range: ByteRange(offset: 1, length: 2))
        XCTAssertEqual(bytes, Data([2, 3]))
    }

    func testAChangedKeyIsRefusedOnScanBrowseAndPlayAndNeverAutoTrusted() async throws {
        let backend = FakeSFTPBackend(files: files, folders: ["/"])
        let pin = CertificatePin(kind: .sshHostKey, host: "nas.local", trusted: "SHA256:approved-earlier")
        let guarded = source(backend: backend, pin: pin)   // the server presents "SHA256:fake-fingerprint"
        for step in 0..<3 {
            do {
                switch step {
                case 0: _ = try await guarded.list("/")
                case 1: _ = try await guarded.info("/a.mkv")
                default: _ = try await guarded.read("/a.mkv", range: ByteRange(offset: 0, length: 1))
                }
                XCTFail("step \(step) must be refused")
            } catch let error as TrustRefusedError {
                XCTAssertTrue(error.refusal.isChange)
                XCTAssertEqual(error.refusal.expected, "SHA256:approved-earlier")
                XCTAssertEqual(error.refusal.presented, "SHA256:fake-fingerprint")
                XCTAssertTrue(error.localizedDescription.contains("not the one you approved"))
            }
        }
        let connects = await backend.connects
        XCTAssertGreaterThanOrEqual(connects, 3, "each try really reached the host key check")
    }

    func testTheRefusalCallbackFiresSoTheAppCanShowTheState() async throws {
        let box = RefusalBox()
        let backend = FakeSFTPBackend(files: files, folders: ["/"])
        let pin = CertificatePin(kind: .sshHostKey, host: "nas.local", trusted: "SHA256:old") { box.add($0) }
        _ = try? await source(backend: backend, pin: pin).authenticate()
        XCTAssertEqual(box.all.count, 1)
        XCTAssertEqual(box.all.first?.presented, "SHA256:fake-fingerprint")
    }
}

private final class RefusalBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TrustRefusal] = []
    var all: [TrustRefusal] { lock.withLock { items } }
    func add(_ r: TrustRefusal) { lock.withLock { items.append(r) } }
}
