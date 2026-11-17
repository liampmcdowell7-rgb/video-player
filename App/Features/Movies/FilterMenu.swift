import SwiftUI
import AppLogic
import LibraryIndex

/// Filters as toggles in a menu. Options of one group combine with "or", groups with "and" (the library's rule).
struct FilterMenu: View {
    let model: ScreenModel<ItemGridViewModel>

    private let groups: [(title: String, options: [FilterOption])] = [
        ("Watched", [.watch(.unwatched), .watch(.inProgress), .watch(.watched), .favorites]),
        ("Resolution", [.resolution(.uhd4k), .resolution(.hd1080), .resolution(.hd720), .resolution(.sd)]),
        ("Dynamic Range", [.hdr(.dolbyVision), .hdr(.hdr10Plus), .hdr(.hdr10), .hdr(.hlg), .hdr(.sdr)]),
        ("Sound", [.atmos, .minChannels(8), .minChannels(6)]),
    ]

    var body: some View {
        Menu("Filter", systemImage: "line.3.horizontal.decrease.circle") {
            ForEach(groups, id: \.title) { group in
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
        }
    }

    private func binding(for option: FilterOption) -> Binding<Bool> {
        Binding(
            get: { option.isOn(in: model.screen.query.filter) },
            set: { _ in Task { await model.run { await $0.toggle(option) } } })
    }
}
