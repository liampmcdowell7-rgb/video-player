import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal
import MetadataOnline
import UserData

// Artwork for the library cards (docs/ARTWORK_DISCOVER.md). Precedence, strongest first (docs/METADATA.md, "local sidecar
// data wins over online data"):
//   1. a picture next to the video on the source (poster / folder / cover ..., chosen by `SidecarImageFinder`);
//   2. for a Plex source only (R270, R307), the server's own poster or episode still, read once and cached;
//   3. the poster of the title the metadata matcher found online, as a web address (nothing is downloaded here);
//   3. nothing: the card keeps its placeholder symbol.
// Everything is read from the library index, so browsing never waits on a server for the folder listing.

public enum ArtworkKey: Equatable, Sendable {
    case item(Int64)
    case series(Int64)
    /// R471 (22): one season of a show: "season-<seriesID>-<number>" (0 is Specials).
    case season(seriesID: Int64, number: Int)
    /// A poster path from TMDB (Discover cards): "remote:/abc.jpg".
    case remote(String)

    /// R471 (22): the key of one season's poster.
    public static func seasonKey(seriesID: Int64, number: Int) -> String { "season-" + String(seriesID) + "-" + String(number) }

    public init?(_ text: String) {
        if text.hasPrefix("item-"), let id = Int64(text.dropFirst(5)) { self = .item(id); return }
        if text.hasPrefix("series-"), let id = Int64(text.dropFirst(7)) { self = .series(id); return }
        if text.hasPrefix("season-") {
            let parts = text.dropFirst(7).split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, let id = Int64(parts[0]), let number = Int(parts[1]), number >= 0 else { return nil }
            self = .season(seriesID: id, number: number)
            return
        }
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
    /// Turns a backdrop path into an address (#15 6.2).
    func backdropURL(path: String) async -> URL?
    /// R455: the small picture of a gallery candidate (the kind's thumbnail size); the full size is fetched only for the choice.
    func thumbnailURL(path: String, kind: ArtworkGalleryKind) async -> URL?
    /// Synopsis and cast of the title a movie is already matched to (no new matching), or nil (#15 6.2).
    func details(forItem item: LibraryItem) async -> TitleDetails?
    /// Synopsis and cast of a series by its online id, or nil (#22 B, show page).
    func details(forSeriesID tmdbID: Int) async -> TitleDetails?
    /// R471 (22): one season of a series by its online id (its name, synopsis and poster path), or nil.
    func season(forSeriesID tmdbID: Int, number: Int) async -> SeasonMetadata?
}

public extension OnlineArtworkProviding {
    func images(forItem item: LibraryItem) async -> ImageSet? { nil }
    func images(forSeriesID tmdbID: Int) async -> ImageSet? { nil }
    func logoURL(path: String) async -> URL? { nil }
    func backdropURL(path: String) async -> URL? { nil }
    func thumbnailURL(path: String, kind: ArtworkGalleryKind) async -> URL? { nil }
    func details(forItem item: LibraryItem) async -> TitleDetails? { nil }
    func details(forSeriesID tmdbID: Int) async -> TitleDetails? { nil }
    func season(forSeriesID tmdbID: Int, number: Int) async -> SeasonMetadata? { nil }
}

/// One title-logo picture to try, in order (#15 9.2). The app decodes it and checks it with `TitleLogoRules.check`; the
/// first that passes is drawn, and with none the text title stays.
public struct LogoCandidate: Equatable, Sendable {
    public var source: TitleLogoSource
    /// `.file` (read from the source, cached) or `.remote` (fetched by the system image loader).
    public var location: ArtworkResult
    /// R455: the user's own choice. It is drawn without `TitleLogoRules.check` (the user looked at it in the gallery).
    public var isUserChoice: Bool = false
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
    private let server: (any ServerMetadataProviding)?
    /// R455: the user's artwork choices (the user layer), asked before every source.
    private let overrides: (any ArtworkOverriding)?
    /// R456: Metadata and Artwork > Prefer Local Artwork (on by default): a picture next to the media before the online one.
    private let preferLocalArtwork: @Sendable () -> Bool
    private let now: @Sendable () -> Date
    private var misses: [String: Date] = [:]
    /// R471 (75): the number of the newest lookup of each key still running (removed when it ends).
    private var lookups: [String: Int] = [:]
    /// Numbers never repeat, so a lookup still running is never mistaken for a later one of the same key.
    private var lastLookup = 0
    /// How long a "found nothing" answer is remembered, so scrolling past a title does not repeat the lookups. PROVISIONAL.
    public static let missMemory: TimeInterval = 15 * 60

