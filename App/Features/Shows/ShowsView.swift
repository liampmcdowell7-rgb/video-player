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
    /// R375: the first show of the letter picked in the toolbar's Jump to Letter; the grid scrolls to it and clears it.
    @State private var jumpTo: Int64?

    var body: some View {
        VStack(alignment: .leading) {
            if let model {
                if !showsControls(model) {
                    // An empty Shows screen still says where unsorted files are (addendum #18 C).
                    NeedsReviewButton(count: reviewCount)
                } else {
                    // R375: the controls are the system toolbar (below), also over "No Matches" so one filter can be
                    // changed; only the count stays above the grid.
                    GridCountLine(count: model.screen.countText)
                }
                ScreenStateView(state: model.screen.state, onEmptyAction: { emptyAction(model) }, onRetry: { Task { await reload() } }) { series in
                    ShowsGrid(series: series, jumpTo: $jumpTo)
                }
            } else {
                LoadingView()
            }
        }
        .modifier(ShowsToolbar(model: model, shown: model.map(showsControls) ?? false, reviewCount: reviewCount,
                               onSave: { showSaveView = true }, onJump: { jumpTo = $0.firstID }))
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
        if model == nil { model = ScreenModel(ShowsViewModel(store: services.store, sort: LibrarySortDefault.stored(UserDefaults.standard.string(forKey: AppPreference.sortOrder.rawValue)).itemSort)) }
        await model?.run { await $0.load() }
        await model?.run { await $0.refreshSavedViews() }
        reviewCount = (try? await services.store.needsReviewCount()) ?? 0
    }
}

/// R375: the Shows controls as the system toolbar, in the Movies order (`MoviesToolbar`).
private struct ShowsToolbar: ViewModifier {
    let model: ScreenModel<ShowsViewModel>?
    let shown: Bool
    let reviewCount: Int
    var onSave: () -> Void
    var onJump: (JumpTarget) -> Void

    func body(content: Content) -> some View {
        let targets: [JumpTarget] = model?.screen.jumpTargets ?? []
        return content.libraryToolbar(shown: shown && model != nil, hasMore: reviewCount > 0 || !targets.isEmpty) {
            if let model { SortFilterMenu(model: model) }
        } savedViews: {
            if let model { SavedViewsMenu(model: model, onSave: onSave) }
        } more: {
            NeedsReviewMenuItem(count: reviewCount)
            if !targets.isEmpty {
                AlphabetJumpMenu(letters: targets.map { AlphabetJumpEntry(letter: $0.letter, count: $0.count) }) { letter in
                    if let target = targets.first(where: { $0.letter == letter }) { onJump(target) }
                }
            }
        }
    }
}

/// The poster grid. The jump list is offered only for the title sort, where a letter is one scroll target; R375: the
/// letter comes from the toolbar's More menu (`jumpTo`).
private struct ShowsGrid: View {
    let series: [SeriesSummary]
    @Binding var jumpTo: Int64?

    var body: some View {
        ScrollViewReader { proxy in
            PosterGridLayout {
                ForEach(series) { show in
                    SeriesCard(series: show)
                        .id(show.id)
                }
            }
            .onChange(of: jumpTo) { _, target in
                guard let target else { return }
                proxy.scrollTo(target, anchor: .top)
                jumpTo = nil
            }
        }
    }
}
