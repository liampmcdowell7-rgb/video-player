import Foundation

/// An audio track, embedded in the file or not.
public struct AudioTrackInfo: Equatable, Sendable {
    public var id: String
    public var language: LanguageTag?
    /// Codec name for display ("DTS-HD MA", "E-AC-3", "AAC").
    public var codec: String
    /// Channel count of the layout (8 for 7.1). Dolby Atmos carried in E-AC-3 reports its 5.1 bed here.
    public var channels: Int
    public var isAtmos: Bool
    public var isDefault: Bool
    public var isCommentary: Bool
    public var isAudioDescription: Bool

    public init(
        id: String, language: LanguageTag?, codec: String, channels: Int, isAtmos: Bool = false,
        isDefault: Bool = false, isCommentary: Bool = false, isAudioDescription: Bool = false
    ) {
        self.id = id
        self.language = language
        self.codec = codec
        self.channels = channels
        self.isAtmos = isAtmos
        self.isDefault = isDefault
        self.isCommentary = isCommentary
        self.isAudioDescription = isAudioDescription
    }
}

/// A subtitle track, embedded or an external file.
public struct SubtitleTrackInfo: Equatable, Sendable {
    public var id: String
    public var language: LanguageTag?
    public var codec: String
    public var isExternal: Bool
    public var isForced: Bool
    public var isDefault: Bool
    public var isSDH: Bool
    public var isCommentary: Bool

    public init(
        id: String, language: LanguageTag?, codec: String = "", isExternal: Bool = false,
        isForced: Bool = false, isDefault: Bool = false, isSDH: Bool = false, isCommentary: Bool = false
    ) {
        self.id = id
        self.language = language
        self.codec = codec
        self.isExternal = isExternal
        self.isForced = isForced
        self.isDefault = isDefault
        self.isSDH = isSDH
        self.isCommentary = isCommentary
    }
}

public enum SDHPreference: String, Sendable, Codable {
    case prefer, avoid, noPreference
}

/// The user's choices from Settings > Playback.
public struct TrackPreferences: Equatable, Sendable {
    /// In order of wish. Empty means no wish.
    public var preferredAudioLanguages: [LanguageTag]
    /// In order of wish. Empty means "same as the audio wishes".
    public var preferredSubtitleLanguages: [LanguageTag]
    /// Play the original-language audio and show only forced subtitles.
    public var originalLanguagePlusForcedSubtitles: Bool
    public var preferHighestChannelCount: Bool
    public var preferAtmos: Bool
    public var sdh: SDHPreference
    /// Show full subtitles even when the audio is in a preferred audio language (for people who list a language
    /// they like to hear but still want subtitles, such as Japanese audio with English subtitles).
    public var alwaysShowSubtitles: Bool

    public init(
        preferredAudioLanguages: [LanguageTag] = [],
        preferredSubtitleLanguages: [LanguageTag] = [],
        originalLanguagePlusForcedSubtitles: Bool = false,
        preferHighestChannelCount: Bool = true,
        preferAtmos: Bool = true,
        sdh: SDHPreference = .noPreference,
        alwaysShowSubtitles: Bool = false
    ) {
        self.preferredAudioLanguages = preferredAudioLanguages
        self.preferredSubtitleLanguages = preferredSubtitleLanguages
        self.originalLanguagePlusForcedSubtitles = originalLanguagePlusForcedSubtitles
        self.preferHighestChannelCount = preferHighestChannelCount
        self.preferAtmos = preferAtmos
        self.sdh = sdh
        self.alwaysShowSubtitles = alwaysShowSubtitles
    }
}

/// What the user picked by hand for a series, described by attributes (track ids change from file to file).
public struct SeriesTrackChoice: Equatable, Sendable, Codable {
    public var audioLanguage: LanguageTag?
    public var audioChannels: Int?
    public var audioIsAudioDescription: Bool
    public var audioIsCommentary: Bool
    /// The user turned subtitles off.
    public var subtitlesOff: Bool
    public var subtitleLanguage: LanguageTag?
    public var subtitleIsForced: Bool
    public var subtitleIsSDH: Bool

