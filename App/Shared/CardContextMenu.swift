import SwiftUI
import AppLogic
import LibraryIndex

/// Long press on a card: mark watched or unwatched, favourite, and Move to Movies / Move to Shows (docs/SORTING.md).
/// (Match top menu actions to swipe actions: none here.)
struct CardContextMenu: ViewModifier {
    let card: ItemCard
    @Environment(AppServices.self) private var services
    @State private var move: SortMoveTarget?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button(card.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: card.isWatched ? "eye.slash" : "eye") {
                    Task { await services.setWatched(card.id, !card.isWatched) }
                }
                Button(card.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: card.isFavorite ? "heart.slash" : "heart") {
                    Task { await services.setFavorite(card.id, !card.isFavorite) }
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
