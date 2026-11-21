import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal

/// R374 (owner's review of R371, 21 Nov 2026, item 2): the content rating of the source itself, the first layer of the
/// rating (R371), for more than Plex:
/// - a media server's own rating: Plex `contentRating`, Jellyfin and Emby `OfficialRating` (`ServerMetadataProviding`);
/// - the title's own NFO file (`<mpaa>` or `<certification>`), read once and kept in the library (`LibraryItem.contentRating`).
/// The server's rating comes first, then the NFO file's. The functionality follows the owner's reference player (decided
/// by the owner's standing rule R312).
public enum SourceRatings {
    /// The largest NFO file read for a rating; a real one is a few kilobytes.
    public static let maxNFOBytes = 1_000_000

    /// The rating an NFO file gives for this kind of item: the first `<movie>` (a film) or `<episodedetails>` (an
    /// episode) document with a certification. "" when the file has none (recorded, so it is not read again).
    public static func nfoRating(_ data: Data, kind: ItemKind) -> String {
        let wanted: NFOKind = kind == .movie ? .movie : .episode
        let file = NFOParser.parse(data)
        let doc = file.documents.first { $0.kind == wanted && ContentRating.clean($0.certification) != nil }
        return doc?.certification?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The item's NFO rating: the stored one when the file was read before; otherwise the NFO file next to the item's
    /// preferred file (same name, ".nfo") is read once and the result is kept. Nil when there is no NFO file or it cannot
    /// be read now (then it is tried again next time).
    public static func nfoRating(item: LibraryItem, store: any LibraryStore, reader: any SidecarReading) async -> String? {
        if let stored = item.contentRating { return stored }
        var fileID = item.preferredFileID
        if fileID == nil { fileID = (try? await store.versions(of: item.id))?.first?.id }
        guard let fileID,
              let sidecars = try? await store.sidecars(for: fileID),
              let nfo = sidecars.first(where: { $0.kind == .nfo }),
              let data = try? await reader.read(sourceID: nfo.sourceID, path: nfo.path, maxBytes: maxNFOBytes), !data.isEmpty
        else { return nil }
        let rating = nfoRating(data, kind: item.kind)
        try? await store.setMetadata(itemID: item.id, ItemMetadata(contentRating: rating))
        return rating
    }
}

/// The source layer (`DetailsLayer.source`) for a movie page ("item-N"): the server's synopsis (Plex, R307) and the
/// source's own rating (R371, R374: the server's, then the NFO file's).
public struct SourceDetailsLayer: TitleDetailsSource {
    private let store: any LibraryStore
    private let server: (any ServerMetadataProviding)?
    private let reader: (any SidecarReading)?

    public init(store: any LibraryStore, server: (any ServerMetadataProviding)?, reader: (any SidecarReading)?) {
        self.store = store
        self.server = server
        self.reader = reader
    }

    public func details(key: String) async -> TitleDetails? {
        guard case .item(let id)? = ArtworkKey(key), let item = try? await store.item(id: id) else { return nil }
        var details: TitleDetails?
        if let server { details = await ServerDetailsLayer(store: store, server: server).details(key: key) }
        if details?.contentRating == nil, let reader,
           let rating = ContentRating.clean(await SourceRatings.nfoRating(item: item, store: store, reader: reader)) {
            var d = details ?? TitleDetails(overview: nil, cast: [])
            d.contentRating = rating
            details = d
        }
        return details
    }
}
