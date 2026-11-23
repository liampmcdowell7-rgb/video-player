import AVFoundation
import AppLogic
import Subtitles

/// R458: at the start of a playback the stored defaults (Settings > Language > Audio and Subtitles, Playback > Subtitles) pick
/// the audio and subtitle option of the system player's own item. The choice a person made for this show earlier wins; with
/// everything on Auto nothing is changed and the system's own choice stands (R312). Apple: `AVPlayerItem.select(_:in:)` "selects a
/// media option in a given media selection group and deselects all other options in that group".
@MainActor
enum StartTrackChoice {
    /// The option lists of one item, as the pure selector reads them. Index = id.
    private struct Lists {
        var audioGroup: AVMediaSelectionGroup?
        var subtitleGroup: AVMediaSelectionGroup?
        var audio: [AudioTrackInfo] = []
        var subtitles: [SubtitleTrackInfo] = []
    }

    static func apply(to item: AVPlayerItem, seriesTitle: String?, defaults: UserDefaults = .standard) async {
        let audioStored = defaults.string(forKey: AppPreference.audioLanguage.rawValue)
        let subtitleStored = defaults.string(forKey: AppPreference.subtitleLanguage.rawValue)
        let mode = SubtitleMode(rawValue: defaults.string(forKey: AppPreference.subtitleMode.rawValue) ?? "") ?? .auto
        let remembered = rememberedChoice(for: seriesTitle, defaults: defaults)
        if remembered == nil, StartTrackRules.usesSystemChoice(audio: audioStored, subtitleLanguage: subtitleStored, mode: mode) { return }
        let lists = await read(item)
        let system = Locale.preferredLanguages
        let result = TrackDefaults.select(
            audio: lists.audio, subtitles: lists.subtitles, originalLanguage: nil,
            audioLanguage: TrackLanguageChoice.tag(stored: audioStored, system: system),
            subtitleLanguage: TrackLanguageChoice.tag(stored: subtitleStored, system: system),
            mode: mode, remembered: remembered)
        if let group = lists.audioGroup, let id = result.audioTrackID, let index = Int(id), group.options.indices.contains(index) {
            item.select(group.options[index], in: group)
        }
        if let group = lists.subtitleGroup {
            if let id = result.subtitleTrackID, let index = Int(id), group.options.indices.contains(index) {
                item.select(group.options[index], in: group)
            } else if group.allowsEmptySelection {
                item.select(nil, in: group)
            }
        }
    }

    /// Keeps what the person picked in the player for this show (Remember Audio and Subtitle Choice for Each Show).
    static func remember(from item: AVPlayerItem, seriesTitle: String?, defaults: UserDefaults = .standard) async {
        guard let seriesTitle, defaults.object(forKey: SettingsKey.rememberTrackChoicePerShow.rawValue) as? Bool ?? true else { return }
        let lists = await read(item)
        let selection = item.currentMediaSelection
        let audio = lists.audioGroup.flatMap { group in
            selection.selectedMediaOption(in: group).flatMap { group.options.firstIndex(of: $0) }
        }.flatMap { index in lists.audio.first { $0.id == String(index) } }
        let subtitle = lists.subtitleGroup.flatMap { group in
            selection.selectedMediaOption(in: group).flatMap { group.options.firstIndex(of: $0) }
        }.flatMap { index in lists.subtitles.first { $0.id == String(index) } }
        let choice = SeriesTrackChoice(audio: audio, subtitle: subtitle)
        if let data = try? JSONEncoder().encode(choice) { defaults.set(data, forKey: StartTrackRules.rememberKey(seriesTitle: seriesTitle)) }
    }

    private static func rememberedChoice(for seriesTitle: String?, defaults: UserDefaults) -> SeriesTrackChoice? {
        guard let seriesTitle, defaults.object(forKey: SettingsKey.rememberTrackChoicePerShow.rawValue) as? Bool ?? true,
              let data = defaults.data(forKey: StartTrackRules.rememberKey(seriesTitle: seriesTitle)) else { return nil }
        return try? JSONDecoder().decode(SeriesTrackChoice.self, from: data)
    }

    private static func read(_ item: AVPlayerItem) async -> Lists {
        var lists = Lists()
        if let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) {
            lists.audioGroup = group
            lists.audio = group.options.enumerated().map { index, option in
                AudioTrackInfo(id: String(index), language: option.extendedLanguageTag.flatMap { LanguageTag($0) }, codec: "",
                               channels: 2, isDefault: index == 0,
                               isAudioDescription: option.hasMediaCharacteristic(.describesVideoForAccessibility))
            }
        }
        if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
            lists.subtitleGroup = group
            lists.subtitles = group.options.enumerated().map { index, option in
                SubtitleTrackInfo(id: String(index), language: option.extendedLanguageTag.flatMap { LanguageTag($0) },
                                  isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles),
                                  isSDH: option.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility))
            }
        }
        return lists
    }
}
