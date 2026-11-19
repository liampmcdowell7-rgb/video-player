import SwiftUI
import AppLogic

/// A titled shelf of cards (Home rows, Continue Watching).
struct CardRow: View {
    let row: HomeRow

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(row.title, style: .title3)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between posters (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(row.cards) { card in
                        if row.id == .continueWatching {
                            // #15 4.1 (R185, PROVISIONAL): Continue Watching uses 16:9 cards, three to a screen width.
                            PosterCard(card: card, wide: true)
                                // design-lint:allow HIG Layout, 40 pt spacing; three 16:9 cards span the same width as six posters (R185)
                                .containerRelativeFrame(.horizontal, count: 3, spacing: 40)
                        } else {
                            PosterCard(card: card)
                                // design-lint:allow HIG Layout, six columns of the grid so shelf posters line up with grid posters
                                .containerRelativeFrame(.horizontal, count: 6, spacing: 40)
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}
