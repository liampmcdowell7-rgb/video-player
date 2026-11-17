import SwiftUI
import AppLogic
import LibraryIndex

struct SortMenu: View {
    let model: ScreenModel<ItemGridViewModel>

    var body: some View {
        Menu("Sort", systemImage: "arrow.up.arrow.down") {
            Picker("Sort By", selection: key) {
                ForEach(SortChoice.all) { choice in
                    Text(choice.title).tag(choice.key)
                }
            }
            Button(model.screen.query.sort.ascending ? "Show Largest First" : "Show Smallest First", systemImage: "arrow.up.arrow.down") {
                let current = model.screen.query.sort.key
                Task { await model.run { await $0.chooseSort(current) } }
            }
        }
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
