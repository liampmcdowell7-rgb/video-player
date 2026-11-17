import SwiftUI
import AppLogic

/// Asks for a name and saves the current sort and filters as a view.
struct SaveViewSheet: View {
    let model: ScreenModel<ItemGridViewModel>
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
                            await model.run { screen in _ = try? await screen.saveCurrentView(name: chosen) }
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .navigationTitle("Save View")
        }
    }
}
