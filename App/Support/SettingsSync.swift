import Foundation
import AppLogic
import UserData

/// R456: the settings of "Settings and Watch State" between this device and the user data (iCloud sync, backup and export).
/// Only the keys of `AppPreference` travel; a PIN or a password is never among them.
extension AppServices {
    /// After a change in Settings: write what changed into the ledger.
    func pushSettings() {
        PreferenceSync.push(to: ledger, stored: { PreferenceSync.value(of: UserDefaults.standard.object(forKey: $0)) })
    }

    /// At launch and when Settings opens: take what another device (or a restore) set.
    func pullSettings() {
        for (key, value) in PreferenceSync.pull(from: ledger) {
            switch value {
            case let .bool(b): if UserDefaults.standard.object(forKey: key) as? Bool != b { UserDefaults.standard.set(b, forKey: key) }
            case let .string(s): if UserDefaults.standard.string(forKey: key) != s { UserDefaults.standard.set(s, forKey: key) }
            default: break
            }
        }
    }
}
