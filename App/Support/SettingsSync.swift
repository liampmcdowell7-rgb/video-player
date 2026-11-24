import Foundation
import AppLogic
import UserData

/// R456, R457: the settings of "Settings and Watch State" between this device and the user data (iCloud sync, backup and
/// export). Only the keys of `AppPreference` travel; a PIN, a password or a key is never among them.
///
/// Order (R457 item 1): a setting is written to the ledger only when THIS device changed it since it last wrote or read it (the
/// baseline, kept on this device). After every completed sync the device first writes its own pending edits, then takes the
/// ledger's newest values. Opening Settings only writes edits, so a newer value from another device is never overwritten with
/// this device's older stored value.
extension AppServices {
    private static var defaults: UserDefaults { .standard }

    private func stored(_ key: String) -> UDValue? { AppPreference(rawValue: key)?.read(Self.defaults.object(forKey: key)) }

    private func loadBaseline() -> PreferenceBaseline {
        PreferenceBaseline(encoded: Self.defaults.string(forKey: AppPreference.baselineKey))
            ?? PreferenceSync.firstBaseline(stored: { [self] in stored($0) })
    }

    private func saveBaseline(_ baseline: PreferenceBaseline) { Self.defaults.set(baseline.encoded, forKey: AppPreference.baselineKey) }

    /// After a change in Settings: write what THIS device changed into the ledger.
    func pushSettings() {
        saveBaseline(PreferenceSync.push(to: ledger, stored: { [self] in stored($0) }, baseline: loadBaseline()))
    }

    /// After a sync, at launch and after a restore: own pending edits first, then the newest values of the ledger.
    func reconcileSettings() {
        pushSettings()
        let result = PreferenceSync.pull(from: ledger, stored: { [self] in stored($0) }, baseline: loadBaseline())
        for (key, value) in result.apply {
            switch value {
            case let .bool(b): Self.defaults.set(b, forKey: key)
            case let .string(s): Self.defaults.set(s, forKey: key)
            case let .int(i): Self.defaults.set(Int(i), forKey: key)
            default: break
            }
        }
        saveBaseline(result.baseline)
    }
}
