import SwiftUI
import AppLogic
import UserData

/// R471 (23), PROVISIONAL: a long press on a show's poster. The show page's own actions list, kept to what a card can run
/// (`ProductActions.cardList`, the same words and order as the page): Add to List, Rate, Mark All as Watched or Unwatched,
/// Change Artwork, Edit Details and Delete from Library. Mark All and Delete ask first, as on the page. The show's online id
/// and its edit keys are read only when an action is chosen (no library read per poster on screen), so Unmatch and Fix
/// Match, which need to know whether the show is matched, stay on the page.
struct SeriesCardMenu: ViewModifier {
    let series: SeriesSummary
    @Environment(AppServices.self) private var services
    @State private var editRequest: ShowEditRequest?
    @State private var pendingMarkAll: ProductAction?
    @State private var askDelete = false
    @State private var naming: ListNameRequest?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                ForEach(ProductActions.cardList(context), id: \.self) { action in
                    switch action {
                    case .rate:
                        RateMenu(current: nil) { chosen in
                            Task { await services.rate(keys: await showKeys(), itemIDs: [], stars: chosen) }
                        }
                    case .addToList, .addToPlaylistOrCollection:
                        AddToListMenu(action: action, ref: nil) { list in
                            Task { if let ref = await services.titleRef(seriesID: series.id) { services.addToList(list, ref: ref, title: series.title) } }
                        } onNew: { kind in
                            naming = ListNameRequest(kind: kind, title: series.title, ref: { await services.titleRef(seriesID: series.id) })
                        }
                    case .markAllWatched, .markAllUnwatched:
                        Button(action.title, systemImage: action.symbol) { pendingMarkAll = action }
                    case .changeArtwork, .editMetadata:
                        Button(action.title, systemImage: action.symbol) { Task { await openEdit(start: action == .changeArtwork ? .artwork : nil) } }
                    case .delete:
                        Button(action.title, systemImage: action.symbol, role: .destructive) { askDelete = true }
                    default:
                        EmptyView()
                    }
                }
            }
            .confirmationDialog(pendingMarkAll?.title ?? "", isPresented: Binding(get: { pendingMarkAll != nil },
                                                                                   set: { if !$0 { pendingMarkAll = nil } })) {
                if let action = pendingMarkAll {
                    Button(action.title) { Task { await services.setSeriesWatched(series.id, season: nil, watched: action == .markAllWatched) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(pendingMarkAll == .markAllWatched ? "Every episode of this show will be marked as watched."
                                                       : "Every episode of this show will be marked as unwatched.")
            }
            .confirmationDialog(deleteText.title, isPresented: $askDelete, titleVisibility: .visible) {
                Button(deleteText.button, role: .destructive) { Task { await services.removeFromLibrary(.show(seriesID: series.id)) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteText.message)
            }
            .listNameCover($naming)
            .taskCover(item: $editRequest) { request in
                MetadataEditView(title: request.title, keys: request.keys, artworkKey: request.artworkKey, level: request.level,
                                 startGroup: request.startGroup)
            }
    }

    /// The card's facts for the actions list. Matched is not known here (see above); Delete is off while Restrictions are on.
    private var context: ProductActionContext {
        var c = series.actionContext
        c.deleteAllowed = !services.restrictionsOn
        return c
    }

    private var deleteText: (title: String, message: String, button: String) {
        LibraryRemover.confirmation(.show(seriesID: series.id), title: series.title, episodeCount: series.episodeCount)
    }

    private func showKeys() async -> [UDEditKey] {
        EditTarget.showKeys(tmdbID: await services.showOnlineID(seriesID: series.id), title: series.title)
    }

    private func openEdit(start: UDEditField.Group?) async {
        let keys = await showKeys()
        editRequest = ShowEditRequest(id: start == nil ? "show" : "show-artwork", title: series.title, keys: keys,
                                      artworkKey: "series-" + String(series.id), level: .show, startGroup: start)
    }
}

extension View {
    func seriesCardMenu(_ series: SeriesSummary) -> some View { modifier(SeriesCardMenu(series: series)) }
}
