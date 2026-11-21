import Foundation
import VideoPlayerCore
import LibraryIndex

// Plex stage 7 (docs/PLEX_SOURCE.md section 4; OPEN_QUESTIONS R270, R307): the server's own synopsis and poster for a file,
// asked ONLY for files of a Plex source. R270 (PROVISIONAL): Plex's metadata and artwork first, TMDB filling the gaps. Every
// other source keeps its order unchanged (details: Wikidata, then TMDB; artwork: the picture next to the file, then online).

/// A picture a media server keeps for a file: a cache key that changes when the server's picture changes, and the bytes.
public struct ServerPicture: Sendable {
    public var cacheKey: String
    public var fetch: @Sendable (_ maxBytes: Int) async throws -> Data
    public init(cacheKey: String, fetch: @escaping @Sendable (_ maxBytes: Int) async throws -> Data) {
        self.cacheKey = cacheKey
        self.fetch = fetch
    }
}

/// What a media server says about one of its files. The app implements it for Plex (`PlexServerMetadata`); tests use a fake.
public protocol ServerMetadataProviding: Sendable {
    /// The server's synopsis of the title this file belongs to, or nil.
    func summary(for file: StoredFile) async -> String?
    /// The server's poster (a movie) or still (an episode) for this file, or nil.
    func poster(for file: StoredFile) async -> ServerPicture?
}

/// Source kinds whose server metadata is used (R307). Only Plex today: Jellyfin and Emby keep their order (R210).
public enum ServerMetadataKinds {
    public static let used: Set<SourceKind> = [.plex]

    /// The file of an item to ask the server about, when that file comes from a source of a used kind.
    static func file(forItem item: LibraryItem, store: any LibraryStore) async -> StoredFile? {
        guard let versions = try? await store.versions(of: item.id), !versions.isEmpty,
              let sources = try? await store.sources() else { return nil }
        let used = Set(sources.filter { Self.used.contains($0.kind) }.map(\.id))
        let ordered = versions.filter { $0.id == item.preferredFileID } + versions.filter { $0.id != item.preferredFileID }
        return ordered.first { used.contains($0.sourceID) }
    }
}

/// The first details layer (`DetailsLayer.source`): the server's synopsis for a movie page ("item-N"). Show pages
/// ("series-N") get nothing from it: an episode's synopsis is not the show's (the show's own record is not read, R307).
public struct ServerDetailsLayer: TitleDetailsSource {
    private let store: any LibraryStore
    private let server: any ServerMetadataProviding

    public init(store: any LibraryStore, server: any ServerMetadataProviding) {
        self.store = store
        self.server = server
    }

    public func details(key: String) async -> TitleDetails? {
        guard case .item(let id)? = ArtworkKey(key), let item = try? await store.item(id: id),
              let file = await ServerMetadataKinds.file(forItem: item, store: store),
              let summary = await server.summary(for: file)?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty
        else { return nil }
        return TitleDetails(overview: summary, cast: [])
    }
}
