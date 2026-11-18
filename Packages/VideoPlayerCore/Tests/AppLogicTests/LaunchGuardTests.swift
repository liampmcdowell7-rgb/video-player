import XCTest
import Foundation
import UserData
@testable import AppLogic

// Launch safety (docs/API_USAGE.md "Launch safety"): the shared App Group folder is checked before use, the Settings text
// says when iCloud is not available at all, and the launch sync ends in a state (not a crash) for every cloud failure.
// Fakes only; no real iCloud or App Group is used.

final class SharedFolderTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("shared-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testNoGroupFolderIsNil() {
        XCTAssertNil(SharedFolder.usable(nil), "containerURL returns nil without the App Group entitlement")
    }

    func testANonFileURLIsNil() {
        XCTAssertNil(SharedFolder.usable(URL(string: "https://example.invalid/group")!))
    }

    func testAMissingFolderIsCreated() throws {
        let url = dir.appendingPathComponent("group")
        XCTAssertEqual(SharedFolder.usable(url), url)
        var isFolder: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder))
        XCTAssertTrue(isFolder.boolValue)
    }

    func testAFileWhereTheFolderShouldBeIsNil() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("group")
        try Data("x".utf8).write(to: file)
        XCTAssertNil(SharedFolder.usable(file))
    }

    func testAFolderThatCannotBeCreatedIsNil() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("plain-file")
        try Data("x".utf8).write(to: file)
        XCTAssertNil(SharedFolder.usable(file.appendingPathComponent("inside")), "a folder under a file cannot be made")
    }

    func testAReadOnlyFolderIsNil() throws {
        if getuid() == 0 { throw XCTSkip("running as root: permissions are not enforced, so read-only cannot be tested") }
        let url = dir.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        XCTAssertNil(SharedFolder.usable(url))
    }
}

final class CloudUnavailableTextTests: XCTestCase {
    func testTheUnavailableReasonWinsOverTheAccountLine() {
        let m = StorageStatusModel(account: .unknown, secrets: .synced, counts: nil, passwordsNeeded: 0,
                                   cloudUnavailable: CloudUnavailable.notInThisBuild.reason)
        XCTAssertEqual(m.accountLine, CloudUnavailable.notInThisBuild.reason + " Everything is kept on this Apple TV only.")
    }

    func testWithoutAReasonTheAccountLineIsUnchanged() {
        let m = StorageStatusModel(account: .noAccount, secrets: .synced, counts: nil, passwordsNeeded: 0)
        XCTAssertEqual(m.accountLine, "Not signed in to iCloud. Everything is kept on this Apple TV only.")
    }
}

/// The launch sync with every cloud failure the fakes can produce: each ends in a status the Settings text can show.
final class LaunchSyncFailureTests: XCTestCase {
    private func launchSync(_ prepare: (InMemoryCloud) -> Void) async -> CloudSyncStatus {
        let ledger = UserDataLedger(deviceID: "A")
        let cloud = InMemoryCloud()
        prepare(cloud)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = UserDataSyncEngine(ledger: ledger, cloud: cloud, sleep: { _ in })
        let coordinator = CloudSyncCoordinator(ledger: ledger, engine: engine, ledgerFile: file, now: { Date() }, onState: { _ in })
        _ = ledger.apply(UDSettings.patch("k", .int(1), at: ledger.stamp()))
        await coordinator.start(startupSync: { await engine.sync() })
        let state = await coordinator.state
        await coordinator.stop()
        return state.status
    }

    func testSignedOut() async {
        let s = await launchSync { $0.setAccount(.noAccount) }
        XCTAssertEqual(s, .signedOut)
    }

    func testICloudFull() async {
        let s = await launchSync { $0.inject(.save(.quotaExceeded), times: 5) }
        XCTAssertEqual(s, .iCloudFull)
    }

    func testNoNetwork() async {
        let s = await launchSync { $0.inject(.fetch(.networkUnavailable), times: 5); $0.inject(.save(.networkUnavailable), times: 5) }
        XCTAssertEqual(s, .offline)
    }

    func testTheAdapterTextForAMissingCapability() async {
        // What the CloudKit adapters throw when the container could not be made (CloudUnavailable -> UDCloudError.other).
        let s = await launchSync { $0.inject(.fetch(.other(CloudUnavailable.notInThisBuild.reason)), times: 5) }
        guard case .failed = s else { return XCTFail("expected a failed status with a text, got \(s)") }
    }
}
