import SwiftUI
import AppLogic

/// Shows: one poster per series, with the same row as Movies (#21 F): Sort, Filter, Saved Views, Needs Review when files
/// wait there, Jump to Letter for the title sort, and the count.
struct ShowsView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<ShowsViewModel>?
    @State private var showSetup = false
    @State private var showSaveView = false
    @State private var reviewCount = 0

    var body: some View {
        VStack(alignment: .leading) {
            if let model {
                if !showsControls(model) {
                    // An empty Shows screen still says where unsorted files are (addendum #18 C).
                    NeedsReviewButton(count: reviewCount)
                } else if model.screen.state.content == nil {
                    // "No Matches": keep the menus above the message, as on Movies, so one filter can be changed.
                    ShowsControls(model: model, targets: [], reviewCount: reviewCount, onSave: { showSaveView = true }, onJump: { _ in })
                }
                ScreenStateView(state: model.screen.state, onEmptyAction: { emptyAction(model) }, onRetry: { Task { await reload() } }) { series in
                    ShowsGrid(model: model, series: series, reviewCount: reviewCount, onSave: { showSaveView = true })
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

    /// The controls show over a loaded grid and over "No Matches"; not over "No Sources" or "Nothing Here Yet".
    private func showsControls(_ model: ScreenModel<ShowsViewModel>) -> Bool {
        switch model.screen.state {
        case .loaded: return true
        case .empty(let e): return e.reason == .noMatches
        default: return false
        }
    }

    private func emptyAction(_ model: ScreenModel<ShowsViewModel>) {
        if case .empty(let e) = model.screen.state, e.reason == .noMatches {
            Task { await model.run { await $0.clearFilters() } }
        } else {
            showSetup = true
        }
    }

    private func reload() async {
        if model == nil { model = ScreenModel(ShowsViewModel(store: services.store)) }
        await model?.run { await $0.load() }
        await model?.run { await $0.refreshSavedViews() }
        reviewCount = (try? await services.store.needsReviewCount()) ?? 0
    }
}

/// The row above the Shows grid, in the Movies order (`GridControls`), and the filter buttons under it.
private struct ShowsControls: View {
    let model: ScreenModel<ShowsViewModel>
    let targets: [JumpTarget]
    let reviewCount: Int
    var onSave: () -> Void
    var onJump: (JumpTarget) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            // #25 B2: the same one-line row as Movies, with the same More menu when it does not fit.
            // #32 D (R233): Sort, Filter and Saved Views as one group of symbols, Needs Review and Jump to Letter as the second.
            GridToolbar(count: model.screen.countText) {
                SortMenu(model: model)
                FilterMenu(model: model)
            } savedViews: {
                SavedViewsMenu(model: model, onSave: onSave)
            } tools: {
                NeedsReviewButton(count: reviewCount)
                jumpMenu
            } collapsed: {
                SavedViewsMenu(model: model, onSave: onSave)
                NeedsReviewMenuItem(count: reviewCount)
                jumpMenu
            }
            if !model.screen.chips.isEmpty {
                FilterChipsRow(model: model)
            }
        }
    }

    @ViewBuilder
    private var jumpMenu: some View {
        if !targets.isEmpty {
            AlphabetJumpMenu(letters: targets.map { AlphabetJumpEntry(letter: $0.letter, count: $0.count) }) { letter in
                if let target = targets.first(where: { $0.letter == letter }) { onJump(target) }
            }
        }
    }
}

/// The poster grid and its controls. The jump list is offered only for the title sort, where a letter is one scroll target.
private struct ShowsGrid: View {
    let model: ScreenModel<ShowsViewModel>
    let series: [SeriesSummary]
    let reviewCount: Int
    var onSave: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading) {
                ShowsControls(model: model, targets: model.screen.jumpTargets, reviewCount: reviewCount, onSave: onSave) { target in
                    proxy.scrollTo(target.firstID, anchor: .top)
                }
                PosterGridLayout {
                    ForEach(series) { show in
                        SeriesCard(series: show)
                            .id(show.id)
                    }
                }
            }
        }
    }
}
