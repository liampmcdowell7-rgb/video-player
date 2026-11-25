import SwiftUI
import AppLogic

/// Home: R349 (item C, PROVISIONAL) the featured title at the top, full width (`HomeFeaturedView`), then the shelves, one
/// under the other: landscape thumbnails for Continue Watching and Next Up, posters for Recently Added (`CardRow`). `rows`
/// holds only the shelves the Home Screen settings show, and the featured title comes from them.
/// R357 (owner's scan of ec27d52, finding 1): the featured artwork is the PAGE's background, full bleed, as Apple's sample
/// "Creating a tvOS media catalog app in SwiftUI" builds its landing page ("a full-screen image with a material in an
/// overlay", `.ignoresSafeArea()`): it runs to the screen edges and under the tab bar, while the title and buttons keep the
/// system margins inside the scroll view. Above the fold the top of the picture is clear (`.hero`); once the featured area
/// is more than half off screen (`onScrollVisibilityChange`, the sample's fold test) the material covers the whole picture
/// (`.page`), so the shelves stay readable over it.
struct HomeRows: View {
    let rows: [HomeRow]
    @State private var belowFold: Bool = false
    /// R452: where the featured title begins, for the cover behind it.
    @State private var textTop: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        let featured: HomeFeatured? = HomeFeatured.pick(from: rows)
        ScrollView {
            LazyVStack(alignment: .leading) {
                if let featured {
                    HomeFeaturedView(featured: featured)
                        .onScrollVisibilityChange { (visible: Bool) in
                            // Reduce Motion: the material changes without the fade.
                            withAnimation(reduceMotion ? nil : .default) { belowFold = !visible }
                        }
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { (index: Int, row: HomeRow) in
                    CardRow(row: row)
                        // R471 (51): the shelf's number (from 1) for the diagnostics page's focus moves.
                        .environment(\.focusShelf, index + 1)
                }
            }
            // R470: the space the featured column reports its top in (ArtTextTop).
            .artTextContent()
        }
        .artTextTop($textTop)
        // R345: the focused cards grow past the page's scroll view; it must not clip them.
        .scrollClipDisabled()
        // R471 (51): each focus move on the shelves (shelf and place) and slow frames while the page scrolls.
        .scrollDiagnostics(screen: "Home", columns: nil)
        // R346 (item A): one focus region, so Up from a lower shelf scrolls back to the featured area before the tab bar.
        .focusSection()
        .background {
            if let featured {
                // R357: behind the whole page, ignoring the safe area (BackdropView), not inside the scroll content.
                BackdropView(artworkKey: featured.titleArtworkKey, style: belowFold ? .page : .hero, textTop: textTop)
            }
        }
    }
}