    public init(
        audioLanguage: LanguageTag? = nil, audioChannels: Int? = nil, audioIsAudioDescription: Bool = false,
        audioIsCommentary: Bool = false, subtitlesOff: Bool = false, subtitleLanguage: LanguageTag? = nil,
        subtitleIsForced: Bool = false, subtitleIsSDH: Bool = false
    ) {
        self.audioLanguage = audioLanguage
        self.audioChannels = audioChannels
        self.audioIsAudioDescription = audioIsAudioDescription
        self.audioIsCommentary = audioIsCommentary
        self.subtitlesOff = subtitlesOff
        self.subtitleLanguage = subtitleLanguage
        self.subtitleIsForced = subtitleIsForced
        self.subtitleIsSDH = subtitleIsSDH
    }

    /// Records what the user picked. A nil subtitle means they chose "Off".
    public init(audio: AudioTrackInfo?, subtitle: SubtitleTrackInfo?) {
        self.init(
            audioLanguage: audio?.language, audioChannels: audio?.channels,
            audioIsAudioDescription: audio?.isAudioDescription ?? false, audioIsCommentary: audio?.isCommentary ?? false,
            subtitlesOff: subtitle == nil, subtitleLanguage: subtitle?.language,
            subtitleIsForced: subtitle?.isForced ?? false, subtitleIsSDH: subtitle?.isSDH ?? false
        )
    }
}

public struct TrackSelectionResult: Equatable, Sendable {
    public var audioTrackID: String?
    /// nil means subtitles off.
    public var subtitleTrackID: String?
    /// One plain sentence for the audio choice, fit to show in the UI.
    public var audioReason: String
    public var subtitleReason: String
}

/// Picks the audio and subtitle track to start playback with. Pure function of its inputs.
///
/// Audio, in order: (1) the earlier choice for this series, matched by language and kind; (2) with the
/// "original language" mode, the original language; (3) the first preferred language that exists; (4) the
/// file's default track, else the first. Audio description and commentary tracks are skipped in 2 to 4
/// unless nothing else exists. Inside the chosen language: Atmos first (if wanted), then most channels
/// (if wanted), then the file's default flag, then file order.
///
/// Subtitles, in order: (1) the earlier choice; (2) original-language mode with original audio: only a
/// forced track in a wished language; (3) audio in a preferred audio language (or unknown): only a forced track
/// in a wished language; (4) otherwise a full track in the first wished language that has one, applying the
/// SDH preference; forced-only as a last resort; (5) off.
public enum TrackSelector {

    public static func select(
        audio: [AudioTrackInfo],
        subtitles: [SubtitleTrackInfo],
        originalLanguage: LanguageTag?,
        preferences: TrackPreferences,
        remembered: SeriesTrackChoice? = nil
    ) -> TrackSelectionResult {
        let (chosenAudio, audioReason) = chooseAudio(audio, original: originalLanguage, prefs: preferences, remembered: remembered)
        let (chosenSub, subReason) = chooseSubtitle(subtitles, audio: chosenAudio, original: originalLanguage, prefs: preferences, remembered: remembered)
        return TrackSelectionResult(audioTrackID: chosenAudio?.id, subtitleTrackID: chosenSub?.id, audioReason: audioReason, subtitleReason: subReason)
    }

    // MARK: Audio

