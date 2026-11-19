import SwiftUI
import AppLogic

/// Settings: one row per area, each opening its own page. #15 3.1: the rows sit in the bounded right column with a symbol
/// each (L1, L2, L10); the left column says what Settings holds (L6: the tab bar names the tab, the page title is not
/// repeated in a dim bar). Symbol names are standard SF Symbols (unverified, from memory; OPEN_QUESTIONS R178).
struct SettingsView: View {
    var body: some View {
        SettingsPane(title: "Settings", summary: SettingsTexts.rootSummary) {
            Section {
                link("Playback", "play.rectangle") { PlaybackSettingsView() }
                link("Home Screen", "house") { HomeScreenSettingsView() }
                link("Sources", "externaldrive") { SourcesSettingsView() }
                link("Library", "books.vertical") { LibrarySettingsView() }
                link(OnlineLookupText.settingsTitle, "globe") { OnlineLookupSettingsView() }
            }
            Section {
                link("Storage and iCloud", "icloud") { StorageSettingsView() }
                link("Backup", "arrow.clockwise.icloud") { BackupSettingsView() }
            }
            Section {
                link("Accessibility", "accessibility") { AccessibilitySettingsView() }
                link("About", "info.circle") { AboutView() }
            }
        }
    }

    private func link<Destination: View>(_ title: String, _ symbol: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) { RowLabel(title, systemImage: symbol) }
    }
}
