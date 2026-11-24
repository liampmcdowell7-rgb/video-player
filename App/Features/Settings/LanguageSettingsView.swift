import SwiftUI
import AppLogic

/// Settings > Language (R456, PROVISIONAL): the language of online descriptions and of the pictures' text. Auto follows the
/// Apple TV's language. Audio and subtitle languages are not here: the system player picks those tracks (its own panel).
struct LanguageSettingsView: View {
    @AppStorage(AppPreference.metadataLanguage.rawValue) private var metadata = LanguagePreference.auto
    @AppStorage(AppPreference.artworkLanguage.rawValue) private var artwork = LanguagePreference.auto

    var body: some View {
        SettingsPane(title: "Language", summary: "Auto uses the language of this Apple TV.") {
            Section {
                picker("Metadata", selection: $metadata)
                picker("Artwork", selection: $artwork)
            } footer: {
                Text("Audio and subtitle languages are chosen in the player.")
            }
        }
    }

    private func picker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("Auto").tag(LanguagePreference.auto)
            ForEach(LanguagePreference.choices, id: \.code) { Text($0.name).tag($0.code) }
        }
    }
}
