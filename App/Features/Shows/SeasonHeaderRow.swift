import SwiftUI
import AppLogic

/// R471 (22), PROVISIONAL: the chosen season's own text and poster on the show page, between the season picker and its
/// episodes. The poster (only when one was found: a season's picture next to the media, the user's choice, or the season's
/// online poster) is a small 2:3 picture; the season's title and synopsis are one system card button (`.card`, the system's
/// focus lift and platter, so no text sits on the backdrop without a material, R470). Selecting it shows the whole synopsis
/// in a cover, as About does. Without a synopsis the title stands alone, as a section header.
struct SeasonHeaderRow: View {
    let header: SeasonHeader
    let artworkKey: String
    let showsPoster: Bool
    @State private var showsSummary = false

    var body: some View {
        HStack(alignment: .top) {
            if showsPoster {
                ArtworkView(key: artworkKey, symbol: "tv")
                    // design-lint:allow HIG Layout, the season poster one eighth of the page width, as a grid column of eight
                    .containerRelativeFrame(.horizontal, count: 8, spacing: 40)
                    .accessibilityHidden(true)
            }
            if let overview = header.overview {
                Button { showsSummary = true } label: {
                    VStack(alignment: .leading) {
                        FittingText(header.title, style: .headline)
                        Text(overview)
                            .font(.callout)
                            .lineLimit(3, reservesSpace: false)
                            .multilineTextAlignment(.leading)
                    }
                    .padding()
                    .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
                }
                .buttonStyle(.card)
                .accessibilityHint("Shows the season's whole synopsis")
                .accessibilityIdentifier("show.seasonHeader")
                .taskCover(isPresented: $showsSummary) {
                    SynopsisCover(title: header.title, text: overview, artworkKey: artworkKey, prefersEpisodeStill: false)
                }
            } else {
                ShelfHeader(header.title)
            }
        }
        // R424: a focus section the page's whole width, so Up and Down reach it from any column.
        .productPageRow()
    }
}
