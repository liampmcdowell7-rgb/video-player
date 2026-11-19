import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal
import MetadataOnline

// Artwork for the library cards (docs/ARTWORK_DISCOVER.md). Precedence, strongest first (docs/METADATA.md, "local sidecar
// data wins over online data"):
//   1. a picture next to the video on the source (poster / folder / cover ..., chosen by `SidecarImageFinder`);
//   2. the poster of the title the metadata matcher found online, as a web address (nothing is downloaded here);
//   3. nothing: the card keeps its placeholder symbol.
// Everything is read from the library index, so browsing never waits on a server for the folder listing.

public enum ArtworkKey: Equatable, Sendable {
    case item(Int64)
    case series(Int64)
    /// A poster path from TMDB (Discover cards): "remote:/abc.jpg".
    case remote(String)

    public init?(_ text: String) {
        if text.hasPrefix("item-"), let id = Int64(text.dropFirst(5)) { self = .item(id); return }
        if text.hasPrefix("series-"), let id = Int64(text.dropFirst(7)) { self = .series(id); return }
        if text.hasPrefix("remote:") {
            let path = String(text.dropFirst(7))
            guard path.hasPrefix("/"), path.count > 1 else { return nil }
            self = .remote(path)
            return
        }
        return nil
    }
}

public enum ArtworkResult: Equatable, Sendable {
    /// A file in the artwork cache (read from a source).
    case file(URL)
    /// A web address the system image loader fetches and caches.
    case remote(URL)
    case none
}

/// Reads one picture file from a source. The app implements it with the source factory; tests use a fake.
public protocol SidecarReading: Sendable {
    func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data
}

/// Online artwork through the metadata matcher. Implemented by `TMDBArtworkProvider`; nil in the engine when no key is entered.
public protocol OnlineArtworkProviding: Sendable {
    /// The poster of the title this item matches (matching it first when needed), or nil (no match, needs review, lookup failed).
    func posterURL(forItem item: LibraryItem, file: StoredFile?) async -> URL?
    /// The poster of a series by its online id.
    func posterURL(forSeriesID tmdbID: Int) async -> URL?
    /// Turns a poster path into an address.
    func imageURL(path: String) async -> URL?
    /// The online picture sets (posters, backdrops, logos) of the title an item is already matched to (no new matching), or
    /// nil. #15 Part 9: they come with the title details the poster lookup already requested.
    func images(forItem item: LibraryItem) async -> ImageSet?
    /// The online picture sets of a series by its online id, or nil.
    func images(forSeriesID tmdbID: Int) async -> ImageSet?
    /// Turns a logo path into an address.
    func logoURL(path: String) async -> URL?
}

public extension OnlineArtworkProviding {
    func images(forItem item: LibraryItem) async -> ImageSet? { nil }
    func images(forSeriesID tmdbID: Int) async -> ImageSet? { nil }
    func logoURL(path: String) async -> URL? { nil }
}

/// One title-logo picture to try, in order (#15 9.2). The app decodes it and checks it with `TitleLogoRules.check`; the
/// first that passes is drawn, and with none the text title stays.
public struct LogoCandidate: Equatable, Sendable {
    public var source: TitleLogoSource
    /// `.file` (read from the source, cached) or `.remote` (fetched by the system image loader).
    public var location: ArtworkResult
}

