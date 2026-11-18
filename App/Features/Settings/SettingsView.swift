import SwiftUI
import AppLogic

/// Settings: one row per area, each opening its own page.
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("Playback", destination: PlaybackSettingsView())
            NavigationLink("Home Screen", destination: HomeScreenSettingsView())
            NavigationLink("Sources", destination: SourcesSettingsView())
            NavigationLink("Library", destination: LibrarySettingsView())
            NavigationLink(OnlineLookupText.settingsTitle, destination: OnlineLookupSettingsView())
            NavigationLink("Storage and iCloud", destination: StorageSettingsView())
            NavigationLink("Backup", destination: BackupSettingsView())
            NavigationLink("Accessibility", destination: AccessibilitySettingsView())
            NavigationLink("About", destination: AboutView())
        }
        .navigationTitle("Settings")
    }
}
