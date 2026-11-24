import SwiftUI
import AppLogic

/// Settings: one row per area, each opening its own page. #15 3.1: the rows sit in the bounded right column with a symbol
/// each (L1, L2, L10); the left column says what Settings holds (L6: the tab bar names the tab, the page title is not
/// repeated in a dim bar). Symbol names are standard SF Symbols (unverified, from memory; OPEN_QUESTIONS R178).
struct SettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        SettingsPane(title: "Settings", summary: SettingsTexts.rootSummary) {
            Section {
                link("Sources", "externaldrive") { SourcesSettingsView() }
                link("Library", "books.vertical") { LibrarySettingsView() }
                link("General", "gearshape") { GeneralSettingsView() }
            }
            Section {
                link("Sync and Backup", "icloud") { SyncAndBackupSettingsView() }
                link("Metadata and Artwork", "photo.on.rectangle") { MetadataArtworkSettingsView() }
            }
            Section {
                link("Playback", "play.rectangle") { PlaybackSettingsView() }
                link("Audio", "speaker.wave.2") { AudioSettingsView() }
                link("Language", "character.bubble") { LanguageSettingsView() }
            }
            Section {
                link("Parental Controls", "lock") { ParentalControlsView() }
                link("Accessibility", "accessibility") { AccessibilitySettingsView() }
                link("About", "info.circle") { AboutView() }
            } footer: {
                // R456: the app's version in small text at the bottom of the top level.
                Text("Version " + AppInfo.version).font(.caption)
            }
        }
        // R456: a setting changed on a page below is written to the user data when this page shows again (Settings and Watch State).
        .onAppear { services.pushSettings() }
    }

    private func link<Destination: View>(_ title: String, _ symbol: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) { RowLabel(title, systemImage: symbol) }
    }
}
