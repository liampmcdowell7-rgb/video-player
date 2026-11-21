import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal

/// R374 (owner's review of R371, 21 Nov 2026, item 2): the content rating of the source itself, the first layer of the
/// rating (R371), for more than Plex:
/// - a media server's own rating: Plex `contentRating`, Jellyfin and Emby `OfficialRating` (`ServerMetadataProviding`);
/// - when the list lacks it, Jellyfin's and Emby's single-item endpoint, asked once per title and kept in the library;
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

    /// The item's NFO rating as the file writes it: nil when there is no NFO file next to the item's preferred file (same
    /// name, ".nfo") or it cannot be read now; "" when the file has none. Nothing is stored here.
    static func readNFO(item: LibraryItem, store: any LibraryStore, reader: any SidecarReading) async -> String? {
        var fileID = item.preferredFileID
        if fileID == nil { fileID = (try? await store.versions(of: item.id))?.first?.id }
        guard let fileID,
              let sidecars = try? await store.sidecars(for: fileID),
              let nfo = sidecars.first(where: { $0.kind == .nfo }),
              let data = try? await reader.read(sourceID: nfo.sourceID, path: nfo.path, maxBytes: maxNFOBytes), !data.isEmpty
        else { return nil }
        return nfoRating(data, kind: item.kind)
    }

    /// R374: the rating kept in the library for this title, found once: the server's answer to one single-item request
    /// (Jellyfin and Emby, when their list lacked it), else the NFO file's. The answer is stored ("" when the server and
    /// the file say none) and never asked again; nil when nothing could answer now (then it is tried again next time).
    public static func storedRating(item: LibraryItem, store: any LibraryStore, server: (any ServerMetadataProviding)?,
                                    reader: (any SidecarReading)?) async -> String? {
        if let stored = item.contentRating { return stored }
        var answer: String?
        if let server,
           let file = await ServerMetadataKinds.file(forItem: item, store: store, kinds: ServerMetadataKinds.requested) {
            do { answer = try await server.requestContentRating(for: file) ?? "" } catch { answer = nil }
        }
        if ContentRating.clean(answer) == nil, let reader, let nfo = await readNFO(item: item, store: store, reader: reader) {
            if answer == nil || ContentRating.clean(nfo) != nil { answer = nfo }
        }
        guard let answer else { return nil }
        try? await store.setMetadata(itemID: item.id, ItemMetadata(contentRating: answer))
        return answer
    }
}

/// The source layer (`DetailsLayer.source`) for a movie page ("item-N"): the server's synopsis (Plex, R307) and the
/// source's own rating (R371, R374: the server's list, then the kept rating: one single-item request, else the NFO file).
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
        if details?.contentRating == nil, server != nil || reader != nil,
           let rating = ContentRating.clean(await SourceRatings.storedRating(item: item, store: store, server: server, reader: reader)) {
            var d = details ?? TitleDetails(overview: nil, cast: [])
            d.contentRating = rating
            details = d
        }
        return details
    }
}
