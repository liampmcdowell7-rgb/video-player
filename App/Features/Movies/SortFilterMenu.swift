import SwiftUI
import AppLogic
import LibraryIndex

/// R344 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T5): sort and filters together in ONE system menu in the
/// Movies and Shows toolbar row, in place of the separate Sort and Filter menus and the row of filter chips under them
/// (the TV app has no chips). An active filter is shown by the filled symbol, the count in the group's title
/// ("Resolution (2)") and the checkmark of its toggle; it is removed in the menu or with Clear All Filters.
///
/// The menu's first level has six items, so it fits the screen at Larger Text (R235's reason for submenus):
/// - "Sort By (Title, A to Z)": a submenu with the two inline pickers of #32 B (R234): the key and the direction, each with
///   the system checkmark ("The selected item, identified with a checkmark, indicates the current selection"; "By default,
///   picker options in menus appear inline": Apple, "Populating SwiftUI menus with adaptive controls").
/// - one submenu per filter group (#32 C, R235; HIG Menus: submenus "restrict them to a single level"; "if a submenu
///   contains more than about five items, consider creating a new menu"), each option a `Toggle` ("in a menu automatically
///   appears with a checkmark indicating its on or off state").
/// - "Clear All Filters", always listed and unavailable when nothing is on (HIG Menus: "Consider offering a menu item that
///   makes it easy to remove multiple toggled attributes"; "Show people when a menu item is unavailable").
/// The look of the combined menu on tvOS 27 is UNVERIFIED.
struct SortFilterMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>

    var body: some View {
        Menu {
            Menu(SortFilterText.sortTitle(order: spokenOrder)) {
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
            }
            Divider()
            // The groups live in AppLogic (`FilterGroup.library`), shared with Shows.
            ForEach(model.screen.filterGroups) { group in
                Menu(groupTitle(group)) {
                    ForEach(group.options, id: \.self) { option in
                        Toggle(option.title, isOn: binding(for: option))
                    }
                }
            }
            Divider()
            Button(SortFilterText.clearAll, role: .destructive) {
                Task { await model.run { await $0.clearFilters() } }
            }
            .disabled(!model.screen.isFiltered)
        } label: {
            // #32 D (R233): a symbol-only view control; VoiceOver speaks its name (accessibilityLabel below). R375: HIG Toolbars,
            // "Prefer system-provided symbols without borders" (the circled form is gone); whether filters are on is spoken
            // (accessibilityValue) and shown by the checked items and the enabled Clear All Filters in the menu.
            ToolbarSymbol(SortFilterText.title, systemImage: "line.3.horizontal.decrease")
        }
        // #25 A2: named once on the control; VoiceOver hears the order and how many filters are on.
        .accessibilityLabel(SortFilterText.title)
        .accessibilityValue(SortFilterText.spokenValue(order: spokenOrder, filtersOn: filtersOn))
        .accessibilityIdentifier(ControlID.sortAndFilter)
    }

    /// "Title, A to Z": the key and the direction in the menu's own words (typed steps).
    private var spokenOrder: String {
        let sort: ItemSort = model.screen.query.sort
        let name: String = model.screen.sortChoices.first { $0.key == sort.key }?.title ?? sort.key.rawValue
        return name + ", " + SortChoice.directionTitle(for: sort.key, ascending: sort.ascending)
    }

    private var filtersOn: Int { model.screen.isFiltered ? model.screen.chips.count : 0 }

    /// "Resolution" or, with options on, "Resolution (2)", so the open menu shows where the active filters are.
    private func groupTitle(_ group: FilterGroup) -> String {
        let on: Int = group.options.filter { (option: FilterOption) -> Bool in option.isOn(in: model.screen.query.filter) }.count
        guard on > 0 else { return group.title }
        return "\(group.title) (\(on))"
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

    private func binding(for option: FilterOption) -> Binding<Bool> {
        Binding(
            get: { option.isOn(in: model.screen.query.filter) },
            set: { _ in Task { await model.run { await $0.toggle(option) } } })
    }
}