    /// - Parameter server: the media server's own pictures (Plex, R307); asked only for files of a Plex source.
    public init(store: any LibraryStore, cache: ArtworkDiskCache, reader: any SidecarReading, online: (any OnlineArtworkProviding)?,
                server: (any ServerMetadataProviding)? = nil, overrides: (any ArtworkOverriding)? = nil,
                preferLocalArtwork: @escaping @Sendable () -> Bool = { true }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.preferLocalArtwork = preferLocalArtwork
        self.overrides = overrides
        self.store = store
        self.cache = cache
        self.reader = reader
        self.online = online
        self.server = server
        self.now = now
    }

    public func resolve(key text: String) async -> ArtworkResult {
        guard let key = ArtworkKey(text) else { return .none }
        // R455: the user's choice beats every source, so a rescan, Fix Match or an online refresh never replaces it.
        if let field = await overrideField(for: key), let chosen = await overrides?.override(key: text, field: field) { return chosen }
        if let at = misses[text], now().timeIntervalSince(at) < Self.missMemory { return .none }
        // R471 (75): only the newest lookup of a key records its answer; an older one that ends later (the engine is an
        // actor, so lookups of one key interleave at every wait) leaves what the newer one found.
        lastLookup += 1
        let lookup = lastLookup
        lookups[text] = lookup
        let result: ArtworkResult
        do {
            switch key {
            case .item(let id): result = try await resolveItem(id)
            case .series(let id): result = try await resolveSeries(id)
            case let .season(seriesID, number): result = try await resolveSeason(seriesID, number)
            case .remote(let path): result = await online?.imageURL(path: path).map { .remote($0) } ?? .none
            }
        } catch {
            result = .none
        }
        if lookups[text] == lookup {
            lookups[text] = nil
            if result == .none { misses[text] = now() } else { misses[text] = nil }
        }
        return result
    }

    /// R387: an episode's own picture only, the hero of the episode page: its still next to the file (thumb, then its own
    /// poster), then the media server's picture of the episode. Never the show folder's artwork or the show's online
    /// poster, which `resolve(key:)` falls back to for a card; with none, `.none` and the page uses the show's backdrop.
    /// `.none` for a movie or a series key.
    public func episodeStill(key text: String) async -> ArtworkResult {
        guard case .item(let id)? = ArtworkKey(text), let item = try? await store.item(id: id), item.kind == .episode else { return .none }
        if let chosen = await overrides?.override(key: text, field: .episodeStill) { return chosen }
        return (try? await resolveItem(id, stillOnly: true)) ?? .none
    }

    // MARK: Items

    private func resolveItem(_ id: Int64, stillOnly: Bool = false) async throws -> ArtworkResult {
        guard let item = try await store.item(id: id) else { return .none }
        let versions = try await store.versions(of: id)
        let file = versions.first { $0.id == item.preferredFileID } ?? versions.first
        // R456: with Prefer Local Artwork off, a movie's online poster comes before the picture next to the file.
        if !preferLocalArtwork(), !stillOnly, item.kind == .movie, let url = await online?.posterURL(forItem: item, file: file) { return .remote(url) }
        if let file {
            let entries = try await folderEntries(sourceID: file.sourceID, folder: file.parentPath)
            if item.kind == .movie {
                let videos = entries.filter { !$0.isDirectory && FileClassifier.fileExtension(of: $0.name).isVideoExtension }.count
                let found = SidecarImageFinder.images(forMovie: file.name, in: entries, folderHoldsOneVideo: videos <= 1)
                if let hit = found.poster, let r = await cached(hit, file.sourceID) { return r }
            } else {
                let found = SidecarImageFinder.images(forEpisode: file.name, in: entries)
                if let hit = found.thumb ?? found.poster, let r = await cached(hit, file.sourceID) { return r }
                if !stillOnly, let seriesID = item.seriesID, let r = try await showFolderArtwork(seriesID: seriesID) { return r }
            }
        }
        if let server, let serverFile = await ServerMetadataKinds.file(forItem: item, store: store),
           let picture = await server.poster(for: serverFile), let r = await cached(picture) { return r }
        // R387: an episode's online "poster" is its show's poster (TMDBArtworkProvider asks by the series), not a still.
        if stillOnly { return .none }
        if let url = await online?.posterURL(forItem: item, file: file) { return .remote(url) }
        return .none
    }

