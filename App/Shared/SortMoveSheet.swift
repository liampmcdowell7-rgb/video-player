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

/// Move to Movies / Move to Shows (docs/SORTING.md): one value row per field (R333), filled from the file name. The choice is a synced
/// user-data record, so it survives rescans and reaches the other Apple TVs; the next scan files the item. Layout:
/// `TaskPage`, the one task-cover layout (#36 S-B, OPEN_QUESTIONS R254, PROVISIONAL; it was `SettingsPane`'s two columns);
/// the main action is the first button under the fields (L7).
struct SortMoveSheet: View {
    let target: SortMoveTarget
    var onSaved: () -> Void = {}
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SortMoveDraft?
    @State private var problem: String?

    var body: some View {
        // R333: the field rows open entry pages, so the cover has its own navigation stack (as Add a Source); `TaskPage`
        // hides the navigation bar.
        NavigationStack {
            TaskPage(title: SortTexts.moveTitle(target.kind), summary: SortTexts.moveSummary(target.kind)) {
                if let binding = Binding($draft) {
                    // R333 (PROVISIONAL): each field is one tvOS Settings value row; Select opens its entry page with the
                    // right keyboard (`TextEntryRow`). Before: `FieldRow`, a field inside the row platter (R256).
                    let fields: [TextEntryRules.MoveField] = TextEntryRules.moveFields(target.kind)
                    Section {
                        ForEach(fields.filter { $0 == .title || $0 == .year }, id: \.self) { row($0, binding) }
                    } footer: {
                        if target.kind == .movie { Text(TextEntryRules.moveOptionalLine(target.kind)) }
                    }
                    if target.kind == .episode {
                        Section {
                            ForEach(fields.filter { $0 != .title && $0 != .year }, id: \.self) { row($0, binding) }
                        } header: {
                            Text("Episode")
                        } footer: {
                            Text(TextEntryRules.moveOptionalLine(target.kind))
                        }
                    }
                    Section {
                        // #36 S-C (R255): the Move button prominent, Cancel beside it, the same size.
                        TaskButtonRow {
                            TaskButton(binding.wrappedValue.sheetTitle, prominent: true) { Task { await save() } }
                            TaskButton("Cancel", role: .cancel) { dismiss() }
                        }
                    } footer: {
                        if let problem { Text(problem) }
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task { await load() }
    }

    /// R333: one field as a value row; the name is the row title and the entry page heading ("Optional" is in the footer).
    private func row(_ field: TextEntryRules.MoveField, _ draft: Binding<SortMoveDraft>) -> some View {
        let title: String = TextEntryRules.moveTitle(field, kind: target.kind)
        return TextEntryRow(title: title, value: draft[dynamicMember: Self.path(field)], entry: TextEntryRules.moveEntry(field),
                            summary: TextEntryRules.summary(title), identifier: ControlID.moveField(field.rawValue))
    }

    private static func path(_ field: TextEntryRules.MoveField) -> WritableKeyPath<SortMoveDraft, String> {
        switch field {
        case .title: return \.title
        case .year: return \.year
        case .season: return \.season
        case .episode: return \.episode
        case .episodeEnd: return \.episodeEnd
        }
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
        // #36 S-B (R254): `TaskPage`, as every task cover. R410 (run #25, 67-sorted-how-COVER: "PAGE BEHIND THE COVER IS
        // EXPOSED"): inside its own navigation stack, as every other task cover (Fix Match, Move, Save View, File Details,
        // Add a Source). This was the one TaskPage cover whose page sat directly in the presentation, and the one whose
        // page behind stayed in the accessibility tree; why the stack makes that difference is not on any Apple page read
        // (UNVERIFIED).
        NavigationStack {
            TaskPage(title: "How This Was Sorted", summary: SortTexts.infoSummary) {
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
                    // #36 S-C (R255): one row of bezeled buttons, the same size; Done (closing the information) is the most
                    // likely action, so it is the prominent one; Move and Sort Automatically are bordered.
                    TaskButtonRow {
                        if kind == .movie {
                            TaskButton("Move to Shows") { move = .item(itemID, .episode) }
                        } else {
                            TaskButton("Move to Movies") { move = .item(itemID, .movie) }
                        }
                        if let signal = info?.record.signal, signal == .manual || signal == .onlineLookup {
                            TaskButton("Sort Automatically") {
                                Task {
                                    try? await services.sortMover.sortAutomatically(itemID: itemID)
                                    services.sortChoiceSaved()
                                    dismiss()
                                }
                            }
                        }
                        TaskButton("Done", prominent: true) { dismiss() }
                    }
                }
            }
        }
        .task {
            info = try? await services.store.sortInfo(itemID: itemID)
            loaded = true
        }
        .taskCover(item: $move) { target in
            SortMoveSheet(target: target, onSaved: { dismiss() })
        }
    }
}
