import SwiftUI
import AppLogic

/// Shows: one poster per series, with a letter jump list and, when files wait there, the way to Needs Review.
struct ShowsView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<ShowsViewModel>?
    @State private var showSetup = false
    @State private var reviewCount = 0

    var body: some View {
        VStack(alignment: .leading) {
            if let model {
                if model.screen.state.content == nil {
                    // An empty Shows screen still says where unsorted files are (addendum #18 C).
                    NeedsReviewButton(count: reviewCount)
                }
                ScreenStateView(state: model.screen.state, onEmptyAction: { showSetup = true }, onRetry: { Task { await reload() } }) { series in
                    ShowsGrid(series: series, reviewCount: reviewCount)
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { await reload() }
        .sheet(isPresented: $showSetup) { SourceSetupFlow() }
    }

    private func reload() async {
        if model == nil { model = ScreenModel(ShowsViewModel(store: services.store)) }
        await model?.run { await $0.load() }
        reviewCount = (try? await services.store.needsReviewCount()) ?? 0
    }
}

/// The poster grid and its jump menu. The shows are sorted by the same title key the letters use, so a letter is one scroll target.
private struct ShowsGrid: View {
    let series: [SeriesSummary]
    let reviewCount: Int

    var body: some View {
        let targets = AlphabetJump.targets(for: series)
        ScrollViewReader { proxy in
            VStack(alignment: .leading) {
                HStack {
                    if !targets.isEmpty {
                        AlphabetJumpMenu(letters: targets.map { AlphabetJumpEntry(letter: $0.letter, count: $0.count) }) { letter in
                            if let target = targets.first(where: { $0.letter == letter }) {
                                proxy.scrollTo(target.firstID, anchor: .top)
                            }
                        }
                    }
                    NeedsReviewButton(count: reviewCount)
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
