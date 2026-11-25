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
    @State private var editStart: UDEditField.Group?
    /// R471 (14): Unmatch is asked about first (system confirmation dialog).
    @State private var askUnmatch = false
    /// R471 (15): Delete from Library is asked about first.
    @State private var askDelete = false

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
                // R471 (10): the page's own actions list, kept to what a card can run, in the page's order and words.
                ForEach(ProductActions.cardList(context), id: \.self) { action in
                    Button(action.title, systemImage: action.symbol, role: action == .unmatch || action == .delete ? .destructive : nil) { run(action) }
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
            .confirmationDialog(unmatchText.title, isPresented: $askUnmatch, titleVisibility: .visible) {
                Button(unmatchText.button, role: .destructive) { Task { await services.unmatch(.movie(itemID: card.id)) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(unmatchText.message)
            }
            .confirmationDialog(deleteText.title, isPresented: $askDelete, titleVisibility: .visible) {
                Button(deleteText.button, role: .destructive) { Task { await services.removeFromLibrary(.item(itemID: card.id)) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteText.message)
            }
            .taskCover(item: $move) { target in SortMoveSheet(target: target) }
            .taskCover(isPresented: $showEdit) { if !editKeys.isEmpty { MetadataEditView(title: card.title, keys: editKeys, artworkKey: "item-\(card.id)", level: card.kind == .movie ? .movie : .episode, startGroup: editStart) } }
    }

    /// The card's facts for the actions list; Delete from Library is off while Restrictions are on (R471 (15)).
    private var context: ProductActionContext {
        var c = card.actionContext
        c.deleteAllowed = !services.restrictionsOn
        return c
    }

    private var deleteText: (title: String, message: String, button: String) {
        LibraryRemover.confirmation(.item(itemID: card.id), title: card.title)
    }

    private var unmatchText: (title: String, message: String, button: String) {
        Unmatcher.confirmation(.movie(itemID: card.id), title: card.title)
    }

    /// Runs one entry of `ProductActions.cardList`; the list holds nothing else (`ProductActions.cardSupported`).
    private func run(_ action: ProductAction) {
        switch action {
        case .markWatched: Task { await services.setWatched(card.id, true) }
        case .markUnwatched: Task { await services.setWatched(card.id, false) }
        // R449: the same edit screens as the page's More menu.
        case .editMetadata: Task { await openEdit() }
        // R471 (13): the same screen opened on Artwork.
        case .changeArtwork: Task { await openEdit(start: .artwork) }
        // R471 (14): the same confirmation as the page.
        case .unmatch: askUnmatch = true
        case .delete: askDelete = true
        default: break
        }
    }

    private func openEdit(start: UDEditField.Group? = nil) async {
        editStart = start
        guard let item = try? await services.store.item(id: card.id) else { return }
        let files = (try? await services.store.versions(of: card.id)) ?? []
        editKeys = EditTarget.keys(for: item, files: files)
        showEdit = !editKeys.isEmpty
    }
}

extension View {
    func cardContextMenu(_ card: ItemCard) -> some View { modifier(CardContextMenu(card: card)) }
}
