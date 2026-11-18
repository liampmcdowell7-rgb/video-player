import XCTest
import Foundation
import UserData
@testable import LibraryBackup

// Launch safety (docs/API_USAGE.md "Launch safety"): a backup against a cloud that cannot be used ends in a status the
// Backup screen shows, never a crash. The CloudKit adapter reports "unknown" as the account status when the container could
// not be made, and maps the creation failure to UDCloudError.other(reason). Fakes only.

final class BackupLaunchSafetyTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("backup-safe-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func engine(_ cloud: InMemoryBackupCloud) -> BackupEngine {
        let files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(100, seed: 3))
        return BackupEngine(cloud: cloud, content: files, staging: dir.appendingPathComponent("staging"),
                            clock: { Date(timeIntervalSince1970: 2_000_000_000) }, forbidden: { [] },
                            sleep: { _ in }, onStatus: { _ in })
    }

    func testUnknownAccountIsOfflineNotACrash() async {
        let cloud = InMemoryBackupCloud()
        cloud.setAccount(.unknown)
        let r = await engine(cloud).backUp(settings: BackupSettings())
        XCTAssertEqual(r.status, .offline)
        XCTAssertEqual(cloud.calls(.upload), 0)
    }

    func testSignedOut() async {
        let cloud = InMemoryBackupCloud()
        cloud.setAccount(.noAccount)
        let r = await engine(cloud).backUp(settings: BackupSettings())
        XCTAssertEqual(r.status, .signedOut)
    }

    func testAMissingCapabilityIsAFailedStatusWithText() async {
        let cloud = InMemoryBackupCloud()
        cloud.inject(.fetchManifest, .other(CloudUnavailable.notInThisBuild.reason))
        let r = await engine(cloud).backUp(settings: BackupSettings())
        guard case .failed(let text) = r.status else { return XCTFail("expected failed, got \(r.status)") }
        XCTAssertFalse(text.isEmpty)
    }

    func testQuotaAndNoNetwork() async {
        let full = InMemoryBackupCloud()
        full.inject(.upload, .quotaExceeded)
        let r1 = await engine(full).backUp(settings: BackupSettings())
        XCTAssertEqual(r1.status, .iCloudFull)
        let offline = InMemoryBackupCloud()
        offline.inject(.fetchManifest, .networkUnavailable)
        let r2 = await engine(offline).backUp(settings: BackupSettings())
        XCTAssertEqual(r2.status, .offline)
    }
}
