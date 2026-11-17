import XCTest
@testable import VideoPlayerCore

// FIXTURE: fingerprints below are made-up strings shaped like a SHA-256 hex digest and an ssh-keygen "SHA256:" line.
private let hexA = "ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12"
private let hexB = "00" + hexA.dropFirst(2)
private let sshA = "SHA256:Zm9vYmFyZm9vYmFyZm9vYmFyZm9vYmFyZm9vYmFyMTI"
private let sshB = "SHA256:YmF6YmF6YmF6YmF6YmF6YmF6YmF6YmF6YmF6YmF6MTI"

final class CertificatePinTests: XCTestCase {
    func testHexFingerprintsCompareWithoutCaseColonsOrSpaces() {
        XCTAssertTrue(TrustFingerprint.matches(hexA, hexA.uppercased()))
        let colons = stride(from: 0, to: hexA.count, by: 2).map { i -> String in
            let s = hexA.index(hexA.startIndex, offsetBy: i); return String(hexA[s..<hexA.index(s, offsetBy: 2)])
        }.joined(separator: ":")
        XCTAssertTrue(TrustFingerprint.matches(colons, hexA))
        XCTAssertFalse(TrustFingerprint.matches(hexA, hexB))
        XCTAssertFalse(TrustFingerprint.matches("", ""), "two empty strings never count as a match")
    }

    func testSSHFingerprintsAreCaseSensitive() {
        XCTAssertTrue(TrustFingerprint.matches(sshA, sshA))
        XCTAssertFalse(TrustFingerprint.matches(sshA, sshA.lowercased().replacingOccurrences(of: "sha256:", with: "SHA256:")))
        XCTAssertFalse(TrustFingerprint.matches(sshA, sshB))
    }

    func testAPinWithNothingApprovedRefusesAndReportsFirstUse() {
        let pin = CertificatePin(kind: .tlsCertificate, host: "nas.local", trusted: nil)
        XCTAssertFalse(pin.accepts(presented: hexA))
        let refusal = pin.lastRefusal
        XCTAssertEqual(refusal, TrustRefusal(kind: .tlsCertificate, host: "nas.local", expected: nil, presented: hexA))
        XCTAssertEqual(refusal?.isChange, false)
    }

    func testTheApprovedFingerprintIsAcceptedAndALaterDifferentOneIsAChange() {
        let pin = CertificatePin(kind: .tlsCertificate, host: "nas.local", trusted: hexA.uppercased())
        XCTAssertTrue(pin.accepts(presented: hexA))
        XCTAssertNil(pin.lastRefusal)
        XCTAssertFalse(pin.accepts(presented: hexB))
        XCTAssertEqual(pin.lastRefusal?.isChange, true)
        XCTAssertEqual(pin.lastRefusal?.presented, hexB)
        XCTAssertNotNil(pin.takeRefusal())
        XCTAssertNil(pin.lastRefusal, "taking a refusal clears it")
    }

    func testAnEmptyApprovedValueMeansNothingIsApproved() {
        let pin = CertificatePin(kind: .sshHostKey, host: "h", trusted: "  ")
        XCTAssertNil(pin.trusted)
        XCTAssertFalse(pin.accepts(presented: sshA))
        XCTAssertEqual(pin.lastRefusal?.isChange, false)
    }

    func testTheRefusalCallbackIsCalledOnEveryRefusalButNotOnAcceptance() {
        let box = Box()
        let pin = CertificatePin(kind: .sshHostKey, host: "h", trusted: sshA) { box.add($0) }
        XCTAssertTrue(pin.accepts(presented: sshA))
        XCTAssertFalse(pin.accepts(presented: sshB))
        XCTAssertFalse(pin.accepts(presented: sshB))
        XCTAssertEqual(box.count, 2)
    }

