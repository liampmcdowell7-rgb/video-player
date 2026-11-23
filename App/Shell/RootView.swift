import SwiftUI
import AppLogic

/// Navigation shell: the system sidebar (R359), one NavigationStack per item; Movies, Shows and Files in a "Library"
/// section (R376).
///
/// `routeDestinations()` sits on the stack's ROOT VIEW, inside the stack. Apple: "Add this view modifier to a view inside a
/// NavigationStack" (https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)).
/// Until run 44401030622 it was attached to the NavigationStack itself (outside), so no `Route` destination was registered:
/// posters, show cards, Files folders and the Top Shelf link could not open their page (screens 55, 57, 60, 71 not reached;
/// OPEN_QUESTIONS R168). Settings pushes nothing of type `Route`, so it has none.
///
/// Six tabs (AppLogic `AppTabID`; OPEN_QUESTIONS R167, option (c), PROVISIONAL): Home, Movies, Shows, Files, Search,
/// Settings. There is no Discover tab: Discover is shown in the Search tab while its field is empty (SearchView). The Search
/// tab uses the system search role. No custom bar, background or tint (docs/DESIGN_SYSTEM.md, row "Tab bar").
struct RootView: View {
    @Environment(AppServices.self) private var services
    @AppStorage(SettingsKey.scanOnLaunch.rawValue) private var scanOnLaunch = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .home
    @State private var homePath: [Route] = []
    // #21 F: every tab that shows cards keeps its path, so "Go to Movie" / "Go to Show" opens the page on the tab in use.
    @State private var moviesPath: [Route] = []
    @State private var showsPath: [Route] = []
    @State private var filesPath: [Route] = []
    @State private var searchPath: [Route] = []
    /// R348 (item B): each tab's root generation; re-selecting the selected tab raises it (AppLogic `TabRoots`).
    @State private var roots: TabRoots = TabRoots()
    /// #33 B (2): open task covers (`taskCover`, App/Shared/SettingsPane.swift).
    @State private var coverPresence: CoverPresence = CoverPresence.shared

