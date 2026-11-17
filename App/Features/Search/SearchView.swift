import SwiftUI
import AppLogic

/// Search: titles in your library only. Typing starts a search after a short pause.
struct SearchView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<SearchViewModel>?
    @State private var query = ""

    var body: some View {
        Group {
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
        .searchable(text: $query)
        .task(id: query) { await search() }
        .task(id: services.libraryRevision) { await search() }
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
