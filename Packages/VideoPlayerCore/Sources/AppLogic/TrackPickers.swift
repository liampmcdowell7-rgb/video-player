import Foundation
import Subtitles
import PlaybackStatus

// Audio and subtitle pickers (the Info panel's tabs in the player). The view model decides every word on screen and
// which track is selected; the SwiftUI/AVKit layer only draws rows and reports which one was chosen.
//
// Track choice goes through the Subtitles selection rules (`TrackSelector`), so the first selection when playback
// starts and the "same as your earlier choice for this series" memory are exactly the tested rules; a manual pick here
// only changes the selection and produces the `SeriesTrackChoice` to remember. Labels use the honest-status vocabulary
// from PlaybackStatus (`StatusRules.audioContains`: what the FILE contains, never what the TV outputs).

// MARK: Rows

public struct TrackRow: Equatable, Sendable, Identifiable {
    /// The track id, or `TrackRow.offID` for the "Off" row of the subtitle picker.
    public var id: String
    /// Main line: the language ("English"), or "Off".
    public var title: String
    /// Second line: what the track contains ("Dolby Digital Plus with Atmos 5.1", "SubRip (SRT)").
    public var subtitle: String?
    /// Short tags in this order: Default, Forced, SDH, Commentary, Audio Description.
    public var badges: [String]
    public var isSelected: Bool
    public var isOff: Bool

    public static let offID = "off"

    public init(id: String, title: String, subtitle: String? = nil, badges: [String] = [], isSelected: Bool = false, isOff: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.isSelected = isSelected
        self.isOff = isOff
    }
}

public struct TrackSection: Equatable, Sendable {
    /// nil for the unlabeled top section ("Off").
    public var title: String?
    public var rows: [TrackRow]
}

/// The delay row under a picker ("Audio Delay  +250 ms").
public struct SyncOffsetRow: Equatable, Sendable {
    public var label: String
    public var valueText: String
    public var seconds: TimeInterval
    public var canIncrease: Bool
    public var canDecrease: Bool
    /// True when the value is not 0 (the UI can offer "Reset").
    public var canReset: Bool
}

public struct TrackPickerState: Equatable, Sendable {
    /// "Audio" or "Subtitles".
    public var title: String
    public var sections: [TrackSection]
    /// One plain sentence saying why the selected track was chosen (from the selection rules); nil when the user chose it.
    public var reason: String?
    public var sync: SyncOffsetRow

    public var rows: [TrackRow] { sections.flatMap(\.rows) }
    public var selectedRow: TrackRow? { rows.first(where: \.isSelected) }
}

/// What the player must do after a pick.
public struct TrackChange: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case audio, subtitle }
    public var kind: Kind
    /// The track to switch to; nil with kind .subtitle means subtitles off.
    public var trackID: String?
    /// Store this as the series' remembered choice (Subtitles rule 1 uses it next episode).
    public var remember: SeriesTrackChoice
}

// MARK: Labels

public enum TrackLabels {
    /// Maps a codec name as probes write it ("DTS-HD MA", "E-AC-3", "ec3", "TrueHD") to the status vocabulary.
    public static func audioKind(of codec: String) -> AudioCodecKind? {
        let key = codec.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "ac3", "dolbydigital", "aac3": return .ac3
        case "eac3", "ec3", "ddp", "dolbydigitalplus", "eac3joc": return .eac3
        case "truehd", "mlp", "dolbytruehd": return .trueHD
        case "dts", "dca", "dtscore": return .dts
        case "dtshdma", "dtshd", "dtshdmasteraudio", "dtshdmaster": return .dtsHDMA
        case "dtsx": return .dtsX
        case "aac", "mp4a", "aaclc", "heaac": return .aac
        case "flac": return .flac
        case "pcm", "lpcm", "pcms16le", "pcms24le", "pcms32le", "pcmbluray": return .pcm
        case "opus": return .opus
        case "vorbis": return .vorbis
        case "dtshdhra", "dtshdhighresolution", "dtshdhr": return .dtsHDHRA
        default: return nil
        }
    }

    /// "Dolby Digital Plus with Atmos 5.1" from the status rules, or "<codec> <layout>" when the codec is not known.
    public static func audioDescription(_ track: AudioTrackInfo) -> String {
        if let kind = audioKind(of: track.codec) {
            let content = AudioTrackContent(kind: kind, channels: track.channels, hasAtmos: track.isAtmos)
            return StatusRules.audioContains(content)
        }
        let name = track.codec.trimmingCharacters(in: .whitespaces)
        let layout = StatusText.layout(track.channels)
        return name.isEmpty ? layout : "\(name) \(layout)"
    }

    public static func language(_ tag: LanguageTag?) -> String {
        guard let tag else { return "Unknown language" }
        return LanguageTable.displayName(tag)
    }

    /// "SubRip (SRT)", "WebVTT", "Advanced SubStation (ASS)", "PGS (picture)", otherwise the codec upper-cased.
    public static func subtitleFormat(_ codec: String) -> String? {
        let key = codec.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "": return nil
        case "srt", "subrip", "ssubrip": return "SubRip (SRT)"
        case "vtt", "webvtt": return "WebVTT"
        case "ass": return "Advanced SubStation (ASS)"
        case "ssa": return "SubStation (SSA)"
        case "pgs", "sup", "hdmvpgs", "pgssub", "hdmvpgssubtitle": return "PGS (picture)"
        case "vobsub", "dvdsub", "idx", "sub": return "VobSub (picture)"
        case "mov_text", "movtext", "tx3g": return "Timed Text"
        default: return codec.uppercased()
        }
    }
}

