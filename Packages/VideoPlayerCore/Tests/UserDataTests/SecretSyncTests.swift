import XCTest
@testable import UserData

final class SecretSyncTests: XCTestCase {
    private func make() -> (MirroredSecrets, InMemoryCredentialStore, InMemorySecretCloud) {
        let local = InMemoryCredentialStore(), cloud = InMemorySecretCloud()
        return (MirroredSecrets(local: local, cloud: cloud), local, cloud)
    }

    func testSavingWritesBothCopies() async throws {
        let (m, local, cloud) = make()
        let state = try await m.set("pw1", for: "a")
        XCTAssertEqual(state, .synced)
        XCTAssertEqual(try local.secret(for: "a"), "pw1")
        XCTAssertEqual(cloud.snapshot["a"], "pw1")
    }

    func testSignedOutKeepsTheLocalCopyAndSaysSo() async throws {
        let (m, local, cloud) = make()
        cloud.setSignedIn(false)
        let state = try await m.set("pw1", for: "a")
        XCTAssertEqual(state, .signedOut)
        XCTAssertEqual(try local.secret(for: "a"), "pw1", "the app still works without the cloud")
        XCTAssertTrue(cloud.snapshot.isEmpty)
    }

    func testANewDeviceRestoresSecretsFromTheCloud() async throws {
        let (m, local, cloud) = make()
        _ = try await m.set("pw1", for: "a"); _ = try await m.set("pw2", for: "b")
        local.clear()                                                 // reset / new device
        let report = await m.reconcile(sourceIDs: ["a", "b", "c"])
        XCTAssertEqual(Set(report.restored), ["a", "b"])
        XCTAssertEqual(report.stillMissing, ["c"], "a source with no secret anywhere is asked for again")
        XCTAssertEqual(m.secret(for: "a"), "pw1")
        XCTAssertEqual(cloud.snapshot.count, 2)
    }

    func testSecretsMissingFromTheCloudAreUploaded() async throws {
        let (m, local, cloud) = make()
        try local.setSecret("only-here", for: "a")
        let report = await m.reconcile(sourceIDs: ["a"])
        XCTAssertEqual(report.uploaded, ["a"])
        XCTAssertEqual(cloud.snapshot["a"], "only-here")
    }

    func testAKeyResetEmptiesTheCloudAndTheLocalCopiesAreUploadedAgain() async throws {
        let (m, _, cloud) = make()
        _ = try await m.set("pw1", for: "a")
        cloud.resetEncryptionKey()
        let report = await m.reconcile(sourceIDs: ["a"])
        XCTAssertEqual(report.state, .recoveredAfterKeyReset)
        XCTAssertEqual(report.uploaded, ["a"])
        XCTAssertEqual(cloud.snapshot["a"], "pw1")
        XCTAssertEqual(m.secret(for: "a"), "pw1", "nothing was lost on this device")
    }

    func testAKeyResetOnANewDeviceLeavesTheSecretsToBeTypedAgain() async throws {
        let (m, local, cloud) = make()
        _ = try await m.set("pw1", for: "a")
        local.clear()
        cloud.resetEncryptionKey()
        let report = await m.reconcile(sourceIDs: ["a"])
        XCTAssertEqual(report.stillMissing, ["a"])
        XCTAssertEqual(report.state, .recoveredAfterKeyReset)
    }

    func testCloudOutageNeverBlocksAndReportsUnavailable() async throws {
        let (m, local, cloud) = make()
        cloud.failNextCalls(with: "network down")
        try local.setSecret("pw1", for: "a")
        let report = await m.reconcile(sourceIDs: ["a", "b"])
        XCTAssertEqual(report.state, .unavailable("network down"))
        XCTAssertEqual(report.stillMissing, ["b"])
        XCTAssertEqual(m.secret(for: "a"), "pw1")
    }

    func testRemovingDeletesBothCopies() async throws {
        let (m, local, cloud) = make()
        _ = try await m.set("pw1", for: "a")
        _ = try await m.remove(sourceID: "a")
        XCTAssertNil(try local.secret(for: "a"))
        XCTAssertNil(cloud.snapshot["a"])
    }

    func testAChangedLocalSecretReplacesTheCloudOne() async throws {
        let (m, local, cloud) = make()
        _ = try await m.set("old", for: "a")
        try local.setSecret("new", for: "a")
        _ = await m.reconcile(sourceIDs: ["a"])
        XCTAssertEqual(cloud.snapshot["a"], "new")
    }

    /// docs/NAMES.md: the password texts name iCloud (the service that holds the copy) instead of a generic "cloud", and
    /// never claim more than the state says.
    func testSettingsTextNamesICloudAndStatesTheReset() {
        let states: [CloudSecretState] = [.synced, .signedOut, .recoveredAfterKeyReset, .unavailable("x")]
        for s in states {
            let t = CredentialStorageText.summary(s)
            XCTAssertTrue(t.contains("iCloud"), t)
            XCTAssertFalse(t.contains("cloud storage") || t.contains("cloud sync") || t.contains("cloud copy"), t)
            XCTAssertTrue(t.contains("device"))
        }
        XCTAssertTrue(CredentialStorageText.summary(.signedOut).contains("this device only"))
        XCTAssertTrue(CredentialStorageText.resetNote.contains("Resetting this device"))
    }
}
