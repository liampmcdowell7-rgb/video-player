import SwiftUI

/// The screens a `Route` leads to. Applied once per tab's navigation stack.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .item(let id):
                ItemDetailView(itemID: id).screenIdentifier("screen.item")
            case .series(let id):
                SeriesView(seriesID: id).screenIdentifier("screen.series")
            case .folder(let sourceID, let sourceName, let path):
                FilesFolderView(sourceID: sourceID, sourceName: sourceName, path: path).screenIdentifier("screen.folder")
            case .needsReview:
                NeedsReviewView().screenIdentifier("screen.needsReview")
            case .person(let name):
                PersonView(name: name).screenIdentifier("screen.person")
            }
        }
    }
}

extension View {
    func routeDestinations() -> some View { modifier(RouteDestinations()) }
}