    /// A media server's picture through the same cache as sidecars (its key changes when the server's picture changes).
    private func cached(_ picture: ServerPicture) async -> ArtworkResult? {
        let key = Self.serverCacheKey(picture.cacheKey)
        if let url = cache.url(forKey: key) { return .file(url) }
        guard let data = try? await picture.fetch(Self.maxSidecarBytes), !data.isEmpty, data.count <= Self.maxSidecarBytes,
              let url = try? cache.store(data, key: key) else { return nil }
        return .file(url)
    }

    // MARK: Series

    private func resolveSeries(_ seriesID: Int64) async throws -> ArtworkResult {
        // R457: with Prefer Local Artwork off the online poster of a show comes before the picture in the show folder.
        if !preferLocalArtwork(), let url = try await onlineSeriesPoster(seriesID) { return .remote(url) }
        if let r = try await showFolderArtwork(seriesID: seriesID) { return r }
        if let url = try await onlineSeriesPoster(seriesID) { return .remote(url) }
        return .none
    }

    private func onlineSeriesPoster(_ seriesID: Int64) async throws -> URL? {
        guard let online else { return nil }
        let episodes = try await store.episodes(ofSeries: seriesID)
        let ids = episodes.compactMap(\.tmdbID)
        if ids.isEmpty {
            // No online id yet: ask the matcher through one episode, which also records the id for next time.
            guard let first = episodes.first else { return nil }
            let file = try await store.versions(of: first.id).first
            return await online.posterURL(forItem: first, file: file)
        }
        let counts = Dictionary(grouping: ids, by: { $0 }).mapValues(\.count)
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else { return nil }
        return await online.posterURL(forSeriesID: best)
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

    // MARK: Seasons (R471 (22))

    /// A season's poster: the picture for that season next to the media (`SidecarImageFinder.images(forSeason:)`: in the show
    /// folder, then in the season's own folder), then the season's online poster. With Prefer Local Artwork off, the online
    /// one first (as R457 does for a show). No fallback to the show's poster: the page shows the season's text without one.
    private func resolveSeason(_ seriesID: Int64, _ number: Int) async throws -> ArtworkResult {
        if !preferLocalArtwork(), let url = try await onlineSeasonPoster(seriesID, number) { return .remote(url) }
        if let hit = try await seasonFolderEntry(seriesID: seriesID, season: number, role: .poster),
           let r = await cached(hit.entry, hit.sourceID) { return r }
        if let url = try await onlineSeasonPoster(seriesID, number) { return .remote(url) }
        return .none
    }

    private func onlineSeasonPoster(_ seriesID: Int64, _ number: Int) async throws -> URL? {
        guard let online, let tmdbID = try await seriesOnlineID(seriesID),
              let path = await online.season(forSeriesID: tmdbID, number: number)?.posterPath else { return nil }
        return await online.imageURL(path: path)
    }

    /// A picture of `role` for one season. The folder of the season's first episode is the season folder when it is named
    /// like one (the show folder is the one above it); otherwise it is the show folder itself.
    private func seasonFolderEntry(seriesID: Int64, season: Int, role: SidecarImageRole) async throws -> (entry: SourceEntry, sourceID: String)? {
        let episodes = try await store.episodes(ofSeries: seriesID)
        guard let episode = episodes.first(where: { $0.season == season }),
              let file = try await store.versions(of: episode.id).first else { return nil }
        let folder = file.parentPath
        let last = String(folder.split(separator: "/").last ?? "")
        var showFolder = folder
        var seasonEntries: [SourceEntry]?
        if SidecarImageFinder.seasonNumber(ofFolder: last) != nil {
            showFolder = Self.parent(of: folder)
            seasonEntries = try await folderEntries(sourceID: file.sourceID, folder: folder)
        }
        let showEntries = try await folderEntries(sourceID: file.sourceID, folder: showFolder)
        guard let hit = SidecarImageFinder.images(forSeason: season, showFolder: showEntries, seasonFolder: seasonEntries)[role] else { return nil }
        return (hit, file.sourceID)
    }

    /// R471 (22): a season's own name and synopsis online (nil without online lookup or a match). The page puts the user's
    /// edits on top (`SeasonHeader.make`).
    public func season(key text: String) async -> SeasonMetadata? {
        guard let online, case let .season(seriesID, number)? = ArtworkKey(text),
              let tmdbID = try? await seriesOnlineID(seriesID) else { return nil }
        return await online.season(forSeriesID: tmdbID, number: number)
    }

    // MARK: Title logos (#15 Part 9)

    /// The title-logo pictures to try for a movie page (`item-N`) or a show page (`series-N`), strongest source first: a
    /// local file next to the media, then the matched title's online logos (only when online lookup has a key; the online
    /// candidates come ordered by `TitleLogoRules.ordered`). An episode uses its show's logos. Empty: the text title stays.
    public func logoCandidates(key text: String, userLanguage: String?) async -> [LogoCandidate] {
        guard let key = ArtworkKey(text) else { return [] }
        var out: [LogoCandidate] = []
        if let chosen = await overrides?.override(key: text, field: .logo) { return [LogoCandidate(source: .localFile, location: chosen, isUserChoice: true)] }
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
            case .remote, .season:
                return []
            }
        } catch {
            return Self.ordered(out, preferLocal: preferLocalArtwork())
        }
        return Self.ordered(out, preferLocal: preferLocalArtwork())
    }

