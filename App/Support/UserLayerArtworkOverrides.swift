import Foundation
import LibraryIndex
import UserData
import AppLogic

/// R455: the user's artwork choices as the engine reads them. The single place every picture goes through (cards, heroes, the
/// detail pages, the Top Shelf folder and the player's info panel all ask `ArtworkEngine`, which asks this first): the choice
/// of the user layer (`UDEditField` poster, backdrop, logo, episodeStill) as a file of the user-artwork folder.
/// An online choice that has no file yet (synced from another device before its file arrived) gives no override, so the
/// automatic rule shows; the choice flow always copies the picture into the folder first.
struct UserLayerArtworkOverrides: ArtworkOverriding {
    let ledger: UserDataLedger
    let store: SQLiteLibraryStore

    func override(key: String, field: UDEditField) async -> ArtworkResult? {
        let keys = await editKeys(for: key)
        guard !keys.isEmpty, case let .file(name)? = ledger.edits(for: keys)[field]?.artwork,
              let url = UserArtworkFolder.store.url(for: name) else { return nil }
        return .file(url)
    }

    /// The edit keys of an artwork key: a movie or an episode by its item, a show by the online id its episodes carry.
    private func editKeys(for key: String) async -> [UDEditKey] {
        switch ArtworkKey(key) {
        case .item(let id)?:
            guard let item = try? await store.item(id: id), let files = try? await store.versions(of: id) else { return [] }
            return EditTarget.keys(for: item, files: files)
        case .series(let seriesID)?:
            let ids = ((try? await store.episodes(ofSeries: seriesID)) ?? []).compactMap(\.tmdbID)
            guard let tmdb = Dictionary(grouping: ids, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key else { return [] }
            return [UDEditKey.show(tmdbID: tmdb)]
        default:
            return []
        }
    }
}
