import SwiftUI
import AppLogic

/// Settings > Playback. #15 3.2: bounded column (`SettingsPane`), footers of one or two lines, the full explanations on
/// "Learn More" pages (SettingsTexts).
struct PlaybackSettingsView: View {
    @AppStorage(SettingsKey.autoPlayNextEpisode.rawValue) private var autoPlayNext = true
    @AppStorage(SettingsKey.showSkipButtons.rawValue) private var skipButtons = true
    @AppStorage(SettingsKey.showPlaybackStatsButton.rawValue) private var statsButton = true
    @AppStorage(SettingsKey.rememberTrackChoicePerShow.rawValue) private var rememberTracks = true
    @AppStorage(SettingsKey.trueHDCompatibilityCore.rawValue) private var trueHDCore = false
    /// R311: the last playback that failed on this Apple TV (`PlaybackProblemLog`), tokens removed.
    @AppStorage(PlaybackProblem.storageKey) private var problemData: Data?

    var body: some View {
        SettingsPane(title: "Playback", summary: SettingsTexts.playbackSummary) {
            Section {
                SettingToggle("Play Next Episode Automatically", isOn: $autoPlayNext)
                SettingToggle("Show Skip Buttons", isOn: $skipButtons)
                LearnMoreLink(title: SettingsTexts.skipLearnMoreTitle, text: SettingsTexts.skipFull)
            } footer: {
                Text(SettingsTexts.skipShort)
            }
            Section {
                SettingToggle("Remember Audio and Subtitle Choice for Each Show", isOn: $rememberTracks)
                SettingToggle("Show Playback Stats in the Player", isOn: $statsButton)
            } footer: {
                Text(SettingsTexts.statsFooter)
            }
            Section {
                SettingToggle("Play the Dolby Digital Core of Dolby TrueHD", isOn: $trueHDCore)
                LearnMoreLink(title: SettingsTexts.trueHDLearnMoreTitle, text: SettingsTexts.trueHDFull)
            } footer: {
                Text(SettingsTexts.trueHDShort)
            }
            // R311: what the owner reads after a failed start, without a Mac: the step, the source, the file and the error.
            Section(PlaybackProblem.sectionTitle) {
                if let problem = PlaybackProblem.decoded(problemData) {
                    ForEach(Array(problem.rows.dropLast().enumerated()), id: \.offset) { _, row in
                        ValueRow(row.label, value: row.value)
                    }
                    Text(problem.error)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    StatusText(PlaybackProblem.noneText)
                }
            }
        }
    }
}
