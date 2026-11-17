import SwiftUI
import AppLogic

/// One folder of one source. Opening a folder pushes another of these, so Back on the remote goes up one level.
struct FilesFolderView: View {
    let sourceID: String
    let sourceName: String
    let path: String
    @Environment(AppServices.self) private var services
    @State private var model: ScreenModel<FilesBrowserViewModel>?
    @State private var selected: FileRow?

    var body: some View {
        Group {
            if let model {
                ScreenStateView(state: model.screen.state, onRetry: { Task { await reload() } }) { content in
                    List(content.rows) { row in
                        FileRowView(sourceID: sourceID, sourceName: sourceName, row: row, onSelectFile: { selected = row })
                            .onAppear {
                                if row.id == content.rows.last?.id, content.hasMore {
                                    Task { await model.run { await $0.loadMore() } }
                                }
                            }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle(path == "/" ? sourceName : (path as NSString).lastPathComponent)
        .task { await reload() }
        .sheet(item: $selected) { row in FileDetailsSheet(row: row) }
    }

    private func reload() async {
        if model == nil {
            model = ScreenModel(FilesBrowserViewModel(store: services.store, sourceID: sourceID, sourceName: sourceName, folder: path))
        }
        await model?.run { await $0.load() }
    }
}
