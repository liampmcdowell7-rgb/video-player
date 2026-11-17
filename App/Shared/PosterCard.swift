import SwiftUI
import AppLogic

/// One title in a row or grid: the poster is the button (system `.card` style, Liquid Glass on focus), the text sits below it.
struct PosterCard: View {
    let card: ItemCard

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(value: Route.item(card.id)) {
                ArtworkView(key: card.artworkKey, symbol: card.kind == .movie ? "film" : "tv")
            }
            .buttonStyle(.card)
            .accessibilityLabel(card.title)
            .cardContextMenu(card)
            if let progress = card.progress {
                ProgressView(value: progress)
            }
            Text(card.title)
                .font(.caption)
                .lineLimit(1)
            if let subtitle = card.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !card.badges.isEmpty {
                Text(card.badges.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
