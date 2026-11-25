import SwiftUI
import AppLogic

/// R471 (25) (PROVISIONAL): "Related" on the show page: the library's other shows that share a genre (`RelatedShows`),
/// portrait posters as on the movie page's Related shelf (`RelatedShelf`, six columns), each opening its show page and
/// keeping its long-press menu (`SeriesCard`). NOT COMPILED for tvOS.
struct RelatedShowsShelf: View {
    let shows: [SeriesSummary]

    var body: some View {
        VStack(alignment: .leading) {
            ShelfHeader(RelatedTitles.heading)
                .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
            ScrollView(.horizontal) {
                // design-lint:allow HIG Layout, 40 pt horizontal spacing between posters (docs/DESIGN_SYSTEM.md section 4)
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(shows) { show in
                        SeriesCard(series: show)
                            // design-lint:allow HIG Layout, six columns of the grid so shelf posters line up with grid posters
                            .containerRelativeFrame(.horizontal, count: 6, spacing: 40)
                            .accessibilityIdentifier("product.related.show.\(show.id)")
                    }
                }
                .equalCaptionRow()
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, CGFloat(RowSpacing.shelfFocusRoom))
        }
        .productPageRow()
    }
}
