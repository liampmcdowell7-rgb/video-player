import SwiftUI
import AppLogic
import LibraryIndex

/// Sort for Movies and Shows (#32 B, OPEN_QUESTIONS R234, PROVISIONAL): two inline pickers in one menu, so the system draws a
/// checkmark on the current key AND on the current direction ("The selected item, identified with a checkmark, indicates
/// the current selection"; "By default, picker options in menus appear inline": Apple, "Populating SwiftUI menus with
/// adaptive controls"). The direction words follow the key (A to Z, Newest First, Longest First: `SortChoice.directionTitles`),
/// instead of one "Show Largest First" button for every key. Files has no sort menu (its folders list by name).
struct SortMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>

    var body: some View {
        Menu {
            Picker("Sort By", selection: key) {
                ForEach(model.screen.sortChoices) { choice in
                    Text(choice.title).tag(choice.key)
                }
            }
            .pickerStyle(.inline)
            Picker("Order", selection: ascending) {
                Text(SortChoice.directionTitle(for: model.screen.query.sort.key, ascending: true)).tag(true)
                Text(SortChoice.directionTitle(for: model.screen.query.sort.key, ascending: false)).tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            // #32 D (R233): a symbol-only view control; VoiceOver speaks its name (accessibilityLabel below).
            ToolbarSymbol("Sort", systemImage: "arrow.up.arrow.down")
        }
        // #25 A2: named once on the control; VoiceOver hears "Sort" and the current order.
        .accessibilityLabel("Sort")
        .accessibilityValue(spokenOrder)
        .accessibilityIdentifier(ControlID.sort)
    }

    /// "Title, A to Z": the key and the direction in the menu's own words (typed steps).
    private var spokenOrder: String {
        let sort: ItemSort = model.screen.query.sort
        let name: String = model.screen.sortChoices.first { $0.key == sort.key }?.title ?? sort.key.rawValue
        return name + ", " + SortChoice.directionTitle(for: sort.key, ascending: sort.ascending)
    }

    private var key: Binding<ItemSortKey> {
        Binding(
            get: { model.screen.query.sort.key },
            set: { newKey in
                guard newKey != model.screen.query.sort.key else { return }
                Task { await model.run { await $0.chooseSort(newKey) } }
            })
    }

    /// Choosing the other direction repeats the current key, which flips it (the screen's rule).
    private var ascending: Binding<Bool> {
        Binding(
            get: { model.screen.query.sort.ascending },
            set: { wanted in
                guard wanted != model.screen.query.sort.ascending else { return }
                let current = model.screen.query.sort.key
                Task { await model.run { await $0.chooseSort(current) } }
            })
    }
}
