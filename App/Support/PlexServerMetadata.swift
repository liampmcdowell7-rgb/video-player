import Foundation
import VideoPlayerCore
import LibraryIndex
import AppLogic
import SourcePlex
import SourceJellyfin
import SourceEmby

/// Plex's own synopsis and pictures for a file (and, R374, the content rating of Plex, Jellyfin and Emby items) (docs/PLEX_SOURCE.md section 4; OPEN_QUESTIONS R270, R307). The details and
/// artwork layers ask this only for files of a Plex source (`ServerMetadataKinds`); it answers nil for anything else.
/// Everything comes from the listing the client already holds (no extra request), except the picture bytes, which are
/// read once with the token in a header and then kept in the artwork cache.
struct PlexServerMetadata: ServerMetadataProviding {
    /// The live source for a saved source id (the same closure the sidecar reader uses).
    let sourceFor: @Sendable (String) async -> (any MediaSource)?

    func summary(for file: StoredFile) async -> String? {
        guard let plex = await sourceFor(file.sourceID) as? PlexClient else { return nil }
        return (try? await plex.serverItem(at: file.path))??.metadata.summary
    }

    /// R371: Plex's `contentRating` of the item, from the same listing (no extra request). R374: also Jellyfin's and Emby's
    /// `OfficialRating`, from the item list their clients already hold (no extra request). The synopsis and pictures stay
    /// Plex only (R307, R210).
    func contentRating(for file: StoredFile) async -> String? {
        let source = await sourceFor(file.sourceID)
        if let plex = source as? PlexClient { return (try? await plex.serverItem(at: file.path))??.metadata.contentRating }
        if let jellyfin = source as? JellyfinClient { return (try? await jellyfin.officialRating(at: file.path)) ?? nil }
        if let emby = source as? EmbyClient { return (try? await emby.officialRating(at: file.path)) ?? nil }
        return nil
    }

    func poster(for file: StoredFile) async -> ServerPicture? {
        guard let plex = await sourceFor(file.sourceID) as? PlexClient,
              let item = (try? await plex.serverItem(at: file.path)) ?? nil,
              let thumb = item.metadata.thumb, thumb.hasPrefix("/") else { return nil }
        // The thumb path carries the server's own version of the picture, so a changed poster gets a new cache key.
        return ServerPicture(cacheKey: "plex|\(file.sourceID)|\(thumb)") { maxBytes in
            try await plex.imageData(thumb, maxBytes: maxBytes)
        }
    }
}