    var body: some View {
        @Bindable var services = services
        TabView(selection: tabSelection) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                NavigationStack(path: $homePath) { HomeView().tabRootScreen("Home", identifier: "screen.home").routeDestinations() }
                    .id(roots.generation(of: .home))
                    .uiTestAccessibilityOverrides()
                    .accessibilityHidden(coverPresence.isCovered)
            }
            // R376 (decided by the owner's standing rule R312; R359 option (d)): Movies, Shows and Files in ONE system section,
            // as the sample's `SidebarContentView` makes "a sectioned sidebar" (AppLogic `AppSidebar`, Linux-tested). The
            // header is the literal "Library" (`AppSidebar.libraryTitle`; `TabSection`'s title is a `LocalizedStringResource`).
            // The values and the selection binding are unchanged, so R348's re-selection works inside the section too.
            // UNVERIFIED (not on Apple's pages): how tvOS 27 draws the section header, whether a section can be collapsed in
            // the tvOS sidebar, and how the header is exposed to VoiceOver and XCUITest (note -TABBAR records it).
            TabSection("Library") {
                Tab("Movies", systemImage: "film", value: AppTab.movies) {
                    NavigationStack(path: $moviesPath) { MoviesView().tabRootScreen("Movies", identifier: "screen.movies").routeDestinations() }
                        .id(roots.generation(of: .movies))
                        .uiTestAccessibilityOverrides()
                        .accessibilityHidden(coverPresence.isCovered)
                }
                Tab("Shows", systemImage: "tv", value: AppTab.shows) {
                    NavigationStack(path: $showsPath) { ShowsView().tabRootScreen("Shows", identifier: "screen.shows").routeDestinations() }
                        .id(roots.generation(of: .shows))
                        .uiTestAccessibilityOverrides()
                        .accessibilityHidden(coverPresence.isCovered)
                }
                Tab("Files", systemImage: "folder", value: AppTab.files) {
                    NavigationStack(path: $filesPath) { FilesView().tabRootScreen("Files", identifier: "screen.files").routeDestinations() }
                        .id(roots.generation(of: .files))
                        .uiTestAccessibilityOverrides()
                        .accessibilityHidden(coverPresence.isCovered)
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                NavigationStack(path: $searchPath) { SearchView().screenIdentifier("screen.search").screenHeader("Search").routeDestinations() }
                    .id(roots.generation(of: .search))
                    .uiTestAccessibilityOverrides()
                    .accessibilityHidden(coverPresence.isCovered)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView().tabRootScreen("Settings", identifier: "screen.settings") }
                    .id(roots.generation(of: .settings))
                    .uiTestAccessibilityOverrides()
                    .accessibilityHidden(coverPresence.isCovered)
            }
        }
        // R359 (owner's scan of ec27d52, 21 Nov 2026, finding 3; R167 option (f)): the system sidebar instead of the top tab
        // bar, as Apple's sample "Creating a tvOS media catalog app in SwiftUI" ("the new sidebar adaptive tab view style
        // that provides a sidebar in tvOS"). Apple, `sidebarAdaptable`: "macOS and tvOS always show a sidebar". The same
        // `Tab`s, values and selection binding (R348's re-selection) are kept; only the style changes. How the sidebar
        // collapses while the content has the focus, and whether re-selecting the selected item calls the binding's
        // setter, are not on Apple's pages: UNVERIFIED until a run (notes -TABBAR, -RESELECT).
        .tabViewStyle(.sidebarAdaptable)
        // #33 B (2): while a task cover is open, the tabs and the page under it are hidden from VoiceOver (HIG Modality: a
        // modal view "prevents interaction with the parent view"). The cover is presented in its own window subtree, so it
        // stays (notes 10-add-source-types-HIERARCHY, 74-file-details-HIERARCHY of the run of 20 Nov).
        // #36 8 T3: in the second run of 20 Nov the page was still in the tree under every cover (the -COVER notes: screen.home
        // 13 times, screen.item, screen.movies, screen.shows, screen.needsReview, screen.folder; 74-file-details-HIERARCHY
        // line 20: "StaticText, …, identifier: 'screen.folder'" in the page's subtree, the cover a separate top-level subtree
        // with an Alert, line 113 to 116). This modifier on the TabView did not reach the hosted pages (whether because the
        // tvOS TabView is a UIKit container is not on any page read), so every tab's NavigationStack is now hidden as well,
        // above; the TabView keeps it for the tab bar.
        // #36 group 2: the third run of 20 Nov (341b43b) still listed the page under about 30 covers with both of these in
        // place (10-add-source-types-HIERARCHY: screen.home and its four children; 66-move-sheet: screen.needsReview), so
        // each screen now hides ITSELF, inside its own hosted content (`screenIdentifier`, HiddenUnderTaskCover below).
        .accessibilityHidden(coverPresence.isCovered)
        .environment(coverPresence)
        .overlay(alignment: .bottom) {
            // The automatic restore after a cleanup or on a new Apple TV (docs/BACKUP.md). Standard progress view, no custom style.
            if services.backup.isAutoRestoring {
                RestoreBanner(status: services.backup.status)
                    .padding()
            }
        }
        .fullScreenCover(item: $services.playRequest) { request in
            PlayerScreen(request: request)
                .uiTestAccessibilityOverrides()
        }
        // #15 8.1: a title that cannot be played is a system alert over the page it was started from, not a view inside it.
        .alert(services.playFailure?.failure.alertTitle ?? PlaybackFailure.title,
               isPresented: Binding(get: { services.playFailure != nil }, set: { if !$0 { services.playFailure = nil } }),
               presenting: services.playFailure) { prompt in
            if prompt.failure.canTryAgain {
                Button("Try Again") {
                    services.playFailure = nil
                    services.playRequest = PlayRequest(itemID: prompt.request.itemID, fromStart: prompt.request.fromStart)
                }
            }
            Button("Done", role: .cancel) { services.playFailure = nil }
        } message: { prompt in
            Text(prompt.failure.text)
        }
        .onOpenURL { url in open(DeepLink.parse(url)) }
        .onChange(of: services.openRequest) {
            guard let route = services.openRequest else { return }
            services.openRequest = nil
            push(route)
        }
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

    /// R348 (owner's device test of build 5, item B; PROVISIONAL): the tab bar's selection. Selecting the tab that is
    /// already selected takes it back to its first page at the top, as Apple's apps do: the tab's path is emptied and its
    /// stack is rebuilt from the root (a new `.id`), which also removes pages pushed by destination (Settings, Files) that
    /// no path holds. Whether tvOS calls the binding's setter when the selected tab is pressed again is UNVERIFIED (no
    /// Apple page read says so); the UI test's -RESELECT note proves it on the next run.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { selection }, set: { (tab: AppTab) in
            if roots.select(tab, current: selection) { clearPath(of: tab) }
            selection = tab
        })
    }

    /// The pages of one tab's path (the stack's `.id` change removes the rest).
    private func clearPath(of tab: AppTab) {
        switch tab {
        case .home: homePath = []
        case .movies: moviesPath = []
        case .shows: showsPath = []
        case .files: filesPath = []
        case .search: searchPath = []
        case .settings: break
        }
    }

    /// Pushes a page on the stack of the tab in use (Settings shows no cards; its request opens on Home).
    private func push(_ route: Route) {
        switch selection {
        case .movies: moviesPath.append(route)
        case .shows: showsPath.append(route)
        case .files: filesPath.append(route)
        case .search: searchPath.append(route)
        default:
            selection = .home
            homePath.append(route)
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
    ///
    /// R375 (decided by the owner's standing rule R312): `toolbar` is true on Movies and Shows, whose controls are the system
    /// toolbar (`libraryToolbar`): the navigation bar stays visible to hold them, and its title is left empty so R166 holds
    /// (HIG Toolbars: "If titling a toolbar seems redundant, you can leave the title area empty"); the container still
    /// carries the screen's name for VoiceOver (`screenHeader`). How tvOS 27 draws that bar under the tab bar or beside the
    /// sidebar: UNVERIFIED.
    /// R413: Movies and Shows no longer pass `toolbar: true`; their controls are a row on the page (`libraryToolbar`), so
    /// the navigation bar would be empty (rule L6: no empty band). The parameter stays for a screen that needs the bar.
    func tabRootScreen(_ title: String, identifier: String, toolbar: Bool = false) -> some View {
        navigationTitle(toolbar ? "" : title)
            .toolbarVisibility(toolbar ? .visible : .hidden, for: .navigationBar)
            .screenIdentifier(identifier)
            .screenHeader(title)
    }

    /// A pushed page (#15 rule D1, PROVISIONAL like R166): the navigation bar is hidden, so tvOS draws no dim centred
    /// duplicate of the title above the content (evidence: "Sample Movie 1" at y=248 over the real title at y=345, 57; on the
    /// show page it floated over the list, 56; "Sample Library", 71). The title stays the screen's name for the system and
    /// its VoiceOver header; Menu still goes back one level (the bar has no back button on tvOS). design-lint rule
    /// pushed-title requires this (or tabRootScreen) wherever a page sets a navigation title.
    func pushedScreen(_ title: String) -> some View {
        navigationTitle(title)
            .toolbarVisibility(.hidden, for: .navigationBar)
            // One container first (as tabRootScreen does through screenIdentifier), so the header label names the
            // screen and is not applied to each child element.
            .accessibilityElement(children: .contain)
            .screenHeader(title)
            // R407 (A11Y1): the UI-test overrides on every pushed page that names itself here (pages opened by a
            // `NavigationLink` with an inline destination are not `Route` destinations; see RouteDestinations).
            .uiTestAccessibilityOverrides()
    }

    /// The screen's name, spoken as a header when VoiceOver enters the screen (the container keeps its children).
    func screenHeader(_ title: String) -> some View {
        accessibilityLabel(title).accessibilityAddTraits(.isHeader)
    }

    /// A stable name for UI tests (UITests/ScreenshotTests.swift waits on these instead of on visible text). The screen stays one
    /// accessibility container: its own elements keep their labels and focus order; only the container gets the identifier.
    func screenIdentifier(_ identifier: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(identifier)
            .modifier(HiddenUnderTaskCover())
    }
}

/// #36 group 2: every page screen (the views that carry a "screen." identifier through `screenIdentifier`) is hidden from
/// accessibility while a task cover is open: Apple, `accessibilityHidden(_:)`, "Specifies whether to hide this view from
/// system accessibility features." The modifier on each tab's NavigationStack and on the TabView (RootView) did not reach
/// the pages in the third run of 20 Nov; this one is applied inside the page's own SwiftUI content, so it does not depend
/// on SwiftUI passing the flag through a UIKit container (whether it does is not on any Apple page read: unverified). A
/// screen inside the cover itself is never hidden (`isInTaskCover`, set by TaskCoverChrome).
struct HiddenUnderTaskCover: ViewModifier {
    /// R292: the shared counter, not the environment (see TaskCoverChrome).
    private var presence: CoverPresence? { CoverPresence.shared }
    @Environment(\.isInTaskCover) private var isInTaskCover: Bool

    func body(content: Content) -> some View {
        let hidden: Bool = !isInTaskCover && (presence?.isCovered ?? false)
        #if DEBUG
        // R362 (item 10): what this screen was told, for the -COVER note (UI-test launches only).
        if UITestMode.current != .off {
            content.accessibilityHidden(hidden).accessibilityValue("cover probe: told hidden \(hidden)")
        } else {
            content.accessibilityHidden(hidden)
        }
        #else
        content.accessibilityHidden(hidden)
        #endif
    }
}
