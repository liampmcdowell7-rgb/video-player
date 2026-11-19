import SwiftUI
import AppLogic

struct PlaybackSettingsView: View {
    @AppStorage(SettingsKey.autoPlayNextEpisode.rawValue) private var autoPlayNext = true
    @AppStorage(SettingsKey.showSkipButtons.rawValue) private var skipButtons = true
    @AppStorage(SettingsKey.showPlaybackStatsButton.rawValue) private var statsButton = true
    @AppStorage(SettingsKey.rememberTrackChoicePerShow.rawValue) private var rememberTracks = true
    @AppStorage(SettingsKey.trueHDCompatibilityCore.rawValue) private var trueHDCore = false

    var body: some View {
        Form {
            Section {
                Toggle("Play Next Episode Automatically", isOn: $autoPlayNext)
                Toggle("Show Skip Buttons", isOn: $skipButtons)
            } footer: {
                Text("Skip buttons and the next-episode card appear only for titles that have intro, recap or credits markers. Markers come from chapters named Intro, Recap or Credits in MKV files, from .edl or .segments.json files next to the video, and from positions you mark yourself in the player. Markers from online lookups or from analysing the video are not available yet.")
            }
            Section {
                Toggle("Remember Audio and Subtitle Choice for Each Show", isOn: $rememberTracks)
                Toggle("Show Playback Stats in the Player", isOn: $statsButton)
            } footer: {
                Text("Playback Stats adds one item to the player’s menu. It is off on screen until you open it.")
            }
            Section {
                Toggle("Play the Dolby Digital Core of Dolby TrueHD", isOn: $trueHDCore)
            } footer: {
                Text("Off: Dolby TrueHD is decoded in full, losslessly, in its own channel layout up to 7.1 (Atmos plays as its 7.1 bed). On: tracks that carry a Dolby Digital core play that 5.1 core instead, which is lossy. Applies to the next title you play.")
            }
        }
        .pushedScreen("Playback")
    }
}
