import SwiftUI
import AppLogic
import LibraryIndex

/// Files: every source, then its folders exactly as they are on the server.
struct FilesView: View {
    @Environment(AppServices.self) private var services
    @State private var sources: [LibrarySourceRecord]?
    @State private var showSetup = false

    var body: some View {
        Group {
            if let sources {
                if sources.isEmpty {
                    EmptyStateView(empty: HomeViewModel.noSourcesForFiles, action: { showSetup = true })
                } else {
                    List(sources, id: \.id) { source in
                        NavigationLink(value: Route.folder(sourceID: source.id, sourceName: source.name, path: "/")) {
                            RowLabel(source.name, systemImage: "externaldrive")
                        }
                    }
                }
            } else {
                LoadingView()
            }
        }
        .task(id: services.libraryRevision) { sources = (try? await services.store.sources()) ?? [] }
        .sheet(isPresented: $showSetup) { SourceSetupFlow() }
    }
}
