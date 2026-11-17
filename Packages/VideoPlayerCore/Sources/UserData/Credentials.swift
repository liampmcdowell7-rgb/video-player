import Foundation

/// Where passwords and tokens live. The real store is the Keychain (Apple/KeychainCredentialStore.swift).
///
/// IMPORTANT (docs/STORAGE_MODEL.md, "Credentials"): Apple's documentation for `kSecAttrSynchronizable` says tvOS does
/// not synchronize keychain items through iCloud; items "never leave the device". So a new Apple TV, or one whose
/// keychain was lost, has the source list (from the cloud) but NOT the passwords. `CredentialGap` finds those sources so
/// the app can ask for the password again, instead of failing with a confusing error.
public protocol CredentialStore: Sendable {
    func secret(for sourceID: String) throws -> String?
    func setSecret(_ secret: String, for sourceID: String) throws
    func removeSecret(for sourceID: String) throws
}

public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func secret(for sourceID: String) throws -> String? { lock.withLock { values[sourceID] } }
    public func setSecret(_ secret: String, for sourceID: String) throws { lock.withLock { values[sourceID] = secret } }
    public func removeSecret(for sourceID: String) throws { lock.withLock { values[sourceID] = nil } }
    /// Simulates losing the keychain (a new device, a reset).
    public func clear() { lock.withLock { values = [:] } }
}

public enum CredentialGap {
    /// Sources that need a password (their `auth` is not "none") but have none stored. The app shows these as
    /// "Enter the password again" rows; it never tries to connect to them with an empty password.
    public static func sourcesNeedingPassword(_ sources: [UDSourceDefinition], store: any CredentialStore) -> [UDSourceDefinition] {
        sources.filter { s in
            guard s.auth != "none", !s.auth.isEmpty else { return false }
            return ((try? store.secret(for: s.id)) ?? nil) == nil
        }
    }
}
