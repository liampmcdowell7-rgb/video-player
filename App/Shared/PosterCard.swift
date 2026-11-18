import SwiftUI
import AppLogic

/// One title in a row or grid: the poster is the button (system `.card` style, Liquid Glass on focus), the text sits below it.
///
/// Every card has the same parts in the same places (screenshot review item 4: posters in one grid row sat at different
/// heights because cards with fewer text lines were centred): a progress slot, the title, the second line and the badge line
/// are always laid out, empty ones hidden, so equal cards are exactly equal in size and their posters line up. Short texts
/// follow rule S1 (`FittingLine`): one line, scaled to the readable minimum, never cut with "…".
struct PosterCard: View {
    let card: ItemCard

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(value: Route.item(card.id)) {
                ArtworkView(key: card.artworkKey, symbol: card.kind == .movie ? "film" : "tv")
            }
            .buttonStyle(.card)
            .accessibilityLabel(card.title)
            .accessibilityValue(card.subtitle ?? "")
            .cardContextMenu(card)
            ProgressView(value: card.progress ?? 0)
                .opacity(card.progress == nil ? 0 : 1)
                .accessibilityHidden(card.progress == nil)
            FittingText(card.title, style: .caption)
            FittingLine(line: card.subtitleLine, style: .caption2)
                .foregroundStyle(.secondary)
            FittingLine(line: card.badgeLine, style: .caption2)
                .foregroundStyle(.secondary)
        }
    }
}

