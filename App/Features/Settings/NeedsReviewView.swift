import SwiftUI
import AppLogic
import LibraryIndex
import UserData

/// Needs Review (docs/SORTING.md): video files that could not be sorted into Movies or Shows. Reached from Settings > Library
/// and from the "Needs Review (N)" button in Movies and Shows. Choosing a file offers Move to Movies and Move to Shows.
/// Layout: `SettingsPane` (#15 L1, D1); system rows only; the file name may wrap (a long name is never cut, L7).
struct NeedsReviewView: View {
    @Environment(AppServices.self) private var services
    @State private var model: NeedsReviewViewModel?
    @State private var chosen: ReviewEntry?
    @State private var move: SortMoveTarget?

    var body: some View {
        SettingsPane(title: "Needs Review", summary: SortTexts.reviewSummary) {
            // While a scan (and the one-time re-sort in it) runs, the list may still change (addendum #18 F).
            if services.scanProgress != nil {
                Section { ScanProgressRow(progress: services.scanProgress) }
            }
            switch model?.state ?? .idle {
            case .idle, .loading:
                ProgressView()
            case .empty(let empty):
                Section {
                    Text(empty.title)
                } footer: {
                    Text(empty.message)
                }
            case .failed(let error):
                Section {
                    Button(error.retryTitle, systemImage: "arrow.clockwise") { Task { await reload() } }
                } header: {
                    Text(error.title)
                } footer: {
                    Text(error.message)
                }
            case .loaded(let entries):
                // #25 B9: a reason shared by every row is said once, in the footer; different reasons stay on their rows.
                let shared = SortTexts.sharedReason(entries.map(\.note))
                Section {
                    ForEach(entries) { entry in
                        Button { chosen = entry } label: {
                            VStack(alignment: .leading) {
                                Text(entry.fileName)
                                if shared == nil {
                                    Text(entry.note)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(SortTexts.reviewFooter(sharedReason: shared))
                }
            }
        }
        .task(id: services.libraryRevision) { await reload() }
        .confirmationDialog(chosen?.fileName ?? "", isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
                            titleVisibility: .visible, presenting: chosen) { entry in
            Button("Move to Movies") { move = .review(entry, .movie) }
            Button("Move to Shows") { move = .review(entry, .episode) }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(entry.note)
        }
        .taskCover(item: $move) { target in
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

/// "Needs Review (N)" in the Movies and Shows controls (addendum #18 C, PROVISIONAL, OPEN_QUESTIONS R173): shown only when N
/// is above 0, a system button next to Sort and Filter, so unsorted files never look missing. A way to the Needs Review page,
/// never unsorted items inside the library screens (library-only rule).
struct NeedsReviewButton: View {
    let count: Int

    var body: some View {
        if count > 0 {
            NavigationLink(value: Route.needsReview) {
                ActionLabel(SortTexts.reviewButton(count), systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier(ControlID.needsReview)
        }
    }
}

/// #25 B2: Needs Review as an item of the toolbar's More menu (a menu cannot hold a NavigationLink): it opens the same page
/// on the tab in use through the app's open request.
struct NeedsReviewMenuItem: View {
    let count: Int
    @Environment(AppServices.self) private var services

    var body: some View {
        if count > 0 {
            Button(SortTexts.reviewButton(count), systemImage: "questionmark.circle") {
                services.openRequest = .needsReview
            }
            .accessibilityIdentifier(ControlID.needsReview)
        }
    }
}
