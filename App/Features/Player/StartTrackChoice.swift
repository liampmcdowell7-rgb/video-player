import AVFoundation
import AppLogic
import Subtitles
import LibraryIndex

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

    static func apply(to item: AVPlayerItem, seriesTitle: String?, itemID: Int64? = nil, defaults: UserDefaults = .standard) async {
        let audioStored = defaults.string(forKey: AppPreference.audioLanguage.rawValue)
        let subtitleStored = defaults.string(forKey: AppPreference.subtitleLanguage.rawValue)
        let mode = SubtitleMode(rawValue: defaults.string(forKey: AppPreference.subtitleMode.rawValue) ?? "") ?? .auto
        // R471 (38): a choice made for this title in its actions menu wins over the show's.
        let remembered = ItemTrackMenu.startChoice(item: itemChoice(itemID, defaults: defaults),
                                                   series: rememberedChoice(for: seriesTitle, defaults: defaults))
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
    static func remember(from item: AVPlayerItem, seriesTitle: String?, itemID: Int64? = nil, defaults: UserDefaults = .standard) async {
        // R471 (38): a title with its own choice keeps the one made in the player too, so the menu shows what was last heard.
        let keepsItem = itemChoice(itemID, defaults: defaults) != nil
        let keepsSeries = seriesTitle != nil && (defaults.object(forKey: SettingsKey.rememberTrackChoicePerShow.rawValue) as? Bool ?? true)
        guard keepsItem || keepsSeries else { return }
        let lists = await read(item)
        let selection = item.currentMediaSelection
        let audio = lists.audioGroup.flatMap { group in
            selection.selectedMediaOption(in: group).flatMap { group.options.firstIndex(of: $0) }
        }.flatMap { index in lists.audio.first { $0.id == String(index) } }
        let subtitle = lists.subtitleGroup.flatMap { group in
            selection.selectedMediaOption(in: group).flatMap { group.options.firstIndex(of: $0) }
        }.flatMap { index in lists.subtitles.first { $0.id == String(index) } }
        let choice = SeriesTrackChoice(audio: audio, subtitle: subtitle)
        guard let data = try? JSONEncoder().encode(choice) else { return }
        if keepsSeries, let seriesTitle { defaults.set(data, forKey: StartTrackRules.rememberKey(seriesTitle: seriesTitle)) }
        if keepsItem, let itemID { defaults.set(data, forKey: ItemTrackMenu.storeKey(itemID: itemID)) }
    }

    /// R471 (38): the Audio and Subtitles rows of a title's actions menu, with the track playback would start with selected.
    static func menuState(tracks: FileTrackDetails, itemID: Int64, seriesTitle: String?, defaults: UserDefaults = .standard) -> ItemTrackMenuState {
        let system = Locale.preferredLanguages
        let mode = SubtitleMode(rawValue: defaults.string(forKey: AppPreference.subtitleMode.rawValue) ?? "") ?? .auto
        return ItemTrackMenu.state(
            tracks: tracks,
            audioLanguage: TrackLanguageChoice.tag(stored: defaults.string(forKey: AppPreference.audioLanguage.rawValue), system: system),
            subtitleLanguage: TrackLanguageChoice.tag(stored: defaults.string(forKey: AppPreference.subtitleLanguage.rawValue), system: system),
            mode: mode, itemChoice: itemChoice(itemID, defaults: defaults),
            seriesChoice: rememberedChoice(for: seriesTitle, defaults: defaults))
    }

    /// R471 (38): keeps a pick from the actions menu for this title only.
    static func keep(_ choice: SeriesTrackChoice, itemID: Int64, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(choice) { defaults.set(data, forKey: ItemTrackMenu.storeKey(itemID: itemID)) }
    }

    private static func itemChoice(_ itemID: Int64?, defaults: UserDefaults) -> SeriesTrackChoice? {
        guard let itemID, let data = defaults.data(forKey: ItemTrackMenu.storeKey(itemID: itemID)) else { return nil }
        return try? JSONDecoder().decode(SeriesTrackChoice.self, from: data)
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
