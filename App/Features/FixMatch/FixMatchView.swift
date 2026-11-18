import SwiftUI
import AppLogic
import LibraryIndex

/// Fix Match: search again and pick the right title when the automatic match is wrong. For an episode the choice can apply to
/// this file, this season or the whole show. Needs the user's own key; without one it says so and sends nothing.
struct FixMatchView: View {
    let itemID: Int64
    let kind: ItemKind
    let currentTitle: String
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScreenModel<FixMatchViewModel>?
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                if services.online.hasCatalogueKey {
                    Section("Title") {
                        TextField("Title", text: $text)
                            .onSubmit { Task { await search() } }
                        Button("Search") { Task { await search() } }
                    }
                    if let model, model.screen.scopeChoices.count > 1 {
                        Section("Applies To") {
                            Picker("Applies To", selection: scopeBinding(model)) {
                                ForEach(model.screen.scopeChoices, id: \.self) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                        }
                    }
                    Section("Matches") {
                        results
                    }
                } else {
                    Section {
                        Text(OnlineLookupText.fixMatchNeedsKey)
                    }
                }
                Button("Cancel", role: .cancel) { dismiss() }
            }
            .navigationTitle("Fix Match")
        }
        .onAppear {
            if text.isEmpty { text = currentTitle }
            ensureModel()
        }
        .onChange(of: services.online.keyRevision) { model = nil; ensureModel() }
    }

    private func scopeBinding(_ model: ScreenModel<FixMatchViewModel>) -> Binding<FixMatchScope> {
        Binding(get: { model.screen.scope }, set: { choice in Task { await model.run { $0.setScope(choice) } } })
    }

    private func ensureModel() {
        if model == nil {
            model = ScreenModel(FixMatchViewModel(store: services.store, searcher: services.online.searcher, itemID: itemID, kind: kind,
                                                  currentTitle: currentTitle, recorder: services.online.recorder))
        }
    }

    @ViewBuilder
    private var results: some View {
        if let model {
            switch model.screen.state {
            case .idle:
                Text("Enter the title and choose Search.")
                    .foregroundStyle(.secondary)
            case .loading:
                ProgressView()
            case .empty(let empty):
                Text(empty.message)
                    .foregroundStyle(.secondary)
            case .failed(let error):
                Text(error.message)
                    .foregroundStyle(.secondary)
            case .loaded(let candidates):
                ForEach(candidates) { candidate in
                    Button {
                        Task { await choose(candidate) }
                    } label: {
                        VStack(alignment: .leading) {
                            FittingText(candidate.title)
                            if !candidate.subtitle.isEmpty {
                                Text(candidate.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } else {
            Text("Enter the title and choose Search.")
                .foregroundStyle(.secondary)
        }
    }

    private func search() async {
        ensureModel()
        let typed = text
        await model?.run { await $0.search(typed) }
    }

    private func choose(_ candidate: MatchCandidate) async {
        await model?.run { await $0.choose(candidate) }
        if model?.screen.applied == true {
            services.libraryRevision += 1
            dismiss()
        }
    }
}
