import SwiftUI
import AppLogic

/// Navigation shell: the standard top tab bar, one NavigationStack per tab.
///
/// `routeDestinations()` sits on the stack's ROOT VIEW, inside the stack. Apple: "Add this view modifier to a view inside a
/// NavigationStack" (https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)).
/// Until run 44401030622 it was attached to the NavigationStack itself (outside), so no `Route` destination was registered:
/// posters, show cards, Files folders and the Top Shelf link could not open their page (screens 55, 57, 60, 71 not reached;
/// OPEN_QUESTIONS R168). Discover and Settings push nothing of type `Route`, so they have none.
///
/// The Search tab uses the system search role, so the system places it at the trailing end. No custom bar, background or tint (docs/DESIGN_SYSTEM.md, row "Tab bar").
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
                NavigationStack(path: $homePath) { HomeView().tabRootScreen("Home", identifier: "screen.home").routeDestinations() }
            }
            Tab("Movies", systemImage: "film", value: AppTab.movies) {
                NavigationStack { MoviesView().tabRootScreen("Movies", identifier: "screen.movies").routeDestinations() }
            }
            Tab("Shows", systemImage: "tv", value: AppTab.shows) {
                NavigationStack { ShowsView().tabRootScreen("Shows", identifier: "screen.shows").routeDestinations() }
            }
            Tab("Files", systemImage: "folder", value: AppTab.files) {
                NavigationStack { FilesView().tabRootScreen("Files", identifier: "screen.files").routeDestinations() }
            }
            if showDiscover {
                Tab("Discover", systemImage: "sparkles", value: AppTab.discover) {
                    NavigationStack { DiscoverView().tabRootScreen("Discover", identifier: "screen.discover") }
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack { SearchView().screenIdentifier("screen.search").screenHeader("Search").routeDestinations() }
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView().tabRootScreen("Settings", identifier: "screen.settings") }
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
            // Time-boxed (R169): the library is on screen from the local database; iCloud never delays the launch.
            await services.launch(scanOnLaunch: scanOnLaunch)
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

extension View {
    /// A top-level tab screen (item 2 of the screenshot review, OPEN_QUESTIONS R166, PROVISIONAL): the content starts right
    /// under the tab bar with NO visible title, like Home and Search, because the selected tab already names the screen. The
    /// navigation title stays (the screen's name for the system) and the screen container carries it as a header for
    /// VoiceOver. `toolbarVisibility(_:for:)` with `.navigationBar`: tvOS 18.0+
    /// (https://developer.apple.com/documentation/swiftui/view/toolbarvisibility(_:for:)). Not used on Search: its system
    /// search field may live in that bar.
    func tabRootScreen(_ title: String, identifier: String) -> some View {
        navigationTitle(title)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .screenIdentifier(identifier)
            .screenHeader(title)
    }

    /// The screen's name, spoken as a header when VoiceOver enters the screen (the container keeps its children).
    func screenHeader(_ title: String) -> some View {
        accessibilityLabel(title).accessibilityAddTraits(.isHeader)
    }

    /// A stable name for UI tests (UITests/ScreenshotTests.swift waits on these instead of on visible text). The screen stays one
    /// accessibility container: its own elements keep their labels and focus order; only the container gets the identifier.
    func screenIdentifier(_ identifier: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
    }
}