// MARK: Model

/// One playback's audio and subtitle choice. Value type: copy it, mutate it, read `audioPicker` / `subtitlePicker`.
public struct TrackPickerModel: Sendable {
    public let audioTracks: [AudioTrackInfo]
    public let subtitleTracks: [SubtitleTrackInfo]
    public let originalLanguage: LanguageTag?
    public let preferences: TrackPreferences

    public private(set) var selectedAudioID: String?
    /// nil = subtitles off.
    public private(set) var selectedSubtitleID: String?
    public private(set) var audioReason: String?
    public private(set) var subtitleReason: String?
    public private(set) var audioDelay: TimeInterval
    public private(set) var subtitleDelay: TimeInterval

    /// Delay change per press of the delay row. Interpretation (PROVISIONAL): 50 ms steps, limit from SyncModel.
    public static let delayStep: TimeInterval = 0.05

    public init(
        audio: [AudioTrackInfo], subtitles: [SubtitleTrackInfo], originalLanguage: LanguageTag?,
        preferences: TrackPreferences, remembered: SeriesTrackChoice? = nil,
        audioDelay: TimeInterval = 0, subtitleDelay: TimeInterval = 0
    ) {
        self.audioTracks = audio
        self.subtitleTracks = subtitles
        self.originalLanguage = originalLanguage
        self.preferences = preferences
        self.audioDelay = SyncModel.clampedDelay(audioDelay)
        self.subtitleDelay = SyncModel.clampedDelay(subtitleDelay)
        let result = TrackSelector.select(audio: audio, subtitles: subtitles, originalLanguage: originalLanguage,
                                          preferences: preferences, remembered: remembered)
        self.selectedAudioID = result.audioTrackID
        self.selectedSubtitleID = result.subtitleTrackID
        self.audioReason = result.audioReason
        self.subtitleReason = result.subtitleReason
    }

    // MARK: Actions

    /// The user picked an audio row. Unknown ids are ignored (returns nil).
    public mutating func selectAudio(id: String) -> TrackChange? {
        guard let track = audioTracks.first(where: { $0.id == id }) else { return nil }
        selectedAudioID = id
        audioReason = nil
        return TrackChange(kind: .audio, trackID: id, remember: remembered(audio: track, subtitle: selectedSubtitle))
    }

    /// The user picked a subtitle row; `nil` or `TrackRow.offID` means Off.
    public mutating func selectSubtitle(id: String?) -> TrackChange? {
        if id == nil || id == TrackRow.offID {
            selectedSubtitleID = nil
            subtitleReason = nil
            return TrackChange(kind: .subtitle, trackID: nil, remember: remembered(audio: selectedAudio, subtitle: nil))
        }
        guard let track = subtitleTracks.first(where: { $0.id == id }) else { return nil }
        selectedSubtitleID = track.id
        subtitleReason = nil
        return TrackChange(kind: .subtitle, trackID: track.id, remember: remembered(audio: selectedAudio, subtitle: track))
    }

    /// Moves the audio delay by `steps` presses (positive = later). Returns the new, clamped delay.
    @discardableResult
    public mutating func stepAudioDelay(_ steps: Int) -> TimeInterval {
        audioDelay = Self.round(SyncModel.clampedDelay(audioDelay + Double(steps) * Self.delayStep))
        return audioDelay
    }

