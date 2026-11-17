import SwiftUI
import AppLogic

struct HomeScreenSettingsView: View {
    @AppStorage(SettingsKey.showContinueWatching.rawValue) private var showContinue = true
    @AppStorage(SettingsKey.showNextUp.rawValue) private var showNextUp = true
    @AppStorage(SettingsKey.showRecentlyAdded.rawValue) private var showRecent = true
    @AppStorage(SettingsKey.continueWatchingDays.rawValue) private var days = SettingsKey.defaultContinueWatchingDays
    @AppStorage(SettingsKey.showDiscover.rawValue) private var showDiscover = true

    var body: some View {
        Form {
            Section("Rows") {
                Toggle("Continue Watching", isOn: $showContinue)
                Toggle("Next Up", isOn: $showNextUp)
                Toggle("Recently Added", isOn: $showRecent)
            }
            Section {
                Picker("Keep Titles in Continue Watching", selection: $days) {
                    ForEach(SettingsKey.continueWatchingChoices, id: \.self) { choice in
                        Text("\(choice) days").tag(choice)
                    }
                }
            } footer: {
                Text("The same titles appear in the Top Shelf row on the Apple TV Home Screen once artwork is available for them.")
            }
            Section("Discover") {
                Toggle("Show Discover", isOn: $showDiscover)
            }
        }
        .navigationTitle("Home Screen")
    }
}
