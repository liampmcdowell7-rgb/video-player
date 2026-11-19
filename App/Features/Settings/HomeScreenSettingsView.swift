import SwiftUI
import AppLogic

/// Settings > Home Screen. #15 3.2: bounded column (`SettingsPane`), one-line footers.
struct HomeScreenSettingsView: View {
    @AppStorage(SettingsKey.showContinueWatching.rawValue) private var showContinue = true
    @AppStorage(SettingsKey.showNextUp.rawValue) private var showNextUp = true
    @AppStorage(SettingsKey.showRecentlyAdded.rawValue) private var showRecent = true
    @AppStorage(SettingsKey.continueWatchingDays.rawValue) private var days = SettingsKey.defaultContinueWatchingDays
    @AppStorage(SettingsKey.showDiscover.rawValue) private var showDiscover = true

    var body: some View {
        SettingsPane(title: "Home Screen", summary: SettingsTexts.homeSummary) {
            Section("Rows") {
                SettingToggle("Continue Watching", isOn: $showContinue)
                SettingToggle("Next Up", isOn: $showNextUp)
                SettingToggle("Recently Added", isOn: $showRecent)
            }
            Section {
                Picker("Keep Titles in Continue Watching", selection: $days) {
                    ForEach(SettingsKey.continueWatchingChoices, id: \.self) { choice in
                        Text("\(choice) days").tag(choice)
                    }
                }
            } footer: {
                Text(SettingsTexts.continueFooter)
            }
            Section {
                SettingToggle("Show Discover", isOn: $showDiscover)
            } header: {
                Text("Discover")
            } footer: {
                Text(SettingsTexts.discoverFooter)
            }
        }
    }
}
