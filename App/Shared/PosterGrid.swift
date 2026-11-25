import SwiftUI
import AppLogic

/// A poster grid of library cards.
struct PosterGrid: View {
    let cards: [ItemCard]
    /// R471 (51): the screen's name on the diagnostics page.
    var screen: String = ""
    var onCardAppear: (Int64) -> Void = { _ in }

    var body: some View {
        PosterGridLayout(screen: screen) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { (index: Int, card: ItemCard) in
                PosterCard(card: card)
                    .focusCell(index: index)
                    .onAppear { onCardAppear(card.id) }
            }
        }
    }
}
