import Foundation
import Security
import AppLogic

/// R459 (Parental Controls; PROVISIONAL, NEVER COMPILED): the passcode record in this device's Keychain. Apple's page for
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (read for this commit): the item can be read only while the device is
/// unlocked, and it does not move to another device or come back from another device's backup. `kSecAttrSynchronizable` is
/// set to false, so the item is never synchronised either. The record holds a salted hash and the lockout count, never the
/// digits (`ParentalPIN`). Nothing here is written to UserDefaults, the user data, the sync or the backup.
struct KeychainPINStore: PINRecordStoring {
    private let service = "com.liamp.videoplayer.parental"
    private let account = "restrictions"

    private var match: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: kCFBooleanFalse as Any]
    }

    func load() -> PINRecord? {
        var query = match
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(PINRecord.self, from: data)
    }

    func save(_ record: PINRecord) throws {
        let data = try JSONEncoder().encode(record)
        let update = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw KeychainStatus(code: update) }
        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainStatus(code: status) }
    }

    func delete() { SecItemDelete(match as CFDictionary) }
}

struct KeychainStatus: Error { let code: OSStatus }
