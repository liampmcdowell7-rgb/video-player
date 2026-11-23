import Foundation
import Subtitles
import LibraryIndex

// R458 (owner's request of 23 Nov 2026, commit B of R457; PROVISIONAL): the pure rules behind the new Playback and Language
// settings. The screens and the player only read these; nothing here touches the system.

/// Playback > Subtitles: what the player turns on at the start when the person has not chosen for this show.
public enum SubtitleMode: String, CaseIterable, Sendable {
    case off, forcedOnly, auto, alwaysOn

    public static let `default`: SubtitleMode = .auto
    public static let key = "subtitleMode"

    public var title: String {
        switch self {
        case .off: return "Off"
        case .forcedOnly: return "Forced Only"
        case .auto: return "Auto"
        case .alwaysOn: return "Always On"
        }
    }

    /// The one line under the row.
    public static let footer = "Auto shows subtitles when the audio is not in your language. Forced Only shows only the lines that translate foreign speech."
}

/// The audio and subtitle language defaults (Language > Audio, Language > Subtitles). "auto" = the Apple TV's language.
public enum TrackLanguageChoice {
    public static let auto = LanguagePreference.auto
    public static let audioKey = "audioLanguage"
    public static let subtitleKey = "subtitleLanguage"

    /// The tag to prefer, or nil when nothing resolves.
    public static func tag(stored: String?, system: [String]) -> LanguageTag? {
        LanguageTag(LanguagePreference.resolved(stored, system: system))
    }
}

/// What the player picks at the start: the stored defaults run through the same `TrackSelector` the track pickers use. A choice
/// the person made earlier for this show (`remembered`) always wins over the defaults.
public enum TrackDefaults {
    public static func preferences(audioLanguage: LanguageTag?, subtitleLanguage: LanguageTag?, mode: SubtitleMode) -> TrackPreferences {
        TrackPreferences(preferredAudioLanguages: audioLanguage.map { [$0] } ?? [],
                         preferredSubtitleLanguages: subtitleLanguage.map { [$0] } ?? [],
                         alwaysShowSubtitles: mode == .alwaysOn)
    }

    public static func select(audio: [AudioTrackInfo], subtitles: [SubtitleTrackInfo], originalLanguage: LanguageTag?,
                              audioLanguage: LanguageTag?, subtitleLanguage: LanguageTag?, mode: SubtitleMode,
                              remembered: SeriesTrackChoice?) -> TrackSelectionResult {
        let prefs = preferences(audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage, mode: mode)
        var result = TrackSelector.select(audio: audio, subtitles: subtitles, originalLanguage: originalLanguage,
                                          preferences: prefs, remembered: remembered)
        // The person's own choice for this show beats every default.
        if remembered != nil { return result }
        switch mode {
        case .off:
            result.subtitleTrackID = nil
            result.subtitleReason = "Subtitles are off in Settings"
        case .forcedOnly:
            let wished = subtitleLanguage ?? audioLanguage
            let forced = subtitles.first { $0.isForced && (wished == nil || ($0.language?.match(wanted: wished!) ?? 0) > 0) }
            result.subtitleTrackID = forced?.id
            result.subtitleReason = forced == nil ? "No forced subtitles in your language" : "Forced subtitles only, as set in Settings"
        case .auto, .alwaysOn:
            break
        }
        return result
    }
}

/// The default playback speed (Playback > Playback Speed). Applied as `AVPlayer.defaultRate`, which the player uses when play
/// is asked for.
public enum PlaybackSpeed {
    public static let key = "playbackSpeed"
    public static let normal = "1.0"
    public static let choices: [(stored: String, title: String)] = [
        ("0.75", "0.75×"), ("1.0", "Normal"), ("1.25", "1.25×"), ("1.5", "1.5×"), ("2.0", "2×"),
    ]

    public static func rate(_ stored: String?) -> Float {
        guard let stored, choices.contains(where: { $0.stored == stored }), let value = Float(stored) else { return 1 }
        return value
    }

    public static func title(_ stored: String?) -> String {
        choices.first { $0.stored == stored }?.title ?? "Normal"
    }
}

/// Resume Playback: on = start at the saved point; off = start at the beginning. Start Over is unchanged.
public enum ResumeRule {
    public static let key = "resumePlayback"

    /// Seconds to start at.
    public static func startPosition(saved: Double, watched: Bool, fromStart: Bool, resume: Bool) -> Double {
        if fromStart || watched || !resume { return 0 }
        return max(0, saved)
    }
}

/// Inactivity Check: after this many episodes in a row without a press, "Are you still watching?" pauses until Select.
public enum InactivityCheck: String, CaseIterable, Sendable {
    case off, after2, after3, after4

    public static let `default`: InactivityCheck = .off
    public static let key = "inactivityCheck"
    public static let question = "Are you still watching?"

    public var title: String {
        switch self {
        case .off: return "Off"
        case .after2: return "After 2 Episodes"
        case .after3: return "After 3 Episodes"
        case .after4: return "After 4 Episodes"
        }
    }

    public var limit: Int? {
        switch self {
        case .off: return nil
        case .after2: return 2
        case .after3: return 3
        case .after4: return 4
        }
    }

    /// True when the prompt comes up before the next episode starts.
    public func asks(episodesInARow: Int) -> Bool {
        guard let limit else { return false }
        return episodesInARow >= limit
    }
}

