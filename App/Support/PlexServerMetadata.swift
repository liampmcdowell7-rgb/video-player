import Foundation
import VideoPlayerCore
import LibraryIndex
import AppLogic
import SourcePlex

/// Plex's own synopsis and pictures for a file (docs/PLEX_SOURCE.md section 4; OPEN_QUESTIONS R270, R307). The details and
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
