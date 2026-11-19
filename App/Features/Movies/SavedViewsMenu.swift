import SwiftUI
import AppLogic
import LibraryIndex

struct SavedViewsMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>
    var onSave: () -> Void

    var body: some View {
        Menu("Saved Views", systemImage: "bookmark") {
            ForEach(model.screen.savedViews) { view in
                Button(view.name) {
                    Task { await model.run { await $0.apply(view) } }
                }
            }
            if !model.screen.savedViews.isEmpty {
                Divider()
            }
            Button("Save Current View", systemImage: "plus", action: onSave)
            if !model.screen.savedViews.isEmpty {
                Menu("Delete a Saved View", systemImage: "trash") {
                    ForEach(model.screen.savedViews) { view in
                        Button(view.name, role: .destructive) {
                            Task { await model.run { await $0.deleteView(id: view.id) } }
                        }
                    }
                }
            }
        }
    }
}
