import Foundation
import LibraryIndex
import Subtitles

/// One row of the Audio or Subtitles submenu on a title's page.
public struct ItemTrackOption: Equatable, Sendable, Identifiable {
    /// The track's position in the file ("0", "1"…), or `TrackRow.offID` for the subtitles' Off row.
    public var id: String
    /// The language ("English"), or "Off".
    public var title: String
    /// What the track is ("Dolby Digital Plus 5.1", "Forced", "SDH"); nil when there is nothing to add.
    public var detail: String?
    public var isSelected: Bool
}

/// What the Audio and Subtitles rows of the actions menu show for one title.
public struct ItemTrackMenuState: Equatable, Sendable {
    public var audio: [ItemTrackOption]
    public var subtitles: [ItemTrackOption]

    /// The current audio track's language, the row's value; nil when the file has no audio track.
    public var audioValue: String? { audio.first(where: \.isSelected)?.title }
    /// The current subtitle's language, or "Off".
    public var subtitleValue: String { subtitles.first(where: \.isSelected)?.title ?? "Off" }
}

/// R471 (38), PROVISIONAL: Audio and Subtitles in a movie's and an episode's actions menu (the reference episode menu lists
/// both with the current choice as their value). The rows list the preferred file's own tracks as the index read them
/// (`FileTrackDetails`); the selected row is the one playback would start with: a choice made here for this title, else
/// the choice kept for the show, else the stored defaults, through the same rules as the player (`TrackDefaults.select`).
/// A pick is kept for this title only, as a `SeriesTrackChoice` (language and kind, not a track number), so the player
/// finds the same track in its own option list when the file is opened.
public enum ItemTrackMenu {
    /// The file's audio tracks in the selector's form; the id is the track's position in the file.
    public static func audioTracks(_ details: FileTrackDetails) -> [AudioTrackInfo] {
        details.audio.enumerated().map { index, track in
            AudioTrackInfo(id: String(index), language: track.language.flatMap { LanguageTag($0) }, codec: track.codec,
                           channels: track.channels ?? 2, isDefault: track.isDefault, isCommentary: track.isCommentary)
        }
    }

    public static func subtitleTracks(_ details: FileTrackDetails) -> [SubtitleTrackInfo] {
        details.subtitles.enumerated().map { index, track in
            SubtitleTrackInfo(id: String(index), language: track.language.flatMap { LanguageTag($0) }, codec: track.codec,
                              isForced: track.isForced, isSDH: track.isHearingImpaired)
        }
    }

    /// The rows, with the track playback would start with selected.
    public static func state(tracks details: FileTrackDetails, audioLanguage: LanguageTag?, subtitleLanguage: LanguageTag?,
                             mode: SubtitleMode, itemChoice: SeriesTrackChoice?, seriesChoice: SeriesTrackChoice?) -> ItemTrackMenuState {
        let audio = audioTracks(details)
        let subtitles = subtitleTracks(details)
        let result = TrackDefaults.select(audio: audio, subtitles: subtitles, originalLanguage: nil,
                                          audioLanguage: audioLanguage, subtitleLanguage: subtitleLanguage, mode: mode,
                                          remembered: startChoice(item: itemChoice, series: seriesChoice))
        let audioRows = audio.map { track in
            ItemTrackOption(id: track.id, title: TrackLabels.language(track.language), detail: audioDetail(track),
                            isSelected: track.id == result.audioTrackID)
        }
        var subtitleRows = [ItemTrackOption(id: TrackRow.offID, title: "Off", detail: nil, isSelected: result.subtitleTrackID == nil)]
        subtitleRows += subtitles.map { track in
            ItemTrackOption(id: track.id, title: TrackLabels.language(track.language), detail: subtitleDetail(track),
                            isSelected: track.id == result.subtitleTrackID)
        }
        return ItemTrackMenuState(audio: audioRows, subtitles: subtitleRows)
    }

    /// The choice to keep after an audio pick (the current subtitle stays as it is). Nil for an id the file does not have.
    public static func choosingAudio(_ id: String, tracks details: FileTrackDetails, current: ItemTrackMenuState) -> SeriesTrackChoice? {
        let audio = audioTracks(details)
        guard let picked = audio.first(where: { $0.id == id }) else { return nil }
        return SeriesTrackChoice(audio: picked, subtitle: selectedSubtitle(details, current))
    }

    /// The choice to keep after a subtitle pick; `TrackRow.offID` turns subtitles off. Nil for an id the file does not have.
    public static func choosingSubtitle(_ id: String, tracks details: FileTrackDetails, current: ItemTrackMenuState) -> SeriesTrackChoice? {
        let audio = audioTracks(details).first { track in current.audio.contains { $0.isSelected && $0.id == track.id } }
        if id == TrackRow.offID { return SeriesTrackChoice(audio: audio, subtitle: nil) }
        guard let picked = subtitleTracks(details).first(where: { $0.id == id }) else { return nil }
        return SeriesTrackChoice(audio: audio, subtitle: picked)
    }

    /// A choice made for this title wins over the one kept for its show.
    public static func startChoice(item: SeriesTrackChoice?, series: SeriesTrackChoice?) -> SeriesTrackChoice? { item ?? series }

    /// Where a title's own choice is kept (beside the show's, `StartTrackRules.rememberKey`).
    public static func storeKey(itemID: Int64) -> String { "vp.trackChoice.item.\(itemID)" }

    static func audioDetail(_ track: AudioTrackInfo) -> String? {
        var parts = [TrackLabels.audioDescription(track)]
        if track.isCommentary { parts.append("Commentary") }
        if track.isAudioDescription { parts.append("Audio Description") }
        let text = parts.filter { !$0.isEmpty }.joined(separator: ", ")
        return text.isEmpty ? nil : text
    }

    static func subtitleDetail(_ track: SubtitleTrackInfo) -> String? {
        var parts: [String] = []
        if track.isForced { parts.append("Forced") }
        if track.isSDH { parts.append("SDH") }
        if parts.isEmpty, let format = TrackLabels.subtitleFormat(track.codec) { parts.append(format) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func selectedSubtitle(_ details: FileTrackDetails, _ current: ItemTrackMenuState) -> SubtitleTrackInfo? {
        subtitleTracks(details).first { track in current.subtitles.contains { $0.isSelected && $0.id == track.id } }
    }
}
