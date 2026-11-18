import SwiftUI
import AppLogic

/// Navigation shell: the standard top tab bar, one NavigationStack per tab. The Search tab uses the system search role,
/// so the system places it at the trailing end. No custom bar, background or tint (docs/DESIGN_SYSTEM.md, row "Tab bar").
struct RootView: View {
    @Environment(AppServices.self) private var services
    /// Settings > Home Screen > Show Discover. When off, the tab is removed and no discovery requests are made.
    @AppStorage(SettingsKey.showDiscover.rawValue) private var showDiscover = true
    @AppStorage(SettingsKey.scanOnLaunch.rawValue) private var scanOnLaunch = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var homePath: [Route] = []

    var body: some View {
        @Bindable var services = services
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $homePath) { HomeView() }
                    .routeDestinations()
            }
            Tab("Movies", systemImage: "film", value: AppTab.movies) {
                NavigationStack { MoviesView() }
                    .routeDestinations()
            }
            Tab("Shows", systemImage: "tv", value: AppTab.shows) {
                NavigationStack { ShowsView() }
                    .routeDestinations()
            }
            Tab("Files", systemImage: "folder", value: AppTab.files) {
                NavigationStack { FilesView() }
                    .routeDestinations()
            }
            if showDiscover {
                Tab("Discover", systemImage: "sparkles", value: AppTab.discover) {
                    NavigationStack { DiscoverView() }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
                    .routeDestinations()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .overlay(alignment: .bottom) {
            // The automatic restore after a cleanup or on a new Apple TV (docs/BACKUP.md). Standard progress view, no custom style.
            if services.backup.isAutoRestoring {
                RestoreBanner(status: services.backup.status)
                    .padding()
            }
        }
        .fullScreenCover(item: $services.playRequest) { request in
            PlayerScreen(request: request)
        }
        .onOpenURL { url in open(DeepLink.parse(url)) }
        .task {
            #if DEBUG
            // UI-test launches (screenshots): no iCloud calls and no scan; the sample library instead, then the asked-for screen.
            if UITestMode.current != .off {
                await UITestMode.prepare(services)
                if let tab = UITestMode.tab(named: UITestMode.value(UITestLaunch.tabArgument)) { selection = tab }
                if let title = UITestMode.value(UITestLaunch.openArgument), let route = await UITestMode.route(forTitle: title, in: services) {
                    selection = .home
                    homePath = [route]
                }
                return
            }
            #endif
            await services.refreshCloudStatus()
            await services.startCloudSync()
            if scanOnLaunch { await services.scanAll() }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { services.sync.request(.becameActive) }
        }
    }

    /// Opens what a link names (a Top Shelf item, for example). Anything that is not exactly one of the known shapes is ignored.
    private func open(_ link: DeepLink?) {
        guard let link else { return }
        selection = .home
        switch link {
        case .item(let id): homePath = [.item(id)]
        case .series(let id): homePath = [.series(id)]
        case .library: homePath = []
        }
    }
}
