import SwiftUI
import AppLogic

/// Asks for a name and saves the current sort and filters as a view.
struct SaveViewSheet<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Saved View", text: $name)
                }
                Section {
                    Button("Save") {
                        let chosen = name
                        Task {
                            await model.run { screen in _ = try? await screen.saveCurrentView(name: chosen, pinned: false) }
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle("Save View") // design-lint:allow sheet root: the title is the sheet's own heading, not a pushed page (rule D1 is for pushed pages)
        }
    }
}
