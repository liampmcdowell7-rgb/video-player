import SwiftUI
import AppLogic

/// The Search tab (OPEN_QUESTIONS R167, option (c), PROVISIONAL). The system search field and keyboard of `.searchable` stay at
/// the top; below them, exactly one of (AppLogic `SearchTabContent`):
/// - field empty, Discover on: Discover (its rows, or its own empty state such as "needs a TMDB key", with nothing sent);
/// - field empty, Discover off (Settings > Home Screen > Show Discover): the "Search Your Library" prompt, no discovery request;
/// - something typed: titles in your library only, after a short pause. Discover is hidden; clearing the field brings it back.
/// Library results and Discover are never in one list.
/// R337 (PROVISIONAL, docs/HIG_AUDIT.md T11): while something is typed, the system `searchSuggestions` lists up to five of the
/// titles found (AppLogic `SearchSuggestions`); HIG Searching: "offer predictive search suggestions". Nothing new is requested
/// or stored. Their exact look under the tvOS 27 keyboard is UNVERIFIED until a run.
/// R343 (Decided by the owner, 21 Nov 2026; T11): while the field is empty, the same system suggestions list the recent
/// searches (HIG Searching: "display a person's recent searches before they start typing"), with Clear Recent Searches.
/// A search is kept when it is submitted, or when the screen is left (a result opened, another tab) with results on it.
/// Kept on this Apple TV only (AppLogic `RecentSearches`: one UserDefaults value, never synced, backed up or sent). How the
/// tvOS 27 keyboard shows suggestions for an empty field, and a button among them, is UNVERIFIED.
struct SearchView: View {
    @Environment(AppServices.self) private var services
    /// Settings > Home Screen > Show Discover. When off, Discover is not shown and no discovery requests are made.
    @AppStorage(SettingsKey.showDiscover.rawValue) private var showDiscover = true
    @State private var model: ScreenModel<SearchViewModel>?
    @State private var discover = DiscoverLoader()
    @State private var query = ""
    /// R343: the recent searches, newest first, one per line (`RecentSearches`).
    @AppStorage(RecentSearches.defaultsKey) private var recentStored = ""

    /// R459: Discover lists titles from online sources that are not in the library, so no rating rule reaches them; it is off
    /// while Parental Controls' Restrictions are on, and no discovery request is made.
    private var content: SearchTabContent { .forQuery(query, showDiscover: showDiscover && OnlineTitleSurface.discover.isAvailable(restricted: services.restrictionsOn)) }

    var body: some View {
        VStack(alignment: .leading) {
            // R398 (audit Q1): Apple, searchSuggestions(_:): "In tvOS, searchable modifiers only support suggestion
            // views of type Text". The system's row has no heading and takes no button, so the label of the recent
            // terms and Clear Recent Searches are here, in the page right under that row, while the field is empty.
            if query.isEmpty, !RecentSearches.decode(recentStored).isEmpty {
                HStack(spacing: CGFloat(RowSpacing.betweenActions)) {
                    ShelfHeader(RecentSearches.heading)
                    // R403 (owner's review of the run on f0a67d3, item 5; PROVISIONAL): the plain bordered button, as
                    // every other secondary action. It had the destructive role, which tvOS drew as red text on a red
                    // capsule (76-search-recent); no Apple page read in this session says a destructive button is drawn
                    // so on tvOS, so the role is dropped. Clearing is undone by searching again.
                    Button(RecentSearches.clearTitle, systemImage: "xmark.circle") { recentStored = "" }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(ControlID.clearRecentSearches)
                }
            }
            // R403: the page's own content fills the rest, at its normal place: a message centres itself in this space,
            // results start at the top.
            Group {
                switch content {
                case .discover:
                    DiscoverView(loader: discover)
                case .prompt, .libraryResults:
                    results
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // R403 (item 5): the stack fills the page from its top leading corner. Before, it was as large as its content
        // and centred, so with a short message ("Discover Needs a Key") the heading and Clear stood in the middle of the
        // page, right on the message.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .searchable(text: $query)
        .searchSuggestions {
            let recent: [String] = RecentSearches.shown(RecentSearches.decode(recentStored), query: query)
            if recent.isEmpty {
                ForEach(suggestions, id: \.self) { title in
                    Text(title).searchCompletion(title)
                }
            } else {
                // R393, R398 (PROVISIONAL): the suggestions row is the SYSTEM's view, and on tvOS it takes `Text` views
                // only (Apple's page). It drew the `Section` header "Recent Searches" as one more chip (76-search-recent).
                // Only the recent terms are handed over; their heading and Clear Recent Searches are in the page.
                ForEach(recent, id: \.self) { text in
                    Text(text).searchCompletion(text)
                }
            }
        }
        .onSubmit(of: .search) { remember() }
        .onDisappear { if hasResults { remember() } }
        .task(id: query) { await search() }
        .task(id: services.libraryRevision) { await search() }
        .task(id: "\(content.loadsDiscover)|\(services.libraryRevision)|\(services.online.keyRevision)") {
            if content.loadsDiscover { await discover.loadIfNeeded(services: services) }
        }
    }

    /// R337: the titles the library search found for the typed text (none for Discover, the prompt or an error).
    private var suggestions: [String] {
        guard case .libraryResults = content, case .loaded(let cards)? = model?.screen.state else { return [] }
        return SearchSuggestions.titles(cards.map(\.title), query: query)
    }

    /// R343: true while library results are on screen for the typed text.
    private var hasResults: Bool {
        guard case .libraryResults = content, case .loaded(let cards)? = model?.screen.state else { return false }
        return !cards.isEmpty
    }

    /// R343: keeps the typed text as a recent search, on this Apple TV only.
    private func remember() {
        recentStored = RecentSearches.encode(RecentSearches.recording(query, in: RecentSearches.decode(recentStored)))
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
