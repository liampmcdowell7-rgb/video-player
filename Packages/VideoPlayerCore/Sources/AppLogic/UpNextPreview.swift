import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal

/// R383 (owner's audit #11, 22 Nov 2026): the picture on the system's Up Next card (`AVContentProposal.previewImage`).
/// Apple's previewImage page (developer.apple.com/documentation/avkit/avcontentproposal/previewimage, read 22 Nov 2026):
/// "The preview image you provide should typically be a frame from the proposed video, not the poster artwork." So the
/// card gets the next episode's still when one is on hand, and nothing otherwise (the system card then has no picture, as
/// before). The show's poster is never used (owner's rule: Apple's published pages win for functionality). "On hand"
/// means already in the artwork cache on this Apple TV: nothing is read from a source and nothing is requested when the
/// card is proposed.
public enum UpNextPreview {
    /// A picture the app might have for the next episode.
    public enum Candidate: Equatable, Sendable {
        /// The episode's own still (a frame of the episode): the "-thumb" picture next to its file, or its media server's
        /// picture of the episode.
        case episodeStill
        /// The show's poster.
        case showPoster
    }

    /// The largest picture handed to the card. A still is far smaller; a larger file is left out rather than decoded.
    public static let maxBytes = 10_000_000

    /// Which of the pictures on hand the card uses: the still, else none (never the poster, Apple's previewImage page).
    public static func choose(onHand: Set<Candidate>) -> Candidate? {
        onHand.contains(.episodeStill) ? .episodeStill : nil
    }

    /// True for bytes worth handing to the system as an image: not empty, not over `maxBytes`, and a JPEG, PNG, HEIF/HEIC
    /// or WebP file by its first bytes. Anything else is left out (the card then has no picture).
    public static func usable(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maxBytes else { return false }
        let b = [UInt8](data.prefix(12))
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return true }                                  // JPEG
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return true }    // PNG
        if b.count >= 12, b[4...7] == [0x66, 0x74, 0x79, 0x70][...] {                          // ISO box "ftyp": HEIF, HEIC
            let brand = String(decoding: b[8...11], as: UTF8.self)
            return ["heic", "heix", "mif1", "msf1", "heim", "heis", "avif"].contains(brand)
        }
        if b.count >= 12, b[0...3] == [0x52, 0x49, 0x46, 0x46][...], b[8...11] == [0x57, 0x45, 0x42, 0x50][...] { return true } // WebP
        return false
    }

    /// The library item id in a card's preview key ("item-42"); nil for any other key.
    public static func itemID(previewKey: String?) -> Int64? {
        guard let previewKey, case .item(let id)? = ArtworkKey(previewKey) else { return nil }
        return id
    }

    /// The next episode's still if it is already in the artwork cache: the "-thumb" picture next to its file (as cached
    /// when it was shown before), else the media server's picture of the episode as cached (`heldPictureCacheKey`, no
    /// request). The folder listing comes from the library index. Nil for anything that is not an episode, or when nothing
    /// is cached.
    public static func cachedStill(itemID: Int64, store: any LibraryStore, cache: ArtworkDiskCache,
                                   server: (any ServerMetadataProviding)?) async -> URL? {
        guard let item = try? await store.item(id: itemID), item.kind == .episode,
              let versions = try? await store.versions(of: itemID) else { return nil }
        if let file = versions.first(where: { $0.id == item.preferredFileID }) ?? versions.first,
           let children = try? await store.children(sourceID: file.sourceID, folder: file.parentPath, sort: FileSort(),
                                                     limit: 2_000, offset: 0) {
            let entries = children.map { SourceEntry(path: $0.path, name: $0.name, isDirectory: $0.isDirectory, size: $0.size,
                                                     modified: $0.modified) }
            if let thumb = SidecarImageFinder.images(forEpisode: file.name, in: entries).thumb,
               let url = cache.url(forKey: ArtworkEngine.sidecarCacheKey(sourceID: file.sourceID,
                                                                         path: thumb.path, size: thumb.size,
                                                                         modified: thumb.modified, etag: thumb.etag)) {
                return url
            }
        }
        if let server, let serverFile = await ServerMetadataKinds.file(forItem: item, store: store),
           let key = await server.heldPictureCacheKey(for: serverFile),
           let url = cache.url(forKey: ArtworkEngine.serverCacheKey(key)) {
            return url
        }
        return nil
    }
}
