import SwiftUI
import AppLogic

/// R349 (owner's device test of build 5, 21 Nov 2026, item C; PROVISIONAL): the featured area at the top of Home, as the
/// Home screen of Apple's TV app on tvOS 27 (docs/DESIGN_SYSTEM.md "Reference screens"): the title's large artwork across
/// the full width (drawn behind the page by `HomeRows`, R357), and over its lower part the title logo (or the name), ONE line of metadata, then Play (or Resume) and
/// More. More opens the title's page. Which title: AppLogic `HomeFeatured.pick` (Continue Watching first).
/// The area is 0.8 of the screen's height (`HomeFeaturedLayout.heightFraction`, R377), so the first shelf shows below it
/// and the person can see there is more (HIG Designing for tvOS: "Deliver beautiful, edge-to-edge artwork").
struct HomeFeaturedView: View {
    let featured: HomeFeatured
    @Environment(AppServices.self) private var services
    /// R371: the featured title's rating, from the same details layers as its page.
    @State private var rating: String?
    /// R396 (audit H5): the featured title's synopsis, from the same details.
    @State private var overview: String?
    /// R471 (46): the featured title's genres, for its kind line.
    @State private var genres: [String] = []
    /// R388 (item B): Play takes the focus once, at launch, as the TV app opens on its featured title (`HomeLaunchFocus`).
    @FocusState private var playFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            // The title logo when there is one (Settings > Accessibility "Title Logos"), the name otherwise (TitleHeader).
            TitleHeader(title: featured.card.title, artworkKey: featured.titleArtworkKey)
            // R471 (46), PROVISIONAL (Home hero photo): the kind line of the title's page ("Movie · Drama", then the
            // rating's box), the shared view, in place of the card's own line and format badges (those stay on the page).
            HeroKindLineView(segments: featured.kindLine(genres: genres, rating: rating))
            // R471 (46): three lines of the synopsis, as the photo (R396 had one), in the shared text column. A long
            // synopsis ends with the system's "…" here; the whole text is on the title's page (More). Nothing without one.
            if let overview {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(ReadableSecondary.style)
                    .lineLimit(HomeFeatured.synopsisLines) // design-lint:allow R396: a teaser of a long synopsis, as on the TV app's Home; the whole text is on the title's page (not a short text under rule S1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
            }
            // #25 B5: one height for the row's buttons (ActionRow), the system Label in each (ActionLabel).
            ActionRow {
                // R471 (46): the product pages' Play capsule (R471 item 3: the system bordered capsule, light when
                // focused), with the mini bar for a started title.
                PlayCapsuleButton(capsule: PlayCapsule.make(progress: featured.card.progress, durationSeconds: nil)) {
                    services.playRequest = PlayRequest(itemID: featured.card.id, fromStart: false)
                }
                .focused($playFocused)
                .accessibilityIdentifier(ControlID.featuredPlay)
                // R396 (audit SF2, H3): a round icon button, as the TV app's Home draws its secondary actions (A1).
                // R471 (46): the photo's info glyph; it opens the title's page.
                NavigationLink(value: pageRoute) {
                    ActionLabel("More", systemImage: "info", iconOnly: true)
                }
                .roundAction()
                .accessibilityLabel("More")
                .accessibilityIdentifier(ControlID.featuredMore)
            }
            // R396 (audit SF7, H4): about 105 pt from the buttons to the first shelf's header, as on the TV app's Home
            // (picture A1: Play's bottom at about 802, the header at about 910). The page's own stack already leaves
            // about 20 pt there (the run on fd9731f), so the rest is added here. R393 had 40 pt.
            .padding(.bottom, CGFloat(RowSpacing.featuredToShelf - RowSpacing.stackGap))
        }
        // R470: the whole text column (title, metadata line, overview, buttons) reports its top for the cover behind it.
        .reportsArtTextTop()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .containerRelativeFrame(.vertical) { (length: CGFloat, _: Axis) -> CGFloat in
            length * HomeFeaturedLayout.heightFraction
        }
        // R357: the artwork is drawn by `HomeRows` behind the whole page (full bleed), not here inside the scroll content,
        // where it stopped at the safe area. This area only holds the text and buttons, inside the system margins.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ControlID.featured)
        .task(id: detailsKey) {
            let details = await services.online.details(key: detailsKey)
            rating = details?.contentRating
            overview = details?.overview
            genres = details?.genres ?? []
        }
        // R388: Home's first frame has nothing focusable (the library is still loading), so tvOS put the focus in the
        // sidebar, which expands, and nothing moved it to the page. The first featured title right after launch asks for it.
        .task {
            if HomeLaunchFocus.state.claim(at: ProcessInfo.processInfo.systemUptime) { playFocused = true }
        }
    }

    /// The details key of the page More opens: the movie ("item-N") or the show ("series-N").
    private var detailsKey: String {
        if featured.card.kind == .episode, let series = featured.card.seriesID { return "series-\(series)" }
        return "item-\(featured.card.id)"
    }

    /// More opens the movie's page, or the show's page for an episode (the TV app's "More" on its Home featured title).
    private var pageRoute: Route {
        if featured.card.kind == .episode, let series = featured.card.seriesID { return .series(series) }
        return .item(featured.card.id)
    }
}

/// R388: the one launch-focus chance for the whole app run (not per Home view: re-selecting Home rebuilds its stack, R348,
/// and must not pull the focus out of the sidebar).
@MainActor
enum HomeLaunchFocus {
    static var state: LaunchFocus = LaunchFocus()
}

/// R349 (PROVISIONAL, alternatives in OPEN_QUESTIONS): the featured area's share of the screen height. Not a point size: the
/// TV app's featured area fills most of the first screen and lets the first shelf show under it.
/// R377 (audit docs/AUDIT_INVENTED_UI.md #2, owner 21 Nov 2026, rule R312): 0.8, the value of Apple's media catalog sample
/// (its header is `containerRelativeFrame(.vertical)` at `length * 0.8`). Was 2/3 (R349).
enum HomeFeaturedLayout {
    static let heightFraction: CGFloat = 0.8
}
