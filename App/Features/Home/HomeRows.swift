import SwiftUI
import AppLogic

/// Home: R349 (item C, PROVISIONAL) the featured title at the top, full width (`HomeFeaturedView`), then the shelves, one
/// under the other: landscape thumbnails for Continue Watching and Next Up, posters for Recently Added (`CardRow`). `rows`
/// holds only the shelves the Home Screen settings show, and the featured title comes from them.
struct HomeRows: View {
    let rows: [HomeRow]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                if let featured = HomeFeatured.pick(from: rows) {
                    HomeFeaturedView(featured: featured)
                }
                ForEach(rows) { row in
                    CardRow(row: row)
                }
            }
        }
        // R345: the focused cards grow past the page's scroll view; it must not clip them.
        .scrollClipDisabled()
        // R346 (item A): one focus region, so Up from a lower shelf scrolls back to the featured area before the tab bar.
        .focusSection()
    }
}
