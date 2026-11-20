import SwiftUI
import AppLogic
import LibraryIndex

/// Saved Views for Movies and Shows (#32 A, OPEN_QUESTIONS R236, PROVISIONAL).
/// - No saved view: a plain button that saves the current view. The old menu then held one item ("Save Current View");
///   HIG Pull-down buttons: "listing a minimum of three items can help the interaction feel worthwhile. If you need to list
///   only one or two items, consider using alternative components."
/// - One or more saved views: a menu of at least three items (the views, Save Current View, Delete a Saved View). The views
///   are an inline picker, so the view now shown carries the system checkmark ("The selected item, identified with a
///   checkmark, indicates the current selection"); none is checked when the grid matches no saved view. A long list of
///   views is acceptable: HIG Menus allows a long, scrolling menu for "user-defined or dynamically generated content".
/// Both forms keep the identifier `ControlID.savedViews`.
struct SavedViewsMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>
    var onSave: () -> Void

    var body: some View {
        if model.screen.savedViews.isEmpty {
            Button(action: onSave) {
                ToolbarSymbol("Save View", systemImage: "bookmark")
            }
            .accessibilityLabel("Save View")
            .accessibilityIdentifier(ControlID.savedViews)
        } else {
            Menu {
                Picker("Saved Views", selection: shown) {
                    ForEach(model.screen.savedViews) { view in
                        Text(view.name).tag(Optional(view.id))
                    }
                }
                .pickerStyle(.inline)
                Section {
                    Button("Save Current View", systemImage: "plus", action: onSave)
                    Menu("Delete a Saved View", systemImage: "trash") {
                        ForEach(model.screen.savedViews) { view in
                            Button(view.name, role: .destructive) {
                                Task { await model.run { await $0.deleteView(id: view.id) } }
                            }
                        }
                    }
                }
            } label: {
                ToolbarSymbol("Saved Views", systemImage: "bookmark")
            }
            .accessibilityLabel("Saved Views")
            .accessibilityValue(shownName)
            .accessibilityIdentifier(ControlID.savedViews)
        }
    }

    /// The saved view whose filter and order the grid shows now, if any.
    private var current: SavedView? {
        model.screen.savedViews.first { (view: SavedView) -> Bool in view.query == model.screen.query }
    }

    private var shownName: String { current?.name ?? "None shown" }

    private var shown: Binding<Int64?> {
        Binding(
            get: { current?.id },
            set: { (id: Int64?) in
                guard let id, id != current?.id, let view = model.screen.savedViews.first(where: { $0.id == id }) else { return }
                Task { await model.run { await $0.apply(view) } }
            })
    }
}
