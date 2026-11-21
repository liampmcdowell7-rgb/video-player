import SwiftUI
import AppLogic

/// One show in the Shows grid: the same parts and sizes as `PosterCard`, text under rule S1 (`FittingLine`).
struct SeriesCard: View {
    let series: SeriesSummary

    var body: some View {
        // R335 (PROVISIONAL): one `.borderless` lockup, the artwork and its text inside the button (as `PosterCard`).
        NavigationLink(value: Route.series(series.id)) {
            VStack(alignment: .leading) {
                ArtworkView(key: series.artworkKey, symbol: "tv")
                    // design-lint:allow R335: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                    .hoverEffect(.highlight)
                // The same side padding as PosterCard (#17 C): the text never touches the card's edge.
                VStack(alignment: .leading) {
                    FittingText(series.title, style: .caption)
                    // "3 seasons · 4 unwatched": the unwatched count goes first when the line is too long.
                    FittingLine(line: detail, style: .caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(series.title)
        .accessibilityValue(detail.full)
    }

    private var detail: ShortLine {
        ShortLine(ordered: series.unwatchedCount > 0 ? [series.seasonsText, "\(series.unwatchedCount) unwatched"] : [series.seasonsText])
    }
}
