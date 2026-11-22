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
    /// R388 (item B): Play takes the focus once, at launch, as the TV app opens on its featured title (`HomeLaunchFocus`).
    @FocusState private var playFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            // The title logo when there is one (Settings > Accessibility "Title Logos"), the name otherwise (TitleHeader).
            TitleHeader(title: featured.card.title, artworkKey: featured.titleArtworkKey)
            // R391 (shared fault 1): the rating badge sits right after the metadata (`BadgeSpacing`). Before, the line
            // took the whole width (`FittingLine` fills it to measure itself) and pushed the badge to the far edge.
            // The system picks the first that fits: the line at its own width with the badge after it, else the line
            // filling the width and shrinking or dropping parts (rule S1).
            ViewThatFits(in: .horizontal) {
                metadataLine(ownWidth: true)
                metadataLine(ownWidth: false)
            }
            // R396 (audit H5): one line of the title's synopsis, as under the featured title of the TV app's Home (A1),
            // in the shared text column. A long synopsis ends with the system's "…" here; the whole text is on the
            // title's page (More). Nothing when the details have none.
            if let overview {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(ReadableSecondary.style)
                    .lineLimit(1) // design-lint:allow R396: a one-line teaser of a long synopsis, as on the TV app's Home; the whole text is on the title's page (not a short text under rule S1)
                    .frame(maxWidth: CGFloat(RowSpacing.textColumn), alignment: .leading)
            }
            // #25 B5: one height for the row's buttons (ActionRow), the system Label in each (ActionLabel).
            ActionRow {
                Button {
                    services.playRequest = PlayRequest(itemID: featured.card.id, fromStart: false)
                } label: {
                    ActionLabel(featured.playTitle, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .focused($playFocused)
                .accessibilityIdentifier(ControlID.featuredPlay)
                // R396 (audit SF2, H3): a round icon button, as the TV app's Home draws its secondary actions (A1).
                NavigationLink(value: pageRoute) {
                    ActionLabel("More", systemImage: "ellipsis", iconOnly: true)
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
        }
        // R388: Home's first frame has nothing focusable (the library is still loading), so tvOS put the focus in the
        // sidebar, which expands, and nothing moved it to the page. The first featured title right after launch asks for it.
        .task {
            if HomeLaunchFocus.state.claim(at: ProcessInfo.processInfo.systemUptime) { playFocused = true }
        }
    }

    private func metadataLine(ownWidth: Bool) -> some View {
        HStack(spacing: CGFloat(BadgeSpacing.afterText)) {
            // R396 (audit H5): the card's second line as text, then the rating and the formats as DRAWN badges (the
            // same badges as on the title's page); before, the formats were words in the text line.
            FittingLine(line: featured.card.subtitleLine, style: .callout)
                .foregroundStyle(ReadableSecondary.style)
                .fixedSize(horizontal: ownWidth, vertical: false)
            // R371: the content rating after the metadata, as on the title's page.
            if let rating {
                RatingBadge(rating: rating)
            }
            BadgeRow(badges: featured.card.formatBadges)
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