    private static func chooseAudio(_ tracks: [AudioTrackInfo], original: LanguageTag?, prefs: TrackPreferences, remembered: SeriesTrackChoice?) -> (AudioTrackInfo?, String) {
        if tracks.isEmpty { return (nil, "The file has no audio tracks") }
        let order = Dictionary(tracks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        func ranked(_ list: [AudioTrackInfo], wanted: LanguageTag?) -> [AudioTrackInfo] {
            list.sorted { a, b in
                if let w = wanted {
                    let ma = a.language?.match(wanted: w) ?? 0, mb = b.language?.match(wanted: w) ?? 0
                    if ma != mb { return ma > mb }
                }
                if prefs.preferAtmos, a.isAtmos != b.isAtmos { return a.isAtmos }
                if prefs.preferHighestChannelCount, a.channels != b.channels { return a.channels > b.channels }
                if a.isDefault != b.isDefault { return a.isDefault }
                return (order[a.id] ?? 0) < (order[b.id] ?? 0)
            }
        }

        // 1. Earlier choice for this series.
        if let r = remembered, let lang = r.audioLanguage {
            let sameKind = tracks.filter { $0.isAudioDescription == r.audioIsAudioDescription && $0.isCommentary == r.audioIsCommentary }
            let matches = sameKind.filter { ($0.language?.match(wanted: lang) ?? 0) > 0 }
            if !matches.isEmpty {
                var pool = matches
                if let ch = r.audioChannels {
                    let best = pool.map { abs($0.channels - ch) }.min() ?? 0
                    pool = pool.filter { abs($0.channels - ch) == best }
                }
                if let pick = ranked(pool, wanted: lang).first {
                    return (pick, "Same audio language as your earlier choice for this series (\(LanguageTable.displayName(lang)))")
                }
            }
        }

        let regular = tracks.filter { !$0.isCommentary && !$0.isAudioDescription }
        let pool = regular.isEmpty ? tracks : regular

        // 2. Original language mode.
        if prefs.originalLanguagePlusForcedSubtitles, let orig = original {
            let m = pool.filter { ($0.language?.match(wanted: orig) ?? 0) > 0 }
            if let pick = ranked(m, wanted: orig).first {
                return (pick, "Original language (\(LanguageTable.displayName(orig)))" + suffix(for: pick, among: m, prefs: prefs))
            }
        }

        // 3. Preferred languages in order.
        for lang in prefs.preferredAudioLanguages {
            let m = pool.filter { ($0.language?.match(wanted: lang) ?? 0) > 0 }
            if let pick = ranked(m, wanted: lang).first {
                return (pick, "Your preferred language (\(LanguageTable.displayName(lang)))" + suffix(for: pick, among: m, prefs: prefs))
            }
        }

        // 4. Fallback.
        if let d = pool.first(where: { $0.isDefault }) {
            return (d, prefs.preferredAudioLanguages.isEmpty
                ? "No language preference set; used the file's default audio track"
                : "None of your preferred languages is in this file; used the file's default audio track")
        }
        if let first = pool.first {
            return (first, prefs.preferredAudioLanguages.isEmpty
                ? "No language preference set; used the first audio track"
                : "None of your preferred languages is in this file; used the first audio track")
        }
        return (nil, "The file has no audio tracks")
    }

    private static func suffix(for pick: AudioTrackInfo, among list: [AudioTrackInfo], prefs: TrackPreferences) -> String {
        if list.count < 2 { return "" }
        if prefs.preferAtmos, pick.isAtmos { return " with Dolby Atmos" }
        if prefs.preferHighestChannelCount, list.contains(where: { $0.channels < pick.channels }) { return " with the most channels (\(channelLabel(pick.channels)))" }
        return ""
    }

    static func channelLabel(_ n: Int) -> String {
        switch n {
        case 1: return "mono"
        case 2: return "stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(n) channels"
        }
    }

    // MARK: Subtitles

    private static func chooseSubtitle(
        _ tracks: [SubtitleTrackInfo], audio: AudioTrackInfo?, original: LanguageTag?, prefs: TrackPreferences, remembered: SeriesTrackChoice?
    ) -> (SubtitleTrackInfo?, String) {
        if tracks.isEmpty { return (nil, "The file has no subtitles") }
        let order = Dictionary(tracks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = tracks.filter { !$0.isCommentary }

        func ranked(_ list: [SubtitleTrackInfo], wanted: LanguageTag?) -> [SubtitleTrackInfo] {
            list.sorted { a, b in
                if let w = wanted {
                    let ma = a.language?.match(wanted: w) ?? 0, mb = b.language?.match(wanted: w) ?? 0
                    if ma != mb { return ma > mb }
                }
                switch prefs.sdh {
                case .prefer: if a.isSDH != b.isSDH { return a.isSDH }
                case .avoid: if a.isSDH != b.isSDH { return !a.isSDH }
                case .noPreference: break
                }
                if a.isDefault != b.isDefault { return a.isDefault }
                return (order[a.id] ?? 0) < (order[b.id] ?? 0)
            }
        }

        // 1. Earlier choice.
        if let r = remembered {
            if r.subtitlesOff { return (nil, "Subtitles were off the last time you chose for this series") }
            if let lang = r.subtitleLanguage {
                let m = candidates.filter { ($0.language?.match(wanted: lang) ?? 0) > 0 && $0.isForced == r.subtitleIsForced }
                var sameKind = m.filter { $0.isSDH == r.subtitleIsSDH }
                if sameKind.isEmpty { sameKind = m }
                if let pick = ranked(sameKind, wanted: lang).first {
                    return (pick, "Same subtitles as your earlier choice for this series (\(LanguageTable.displayName(lang)))")
                }
            }
        }

        let wishes = prefs.preferredSubtitleLanguages.isEmpty ? prefs.preferredAudioLanguages : prefs.preferredSubtitleLanguages
        func forced(in lang: LanguageTag) -> SubtitleTrackInfo? {
            ranked(candidates.filter { $0.isForced && ($0.language?.match(wanted: lang) ?? 0) > 0 }, wanted: lang).first
        }
        func firstForced() -> SubtitleTrackInfo? {
            for lang in wishes { if let f = forced(in: lang) { return f } }
            return nil
        }

        let audioLang = audio?.language
        let isOriginalAudio: Bool = {
            guard let o = original, let a = audioLang else { return false }
            return a.match(wanted: o) > 0
        }()

        // 2. Original-language mode with original audio.
        if prefs.originalLanguagePlusForcedSubtitles, isOriginalAudio {
            if let f = firstForced() { return (f, "Original-language audio with forced subtitles (\(LanguageTable.displayName(f.language ?? LanguageTag(language: "und"))))") }
            return (nil, "Original-language audio; this file has no forced subtitles in your languages, so subtitles are off")
        }

        // 3. Audio the user understands.
        let understood: Bool = {
            guard let a = audioLang else { return true }
            if prefs.preferredAudioLanguages.isEmpty { return true }
            return prefs.preferredAudioLanguages.contains { a.match(wanted: $0) > 0 }
        }()
        if understood && !prefs.alwaysShowSubtitles {
            if let f = firstForced() { return (f, "Forced subtitles for foreign-language lines (\(LanguageTable.displayName(f.language ?? LanguageTag(language: "und"))))") }
            return (nil, "The audio is in a language you chose, so subtitles are off")
        }

        // 4. Foreign audio: a full track in the first wished language that has one.
        for lang in wishes {
            let full = candidates.filter { !$0.isForced && ($0.language?.match(wanted: lang) ?? 0) > 0 }
            if let pick = ranked(full, wanted: lang).first {
                var why = understood
                    ? "You asked for subtitles to always show: \(LanguageTable.displayName(lang)) subtitles"
                    : "The audio is not in your languages; \(LanguageTable.displayName(lang)) subtitles"
                if pick.isSDH, prefs.sdh == .prefer { why += " (SDH, as you prefer)" }
                else if !pick.isSDH, prefs.sdh == .avoid, full.contains(where: { $0.isSDH }) { why += " (not SDH, as you prefer)" }
                return (pick, why)
            }
        }
        if let f = firstForced() { return (f, "The audio is not in your languages; only forced subtitles exist in your languages") }

        // 5. Nothing fits.
        return (nil, wishes.isEmpty ? "No subtitle language preference set, so subtitles are off" : "The audio is not in your languages, but there are no subtitles in your languages")
    }
}
