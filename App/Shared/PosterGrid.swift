import SwiftUI
import AppLogic

/// A poster grid of library cards.
struct PosterGrid: View {
    let cards: [ItemCard]
    var onCardAppear: (Int64) -> Void = { _ in }

    var body: some View {
        PosterGridLayout {
            ForEach(cards) { card in
                PosterCard(card: card)
                    .onAppear { onCardAppear(card.id) }
            }
        }
    }
}
