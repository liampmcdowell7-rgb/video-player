import Foundation
import LibraryIndex
import RemuxEngine
import UserData

// R456 (owner's request of 23 Nov 2026, settings reorganised; PROVISIONAL): the settings added by this commit, as pure logic:
// their keys, defaults, what each controls, and the round trip to the "Settings and Watch State" record of the user data
// (one field per setting, the newest edit wins per field, a newer schema is kept and not read). Nothing here touches the
// Parental PIN or any password: only the keys listed in `AppPreference.synced` ever leave this device.

/// The default order of the Movies and Shows grids (General > Sort Order).
public enum LibrarySortDefault: String, CaseIterable, Sendable {
    case title, dateAdded, releaseDate, rating

    public static let `default` = LibrarySortDefault.title

    public var title: String {
        switch self {
        case .title: return "Title"
        case .dateAdded: return "Date Added"
        case .releaseDate: return "Release Date"
        case .rating: return "Rating"
        }
    }

    /// Title ascending; the others newest or best first.
    public var itemSort: ItemSort {
        switch self {
        case .title: return ItemSort(key: .title, ascending: true)
        case .dateAdded: return ItemSort(key: .added, ascending: false)
        case .releaseDate: return ItemSort(key: .year, ascending: false)
        case .rating: return ItemSort(key: .rating, ascending: false)
        }
    }

    public static func stored(_ raw: String?) -> LibrarySortDefault { raw.flatMap(Self.init(rawValue:)) ?? .default }
}

/// Playback > Streaming Cache: the read-ahead budget of the remux engine (`EngineBudget.memoryBytes`).
public enum StreamingCache: String, CaseIterable, Sendable {
    case auto, small, large

    public static let `default` = StreamingCache.auto

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .small: return "Small"
        case .large: return "Large"
        }
    }

    /// Auto is the engine's own default (192 MB); Small halves it for an Apple TV with little free memory; Large doubles it
    /// (a longer read-ahead for a slow network). PROVISIONAL numbers (R456).
    public var memoryBytes: Int64 {
        switch self {
        case .auto: return EngineBudget().memoryBytes
        case .small: return EngineBudget().memoryBytes / 2
        case .large: return EngineBudget().memoryBytes * 2
        }
    }

    public var budget: EngineBudget { EngineBudget(memoryBytes: memoryBytes) }

    public static func stored(_ raw: String?) -> StreamingCache { raw.flatMap(Self.init(rawValue:)) ?? .default }
}

/// Language > Metadata and Artwork: "Auto" follows the Apple TV's first language; otherwise a two-letter code.
public enum LanguagePreference {
    public static let auto = "auto"
    /// The choices offered besides Auto: the common languages of the online sources (code, name).
    public static let choices: [(code: String, name: String)] = ["en", "es", "fr", "de", "it", "pt", "nl", "sv", "ja", "ko", "zh"].map {
        ($0, Locale(identifier: "en").localizedString(forLanguageCode: $0) ?? $0)
    }

    /// The two-letter language to use: the stored choice, or the first system language.
    public static func resolved(_ stored: String?, system: [String]) -> String {
        if let stored, stored != auto, stored.count == 2 { return stored.lowercased() }
        return String((system.first ?? "en").prefix(2)).lowercased()
    }

    public static func title(_ stored: String?) -> String {
        guard let stored, stored != auto else { return "Auto" }
        return choices.first { $0.code == stored }?.name ?? "Auto"
    }
}

/// Hide Spoilers: the synopsis and the still of an unwatched episode are hidden.
public enum SpoilerRules {
    public static let hiddenSynopsis = "The description is hidden until you have watched this episode."

    /// The synopsis to show: the real one, or the hidden line for an unwatched episode while the setting is on. An episode with
    /// no synopsis stays without one (nothing is invented).
    public static func synopsis(_ text: String?, watched: Bool, hideSpoilers: Bool) -> String? {
        guard hideSpoilers, !watched, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return hiddenSynopsis
    }

