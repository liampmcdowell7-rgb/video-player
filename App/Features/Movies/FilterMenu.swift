import SwiftUI
import AppLogic
import LibraryIndex

/// Filters for Movies and Shows. Options of one group combine with "or", groups with "and" (the library's rule).
///
/// #32 C (OPEN_QUESTIONS R235, PROVISIONAL): the old menu listed all 16 options in four sections, so it ran off the bottom of
/// the screen at the default size and more so at Larger Text (07-shows-toolbar-filter-menu). Now the menu has one submenu
/// per group (Watched, Resolution, Dynamic Range, Sound; at most five options each) and one "Clear All Filters" item:
/// - HIG Menus: "If a menu is too long, consider dividing it into separate menus"; submenus "restrict them to a single
///   level" and "if a submenu contains more than about five items, consider creating a new menu".
/// - Each option is a `Toggle`, which "in a menu automatically appears with a checkmark indicating its on or off state"
///   (Apple, "Populating SwiftUI menus with adaptive controls").
/// - "Consider offering a menu item that makes it easy to remove multiple toggled attributes" (HIG Menus): Clear All
///   Filters, always listed and unavailable when nothing is on ("Show people when a menu item is unavailable").
/// - No item has a symbol, so no group mixes items with and without symbols.
/// - The button shows that filters are on: the filled filter symbol, and the count of active filters in its spoken value.
///   No Apple page found says how to show an active filter (R235 alternatives).
struct FilterMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>

    var body: some View {
        Menu {
            // The groups live in AppLogic (`FilterGroup.library`), shared with Shows.
            ForEach(model.screen.filterGroups) { group in
                Menu(groupTitle(group)) {
                    ForEach(group.options, id: \.self) { option in
                        Toggle(option.title, isOn: binding(for: option))
                    }
                }
            }
            Divider()
            Button("Clear All Filters", role: .destructive) {
                Task { await model.run { await $0.clearFilters() } }
            }
            .disabled(!model.screen.isFiltered)
        } label: {
            ToolbarSymbol("Filter", systemImage: model.screen.isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(spokenState)
        .accessibilityIdentifier(ControlID.filter)
    }

    /// "Resolution" or, with options on, "Resolution (2)", so the open menu shows where the active filters are.
    private func groupTitle(_ group: FilterGroup) -> String {
        let on: Int = group.options.filter { (option: FilterOption) -> Bool in option.isOn(in: model.screen.query.filter) }.count
        guard on > 0 else { return group.title }
        return "\(group.title) (\(on))"
    }

    /// "Off", "1 filter on", "3 filters on" (typed steps).
    private var spokenState: String {
        let count: Int = model.screen.chips.count
        if !model.screen.isFiltered || count == 0 { return "Off" }
        if count == 1 { return "1 filter on" }
        return "\(count) filters on"
    }

    private func binding(for option: FilterOption) -> Binding<Bool> {
        Binding(
            get: { option.isOn(in: model.screen.query.filter) },
            set: { _ in Task { await model.run { await $0.toggle(option) } } })
    }
}
