import SwiftUI
import AppLogic
import LibraryIndex

struct SortMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>

    var body: some View {
        Menu {
            Picker("Sort By", selection: key) {
                ForEach(model.screen.sortChoices) { choice in
                    Text(choice.title).tag(choice.key)
                }
            }
            Button(model.screen.query.sort.ascending ? "Show Largest First" : "Show Smallest First", systemImage: "arrow.up.arrow.down") {
                let current = model.screen.query.sort.key
                Task { await model.run { await $0.chooseSort(current) } }
            }
        } label: {
            // #25 B2: the system label, one height with the other controls of the row (GridToolbar).
            ActionLabel("Sort", systemImage: "arrow.up.arrow.down")
        }
        // #25 A2: named once on the control; VoiceOver hears "Sort".
        .accessibilityLabel("Sort")
        .accessibilityIdentifier(ControlID.sort)
    }

    private var key: Binding<ItemSortKey> {
        Binding(
            get: { model.screen.query.sort.key },
            set: { newKey in
                guard newKey != model.screen.query.sort.key else { return }
                Task { await model.run { await $0.chooseSort(newKey) } }
            })
    }
}