    public static func hidesStill(watched: Bool, hideSpoilers: Bool) -> Bool { hideSpoilers && !watched }
}

/// Metadata and Artwork > Prefer Local Artwork: which comes first for a picture. With it on (the default and today's rule,
/// docs/METADATA.md "local sidecar data wins over online data") a picture next to the media comes before the server's and the
/// online one; off, the online picture comes first and the local one fills the gap. A choice made by the user always wins.
public enum ArtworkPrecedence {
    public enum Source: Equatable, Sendable { case userChoice, localFile, server, online }

    public static func order(preferLocal: Bool) -> [Source] {
        preferLocal ? [.userChoice, .localFile, .server, .online] : [.userChoice, .online, .localFile, .server]
    }
}

/// The settings of this commit and the ones that travel in "Settings and Watch State".
public enum AppPreference: String, CaseIterable, Sendable {
    case sortOrder, hideSpoilers, streamingCache, metadataLanguage, artworkLanguage, preferLocalArtwork

    public static let schemaVersion = 1
    public static let schemaKey = "prefs.schema"

    public var defaultValue: UDValue {
        switch self {
        case .sortOrder: return .string(LibrarySortDefault.default.rawValue)
        case .hideSpoilers: return .bool(false)
        case .streamingCache: return .string(StreamingCache.default.rawValue)
        case .metadataLanguage, .artworkLanguage: return .string(LanguagePreference.auto)
        case .preferLocalArtwork: return .bool(true)
        }
    }

    /// Every key that may be synced or backed up. A PIN, a passcode or a password is never in this list.
    public static var synced: [String] { allCases.map(\.rawValue) }
}

/// The round trip between the device's stored values and the user-data settings record.
public enum PreferenceSync {
    /// What this device would write: every setting that has a stored value (nil = never changed here, so nothing is written
    /// and a value from another device is not overwritten).
    public static func export(stored: (String) -> UDValue?) -> [String: UDValue] {
        var out: [String: UDValue] = [AppPreference.schemaKey: .int(Int64(AppPreference.schemaVersion))]
        for key in AppPreference.allCases { if let v = stored(key.rawValue) { out[key.rawValue] = v } }
        return out
    }

    /// What to apply from the record. A record of a NEWER schema is not read (never restore a newer format); a value of the
    /// wrong type or not in the allow-list is ignored.
    public static func importable(_ record: [String: UDValue]) -> [String: UDValue] {
        if let schema = record[AppPreference.schemaKey]?.asInt, schema > Int64(AppPreference.schemaVersion) { return [:] }
        var out: [String: UDValue] = [:]
        for key in AppPreference.allCases {
            guard let v = record[key.rawValue], sameKind(v, key.defaultValue) else { continue }
            out[key.rawValue] = v
        }
        return out
    }

    private static func sameKind(_ a: UDValue, _ b: UDValue) -> Bool {
        switch (a, b) {
        case (.bool, .bool), (.string, .string), (.int, .int), (.double, .double): return true
        default: return false
        }
    }
}

public extension PreferenceSync {
    /// Writes every setting changed on this device into the ledger (one field per setting, so two devices changing different
    /// settings both win). A value equal to the ledger's is not written again.
    static func push(to ledger: UserDataLedger, stored: (String) -> UDValue?, at date: Date? = nil) {
        let current = ledger.settingValues()
        for (key, value) in export(stored: stored) where current[key] != value { ledger.setSetting(key, value, at: date) }
    }

    /// The values to store on this device from the ledger (after a sync or a restore).
    static func pull(from ledger: UserDataLedger) -> [String: UDValue] { importable(ledger.settingValues()) }

    /// The stored value of a setting as the ledger writes it: a switch is a bool, a choice a string.
    static func value(of object: Any?) -> UDValue? {
        switch object {
        case let b as Bool: return .bool(b)
        case let s as String: return .string(s)
        default: return nil
        }
    }
}
