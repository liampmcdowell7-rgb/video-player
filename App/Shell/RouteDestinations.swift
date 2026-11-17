import SwiftUI

/// The screens a `Route` leads to. Applied once per tab's navigation stack.
struct RouteDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: Route.self) { route in
            switch route {
            case .item(let id):
                ItemDetailView(itemID: id)
            case .series(let id):
                SeriesView(seriesID: id)
            case .folder(let sourceID, let sourceName, let path):
                FilesFolderView(sourceID: sourceID, sourceName: sourceName, path: path)
            }
        }
    }
}

extension View {
    func routeDestinations() -> some View { modifier(RouteDestinations()) }
}
