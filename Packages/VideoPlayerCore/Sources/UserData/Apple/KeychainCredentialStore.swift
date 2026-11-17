#if canImport(Security)
import Foundation
import Security

// NEVER COMPILED (see CloudKitUserDataCloud.swift). Passwords and tokens in the Keychain, on this device only.
//
// Apple's documentation for kSecAttrSynchronizable states that tvOS does not synchronize keychain items through iCloud, and
// that items stored on tvOS never leave the device. So this store does NOT set kSecAttrSynchronizable (it would have no
// effect there) and the app treats a missing secret as "ask again" (CredentialGap), never as an error.
//
// Whether Keychain items on tvOS survive when the system frees space is NOT verified from an Apple page. They are kept
// "when unlocked after first unlock"; the app does not rely on them surviving.

public final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.liamp.videoplayer.sources") {
        self.service = service
    }

    private func query(_ sourceID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: sourceID]
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
        var add = query(sourceID)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
