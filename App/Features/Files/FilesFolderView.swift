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
                    // #15 7.1: the folder name visible on the left (D1: the navigation bar stays hidden) with where it is,
                    // and the rows in a bounded column (L1, L2).
                    PaneColumns(title: title, summary: content.breadcrumb.joined(separator: " › ")) {
                        List(content.rows) { row in
                            FileRowView(sourceID: sourceID, sourceName: sourceName, row: row, onSelectFile: { selected = row })
                                .onAppear {
                                    if row.id == content.rows.last?.id, content.hasMore {
                                        Task { await model.run { await $0.loadMore() } }
                                    }
                                }
                        }
                        // R345: the focused row grows past the list's edge; the list must not clip it (72, 73).
                        .scrollClipDisabled()
                        // R363 (item 11): the Files pages browse a hierarchy, so their lists are plain, said here rather
                        // than left to the platform's automatic style (Settings pages are grouped; D-DS11, D-DS13).
                        .listStyle(.plain)
                    }
                }
            } else {
                LoadingView()
            }
        }
        .pushedScreen(title)
        .task { await reload() }
        .taskCover(item: $selected) { row in FileDetailsSheet(row: row) }
    }

    private var title: String { path == "/" ? sourceName : (path as NSString).lastPathComponent }

    private func reload() async {
        if model == nil {
            model = ScreenModel(FilesBrowserViewModel(store: services.store, sourceID: sourceID, sourceName: sourceName, folder: path))
        }
        await model?.run { await $0.load() }
    }
}
