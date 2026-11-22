import SwiftUI
import AppLogic

/// Home: the featured title, then Continue Watching, Next Up, Recently Added (R349, HomeRows). Rows the user turned off in
/// Settings are left out, and the featured title is picked from the rows that show.
struct HomeView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<HomeViewModel>?
    @State private var showSetup = false
    @AppStorage(SettingsKey.showContinueWatching.rawValue) private var showContinue = true
    @AppStorage(SettingsKey.showNextUp.rawValue) private var showNextUp = true
    @AppStorage(SettingsKey.showRecentlyAdded.rawValue) private var showRecent = true
    @AppStorage(SettingsKey.continueWatchingDays.rawValue) private var days = SettingsKey.defaultContinueWatchingDays

    var body: some View {
        VStack {
            // R388 (item B): above the page only while Home has nothing to show. A scan under a library already on screen
            // (every launch scans) no longer pushes the featured area and the first row down (`HomeScanNotice`).
            if HomeScanNotice.shows(isScanning: services.isScanning, hasContent: model?.screen.state.content.map { !visible($0).isEmpty } ?? false) {
                RebuildingBanner()
            }
            if let model {
                ScreenStateView(state: model.screen.state, onEmptyAction: { showSetup = true }, onRetry: { Task { await reload() } }) { rows in
                    HomeRows(rows: visible(rows))
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { await reload() }
        // R388: when Home was first shown, so the featured title takes the focus only right after launch (`LaunchFocus`).
        .onAppear { HomeLaunchFocus.state.homeShown(at: ProcessInfo.processInfo.systemUptime) }
        .addSourceCover(isPresented: $showSetup)
    }

    private func visible(_ rows: [HomeRow]) -> [HomeRow] {
        rows.filter { row in
            switch row.id {
            case .continueWatching: return showContinue
            case .nextUp: return showNextUp
            case .recentlyAdded: return showRecent
            }
        }
    }

    private func reload() async {
        if model == nil {
            model = ScreenModel(HomeViewModel(store: services.store, retentionDays: days > 0 ? days : SettingsKey.defaultContinueWatchingDays))
        }
        await model?.run { await $0.load() }
    }
}
