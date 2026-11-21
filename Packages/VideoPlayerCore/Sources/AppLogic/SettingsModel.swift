import Foundation
import UserData
import LibraryIndex

/// Names of the stored preferences (UserDefaults keys) and their defaults, shared by the Settings screen and the code that
/// reads them. Defaults are PROVISIONAL (docs/SPECS.md).
public enum SettingsKey: String, CaseIterable, Sendable {
    case showDiscover
    case autoPlayNextEpisode
    case showSkipButtons
    /// R314: the intro (and a recap) is skipped without a press (on by default, owner's request of 21 Nov 2026).
    case skipIntrosAutomatically
    /// R314: the credits are skipped without a press (off by default; the Up Next card counts down instead).
    case skipCreditsAutomatically
    case showPlaybackStatsButton
    case rememberTrackChoicePerShow
    case showContinueWatching
    case showNextUp
    case showRecentlyAdded
    case continueWatchingDays
    case scanOnLaunch
    /// Dolby TrueHD tracks with an embedded Dolby Digital core play that core instead of the full lossless decode.
    case trueHDCompatibilityCore
    /// #15 9.4: title logos in place of the text title on the movie and show pages (on by default; off = text titles).
    case showTitleLogos

    public var defaultBool: Bool {
        switch self {
        case .continueWatchingDays, .trueHDCompatibilityCore, .skipCreditsAutomatically: return false
        default: return true
        }
    }
    public static let defaultContinueWatchingDays = 90
    public static let continueWatchingChoices = [30, 60, 90, 180, 365]
}

/// What the Storage and iCloud section shows. `cloud` comes from the account check; `items`/`files` from the index counts.
public struct StorageStatusModel: Equatable, Sendable {
    public var account: UDAccountStatus
    public var secrets: CloudSecretState
    public var counts: LibraryCounts?
    public var passwordsNeeded: Int
    /// Set when iCloud cannot be used at all by this copy of the app (no iCloud capability); wins over `account`.
    public var cloudUnavailable: String?

    public init(account: UDAccountStatus, secrets: CloudSecretState, counts: LibraryCounts?, passwordsNeeded: Int,
                cloudUnavailable: String? = nil) {
        self.account = account; self.secrets = secrets; self.counts = counts; self.passwordsNeeded = passwordsNeeded
        self.cloudUnavailable = cloudUnavailable
    }

    public var accountLine: String {
        if let cloudUnavailable { return cloudUnavailable + " Everything is kept on this Apple TV only." }
        switch account {
        case .available: return "Signed in to iCloud. Watch history, saved views and your source list sync through your iCloud account."
        case .noAccount: return "Not signed in to iCloud. Everything is kept on this Apple TV only."
        case .restricted: return "iCloud is restricted on this Apple TV. Everything is kept on this Apple TV only."
        case .unknown: return "iCloud status is not known right now."
        }
    }
    public var passwordsLine: String { CredentialStorageText.summary(secrets) }
    public var resetLine: String { CredentialStorageText.resetNote }
    public var libraryLine: String? {
        guard let counts else { return nil }
        return "\(counts.items) titles in \(counts.files) files. The library index can be rebuilt at any time and may be removed by the system when space is low; your watch history is not part of it."
    }
    public var passwordsNeededLine: String? {
        passwordsNeeded == 0 ? nil : (passwordsNeeded == 1 ? "1 source needs its password again." : "\(passwordsNeeded) sources need their password again.")
    }
}

public enum AboutText {
    public static let dataNote = "Movie and show details can come from the files’ own information and from online lookups you allow. Nothing is sold or shared."
}
