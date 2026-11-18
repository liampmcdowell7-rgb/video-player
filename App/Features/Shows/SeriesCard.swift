import SwiftUI
import AppLogic

/// One show in the Shows grid: the same parts and sizes as `PosterCard`, text under rule S1 (`FittingLine`).
struct SeriesCard: View {
    let series: SeriesSummary

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(value: Route.series(series.id)) {
                ArtworkView(key: series.artworkKey, symbol: "tv")
            }
            .buttonStyle(.card)
            .accessibilityLabel(series.title)
            .accessibilityValue(detail.full)
            FittingText(series.title, style: .caption)
            // "3 seasons · 4 unwatched": the unwatched count goes first when the line is too long.
            FittingLine(line: detail, style: .caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var detail: ShortLine {
        ShortLine(ordered: series.unwatchedCount > 0 ? [series.seasonsText, "\(series.unwatchedCount) unwatched"] : [series.seasonsText])
    }
}