    @discardableResult
    public mutating func stepSubtitleDelay(_ steps: Int) -> TimeInterval {
        subtitleDelay = Self.round(SyncModel.clampedDelay(subtitleDelay + Double(steps) * Self.delayStep))
        return subtitleDelay
    }

    public mutating func resetAudioDelay() { audioDelay = 0 }
    public mutating func resetSubtitleDelay() { subtitleDelay = 0 }

    // MARK: Reading

    public var selectedAudio: AudioTrackInfo? { audioTracks.first { $0.id == selectedAudioID } }
    public var selectedSubtitle: SubtitleTrackInfo? { subtitleTracks.first { $0.id == selectedSubtitleID } }

    /// What to remember for the series right now.
    public var rememberedChoice: SeriesTrackChoice { remembered(audio: selectedAudio, subtitle: selectedSubtitle) }

    public var audioPicker: TrackPickerState {
        let rows = audioTracks.map { track in
            TrackRow(id: track.id, title: TrackLabels.language(track.language), subtitle: TrackLabels.audioDescription(track),
                     badges: Self.audioBadges(track), isSelected: track.id == selectedAudioID)
        }
        let sections = rows.isEmpty ? [] : [TrackSection(title: nil, rows: rows)]
        return TrackPickerState(title: "Audio", sections: sections, reason: audioReason,
                                sync: Self.syncRow(label: "Audio Delay", seconds: audioDelay))
    }

    public var subtitlePicker: TrackPickerState {
        var sections = [TrackSection(title: nil, rows: [
            TrackRow(id: TrackRow.offID, title: "Off", isSelected: selectedSubtitleID == nil, isOff: true)
        ])]
        func row(_ t: SubtitleTrackInfo) -> TrackRow {
            TrackRow(id: t.id, title: TrackLabels.language(t.language), subtitle: TrackLabels.subtitleFormat(t.codec),
                     badges: Self.subtitleBadges(t), isSelected: t.id == selectedSubtitleID)
        }
        let embedded = subtitleTracks.filter { !$0.isExternal }.map(row)
        let external = subtitleTracks.filter(\.isExternal).map(row)
        if !embedded.isEmpty { sections.append(TrackSection(title: "In the File", rows: embedded)) }
        if !external.isEmpty { sections.append(TrackSection(title: "External Files", rows: external)) }
        return TrackPickerState(title: "Subtitles", sections: sections, reason: subtitleReason,
                                sync: Self.syncRow(label: "Subtitle Delay", seconds: subtitleDelay))
    }

    // MARK: Helpers

    private func remembered(audio: AudioTrackInfo?, subtitle: SubtitleTrackInfo?) -> SeriesTrackChoice {
        SeriesTrackChoice(audio: audio, subtitle: subtitle)
    }

    static func round(_ seconds: TimeInterval) -> TimeInterval { (seconds * 1000).rounded() / 1000 }

    static func audioBadges(_ t: AudioTrackInfo) -> [String] {
        var b: [String] = []
        if t.isDefault { b.append("Default") }
        if t.isCommentary { b.append("Commentary") }
        if t.isAudioDescription { b.append("Audio Description") }
        return b
    }

    static func subtitleBadges(_ t: SubtitleTrackInfo) -> [String] {
        var b: [String] = []
        if t.isDefault { b.append("Default") }
        if t.isForced { b.append("Forced") }
        if t.isSDH { b.append("SDH") }
        if t.isCommentary { b.append("Commentary") }
        return b
    }

    /// "0 ms", "+250 ms", "-1.5 s" (milliseconds below 1 s in magnitude, seconds with one decimal above).
    public static func delayText(_ seconds: TimeInterval) -> String {
        let ms = Int((seconds * 1000).rounded())
        if ms == 0 { return "0 ms" }
        let sign = ms > 0 ? "+" : "-"
        let mag = abs(ms)
        if mag < 1000 { return "\(sign)\(mag) ms" }
        let s = Double(mag) / 1000
        let text = s == s.rounded() ? String(Int(s)) : String(format: "%.2f", s).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
        return "\(sign)\(text) s"
    }

    static func syncRow(label: String, seconds: TimeInterval) -> SyncOffsetRow {
        SyncOffsetRow(label: label, valueText: delayText(seconds), seconds: seconds,
                      canIncrease: seconds < SyncModel.maxUserDelay - 0.0001,
                      canDecrease: seconds > -SyncModel.maxUserDelay + 0.0001,
                      canReset: abs(seconds) > 0.0001)
    }
}
