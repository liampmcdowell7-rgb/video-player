import SwiftUI
import AppLogic

struct SeriesCard: View {
    let series: SeriesSummary

    var body: some View {
        VStack(alignment: .leading) {
            NavigationLink(value: Route.series(series.id)) {
                ArtworkView(key: series.artworkKey, symbol: "tv")
            }
            .buttonStyle(.card)
            .accessibilityLabel(series.title)
            Text(series.title)
                .font(.caption)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var detail: String {
        series.unwatchedCount > 0 ? "\(series.seasonsText) · \(series.unwatchedCount) unwatched" : series.seasonsText
    }
}
