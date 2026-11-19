#if canImport(Security)
import Foundation
import Security

// NEVER COMPILED (see CloudKitUserDataCloud.swift). Passwords, tokens and API keys in the Keychain.
//
// Apple's documentation for kSecAttrSynchronizable (re-read 2026-11-19) states that tvOS does not synchronize keychain items
// through iCloud, and that items stored on tvOS never leave the device. Source passwords therefore use a store without the
// flag. #26 item 2: the app-wide API keys use their own store (service "com.liamp.videoplayer.keys") with `synchronizable:
// true`, as the user asked; on tvOS the flag has no effect (OPEN_QUESTIONS R207), so the encrypted iCloud copy
// (`MirroredSecrets` + `CloudKitSecretCloud`) is what brings a key to another Apple TV or back after a reinstall.
// Synchronizable items cannot use a "ThisDeviceOnly" accessibility, so both stores use AfterFirstUnlock. If the system
// refuses a synchronizable item (not documented for tvOS; unverified), the key is stored without the flag instead of failing.
//
// Whether Keychain items on tvOS survive when the system frees space is NOT verified from an Apple page. They are kept
// "when unlocked after first unlock"; the app does not rely on them surviving.

public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String
    private let synchronizable: Bool

    public init(service: String = "com.liamp.videoplayer.sources", synchronizable: Bool = false) {
        self.service = service
        self.synchronizable = synchronizable
    }

    /// Reads, updates and deletes match the item whether or not it carries the flag (kSecAttrSynchronizableAny).
    private func query(_ sourceID: String) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: sourceID]
        if synchronizable { q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny }
        return q
    }

    public func secret(for sourceID: String) throws -> String? {
        var q = query(sourceID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return String(data: data, encoding: .utf8)
    }

    public func setSecret(_ secret: String, for sourceID: String) throws {
        let data = Data(secret.utf8)
        let update = SecItemUpdate(query(sourceID) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainError.status(update) }
        var add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: sourceID, kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if synchronizable {
            add[kSecAttrSynchronizable as String] = kCFBooleanTrue
            let status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecSuccess { return }
            add[kSecAttrSynchronizable as String] = nil
        }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func removeSecret(for sourceID: String) throws {
        let status = SecItemDelete(query(sourceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

public enum KeychainError: Error, Equatable {
    case status(OSStatus)
}
#endif