public actor ArtworkEngine {
    /// Largest picture file read from a source. Quality principle (R98), changed 2026-11-17 from 8 MB: a full-resolution
    /// 3840x2160 PNG next to a video can be over 8 MB, and skipping it fell back to a smaller online picture. 40 MB covers
    /// an uncompressed 3840x2160 RGBA image (33.2 MB). PROVISIONAL; the old 8 MB is the alternative if memory is tight.
    public static let maxSidecarBytes = 40_000_000

    private let store: any LibraryStore
    private let cache: ArtworkDiskCache
    private let reader: any SidecarReading
    private let online: (any OnlineArtworkProviding)?
    private let now: @Sendable () -> Date
    private var misses: [String: Date] = [:]
    /// How long a "found nothing" answer is remembered, so scrolling past a title does not repeat the lookups. PROVISIONAL.
    public static let missMemory: TimeInterval = 15 * 60

    public init(store: any LibraryStore, cache: ArtworkDiskCache, reader: any SidecarReading, online: (any OnlineArtworkProviding)?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.cache = cache
        self.reader = reader
        self.online = online
        self.now = now
    }

    public func resolve(key text: String) async -> ArtworkResult {
        guard let key = ArtworkKey(text) else { return .none }
        if let at = misses[text], now().timeIntervalSince(at) < Self.missMemory { return .none }
        let result: ArtworkResult
        do {
            switch key {
            case .item(let id): result = try await resolveItem(id)
            case .series(let id): result = try await resolveSeries(id)
            case .remote(let path): result = await online?.imageURL(path: path).map { .remote($0) } ?? .none
            }
        } catch {
            result = .none
        }
        if result == .none { misses[text] = now() } else { misses[text] = nil }
        return result
    }

    // MARK: Items

    private func resolveItem(_ id: Int64) async throws -> ArtworkResult {
        guard let item = try await store.item(id: id) else { return .none }
        let versions = try await store.versions(of: id)
        let file = versions.first { $0.id == item.preferredFileID } ?? versions.first
        if let file {
            let entries = try await folderEntries(sourceID: file.sourceID, folder: file.parentPath)
            if item.kind == .movie {
                let videos = entries.filter { !$0.isDirectory && FileClassifier.fileExtension(of: $0.name).isVideoExtension }.count
                let found = SidecarImageFinder.images(forMovie: file.name, in: entries, folderHoldsOneVideo: videos <= 1)
                if let hit = found.poster, let r = await cached(hit, file.sourceID) { return r }
            } else {
                let found = SidecarImageFinder.images(forEpisode: file.name, in: entries)
                if let hit = found.thumb ?? found.poster, let r = await cached(hit, file.sourceID) { return r }
                if let seriesID = item.seriesID, let r = try await showFolderArtwork(seriesID: seriesID) { return r }
            }
        }
        if let url = await online?.posterURL(forItem: item, file: file) { return .remote(url) }
        return .none
    }

    // MARK: Series

    private func resolveSeries(_ seriesID: Int64) async throws -> ArtworkResult {
        if let r = try await showFolderArtwork(seriesID: seriesID) { return r }
        guard let online else { return .none }
        let episodes = try await store.episodes(ofSeries: seriesID)
        let ids = episodes.compactMap(\.tmdbID)
        if ids.isEmpty {
            // No online id yet: ask the matcher through one episode, which also records the id for next time.
            guard let first = episodes.first else { return .none }
            let file = try await store.versions(of: first.id).first
            if let url = await online.posterURL(forItem: first, file: file) { return .remote(url) }
            return .none
        }
        let counts = Dictionary(grouping: ids, by: { $0 }).mapValues(\.count)
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else { return .none }
        if let url = await online.posterURL(forSeriesID: best) { return .remote(url) }
        return .none
    }

    /// The poster inside the show folder (the folder above the season folders). An episode folder that is not named like a
    /// season is taken to be the show folder itself.
    private func showFolderArtwork(seriesID: Int64) async throws -> ArtworkResult? {
        guard let first = try await store.episodes(ofSeries: seriesID).first, let file = try await store.versions(of: first.id).first else { return nil }
        var folder = file.parentPath
        let last = String(folder.split(separator: "/").last ?? "")
        if SidecarImageFinder.seasonNumber(ofFolder: last) != nil {
            folder = Self.parent(of: folder)
        }
        let entries = try await folderEntries(sourceID: file.sourceID, folder: folder)
        guard let hit = SidecarImageFinder.images(forShowFolder: entries).poster else { return nil }
        return await cached(hit, file.sourceID)
    }

    // MARK: Title logos (#15 Part 9)

    /// The title-logo pictures to try for a movie page (`item-N`) or a show page (`series-N`), strongest source first: a
    /// local file next to the media, then the matched title's online logos (only when online lookup has a key; the online
    /// candidates come ordered by `TitleLogoRules.ordered`). An episode uses its show's logos. Empty: the text title stays.
    public func logoCandidates(key text: String, userLanguage: String?) async -> [LogoCandidate] {
        guard let key = ArtworkKey(text) else { return [] }
        var out: [LogoCandidate] = []
        do {
            switch key {
            case .item(let id):
                guard let item = try await store.item(id: id) else { return [] }
                if item.kind == .episode, let seriesID = item.seriesID {
                    return await logoCandidates(key: "series-\(seriesID)", userLanguage: userLanguage)
                }
                let versions = try await store.versions(of: id)
                if let file = versions.first(where: { $0.id == item.preferredFileID }) ?? versions.first {
                    let entries = try await folderEntries(sourceID: file.sourceID, folder: file.parentPath)
                    let videos = entries.filter { !$0.isDirectory && FileClassifier.fileExtension(of: $0.name).isVideoExtension }.count
                    let found = SidecarImageFinder.images(forMovie: file.name, in: entries, folderHoldsOneVideo: videos <= 1)
                    if let hit = found.logo, let r = await cached(hit, file.sourceID) { out.append(LogoCandidate(source: .localFile, location: r)) }
                }
                if let online, let set = await online.images(forItem: item) {
                    out += await onlineLogos(set, online, userLanguage)
                }
            case .series(let seriesID):
                if let hit = try await showFolderEntry(seriesID: seriesID, role: .logo), let r = await cached(hit.entry, hit.sourceID) {
                    out.append(LogoCandidate(source: .localFile, location: r))
                }
                if let online, let tmdbID = try await seriesOnlineID(seriesID), let set = await online.images(forSeriesID: tmdbID) {
                    out += await onlineLogos(set, online, userLanguage)
                }
            case .remote:
                return []
            }
        } catch {
            return out
        }
        return out
    }

    private func onlineLogos(_ set: ImageSet, _ online: any OnlineArtworkProviding, _ language: String?) async -> [LogoCandidate] {
        var out: [LogoCandidate] = []
        for ref in TitleLogoRules.ordered(set.logos, userLanguage: language) {
            if let url = await online.logoURL(path: ref.path) { out.append(LogoCandidate(source: .online, location: .remote(url))) }
        }
        return out
    }

    /// The online id most of a series' episodes carry, or nil.
    private func seriesOnlineID(_ seriesID: Int64) async throws -> Int? {
        let ids = try await store.episodes(ofSeries: seriesID).compactMap(\.tmdbID)
        let counts = Dictionary(grouping: ids, by: { $0 }).mapValues(\.count)
        return counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key
    }

    /// A picture of `role` in the show folder (the folder above the season folders), with its source.
    private func showFolderEntry(seriesID: Int64, role: SidecarImageRole) async throws -> (entry: SourceEntry, sourceID: String)? {
        guard let first = try await store.episodes(ofSeries: seriesID).first, let file = try await store.versions(of: first.id).first else { return nil }
        var folder = file.parentPath
        let last = String(folder.split(separator: "/").last ?? "")
        if SidecarImageFinder.seasonNumber(ofFolder: last) != nil {
            folder = Self.parent(of: folder)
        }
        let entries = try await folderEntries(sourceID: file.sourceID, folder: folder)
        guard let hit = SidecarImageFinder.images(forShowFolder: entries)[role] else { return nil }
        return (hit, file.sourceID)
    }

    // MARK: Helpers

    /// The artwork cache key of a picture read from a source. The iCloud backup uses the same function to tell which cached
    /// pictures belong to files the index still holds (docs/BACKUP.md), so the two can never disagree.
    public static func sidecarCacheKey(sourceID: String, path: String, size: Int64?, modified: Date?, etag: String?) -> String {
        "sidecar|\(sourceID)|\(path)|\(size ?? -1)|\(Int(modified?.timeIntervalSince1970 ?? 0))|\(etag ?? "")"
    }

    static func parent(of path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }

    private func folderEntries(sourceID: String, folder: String) async throws -> [SourceEntry] {
        let children = try await store.children(sourceID: sourceID, folder: folder, sort: FileSort(), limit: 2_000, offset: 0)
        return children.map { SourceEntry(path: $0.path, name: $0.name, isDirectory: $0.isDirectory, size: $0.size, modified: $0.modified) }
    }

    /// The cached copy of a sidecar picture, reading it from the source when it is not cached yet. A changed file (size or date)
    /// has a different cache key, so a replaced poster shows up; the old copy ages out of the size-limited cache.
    private func cached(_ entry: SourceEntry, _ sourceID: String) async -> ArtworkResult? {
        let key = Self.sidecarCacheKey(sourceID: sourceID, path: entry.path, size: entry.size, modified: entry.modified, etag: entry.etag)
        if let url = cache.url(forKey: key) { return .file(url) }
        if let size = entry.size, size > Self.maxSidecarBytes { return nil }
        guard let data = try? await reader.read(sourceID: sourceID, path: entry.path, maxBytes: Self.maxSidecarBytes), !data.isEmpty,
              data.count <= Self.maxSidecarBytes, let url = try? cache.store(data, key: key) else { return nil }
        return .file(url)
    }
}

private extension String {
    var isVideoExtension: Bool { FileClassifier.videoExtensions.contains(self) }
}
