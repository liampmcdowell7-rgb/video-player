import SwiftUI

/// The screens a `Route` leads to. Applied once per tab's navigation stack.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            // R407 (owner's review of the run on f0a67d3, item 10; A11Y1): the UI-test text-size and Bold Text overrides
            // again on every pushed page. Larger Text changed the tab roots (Movies, Settings) but not the movie page
            // (84 = 106) or the Sample Library folder (83 = 105): both are pushed `Route` destinations, and the override
            // sat only around each tab's NavigationStack. Why it does not reach a pushed page is NOT on an Apple page
            // read (UNVERIFIED): a pushed page is hosted apart from the stack's root, and the player, presented apart,
            // already needed its own override (RootView). Setting the same values twice changes nothing where they did
            // reach.
            Group {
                destination(route)
            }
            .uiTestAccessibilityOverrides()
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .item(let id):
            ItemDetailView(itemID: id).screenIdentifier("screen.item")
        case .series(let id):
            SeriesView(seriesID: id).screenIdentifier("screen.series")
        case .seriesSeason(let id, let season):
            SeriesView(seriesID: id, startSeason: season).screenIdentifier("screen.series")
        case .folder(let sourceID, let sourceName, let path):
            FilesFolderView(sourceID: sourceID, sourceName: sourceName, path: path).screenIdentifier("screen.folder")
        case .needsReview:
            NeedsReviewView().screenIdentifier("screen.needsReview")
        case .person(let name):
            PersonView(name: name).screenIdentifier("screen.person")
        }
    }
}

extension View {
    func routeDestinations() -> some View { modifier(RouteDestinations()) }
}
