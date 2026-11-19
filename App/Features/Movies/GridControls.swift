import SwiftUI
import AppLogic
import LibraryIndex

/// The row above a grid: sort, filter and saved-view menus, the count, and one button per active filter.
struct GridControls: View {
    let model: ScreenModel<ItemGridViewModel>
    var onSave: () -> Void
    /// Files waiting in Needs Review (docs/SORTING.md); the button shows only above 0.
    var reviewCount = 0

    var body: some View {
        VStack(alignment: .leading) {
            // #15 4.5: the same row as on Shows (`GridToolbar`), so both grids start at the same height.
            // #25 B2: one line; when it does not fit, Saved Views, Needs Review and Jump to Letter go into one More menu.
            GridToolbar(count: model.screen.countText) {
                SortMenu(model: model)
                FilterMenu(model: model)
            } secondary: {
                SavedViewsMenu(model: model, onSave: onSave)
                NeedsReviewButton(count: reviewCount)
                jumpMenu
            } collapsed: {
                SavedViewsMenu(model: model, onSave: onSave)
                NeedsReviewMenuItem(count: reviewCount)
                jumpMenu
            }
            if !model.screen.chips.isEmpty {
                FilterChipsRow(model: model)
            }
        }
    }

    @ViewBuilder
    private var jumpMenu: some View {
        if case .loaded(let grid) = model.screen.state, !grid.alphabet.isEmpty {
            AlphabetJumpMenu(letters: grid.alphabet.map { AlphabetJumpEntry(letter: $0.letter, count: $0.count) }) { letter in
                Task { await model.run { await $0.jump(to: letter) } }
            }
        }
    }
}
