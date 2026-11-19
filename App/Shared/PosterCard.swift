import SwiftUI
import AppLogic

/// One title in a row or grid: the poster is the button (system `.card` style, Liquid Glass on focus), the text sits below it.
///
/// Every card has the same parts in the same places (screenshot review item 4: posters in one grid row sat at different
/// heights because cards with fewer text lines were centred): the title, the second line and the badge line are always laid
/// out, empty ones hidden (the progress is inside the artwork, #15 D4), so equal cards are exactly equal in size and their posters line up. Short texts
/// follow rule S1 (`FittingLine`): one line, scaled to the readable minimum, never cut with "…".
struct PosterCard: View {
    let card: ItemCard

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(value: Route.item(card.id)) {
                // #15 D4: the progress sits inside the artwork's bottom edge, so it moves and lifts with the focused card
                // and every card keeps the same height. Fixed in code, verify in next screenshots.
                ArtworkView(key: card.artworkKey, symbol: card.kind == .movie ? "film" : "tv")
                    .overlay(alignment: .bottom) {
                        if let progress = card.progress {
                            ProgressView(value: progress)
                                .padding()
                        }
                    }
            }
            .buttonStyle(.card)
            .accessibilityLabel(card.title)
            .accessibilityValue(card.subtitle ?? "")
            .cardContextMenu(card)
            // #17 C: the text keeps a side padding, so it never touches the card's edge (Larger Text screenshot 80: titles
            // ended 2-3 px from it). The system's default padding; FittingLine measures the width inside it.
            VStack(alignment: .leading) {
                FittingText(card.title, style: .caption)
                FittingLine(line: card.subtitleLine, style: .caption2)
                    .foregroundStyle(.secondary)
                FittingLine(line: card.badgeLine, style: .caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }
}

