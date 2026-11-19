import SwiftUI
import AppLogic
import LibraryIndex
import UserData

/// Settings > Library > Needs Review (docs/SORTING.md): video files that could not be sorted into Movies or Shows. They are
/// shown nowhere else; choosing one offers Move to Movies and Move to Shows.
struct NeedsReviewView: View {
    @Environment(AppServices.self) private var services
    @State private var model: NeedsReviewViewModel?
    @State private var chosen: ReviewEntry?
    @State private var move: SortMoveTarget?

    var body: some View {
        Form {
            switch model?.state ?? .idle {
            case .idle, .loading:
                ProgressView()
            case .empty(let empty):
                Section {
                    Text(empty.title)
                    Text(empty.message)
                        .foregroundStyle(.secondary)
                }
            case .failed(let error):
                Section {
                    Text(error.title)
                    Text(error.message)
                        .foregroundStyle(.secondary)
                    Button(error.retryTitle) { Task { await reload() } }
                }
            case .loaded(let entries):
                Section {
                    ForEach(entries) { entry in
                        Button { chosen = entry } label: {
                            VStack(alignment: .leading) {
                                Text(entry.fileName)
                                Text(entry.note)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text(SortTexts.reviewFooter)
                }
            }
        }
        .navigationTitle("Needs Review")
        .task(id: services.libraryRevision) { await reload() }
        .confirmationDialog(chosen?.fileName ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { entry in
            Button("Move to Movies") { move = .review(entry, .movie) }
            Button("Move to Shows") { move = .review(entry, .episode) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.note)
        }
        .sheet(item: $move) { target in
            SortMoveSheet(target: target, onSaved: {
                if case .review(let entry, _) = target { model?.remove(entry) }
            })
        }
    }

    private func reload() async {
        var m = model ?? NeedsReviewViewModel(store: services.store)
        await m.load()
        model = m
    }
}
