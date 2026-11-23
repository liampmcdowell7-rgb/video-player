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

    /// What the footer under the switch says it hides (R457): every place that follows the rule.
    public static let footer = "Hides the picture and the description of episodes you have not finished: on the show and episode pages, in Continue Watching and Next Up, and in the player's Info tab."
}

/// Metadata and Artwork > Prefer Local Artwork: which comes first for a picture. With it on (the default and today's rule,
/// docs/METADATA.md "local sidecar data wins over online data") a picture next to the media comes before the server's and the
/// online one; off, the online picture comes first and the local one fills the gap. A choice made by the user always wins.
public enum ArtworkPrecedence {
    public enum Source: Equatable, Sendable { case userChoice, localFile, server, online }

    public static func order(preferLocal: Bool) -> [Source] {
        preferLocal ? [.userChoice, .localFile, .server, .online] : [.userChoice, .online, .localFile, .server]
    }

    /// The line under the switch: what it covers (R457: posters of movies and shows, backgrounds and logos) and what it does
    /// not (an episode's picture has no online source).
    public static func footer(preferLocal: Bool) -> String {
        let order = preferLocal ? "next to your files first, then your server's, then online" : "online first, then next to your files and your server's"
        return "Posters, backgrounds and logos of movies and shows: \(order). Your own choices always win."
    }
}

/// Every setting that travels in "Settings and Watch State" (R457: all switches and pickers of Settings, one field each; R456
/// began with six). The raw value IS the UserDefaults key, so a screen reads `AppPreference.x.rawValue` and never a literal.
/// NEVER in this list: keys and tokens of the online sources, passwords, the Parental PIN, source addresses and account names
/// (the sources have their own sync) and device-only values (recent searches, the backup switches, the last-backup time, the
/// device ID, the playback problem report, the sync baseline below).
public enum AppPreference: String, CaseIterable, Sendable {
    // General
    case sortOrder, hideSpoilers, showContinueWatching, showNextUp, showRecentlyAdded, continueWatchingDays, showDiscover
    // Library and Metadata and Artwork
    case scanOnLaunch, showTitleLogos, preferLocalArtwork, onlineRegion, onlineFreeSources
    // Language
    case metadataLanguage, artworkLanguage
    // Playback
    case streamingCache, autoPlayNextEpisode, showSkipButtons, skipIntrosAutomatically, skipCreditsAutomatically
    case showPlaybackStatsButton, rememberTrackChoicePerShow, trueHDCompatibilityCore
    // R458: language defaults, subtitles, resume, speed, inactivity
    case audioLanguage, subtitleLanguage, subtitleMode, resumePlayback, playbackSpeed, inactivityCheck, playVersion, volumeBoost
    // R458: General (cards) and Metadata
    case showPosterTitles, watchedIndicators, showFilenames, listView, preferLocalMetadata

    public static let schemaVersion = 1
    public static let schemaKey = "prefs.schema"
    /// Where the device keeps what it last wrote to or read from the user data (device-only, never synced).
    public static let baselineKey = "vp.prefs.baseline"

    public var defaultValue: UDValue {
        switch self {
        case .sortOrder: return .string(LibrarySortDefault.default.rawValue)
        case .hideSpoilers: return .bool(false)
        case .streamingCache: return .string(StreamingCache.default.rawValue)
        case .metadataLanguage, .artworkLanguage, .audioLanguage, .subtitleLanguage: return .string(LanguagePreference.auto)
        case .subtitleMode: return .string(SubtitleMode.default.rawValue)
        case .playbackSpeed: return .string(PlaybackSpeed.normal)
        case .inactivityCheck: return .string(InactivityCheck.default.rawValue)
        case .resumePlayback: return .bool(true)
        case .playVersion: return .string(PlayVersion.default.rawValue)
        case .volumeBoost: return .string(VolumeBoost.default.rawValue)
        case .showPosterTitles, .watchedIndicators, .preferLocalMetadata: return .bool(true)
        case .showFilenames, .listView: return .bool(false)
        case .preferLocalArtwork: return .bool(true)
        case .onlineRegion: return .string(OnlineLookupPrefs.defaultRegion)
        case .onlineFreeSources: return .bool(OnlineLookupPrefs.freeSourcesDefault)
        case .continueWatchingDays: return .int(Int64(SettingsKey.defaultContinueWatchingDays))
        case .showDiscover, .autoPlayNextEpisode, .showSkipButtons, .skipIntrosAutomatically, .skipCreditsAutomatically,
             .showPlaybackStatsButton, .rememberTrackChoicePerShow, .showContinueWatching, .showNextUp, .showRecentlyAdded,
             .scanOnLaunch, .trueHDCompatibilityCore, .showTitleLogos:
            return .bool(SettingsKey(rawValue: rawValue)?.defaultBool ?? true)
        }
    }

