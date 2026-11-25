import SwiftUI
import AppLogic

/// One show in the Shows grid: the same parts and sizes as `PosterCard`, text under rule S1 (`FittingLine`).
struct SeriesCard: View {
    let series: SeriesSummary
    /// R471 (40): a Related card's one line, shown only while the card has focus, in place of the title and second line.
    var focusCaption: String? = nil
    @Environment(\.listRows) private var listRows
    @AppStorage(AppPreference.showPosterTitles.rawValue) private var showTitles = true

    var body: some View {
        if listRows {
            // R458: List View, the same row as a movie's.
            NavigationLink(value: Route.series(series.id)) {
                HStack {
                    ArtworkView(key: series.artworkKey, symbol: "tv")
                        .containerRelativeFrame(.horizontal, count: 12, span: 1, spacing: 0) // design-lint:allow R458: a poster one twelfth of the row, as a list row of the Apple TV app (R312); a ratio of the container, not points
                    VStack(alignment: .leading) {
                        FittingText(series.title, style: .caption)
                        FittingLine(line: detail, style: .caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .accessibilityLabel(series.title)
            .accessibilityValue(detail.full)
            // R471 (23): the show's actions on a long press, as a movie's poster has them.
            .seriesCardMenu(series)
        } else {
            lockup
        }
    }

    private var lockup: some View {
        // R335 (PROVISIONAL): one `.borderless` lockup, the artwork and its text inside the button (as `PosterCard`).
        NavigationLink(value: Route.series(series.id)) {
            // R360/R361: the artwork and the text are SIBLINGS in the label, as Apple's sample writes a lockup and as
            // `PosterCard`, so the borderless style moves the text out of the way of the lifted artwork.
            ArtworkView(key: series.artworkKey, symbol: "tv")
                // design-lint:allow R335: Apple's tvOS media catalog sample attaches the borderless lockup's highlight by hand to a custom artwork view; the system effect, not our own
                .hoverEffect(.highlight)
            // The same side padding as PosterCard (#17 C): the text never touches the card's edge.
            if let focusCaption {
                FocusOnlyCaption(text: focusCaption)
                    .padding(.horizontal)
            } else if showTitles {
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
        // R471 (23): the show's actions on a long press, as a movie's poster has them.
        .seriesCardMenu(series)
        .wholeRowOnly() // R443: in a library grid a row is drawn only when whole
    }

    private var detail: ShortLine {
        ShortLine(ordered: series.unwatchedCount > 0 ? [series.seasonsText, "\(series.unwatchedCount) unwatched"] : [series.seasonsText])
    }
}
