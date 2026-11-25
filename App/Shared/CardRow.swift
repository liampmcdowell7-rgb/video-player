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
            // R402 (owner's review of the run on f0a67d3, item 3; PROVISIONAL): room under the header for the lifted card
            // (08-card-long-press-go-to: the focused Continue Watching card covered "Continue Watching"), as under the
            // grid's count line (R392).
            ShelfHeader(row.title)
                .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between posters (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(Array(row.cards.enumerated()), id: \.element.id) { (index: Int, card: ItemCard) in
                        Group {
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
                        // R471 (51): the card's place in its shelf, for the diagnostics page.
                        .focusCell(index: index)
                    }
                }
                // #36 group 4 (R264): every card of the row the same caption height (the lockup captions of Continue
                // Watching; portrait cards have no CardCaption and are unaffected).
                .equalCaptionRow()
            }
            .scrollClipDisabled()
            // R402: the shelf is as tall as its cards with their tallest caption (`fixedSize` takes the content's own
            // height, so a caption that wraps to three lines makes the shelf taller instead of running under the next
            // header), plus room under it for the lifted card and its caption, which moves down as the artwork grows.
            // Only the cards already laid out count (the stack is lazy): a longer caption further right grows the shelf
            // when it is scrolled to. UNVERIFIED until a run (08, 50, 51).
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
        }
    }
}
