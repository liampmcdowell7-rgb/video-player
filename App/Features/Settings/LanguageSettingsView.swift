import SwiftUI
import AppLogic

/// Settings > Language (R456, R458, PROVISIONAL): the default audio and subtitle language, and the language of online descriptions and
/// of the pictures' text. Auto follows the Apple TV's language.
struct LanguageSettingsView: View {
    @AppStorage(AppPreference.audioLanguage.rawValue) private var audio = LanguagePreference.auto
    @AppStorage(AppPreference.subtitleLanguage.rawValue) private var subtitles = LanguagePreference.auto
    @AppStorage(AppPreference.metadataLanguage.rawValue) private var metadata = LanguagePreference.auto
    @AppStorage(AppPreference.artworkLanguage.rawValue) private var artwork = LanguagePreference.auto

    var body: some View {
        SettingsPane(title: "Language", summary: "Auto uses the language of this Apple TV.") {
            Section {
                picker("Audio", selection: $audio)
                picker("Subtitles", selection: $subtitles)
            } footer: {
                Text("What the player picks at the start. A choice you make in the player for a show wins.")
            }
            Section {
                picker("Metadata", selection: $metadata)
                picker("Artwork", selection: $artwork)
            } footer: {
                Text("The language of online descriptions and of the text in pictures.")
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
