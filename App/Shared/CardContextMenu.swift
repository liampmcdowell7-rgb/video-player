import SwiftUI
import AppLogic
import LibraryIndex

/// Long press on a card: Go to Movie / Go to Show, mark watched or unwatched, favourite, Remove from Continue Watching
/// (#21 F, only while the item is in that row), and Move to Movies / Move to Shows (docs/SORTING.md).
/// (Match top menu actions to swipe actions: none here.)
struct CardContextMenu: ViewModifier {
    let card: ItemCard
    @Environment(AppServices.self) private var services
    @State private var move: SortMoveTarget?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let title = card.goToTitle {
                    Button(title, systemImage: card.kind == .movie ? "film" : "tv") {
                        services.openRequest = card.seriesID.map { Route.series($0) } ?? .item(card.id)
                    }
                }
                Button(card.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: card.isWatched ? "eye.slash" : "eye") {
                    Task { await services.setWatched(card.id, !card.isWatched) }
                }
                Button(card.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: card.isFavorite ? "heart.slash" : "heart") {
                    Task { await services.setFavorite(card.id, !card.isFavorite) }
                }
                if card.canRemoveFromContinue {
                    // The store's hide mark (R186): the item leaves Continue Watching and keeps its progress.
                    Button("Remove from Continue Watching", systemImage: "minus.circle") {
                        Task { await services.hideFromContinue(card.id) }
                    }
                }
                if card.kind == .movie {
                    Button("Move to Shows", systemImage: "tv") { move = .item(card.id, .episode) }
                } else if card.kind == .episode {
                    Button("Move to Movies", systemImage: "film") { move = .item(card.id, .movie) }
                }
            }
            .sheet(item: $move) { target in SortMoveSheet(target: target) }
    }
}

extension View {
    func cardContextMenu(_ card: ItemCard) -> some View { modifier(CardContextMenu(card: card)) }
}
