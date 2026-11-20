import SwiftUI
import AppLogic

/// Home: Continue Watching, Next Up, Recently Added. Rows the user turned off in Settings are left out.
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
            if services.isScanning {
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
