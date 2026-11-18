import XCTest
import Foundation
@testable import UserData

// Launch safety (docs/API_USAGE.md "Launch safety"; fourth CI run: the app died at launch in an unsigned simulator build).
// Nothing that needs an entitlement may be made while the app starts, and every cloud failure must end as a state the
// screens can show, never a crash. These tests use fakes only; no real iCloud is contacted.

final class LazyCloudResourceTests: XCTestCase {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func testNothingIsMadeWhenTheResourceIsCreated() {
        let made = Counter()
        let r = LazyCloudResource<String> { made.bump(); return .success("container") }
        XCTAssertFalse(r.wasAttempted)
        XCTAssertEqual(made.value, 0, "the maker must not run in the initializer (that is the launch path)")
    }

    func testTheObjectIsMadeOnceOnFirstUse() throws {
        let made = Counter()
        let r = LazyCloudResource<String> { made.bump(); return .success("container") }
        XCTAssertEqual(try r.value(), "container")
        XCTAssertEqual(try r.value(), "container")
        XCTAssertNil(r.unavailableReason())
        XCTAssertTrue(r.wasAttempted)
        XCTAssertEqual(made.value, 1)
    }

    func testAFailureIsRememberedAndThrownEveryTime() {
        let made = Counter()
        let reason = CloudUnavailable("no iCloud capability")
        let r = LazyCloudResource<String> { made.bump(); return .failure(reason) }
        XCTAssertThrowsError(try r.value()) { XCTAssertEqual($0 as? CloudUnavailable, reason) }
        XCTAssertThrowsError(try r.value()) { XCTAssertEqual($0 as? CloudUnavailable, reason) }
        XCTAssertEqual(r.unavailableReason(), reason)
        XCTAssertEqual(made.value, 1, "a refused creation is not retried on every call")
    }

    func testTheUnavailableResourceNeverMakesAnything() {
        let r = LazyCloudResource<Int>.unavailable(.notInThisBuild)
        XCTAssertEqual(r.unavailableReason(), .notInThisBuild)
        XCTAssertThrowsError(try r.value())
        XCTAssertFalse(CloudUnavailable.notInThisBuild.reason.isEmpty)
    }

    func testConcurrentFirstUseMakesOneObject() async {
        let made = Counter()
        let r = LazyCloudResource<Int> { made.bump(); return .success(7) }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 { group.addTask { _ = try? r.value() } }
        }
        XCTAssertEqual(made.value, 1)
    }
}

final class SecretsLaunchSafetyTests: XCTestCase {
    /// A local store whose every call throws (the Keychain refusing: a missing entitlement, a locked store).
    final class BrokenStore: CredentialStore, @unchecked Sendable {
        struct Refused: Error {}
        func secret(for sourceID: String) throws -> String? { throw Refused() }
        func setSecret(_ secret: String, for sourceID: String) throws { throw Refused() }
        func removeSecret(for sourceID: String) throws { throw Refused() }
    }

    func testABrokenLocalStoreAndAnUnavailableCloudGiveStatesNotCrashes() async {
        let cloud = InMemorySecretCloud()
        cloud.failNextCalls(with: "iCloud is not available in this copy of the app")
        let secrets = MirroredSecrets(local: BrokenStore(), cloud: cloud)
        XCTAssertNil(secrets.secret(for: "a"), "a refused read is 'no password', not a crash")
        do { _ = try await secrets.set("pw", for: "a"); XCTFail("a refused local save must be reported") } catch {}
        let report = await secrets.reconcile(sourceIDs: ["a", "b"])
        XCTAssertEqual(report.state, .unavailable("iCloud is not available in this copy of the app"))
        XCTAssertEqual(report.stillMissing, ["a", "b"])
    }

    func testSignedOutCloudKeepsTheLocalPassword() async throws {
        let cloud = InMemorySecretCloud()
        cloud.setSignedIn(false)
        let local = InMemoryCredentialStore()
        let secrets = MirroredSecrets(local: local, cloud: cloud)
        let state = try await secrets.set("pw", for: "a")
        XCTAssertEqual(state, .signedOut)
        XCTAssertEqual(secrets.secret(for: "a"), "pw")
        let report = await secrets.reconcile(sourceIDs: ["a"])
        XCTAssertEqual(report.state, .signedOut)
    }
}
