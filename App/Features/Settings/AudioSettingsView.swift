import SwiftUI
import AppLogic

/// Settings > Audio (R458, PROVISIONAL). Only what the player can really do: Volume Boost raises the audio the app decodes
/// itself (DTS, Dolby TrueHD, Opus, Vorbis). Downmix Volume and LFE in Stereo Downmix are not here: the system mixes the
/// audio it plays down, and the app has no mixing stage of its own to set (Apple's audio mix only lowers a level).
struct AudioSettingsView: View {
    @AppStorage(AppPreference.volumeBoost.rawValue) private var boost = VolumeBoost.default.rawValue

    var body: some View {
        SettingsPane(title: "Audio", summary: "Level of the audio this app decodes itself.") {
            Section {
                Picker("Volume Boost", selection: $boost) {
                    ForEach(VolumeBoost.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
            } footer: {
                Text(VolumeBoost.footer)
            }
            Section {
                StatusText(VolumeBoost.atmosLine).readableRow()
                    .accessibilityIdentifier(SettingsRowID.last)
            }
        }
    }
}