    func testTheErrorTextSaysChangedAndNeverClaimsTrust() {
        let changed = TrustRefusedError(TrustRefusal(kind: .tlsCertificate, host: "h", expected: hexA, presented: hexB))
        XCTAssertTrue(changed.localizedDescription.contains("not the one you approved"))
        XCTAssertTrue(changed.localizedDescription.contains("certificate"))
        XCTAssertTrue(changed.localizedDescription.contains("Nothing was trusted automatically"))
        let key = TrustRefusedError(TrustRefusal(kind: .sshHostKey, host: "h", expected: nil, presented: sshA))
        XCTAssertTrue(key.localizedDescription.contains("host key"))
        XCTAssertTrue(key.localizedDescription.contains("not been approved"))
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    var count: Int { lock.withLock { n } }
    func add(_ r: TrustRefusal) { lock.withLock { n += 1 } }
}

// A source whose transport "refuses" the server through the pin and throws a vague error, as URLSession would.
private struct RefusingSource: MediaSource {
    let pin: CertificatePin
    let presented: String
    var kind: SourceKind { .webdav }
    var capabilities: SourceCapabilities { SourceCapabilities(authMethods: [.none], byteRanges: true, changeSignals: []) }
    private func connect() throws {
        if !pin.accepts(presented: presented) { throw SourceError.transport("cancelled") }
    }
    func authenticate() async throws { try connect() }
    func list(_ path: String) async throws -> [SourceEntry] { try connect(); return [] }
    func info(_ path: String) async throws -> SourceEntry { try connect(); return SourceEntry(path: path, name: "x", isDirectory: false) }
    func read(_ path: String, range: ByteRange) async throws -> Data { try connect(); return Data([1]) }
    func playbackAccess(for path: String) async throws -> PlaybackAccess { try connect(); return .byteReader }
}

final class TrustGuardedSourceTests: XCTestCase {
    func testAChangedCertificateSurfacesAsATrustErrorFromEveryOperation() async throws {
        let pin = CertificatePin(kind: .tlsCertificate, host: "nas.local", trusted: hexA)
        let guarded = TrustGuardedSource(RefusingSource(pin: pin, presented: hexB), pin: pin)
        for step in 0..<5 {
            do {
                switch step {
                case 0: try await guarded.authenticate()
                case 1: _ = try await guarded.list("/")
                case 2: _ = try await guarded.info("/a")
                case 3: _ = try await guarded.read("/a", range: ByteRange(offset: 0, length: 1))
                default: _ = try await guarded.playbackAccess(for: "/a")
                }
                XCTFail("step \(step) should have been refused")
            } catch let error as TrustRefusedError {
                XCTAssertEqual(error.refusal.expected, hexA)
                XCTAssertEqual(error.refusal.presented, hexB)
                XCTAssertTrue(error.refusal.isChange)
            }
        }
    }

    func testTheApprovedCertificatePassesAndOtherErrorsAreNotDisguised() async throws {
        let pin = CertificatePin(kind: .tlsCertificate, host: "nas.local", trusted: hexA)
        let ok = TrustGuardedSource(RefusingSource(pin: pin, presented: hexA), pin: pin)
        try await ok.authenticate()
        let bytes = try await ok.read("/a", range: ByteRange(offset: 0, length: 1))
        XCTAssertEqual(bytes, Data([1]))
        // A plain network failure with no refusal stays what it was.
        struct Failing: MediaSource {
            var kind: SourceKind { .webdav }
            var capabilities: SourceCapabilities { SourceCapabilities(authMethods: [.none], byteRanges: true, changeSignals: []) }
            func authenticate() async throws { throw SourceError.transport("offline") }
            func list(_ path: String) async throws -> [SourceEntry] { [] }
            func info(_ path: String) async throws -> SourceEntry { throw SourceError.notFound }
            func read(_ path: String, range: ByteRange) async throws -> Data { Data() }
            func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }
        }
        let other = TrustGuardedSource(Failing(), pin: CertificatePin(kind: .tlsCertificate, host: "h", trusted: hexA))
        do { try await other.authenticate(); XCTFail() } catch let error as SourceError { XCTAssertEqual(error, .transport("offline")) }
    }
}
