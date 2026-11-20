import SwiftUI
import AppLogic

/// Asks for a name and saves the current sort and filters as a view. #36 S-B (OPEN_QUESTIONS R254, PROVISIONAL): the one
/// task-cover layout, `TaskPage` (left title in the bounded column), not a centred navigation title.
struct SaveViewSheet<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            TaskPage(title: "Save View") {
                Section("Name") {
                    TextField("Saved View", text: $name)
                }
                Section {
                    // #36 S-C (R255): Save prominent, Cancel beside it, the same size.
                    TaskButtonRow {
                        TaskButton("Save", prominent: true) {
                            let chosen = name
                            Task {
                                await model.run { screen in _ = try? await screen.saveCurrentView(name: chosen, pinned: false) }
                                dismiss()
                            }
                        }
                        TaskButton("Cancel", role: .cancel) { dismiss() }
                    }
                }
            }
        }
    }
}
