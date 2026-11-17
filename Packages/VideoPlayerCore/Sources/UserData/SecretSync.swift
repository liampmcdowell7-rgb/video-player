import Foundation

// Option B of the credential decision (docs/STORAGE_MODEL.md, "Credentials", PROVISIONAL; option A is the recorded fallback):
// server secrets are kept in the cloud in encrypted fields of the user's private database, AND in a local store (the system
// keychain) so the app still works when iCloud is signed out, off or unreachable. The local copy is the one the app
// reads; the iCloud copy exists to restore secrets on a new or reset device.
//
// What Apple's pages say (read 2026-11-17, https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues and
// https://developer.apple.com/documentation/cloudkit/encrypting-user-data): `CKRecord.encryptedValues` is available on tvOS 15.0+;
// values are encrypted on the device before upload and decrypted after download; the key material is in the user's iCloud
// Keychain; if the user loses it and starts over, CloudKit reports `zoneNotFound` with `CKErrorUserDidResetEncryptedDataKey`,
// the cloud data is permanently lost, and the app must recreate the zone and upload its local copy again. This file models
// exactly that. NOT verified on a device: whether an Apple TV takes part in that key material at all.

public enum SecretCloudError: Error, Equatable, Sendable {
    /// No iCloud account, or sync is off for this app.
    case notSignedIn
    /// The encryption key was reset: the cloud copy is gone for good (the wrapper recreated the zone already).
    case keyReset
    case unavailable(String)
}

/// The cloud half. `CloudKitSecretCloud` (Apple/) is the real one; `InMemorySecretCloud` is the test double.
public protocol SecretCloud: Sendable {
    func fetchAll() async throws -> [String: String]
    func save(_ secret: String, for sourceID: String) async throws
    func delete(sourceID: String) async throws
}

public enum CloudSecretState: Equatable, Sendable {
    case synced
    case signedOut
    /// The key had been reset: the cloud copy was recreated from the local copies.
    case recoveredAfterKeyReset
    case unavailable(String)
}

public struct SecretSyncReport: Equatable, Sendable {
    /// Sources whose secret was missing here and was restored from the cloud.
    public var restored: [String]
    /// Sources whose secret was only here and was copied up to the cloud.
    public var uploaded: [String]
    /// Sources that have no secret anywhere: the app asks the person to type it again.
    public var stillMissing: [String]
    public var state: CloudSecretState
}

public final class InMemorySecretCloud: SecretCloud, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var signedIn = true
    private var resetPending = false
    private var failure: String?
    public init() {}

    public func setSignedIn(_ value: Bool) { lock.withLock { signedIn = value } }
    /// The next call fails with `keyReset` and empties the store, like the real zone being recreated.
    public func resetEncryptionKey() { lock.withLock { resetPending = true } }
    public func failNextCalls(with message: String?) { lock.withLock { failure = message } }
    public var snapshot: [String: String] { lock.withLock { values } }

    private func check() throws {
        try lock.withLock {
            if !signedIn { throw SecretCloudError.notSignedIn }
            if let failure { throw SecretCloudError.unavailable(failure) }
            if resetPending { resetPending = false; values = [:]; throw SecretCloudError.keyReset }
        }
    }
    public func fetchAll() async throws -> [String: String] { try check(); return lock.withLock { values } }
    public func save(_ secret: String, for sourceID: String) async throws { try check(); lock.withLock { values[sourceID] = secret } }
    public func delete(sourceID: String) async throws { try check(); lock.withLock { values[sourceID] = nil } }
}

/// Local store plus cloud mirror. Local always comes first: a cloud failure never loses or blocks a secret.
public struct MirroredSecrets: Sendable {
    public let local: any CredentialStore
    public let cloud: any SecretCloud
    public init(local: any CredentialStore, cloud: any SecretCloud) {
        self.local = local
        self.cloud = cloud
    }

    public func secret(for sourceID: String) -> String? { ((try? local.secret(for: sourceID)) ?? nil) }

    /// Saves locally (throws if that fails), then tries the cloud. The returned state says what happened to the cloud copy.
    @discardableResult
    public func set(_ secret: String, for sourceID: String) async throws -> CloudSecretState {
        try local.setSecret(secret, for: sourceID)
        return await push { try await cloud.save(secret, for: sourceID) }
    }

    @discardableResult
    public func remove(sourceID: String) async throws -> CloudSecretState {
        try local.removeSecret(for: sourceID)
        return await push { try await cloud.delete(sourceID: sourceID) }
    }

    private func push(_ body: () async throws -> Void) async -> CloudSecretState {
        do { try await body(); return .synced } catch { return Self.state(for: error) }
    }

    static func state(for error: Error) -> CloudSecretState {
        switch error as? SecretCloudError {
        case .notSignedIn?: return .signedOut
        case .keyReset?: return .recoveredAfterKeyReset
        case .unavailable(let m)?: return .unavailable(m)
        case nil: return .unavailable(String(describing: error))
        }
    }

    /// Run at start-up and after sign-in: restore what is missing here, upload what is missing there.
    /// `sourceIDs` are the sources that need a secret (their authentication is not "none").
    public func reconcile(sourceIDs: [String]) async -> SecretSyncReport {
        var report = SecretSyncReport(restored: [], uploaded: [], stillMissing: [], state: .synced)
        let remote: [String: String]
        do {
            remote = try await cloud.fetchAll()
        } catch SecretCloudError.keyReset {
            // The cloud copy is gone. Nothing to restore; everything held locally is uploaded below.
            remote = [:]
            report.state = .recoveredAfterKeyReset
        } catch {
            report.state = Self.state(for: error)
            report.stillMissing = sourceIDs.filter { secret(for: $0) == nil }
            return report
        }
        for id in sourceIDs {
            if let mine = secret(for: id) {
                if remote[id] != mine {
                    do { try await cloud.save(mine, for: id); report.uploaded.append(id) } catch { report.state = Self.state(for: error) }
                }
            } else if let theirs = remote[id] {
                if (try? local.setSecret(theirs, for: id)) != nil { report.restored.append(id) } else { report.stillMissing.append(id) }
            } else {
                report.stillMissing.append(id)
            }
        }
        return report
    }
}

/// What Settings says about where passwords are kept. Final user-facing text; iCloud is named (docs/NAMES.md).
public enum CredentialStorageText {
    public static func summary(_ state: CloudSecretState) -> String {
        switch state {
        case .synced:
            return "Passwords are kept on this device in protected storage, and an encrypted copy is kept in your iCloud account so a new or reset device can restore them."
        case .signedOut:
            return "You are not signed in to iCloud. Passwords are kept on this device only. If you reset this device you will need to enter them again."
        case .recoveredAfterKeyReset:
            return "Your iCloud encryption key was reset, so the iCloud copy of your passwords was removed. This device still has them and has uploaded them again."
        case .unavailable:
            return "Passwords are kept on this device. The iCloud copy could not be updated right now; it will be tried again."
        }
    }

    public static let resetNote = "Resetting this device removes the passwords stored on it. They come back from iCloud if you are signed in with the same Apple Account; otherwise you will be asked to enter each one again."
}