/// Counts episodes that followed each other on their own. A press of the remote, or Select on the prompt, starts a new count.
public struct EpisodeRun: Equatable, Sendable {
    public private(set) var count = 0
    public init() {}
    public mutating func episodeFinishedOnItsOwn() { count += 1 }
    public mutating func personActed() { count = 0 }
}

/// Playback > Play Version: which file plays when a title has more than one and the person has not picked one with Select
/// Version. A version picked by hand (the title's Versions menu, stored as the item's preferred file) always wins.
public enum PlayVersion: String, CaseIterable, Sendable {
    case auto, highestQuality, mostRecent, ask

    public static let `default`: PlayVersion = .auto
    public static let key = "playVersion"

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .highestQuality: return "Highest Quality"
        case .mostRecent: return "Most Recent"
        case .ask: return "Ask"
        }
    }

    public static let footer = "Auto plays the first file the scan found. A version you choose on a title's page always plays. Ask asks on the title's page; other places play Auto."

    /// The file to play. `nil` only for Ask with several files and no choice made: the page then asks.
    public static func pick(_ files: [StoredFile], explicit: Int64?, mode: PlayVersion) -> StoredFile? {
        if let explicit, let chosen = files.first(where: { $0.id == explicit }) { return chosen }
        guard files.count > 1 else { return files.first }
        switch mode {
        case .auto: return files.first
        case .ask: return nil
        case .highestQuality:
            return files.enumerated().max { a, b in
                let (x, y) = (quality(a.element), quality(b.element))
                if x != y { return x.lexicographicallyPrecedes(y) }
                return a.offset > b.offset
            }?.element
        case .mostRecent:
            return files.enumerated().max { a, b in
                let (x, y) = (a.element.modified ?? a.element.firstSeen, b.element.modified ?? b.element.firstSeen)
                if x != y { return x < y }
                return a.offset > b.offset
            }?.element
        }
    }

    /// Height, then bitrate, then size: a higher picture first, then the richer encode.
    private static func quality(_ file: StoredFile) -> [Int64] {
        [Int64(file.technical?.height ?? 0), file.technical?.bitrate ?? 0, file.size ?? 0]
    }

    /// The Play button of a title with several versions asks which one.
    public static func asks(mode: PlayVersion, versionCount: Int, hasExplicitChoice: Bool) -> Bool {
        mode == .ask && versionCount > 1 && !hasExplicitChoice
    }
}

/// R458: what the player does at the start with the stored defaults, and where a show's own choice is kept.
public enum StartTrackRules {
    /// True when Audio, Subtitles (language) and Subtitles (mode) are all left on Auto: the system player's own choice stands, so a
    /// person who never opens these settings sees no change.
    public static func usesSystemChoice(audio: String?, subtitleLanguage: String?, mode: SubtitleMode) -> Bool {
        (audio ?? LanguagePreference.auto) == LanguagePreference.auto
            && (subtitleLanguage ?? LanguagePreference.auto) == LanguagePreference.auto && mode == .auto
    }

    /// The device-only key of a show's remembered choice (never synced or backed up: it is a device convenience).
    public static func rememberKey(seriesTitle: String) -> String {
        "vp.trackChoice." + seriesTitle.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

/// Settings > Audio > Volume Boost (R458, PROVISIONAL): raises the level of audio the app decodes itself (DTS, TrueHD, Opus,
/// Vorbis). Off by default. Decibel steps; `RemuxEngine.AudioGain` applies it.
public enum VolumeBoost: String, CaseIterable, Sendable {
    case off, low, high

    public static let `default`: VolumeBoost = .off

    public var title: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .high: return "High"
        }
    }

    /// 3 dB and 6 dB: about 1.4 and 2 times the amplitude.
    public var decibels: Double {
        switch self {
        case .off: return 0
        case .low: return 3
        case .high: return 6
        }
    }

    public var factor: Float { decibels == 0 ? 1 : Float(pow(10, decibels / 20)) }

    public static func stored(_ raw: String?) -> VolumeBoost { raw.flatMap(VolumeBoost.init(rawValue:)) ?? .default }

    public static let footer = "Raises DTS, Dolby TrueHD, Opus and Vorbis audio. Loud passages can distort. Dolby Atmos and other system-decoded audio use the volume of your TV or receiver."
    public static let atmosLine = "Dolby Atmos is set in the Apple TV's own Settings, under Video and Audio."
}

/// General > Show Filenames and Show Poster Titles (R458): the text under a poster.
public enum PosterCaption {
    /// The caption's first line: the file name when Show Filenames is on and a name is known, else the title.
    public static func text(title: String, fileName: String?, showFilenames: Bool) -> String {
        guard showFilenames, let fileName, !fileName.isEmpty else { return title }
        return fileName
    }
}

/// Metadata and Artwork > Prefer Local Metadata (R458, PROVISIONAL). On is today's order: your own edits, then what the source
/// and the files hold (a server's text, the title's own information file), then online. Off puts online before the files.
/// Your own edits always come first, in both orders.
public enum MetadataPrecedence {
    public static func order(preferLocal: Bool) -> [DetailsLayer] {
        preferLocal ? [.source, .wikidata, .tmdb] : [.wikidata, .tmdb, .source]
    }

    public static func footer(preferLocal: Bool) -> String {
        preferLocal
            ? "Descriptions, cast and ratings come from your files and server first, then online. Your own edits always come first."
            : "Descriptions, cast and ratings come from online first, then your files and server. Your own edits always come first."
    }
}