    /// Every key that may be synced or backed up. A PIN, a passcode or a password is never in this list.
    public static var synced: [String] { allCases.map(\.rawValue) }

    /// What UserDefaults holds for this key, as the ledger writes it. The type follows the default (a switch is a bool, a
    /// choice a string, the days an integer), so a stored 1 is never read as `true` by mistake. Anything else is nil.
    public func read(_ object: Any?) -> UDValue? {
        guard let object else { return nil }
        switch defaultValue {
        case .bool: return (object as? Bool).map { .bool($0) }
        case .string: return (object as? String).map { .string($0) }
        case .int: return (object as? Int).map { .int(Int64($0)) }
        default: return nil
        }
    }
}

/// What this device last wrote to the ledger or took from it, per key. A setting is pushed only when its stored value differs
/// from this, so a device that merely opens Settings never overwrites a newer value from another device (R457 item 1).
public struct PreferenceBaseline: Equatable, Sendable {
    public var values: [String: UDValue]

    public init(values: [String: UDValue] = [:]) { self.values = values }

    /// The device-only text form (a JSON object of "b:true", "s:rating", "i:90").
    public var encoded: String {
        var out: [String: String] = [:]
        for (key, value) in values {
            switch value {
            case let .bool(b): out[key] = "b:\(b)"
            case let .string(s): out[key] = "s:" + s
            case let .int(i): out[key] = "i:\(i)"
            default: break
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    public init?(encoded: String?) {
        guard let encoded, let data = encoded.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        var values: [String: UDValue] = [:]
        for (key, text) in object {
            guard AppPreference(rawValue: key) != nil, text.count >= 2 else { continue }
            let body = String(text.dropFirst(2))
            switch text.prefix(2) {
            case "b:": values[key] = .bool(body == "true")
            case "s:": values[key] = .string(body)
            case "i:": if let i = Int64(body) { values[key] = .int(i) }
            default: break
            }
        }
        self.values = values
    }
}

/// The round trip between the device's stored values and the user-data settings record.
public enum PreferenceSync {
    /// Every setting that has a stored value (nil = never changed here). Used for the list of keys and the first baseline.
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

    /// The first baseline of a device that has none: everything stored now counts as already synced, so nothing old is written
    /// with a new stamp; the values of the ledger then arrive by `pull`.
    public static func firstBaseline(stored: (String) -> UDValue?) -> PreferenceBaseline {
        var values: [String: UDValue] = [:]
        for key in AppPreference.allCases { if let v = stored(key.rawValue) { values[key.rawValue] = v } }
        return PreferenceBaseline(values: values)
    }

    /// The settings this device changed since the baseline: a stored value that differs from what was last written or read.
    /// A value merely different from the ledger is not a change (the ledger may hold another device's newer edit).
    public static func changes(stored: (String) -> UDValue?, baseline: PreferenceBaseline) -> [String: UDValue] {
        var out: [String: UDValue] = [:]
        for key in AppPreference.allCases {
            guard let v = stored(key.rawValue), baseline.values[key.rawValue] != v else { continue }
            out[key.rawValue] = v
        }
        return out
    }

    /// Writes the changed settings into the ledger (one field per setting, so two devices changing different settings both win)
    /// and returns the new baseline. Nothing changed, nothing written.
    @discardableResult
    public static func push(to ledger: UserDataLedger, stored: (String) -> UDValue?, baseline: PreferenceBaseline, at date: Date? = nil) -> PreferenceBaseline {
        var next = baseline
        for (key, value) in changes(stored: stored, baseline: baseline) {
            ledger.setSetting(key, value, at: date)
            next.values[key] = value
        }
        return next
    }

    /// What to store on this device from the ledger (after a sync or a restore), with the new baseline: the baseline takes the
    /// ledger's value for every key the ledger holds, so the next push does not write it back.
    public static func pull(from ledger: UserDataLedger, stored: (String) -> UDValue?, baseline: PreferenceBaseline) -> (apply: [String: UDValue], baseline: PreferenceBaseline) {
        var next = baseline
        var apply: [String: UDValue] = [:]
        for (key, value) in importable(ledger.settingValues()) {
            next.values[key] = value
            if stored(key) != value { apply[key] = value }
        }
        return (apply, next)
    }
}
