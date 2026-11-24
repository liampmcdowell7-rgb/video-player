import SwiftUI
import AppLogic
import LibraryIndex
import UserData

/// Long press on a card: Go to Movie / Go to Show, mark watched or unwatched, favourite, Remove from Continue Watching
/// (#21 F, only while the item is in that row), and Move to Movies / Move to Shows (docs/SORTING.md).
/// (Match top menu actions to swipe actions: none here.)
struct CardContextMenu: ViewModifier {
    let card: ItemCard
    @Environment(AppServices.self) private var services
    @State private var move: SortMoveTarget?
    @State private var showEdit = false
    @State private var editKeys: [UDEditKey] = []

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if let title = card.goToTitle {
                    Button(title, systemImage: card.kind == .movie ? "film" : "tv") {
                        services.openRequest = card.seriesID.map { Route.series($0) } ?? .item(card.id)
                    }
                    // #25 A2: found by identifier in the tests (67); a context menu item may not carry it on every system
                    // version, so the tests fall back to the label "Go to Movie".
                    .accessibilityIdentifier(ControlID.goToTitle)
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
                if card.kind == .movie || card.kind == .episode {
                    // R449: the same edit screens as the page's More menu.
                    Button("Edit", systemImage: "pencil") { Task { await openEdit() } }
                }
                if card.kind == .movie {
                    Button("Move to Shows", systemImage: "tv") { move = .item(card.id, .episode) }
                } else if card.kind == .episode {
                    Button("Move to Movies", systemImage: "film") { move = .item(card.id, .movie) }
                }
            }
            .taskCover(item: $move) { target in SortMoveSheet(target: target) }
            .taskCover(isPresented: $showEdit) { if !editKeys.isEmpty { MetadataEditView(title: card.title, keys: editKeys, artworkKey: "item-\(card.id)", level: card.kind == .movie ? .movie : .episode) } }
    }

    private func openEdit() async {
        guard let item = try? await services.store.item(id: card.id) else { return }
        let files = (try? await services.store.versions(of: card.id)) ?? []
        editKeys = EditTarget.keys(for: item, files: files)
        showEdit = !editKeys.isEmpty
    }
}

extension View {
    func cardContextMenu(_ card: ItemCard) -> some View { modifier(CardContextMenu(card: card)) }
}
