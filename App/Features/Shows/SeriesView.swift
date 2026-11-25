import SwiftUI
import AppLogic

/// A show: the Play button, then every season with its episodes.
struct SeriesView: View {
    let seriesID: Int64
    /// R471 (31): the season to open on (an episode's Go to Season); nil opens on the next-up episode's season.
    var startSeason: Int? = nil
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<SeasonsViewModel>?

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onRetry: { Task { await reload() } }) { content in
                    SeasonsList(content: content, seriesID: seriesID, model: model, onPlay: play, startSeason: startSeason)
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { await reload() }
    }

    private func play(_ episodeID: Int64) {
        services.playRequest = PlayRequest(itemID: episodeID, fromStart: false)
    }

    private func reload() async {
        if model == nil { model = ScreenModel(SeasonsViewModel(store: services.store, seriesID: seriesID)) }
        await model?.run { await $0.load() }
    }
}
