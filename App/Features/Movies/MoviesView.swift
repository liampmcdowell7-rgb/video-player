import SwiftUI
import AppLogic

/// Movies: a poster grid with filters, sorts and saved views.
struct MoviesView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<ItemGridViewModel>?
    @State private var showSetup = false
    @State private var showSaveView = false
    @State private var reviewCount = 0

    var body: some View {
        VStack(alignment: .leading) {
            if let model {
                if showsControls(model) {
                    GridControls(model: model, onSave: { showSaveView = true }, reviewCount: reviewCount)
                } else {
                    // An empty Movies screen still says where unsorted files are (addendum #18 C).
                    NeedsReviewButton(count: reviewCount)
                }
                ScreenStateView(state: model.screen.state, onEmptyAction: { emptyAction(model) }, onRetry: { Task { await reload() } }) { grid in
                    PosterGrid(cards: grid.cards, onCardAppear: { id in
                        Task { await model.run { await $0.loadMoreIfNeeded(visible: id) } }
                    })
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { await reload() }
        .addSourceCover(isPresented: $showSetup)
        .taskCover(isPresented: $showSaveView) {
            if let model { SaveViewSheet(model: model) }
        }
    }

    private func showsControls(_ model: ScreenModel<ItemGridViewModel>) -> Bool {
        if case .empty(let e) = model.screen.state { return e.reason == .noMatches }
        return true
    }

    private func emptyAction(_ model: ScreenModel<ItemGridViewModel>) {
        if case .empty(let e) = model.screen.state, e.reason == .noMatches {
            Task { await model.run { await $0.clearFilters() } }
        } else {
            showSetup = true
        }
    }

    private func reload() async {
        if model == nil { model = ScreenModel(ItemGridViewModel.movies(store: services.store)) }
        await model?.run { await $0.load() }
        await model?.run { await $0.refreshSavedViews() }
        reviewCount = (try? await services.store.needsReviewCount()) ?? 0
    }
}
