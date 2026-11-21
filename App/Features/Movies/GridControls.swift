import SwiftUI
import AppLogic
import LibraryIndex

/// The Movies controls. R344 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T5): one Sort and Filter menu, no row
/// of filter chips; active filters show in the menu (`SortFilterMenu`). R375 (decided by the owner's standing rule R312):
/// the controls are the system toolbar (`libraryToolbar`, App/Shared/GridToolbar.swift), not a row in the content; the
/// count stays above the grid as one line of text (`GridCountLine`).
struct MoviesToolbar: ViewModifier {
    let model: ScreenModel<ItemGridViewModel>?
    let shown: Bool
    var onSave: () -> Void
    /// Files waiting in Needs Review (docs/SORTING.md); the More menu item shows only above 0.
    var reviewCount = 0

    func body(content: Content) -> some View {
        content.libraryToolbar(shown: shown && model != nil, hasMore: reviewCount > 0 || !letters.isEmpty) {
            if let model { SortFilterMenu(model: model) }
        } savedViews: {
            if let model { SavedViewsMenu(model: model, onSave: onSave) }
        } more: {
            NeedsReviewMenuItem(count: reviewCount)
            if let model, !letters.isEmpty {
                AlphabetJumpMenu(letters: letters) { letter in
                    Task { await model.run { await $0.jump(to: letter) } }
                }
            }
        }
    }

    /// The jump list is offered only when the grid has letters (the title sort).
    private var letters: [AlphabetJumpEntry] {
        guard let model, case .loaded(let grid) = model.screen.state else { return [] }
        return grid.alphabet.map { AlphabetJumpEntry(letter: $0.letter, count: $0.count) }
    }
}
