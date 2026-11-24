import SwiftUI
import AppLogic

/// Settings > General (R456, PROVISIONAL): how the library and Home look and behave. Flat rows, the value at the right edge,
/// a picker for the option with more than two values. The Home rows moved here from their own page.
struct GeneralSettingsView: View {
    @AppStorage(AppPreference.sortOrder.rawValue) private var sortOrder = LibrarySortDefault.default.rawValue
    @AppStorage(AppPreference.hideSpoilers.rawValue) private var hideSpoilers = false
    @AppStorage(SettingsKey.showContinueWatching.rawValue) private var showContinue = true
    @AppStorage(SettingsKey.showNextUp.rawValue) private var showNextUp = true
    @AppStorage(SettingsKey.showRecentlyAdded.rawValue) private var showRecent = true
    @AppStorage(SettingsKey.continueWatchingDays.rawValue) private var days = SettingsKey.defaultContinueWatchingDays
    @AppStorage(SettingsKey.showDiscover.rawValue) private var showDiscover = true

    var body: some View {
        SettingsPane(title: "General", summary: "How the library and Home look and behave.") {
            Section {
                Picker("Sort Order", selection: $sortOrder) {
                    ForEach(LibrarySortDefault.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
                SettingToggle("Hide Spoilers", isOn: $hideSpoilers)
            } footer: {
                Text(SpoilerRules.footer)
            }
            Section("Home") {
                SettingToggle("Continue Watching", isOn: $showContinue)
                SettingToggle("Next Up", isOn: $showNextUp)
                SettingToggle("Recently Added", isOn: $showRecent)
                SettingToggle("Show Discover", isOn: $showDiscover)
                Picker("Keep Titles in Continue Watching", selection: $days) {
                    ForEach(SettingsKey.continueWatchingChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
            }
        }
    }
}
