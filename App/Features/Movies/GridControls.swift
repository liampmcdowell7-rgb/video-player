import SwiftUI
import AppLogic
import LibraryIndex

/// The row above a grid: the Sort and Filter menu, the saved-view menu and the count. R344 (Decided by the owner, 21 Nov
/// 2026; docs/HIG_AUDIT.md T5): no row of filter chips any more; active filters show in the menu (`SortFilterMenu`).
struct GridControls: View {
    let model: ScreenModel<ItemGridViewModel>
    var onSave: () -> Void
    /// Files waiting in Needs Review (docs/SORTING.md); the button shows only above 0.
    var reviewCount = 0

    var body: some View {
        VStack(alignment: .leading) {
            // #15 4.5: the same row as on Shows (`GridToolbar`), so both grids start at the same height.
            // #25 B2: one line; when it does not fit, Saved Views, Needs Review and Jump to Letter go into one More menu.
            // #32 D (R233): the view controls and Saved Views as one group of symbols, Needs Review and Jump to Letter as the
            // second. R344: Sort and Filter are one menu.
            GridToolbar(count: model.screen.countText) {
                SortFilterMenu(model: model)
            } savedViews: {
                SavedViewsMenu(model: model, onSave: onSave)
            } tools: {
                NeedsReviewButton(count: reviewCount)
                jumpMenu
            } collapsed: {
                SavedViewsMenu(model: model, onSave: onSave)
                NeedsReviewMenuItem(count: reviewCount)
                jumpMenu
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
