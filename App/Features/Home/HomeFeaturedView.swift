import SwiftUI
import AppLogic

/// R349 (owner's device test of build 5, 21 Nov 2026, item C; PROVISIONAL): the featured area at the top of Home, as the
/// Home screen of Apple's TV app on tvOS 27 (docs/DESIGN_SYSTEM.md "Reference screens"): the title's large artwork across
/// the full width, and over its lower part the title logo (or the name), ONE line of metadata, then Play (or Resume) and
/// More. More opens the title's page. Which title: AppLogic `HomeFeatured.pick` (Continue Watching first).
/// The area is two thirds of the screen's height (`HomeFeaturedLayout.heightFraction`), so the first shelf shows below it
/// and the person can see there is more (HIG Designing for tvOS: "Deliver beautiful, edge-to-edge artwork").
struct HomeFeaturedView: View {
    let featured: HomeFeatured
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(alignment: .leading) {
            // The title logo when there is one (Settings > Accessibility "Title Logos"), the name otherwise (TitleHeader).
            TitleHeader(title: featured.card.title, artworkKey: featured.titleArtworkKey)
            FittingLine(line: featured.metadata, style: .callout)
                .foregroundStyle(ReadableSecondary.style)
            // #25 B5: one height for the row's buttons (ActionRow), the system Label in each (ActionLabel).
            ActionRow {
                Button {
                    services.playRequest = PlayRequest(itemID: featured.card.id, fromStart: false)
                } label: {
                    ActionLabel(featured.playTitle, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(ControlID.featuredPlay)
                NavigationLink(value: pageRoute) {
                    ActionLabel("More", systemImage: "ellipsis")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(ControlID.featuredMore)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .containerRelativeFrame(.vertical) { (length: CGFloat, _: Axis) -> CGFloat in
            length * HomeFeaturedLayout.heightFraction
        }
        .background { BackdropView(artworkKey: featured.titleArtworkKey, style: .hero) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(ControlID.featured)
    }

    /// More opens the movie's page, or the show's page for an episode (the TV app's "More" on its Home featured title).
    private var pageRoute: Route {
        if featured.card.kind == .episode, let series = featured.card.seriesID { return .series(series) }
        return .item(featured.card.id)
    }
}

/// R349 (PROVISIONAL, alternatives in OPEN_QUESTIONS): the featured area's share of the screen height. Not a point size: the
/// TV app's featured area fills most of the first screen and lets the first shelf show under it; Apple publishes no number.
enum HomeFeaturedLayout {
    static let heightFraction: CGFloat = 2.0 / 3.0
}