    /// R457: the logo candidates in the order of Prefer Local Artwork: local files first (on) or online first (off); each group
    /// keeps its own order. The user's own choice never gets here (it returns alone, first).
    static func ordered(_ candidates: [LogoCandidate], preferLocal: Bool) -> [LogoCandidate] {
        let local = candidates.filter { $0.source == .localFile }, other = candidates.filter { $0.source != .localFile }
        return preferLocal ? local + other : other + local
    }

    // MARK: Backdrops and details (#15 6.2)

    /// The wide picture behind a movie page (`item-N`) or a show page (`series-N`): a fan-art picture next to the media first
    /// (`fanart`, `backdrop`, `background`, chosen by `SidecarImageFinder`), then the matched title's best online backdrop
    /// (only with a key). An episode uses its show's. `.none`: the page keeps its plain background.
    public func backdrop(key text: String, userLanguage: String?) async -> ArtworkResult {
        guard let key = ArtworkKey(text) else { return .none }
        if let chosen = await overrides?.override(key: text, field: .backdrop) { return chosen }
        do {
            switch key {
            case .item(let id):
                guard let item = try await store.item(id: id) else { return .none }
                if item.kind == .episode, let seriesID = item.seriesID {
                    return await backdrop(key: "series-\(seriesID)", userLanguage: userLanguage)
                }
                let versions = try await store.versions(of: id)
                // R457: with Prefer Local Artwork off the online backdrop comes before the picture next to the file.
                if !preferLocalArtwork(), let online, let set = await online.images(forItem: item), let ref = set.bestBackdrop(language: userLanguage),
                   let url = await online.backdropURL(path: ref.path) {
                    return .remote(url)
                }
                if let file = versions.first(where: { $0.id == item.preferredFileID }) ?? versions.first {
                    let entries = try await folderEntries(sourceID: file.sourceID, folder: file.parentPath)
                    let videos = entries.filter { !$0.isDirectory && FileClassifier.fileExtension(of: $0.name).isVideoExtension }.count
                    let found = SidecarImageFinder.images(forMovie: file.name, in: entries, folderHoldsOneVideo: videos <= 1)
                    if let hit = found.backdrop, let r = await cached(hit, file.sourceID) { return r }
                }
                if let online, let set = await online.images(forItem: item), let ref = set.bestBackdrop(language: userLanguage),
                   let url = await online.backdropURL(path: ref.path) {
                    return .remote(url)
                }
            case .series(let seriesID):
                if !preferLocalArtwork(), let online, let tmdbID = try await seriesOnlineID(seriesID), let set = await online.images(forSeriesID: tmdbID),
                   let ref = set.bestBackdrop(language: userLanguage), let url = await online.backdropURL(path: ref.path) {
                    return .remote(url)
                }
                if let hit = try await showFolderEntry(seriesID: seriesID, role: .backdrop), let r = await cached(hit.entry, hit.sourceID) {
                    return r
                }
                if let online, let tmdbID = try await seriesOnlineID(seriesID), let set = await online.images(forSeriesID: tmdbID),
                   let ref = set.bestBackdrop(language: userLanguage), let url = await online.backdropURL(path: ref.path) {
                    return .remote(url)
                }
            case .remote, .season:
                return .none
            }
        } catch {
            return .none
        }
        return .none
    }

