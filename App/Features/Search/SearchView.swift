import SwiftUI
import AppLogic

/// The Search tab (OPEN_QUESTIONS R167, option (c), PROVISIONAL). The system search field and keyboard of `.searchable` stay at
/// the top; below them, exactly one of (AppLogic `SearchTabContent`):
/// - field empty, Discover on: Discover (its rows, or its own empty state such as "needs a TMDB key", with nothing sent);
/// - field empty, Discover off (Settings > Home Screen > Show Discover): the "Search Your Library" prompt, no discovery request;
/// - something typed: titles in your library only, after a short pause. Discover is hidden; clearing the field brings it back.
/// Library results and Discover are never in one list.
struct SearchView: View {
    @Environment(AppServices.self) private var services
    /// Settings > Home Screen > Show Discover. When off, Discover is not shown and no discovery requests are made.
    @AppStorage(SettingsKey.showDiscover.rawValue) private var showDiscover = true
    @State private var model: ScreenModel<SearchViewModel>?
    @State private var discover = DiscoverLoader()
    @State private var query = ""

    private var content: SearchTabContent { .forQuery(query, showDiscover: showDiscover) }

    var body: some View {
        Group {
            switch content {
            case .discover:
                DiscoverView(loader: discover)
            case .prompt, .libraryResults:
                results
            }
        }
        .searchable(text: $query)
        .task(id: query) { await search() }
        .task(id: services.libraryRevision) { await search() }
        .task(id: "\(content.loadsDiscover)|\(services.libraryRevision)|\(services.online.keyRevision)") {
            if content.loadsDiscover { await discover.loadIfNeeded(services: services) }
        }
    }

    @ViewBuilder private var results: some View {
        if let model {
            switch model.screen.state {
            case .empty(let empty):
                EmptyStateView(empty: empty, action: {})
            case .loaded(let cards):
                PosterGrid(cards: cards)
            case .failed(let error):
                ErrorStateView(error: error, retry: { Task { await search() } })
            case .idle, .loading:
                LoadingView()
            }
        } else {
            LoadingView()
        }
    }

    private func search() async {
        if model == nil { model = ScreenModel(SearchViewModel(store: services.store)) }
        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }
        let text = query
        await model?.run { await $0.search(text) }
    }
}
