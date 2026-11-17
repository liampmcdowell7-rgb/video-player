import XCTest
@testable import VideoPlayerCore

final class SourceStatusTests: XCTestCase {
    static let realServer: Set<SourceKind> = [.webdav, .jellyfin, .emby, .ftp, .upnp]
    static let contractOnly: Set<SourceKind> = [.smb, .nfs, .sftp, .directLink, .oneDrive]

    func testVerificationLevelsMatchTheEvidenceInDocsSources() {
        for kind in SourceKind.allCases {
            if Self.realServer.contains(kind) {
                XCTAssertEqual(kind.verification, .realServer, "\(kind)")
                XCTAssertNil(kind.notVerifiedLabel, "\(kind)")
            } else if Self.contractOnly.contains(kind) {
                XCTAssertEqual(kind.verification, .contractTestsOnly, "\(kind)")
                XCTAssertEqual(kind.notVerifiedLabel, "Not yet verified against a real server", "\(kind)")
            } else {
                XCTAssertEqual(kind.verification, .notVerified, "\(kind) must not claim verification yet")
                XCTAssertEqual(kind.notVerifiedLabel, "Not yet verified against a real server", "\(kind)")
            }
        }
    }

    func testLimitsMatchTheDocumentedDecisions() {
        XCTAssertEqual(SourceKind.dropbox.limit, .platformLimited)
        XCTAssertEqual(SourceKind.googleDrive.limit, .platformLimited)
        XCTAssertEqual(SourceKind.plex.limit, .vendorAccountBlocked)
        XCTAssertEqual(SourceKind.oneDrive.limit, .vendorAccountBlocked)
        let limited: Set<SourceKind> = [.dropbox, .googleDrive, .plex, .oneDrive]
        for kind in SourceKind.allCases where !limited.contains(kind) {
            XCTAssertEqual(kind.limit, .none, "\(kind)")
            XCTAssertTrue(kind.gatesPublicRelease)
        }
        for kind in limited { XCTAssertFalse(kind.gatesPublicRelease) }
    }

    func testVerificationOrdering() {
        XCTAssertTrue(VerificationLevel.notVerified < .contractTestsOnly)
        XCTAssertTrue(VerificationLevel.contractTestsOnly < .realServer)
        XCTAssertTrue(VerificationLevel.realServer < .onDevice)
    }
}
