import SwiftUI
import AppLogic

/// A show: the Play button, then every season with its episodes.
struct SeriesView: View {
    let seriesID: Int64
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<SeasonsViewModel>?

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onRetry: { Task { await reload() } }) { content in
                    SeasonsList(content: content, model: model, onPlay: play)
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