    /// Synopsis and cast for a movie page ("item-N") or a show page ("series-N", #22 B), from the online details of the matched
    /// title. Nil without a key, without a match, for an episode page, or when both are empty (the page then shows no band).
    public func details(key text: String) async -> TitleDetails? {
        guard let online else { return nil }
        let found: TitleDetails?
        switch ArtworkKey(text) {
        case .item(let id)?:
            guard let item = try? await store.item(id: id), item.kind == .movie else { return nil }
            found = await online.details(forItem: item)
        case .series(let seriesID)?:
            guard let tmdbID = try? await seriesOnlineID(seriesID) else { return nil }
            found = await online.details(forSeriesID: tmdbID)
        default:
            return nil
        }
        guard let found, !found.isEmpty else { return nil }
        return found
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

    /// R455: the field a card's key is edited under: a movie or show poster; an episode card shows the still.
    private func overrideField(for key: ArtworkKey) async -> UDEditField? {
        switch key {
        case .series: return .poster
        case .item(let id):
            guard let item = try? await store.item(id: id) else { return nil }
            return item.kind == .episode ? .episodeStill : .poster
        case .remote: return nil
        case .season: return .seasonPoster
        }
    }

    // MARK: Helpers

    /// The artwork cache key of a picture read from a source. The iCloud backup uses the same function to tell which cached
    /// pictures belong to files the index still holds (docs/BACKUP.md), so the two can never disagree.
    /// The disk-cache key of a media server's picture (R383: also read by `UpNextPreview.cachedStill`).
    public static func serverCacheKey(_ pictureKey: String) -> String { "server|" + pictureKey }

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

// MARK: Gallery candidates (R455)

public extension ArtworkEngine {
    /// The candidates of one kind for the item or show behind `key`, in the gallery's order: online (only when `onlineOn`),
    /// From Your Files, From the Server. The "Web Address" candidate is typed by the user and is not listed here. Nothing is
    /// fetched except small lists the title details already hold; pictures are fetched by the screen, thumbnails only.
    func gallery(key text: String, kind: ArtworkGalleryKind, userLanguage: String?, onlineOn: Bool) async -> ArtworkGallery {
        var found: [ArtworkCandidate] = []
        if onlineOn, let set = await onlineImageSet(key: text) {
            found += ArtworkCandidates.online(set, kind: kind)
        }
        found += await localCandidates(key: text, kind: kind)
        return ArtworkGallery(kind: kind, candidates: ArtworkCandidates.sorted(found, userLanguage: userLanguage), onlineSwitchOff: !onlineOn)
    }

    /// The thumbnail address of an online candidate (small size); nil without an online provider.
    func thumbnailURL(path: String, kind: ArtworkGalleryKind) async -> URL? {
        await online?.thumbnailURL(path: path, kind: kind)
    }

    /// The full-size address of an online candidate, fetched only for the chosen picture.
    func fullURL(path: String, kind: ArtworkGalleryKind) async -> URL? {
        switch kind {
        case .poster, .seasonPoster: return await online?.imageURL(path: path)
        case .background, .episodeStill: return await online?.backdropURL(path: path)
        case .logo: return await online?.logoURL(path: path)
        }
    }

    /// The cached file of a candidate that is not online (From Your Files, From the Server), for its thumbnail and for the copy
    /// that is stored when it is chosen. Reads the picture once, through the artwork cache.
    func localPicture(_ candidate: ArtworkCandidate, key text: String) async -> ArtworkResult {
        switch candidate.origin {
        case .online: return .none
        case let .yourFile(sourceID, path):
            let entry = SourceEntry(path: path, name: String(path.split(separator: "/").last ?? ""), isDirectory: false, size: nil, modified: nil)
            return await cached(entry, sourceID) ?? .none
        case .server:
            guard let server, case .item(let id)? = ArtworkKey(text), let item = try? await store.item(id: id),
                  let serverFile = await ServerMetadataKinds.file(forItem: item, store: store),
                  let picture = await server.poster(for: serverFile) else { return .none }
            return await cached(picture) ?? .none
        }
    }

    private func onlineImageSet(key text: String) async -> ImageSet? {
        guard let online, let key = ArtworkKey(text) else { return nil }
        switch key {
        case .item(let id):
            guard let item = try? await store.item(id: id) else { return nil }
            return await online.images(forItem: item)
        case .series(let seriesID):
            guard let tmdbID = try? await seriesOnlineID(seriesID) else { return nil }
            return await online.images(forSeriesID: tmdbID)
        case .remote, .season: return nil
        }
    }

    private func localCandidates(key text: String, kind: ArtworkGalleryKind) async -> [ArtworkCandidate] {
        guard let key = ArtworkKey(text) else { return [] }
        var out: [ArtworkCandidate] = []
        let role: SidecarImageRole
        switch kind {
        case .poster, .seasonPoster: role = .poster
        case .background: role = .backdrop
        case .logo: role = .logo
        case .episodeStill: role = .thumb
        }
        do {
            switch key {
            case .item(let id):
                guard let item = try await store.item(id: id) else { return [] }
                let versions = try await store.versions(of: id)
                guard let file = versions.first(where: { $0.id == item.preferredFileID }) ?? versions.first else { return [] }
                let entries = try await folderEntries(sourceID: file.sourceID, folder: file.parentPath)
                let found: SidecarImages
                if item.kind == .movie {
                    let videos = entries.filter { !$0.isDirectory && FileClassifier.fileExtension(of: $0.name).isVideoExtension }.count
                    found = SidecarImageFinder.images(forMovie: file.name, in: entries, folderHoldsOneVideo: videos <= 1)
                } else {
                    found = SidecarImageFinder.images(forEpisode: file.name, in: entries)
                }
                if let hit = found[role] { out.append(ArtworkCandidate(source: .yourFiles, origin: .yourFile(sourceID: file.sourceID, path: hit.path))) }
                if let server, let serverFile = await ServerMetadataKinds.file(forItem: item, store: store),
                   kind == .poster || kind == .episodeStill, let picture = await server.poster(for: serverFile) {
                    out.append(ArtworkCandidate(source: .server, origin: .server(picture.cacheKey)))
                }
            case .series(let seriesID):
                if let hit = try await showFolderEntry(seriesID: seriesID, role: role) {
                    out.append(ArtworkCandidate(source: .yourFiles, origin: .yourFile(sourceID: hit.sourceID, path: hit.entry.path)))
                }
            case let .season(seriesID, number):
                // R471 (22): the season's own picture next to the media.
                if kind == .seasonPoster, let hit = try await seasonFolderEntry(seriesID: seriesID, season: number, role: .poster) {
                    out.append(ArtworkCandidate(source: .yourFiles, origin: .yourFile(sourceID: hit.sourceID, path: hit.entry.path)))
                }
            case .remote: break
            }
        } catch {
            return out
        }
        return out
    }
}
