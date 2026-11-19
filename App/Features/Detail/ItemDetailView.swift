import SwiftUI
import AppLogic

/// A movie or an episode: facts, Play, versions, extras and the less common actions.
struct ItemDetailView: View {
    let itemID: Int64
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<ItemDetailViewModel>?
    @State private var showFixMatch = false
    @State private var showSortInfo = false

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onRetry: { Task { await reload() } }) { content in
                    ItemDetailContentView(content: content, model: model, onPlay: play, onFixMatch: { showFixMatch = true },
                                          onSortInfo: { showSortInfo = true })
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { await reload() }
        .sheet(isPresented: $showFixMatch) {
            if let content = model?.screen.state.content {
                FixMatchView(itemID: itemID, kind: content.kind, currentTitle: content.title)
            }
        }
        .sheet(isPresented: $showSortInfo) {
            if let content = model?.screen.state.content {
                SortInfoSheet(itemID: itemID, kind: content.kind)
            }
        }
    }

    private func play(fromStart: Bool) {
        services.playRequest = PlayRequest(itemID: itemID, fromStart: fromStart)
    }

    private func reload() async {
        if model == nil {
            model = ScreenModel(ItemDetailViewModel(store: services.store, itemID: itemID, trackReader: services.trackDetailsReader))
        }
        await model?.run { await $0.load() }
        // #21 C: the frame rate and every audio and subtitle track, read from the file's header once and then kept.
        await model?.run { await $0.loadTrackDetails() }
    }
}
