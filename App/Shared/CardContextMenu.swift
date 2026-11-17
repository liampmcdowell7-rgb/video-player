import SwiftUI
import AppLogic

/// Long press on a card: mark watched or unwatched, favourite. (Match top menu actions to swipe actions: none here.)
struct CardContextMenu: ViewModifier {
    let card: ItemCard
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(card.isWatched ? "Mark as Unwatched" : "Mark as Watched", systemImage: card.isWatched ? "eye.slash" : "eye") {
                Task { await services.setWatched(card.id, !card.isWatched) }
            }
            Button(card.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: card.isFavorite ? "heart.slash" : "heart") {
                Task { await services.setFavorite(card.id, !card.isFavorite) }
            }
        }
    }
}

extension View {
    func cardContextMenu(_ card: ItemCard) -> some View { modifier(CardContextMenu(card: card)) }
}
