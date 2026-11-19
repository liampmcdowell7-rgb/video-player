import SwiftUI
import AppLogic
import LibraryIndex

/// Filters as toggles in a menu. Options of one group combine with "or", groups with "and" (the library's rule).
struct FilterMenu<Screen: QueryGridScreen>: View {
    let model: ScreenModel<Screen>

    var body: some View {
        Menu {
            // The groups (Watched, Resolution, Dynamic Range, Sound) live in AppLogic (`FilterGroup.library`), shared with Shows.
            ForEach(model.screen.filterGroups) { group in
                Section(group.title) {
                    ForEach(group.options, id: \.self) { option in
                        Toggle(option.title, isOn: binding(for: option))
                    }
                }
            }
            if model.screen.isFiltered {
                Button("Clear Filters", role: .destructive) {
                    Task { await model.run { await $0.clearFilters() } }
                }
            }
        } label: {
            ActionLabel("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filter")
        .accessibilityIdentifier(ControlID.filter)
    }

    private func binding(for option: FilterOption) -> Binding<Bool> {
        Binding(
            get: { option.isOn(in: model.screen.query.filter) },
            set: { _ in Task { await model.run { await $0.toggle(option) } } })
    }
}
