import SwiftUI
import AppLogic

/// R396 (docs/AUDIT_VISUAL_TVAPP.md SF7, H4): the header of a shelf, as the TV app draws "Continue Watching" (picture A1):
/// smaller than a title and grey. The system Headline style in the readable secondary level (R240), one line (rule S1).
/// Before: Title 3 in white on Home, Headline in white on the pages. One view, so every shelf header is the same.
struct ShelfHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        FittingText(title, style: .headline)
            .foregroundStyle(ReadableSecondary.style)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A titled shelf of cards (Home rows, Continue Watching).
struct CardRow: View {
    let row: HomeRow

    var body: some View {
        VStack(alignment: .leading) {
            ShelfHeader(row.title)
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between posters (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(row.cards) { card in
                        if row.id.usesLandscapeCards {
                            // #15 4.1 (R185, PROVISIONAL): Continue Watching uses 16:9 cards, three to a screen width.
                            // R349 (item C): Next Up too, as the TV app's "Up Next" (AppLogic `usesLandscapeCards`).
                            PosterCard(card: card, wide: true)
                                // R396 (audit H6): five across, as the TV app's Continue Watching (picture A1: cards about
                                // 318 pt wide; five columns at 40 pt are 320 pt). Three across (560 pt) before (R185).
                                // design-lint:allow HIG Layout, 40 pt spacing; five 16:9 cards to a page width (R396)
                                .containerRelativeFrame(.horizontal, count: RowSpacing.landscapeShelfColumns, spacing: 40)
                        } else {
                            PosterCard(card: card)
                                // design-lint:allow HIG Layout, six columns of the grid so shelf posters line up with grid posters
                                .containerRelativeFrame(.horizontal, count: 6, spacing: 40)
                        }
                    }
                }
                // #36 group 4 (R264): every card of the row the same caption height (the lockup captions of Continue
                // Watching; portrait cards have no CardCaption and are unaffected).
                .equalCaptionRow()
            }
            .scrollClipDisabled()
        }
    }
}
