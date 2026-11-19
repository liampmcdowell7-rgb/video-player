import SwiftUI
import AppLogic
import LibraryIndex
import UserData

/// What a Move choice is for: a library item (every version of it) or one Needs Review file.
enum SortMoveTarget: Identifiable, Equatable {
    case item(Int64, UDSortOverrideValue.Kind)
    case review(ReviewEntry, UDSortOverrideValue.Kind)

    var id: String {
        switch self {
        case .item(let id, let kind): return "item-\(id)-\(kind.rawValue)"
        case .review(let entry, let kind): return "review-\(entry.id)-\(kind.rawValue)"
        }
    }

    var kind: UDSortOverrideValue.Kind {
        switch self {
        case .item(_, let kind), .review(_, let kind): return kind
        }
    }

    static func == (a: SortMoveTarget, b: SortMoveTarget) -> Bool { a.id == b.id }
}

/// Move to Movies / Move to Shows (docs/SORTING.md): system form fields, filled from the file name. The choice is a synced
/// user-data record, so it survives rescans and reaches the other Apple TVs; the next scan files the item. Layout:
/// `SettingsPane` (#15 L1, D1); the main action is the first button under the fields (L7).
struct SortMoveSheet: View {
    let target: SortMoveTarget
    var onSaved: () -> Void = {}
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SortMoveDraft?
    @State private var problem: String?

    var body: some View {
        SettingsPane(title: SortTexts.moveTitle(target.kind), summary: SortTexts.moveSummary(target.kind)) {
            if let binding = Binding($draft) {
                Section {
                    TextField(binding.wrappedValue.titleLabel, text: binding.title)
                    TextField("Year (Optional)", text: binding.year)
                }
                if target.kind == .episode {
                    Section("Episode") {
                        TextField("Season", text: binding.season)
                        TextField("Episode", text: binding.episode)
                        TextField("Last Episode (Optional)", text: binding.episodeEnd)
                    }
                }
                Section {
                    Button(binding.wrappedValue.sheetTitle, systemImage: target.kind == .movie ? "film" : "tv") { Task { await save() } }
                    Button("Cancel", role: .cancel) { dismiss() }
                } footer: {
                    if let problem { Text(problem) }
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        let mover = services.sortMover
        switch target {
        case .item(let id, let kind): draft = (try? await mover.draft(itemID: id, to: kind)) ?? SortMoveDraft(kind: kind, title: "")
        case .review(let entry, let kind): draft = mover.draft(for: entry, to: kind)
        }
    }

    private func save() async {
        guard let draft else { return }
        do {
            switch target {
            case .item(let id, _): try await services.sortMover.move(itemID: id, draft)
            case .review(let entry, _): try services.sortMover.move(entry, draft)
            }
            services.sortChoiceSaved()
            onSaved()
            dismiss()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? "The choice could not be saved."
        }
    }
}

/// How an item was sorted (the item info, from the detail page's More menu): the rule that decided and why, with Move and,
/// after a Move, Sort Automatically. Plain facts are `LabeledContent` and footer text, never rows that look like buttons (L3).
struct SortInfoSheet: View {
    let itemID: Int64
    let kind: ItemKind
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var info: ItemSortInfo?
    @State private var loaded = false
    @State private var move: SortMoveTarget?

    var body: some View {
        SettingsPane(title: "How This Was Sorted", summary: SortTexts.infoSummary) {
            Section {
                if let info {
                    LabeledContent("Sorted By", value: SortTexts.title(info.record.signal))
                    LabeledContent("File", value: info.fileName)
                } else if !loaded {
                    ProgressView()
                }
            } footer: {
                if let info, !info.record.note.isEmpty {
                    Text(info.record.note)
                } else if loaded && info == nil {
                    Text(SortTexts.notRecorded)
                }
            }
            Section {
                if kind == .movie {
                    Button("Move to Shows", systemImage: "tv") { move = .item(itemID, .episode) }
                } else {
                    Button("Move to Movies", systemImage: "film") { move = .item(itemID, .movie) }
                }
                if let signal = info?.record.signal, signal == .manual || signal == .onlineLookup {
                    Button("Sort Automatically", systemImage: "arrow.uturn.backward") {
                        Task {
                            try? await services.sortMover.sortAutomatically(itemID: itemID)
                            services.sortChoiceSaved()
                            dismiss()
                        }
                    }
                }
                Button("Done") { dismiss() }
            }
        }
        .task {
            info = try? await services.store.sortInfo(itemID: itemID)
            loaded = true
        }
        .sheet(item: $move) { target in
            SortMoveSheet(target: target, onSaved: { dismiss() })
        }
    }
}
