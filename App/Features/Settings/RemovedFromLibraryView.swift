import SwiftUI
import AppLogic
import UserData

/// R471 (15), PROVISIONAL: Settings > Library > Removed from Library. The titles the user deleted from the library (Delete
/// from Library on a page or a card), newest first. Choosing one asks, then brings it back: the record goes and the next scan
/// adds the file again (it never left the source). Layout: `SettingsPane`, system rows only; a long name wraps (L7).
struct RemovedFromLibraryView: View {
    @Environment(AppServices.self) private var services
    @State private var removals: [UDLibraryRemoval] = []
    @State private var chosen: UDLibraryRemoval?

    var body: some View {
        SettingsPane(title: "Removed from Library", summary: LibraryRemovalTexts.summary) {
            if removals.isEmpty {
                Section {
                    Text(LibraryRemovalTexts.emptyTitle)
                } footer: {
                    Text(LibraryRemovalTexts.emptyMessage)
                }
            } else {
                Section {
                    ForEach(removals, id: \.self) { removal in
                        Button { chosen = removal } label: {
                            VStack(alignment: .leading) {
                                Text(removal.title)
                                Text(LibraryRemovalTexts.fileName(removal.path))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text(LibraryRemovalTexts.footer)
                }
            }
        }
        .task(id: services.libraryRevision) { removals = services.ledger.libraryRemovals() }
        .confirmationDialog(chosen?.title ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { removal in
            Button(LibraryRemovalTexts.restore) { Task { await services.restoreToLibrary(removal) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(LibraryRemovalTexts.restoreMessage)
        }
    }
}
