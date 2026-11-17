import SwiftUI
import AppLogic

/// Shows: one poster per series, with a letter jump list.
struct ShowsView: View {
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<ShowsViewModel>?
    @State private var showSetup = false

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onEmptyAction: { showSetup = true }, onRetry: { Task { await reload() } }) { series in
                    ShowsGrid(series: series)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Shows")
        .task(id: services.libraryRevision) { await reload() }
        .sheet(isPresented: $showSetup) { SourceSetupFlow() }
    }

    private func reload() async {
        if model == nil { model = ScreenModel(ShowsViewModel(store: services.store)) }
        await model?.run { await $0.load() }
    }
}

/// The poster grid and its jump menu. The shows are sorted by the same title key the letters use, so a letter is one scroll target.
private struct ShowsGrid: View {
    let series: [SeriesSummary]

    var body: some View {
        let targets = AlphabetJump.targets(for: series)
        ScrollViewReader { proxy in
            VStack(alignment: .leading) {
                if !targets.isEmpty {
                    AlphabetJumpMenu(letters: targets.map { AlphabetJumpEntry(letter: $0.letter, count: $0.count) }) { letter in
                        if let target = targets.first(where: { $0.letter == letter }) {
                            proxy.scrollTo(target.firstID, anchor: .top)
                        }
                    }
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
