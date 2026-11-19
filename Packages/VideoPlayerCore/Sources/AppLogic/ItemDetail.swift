import Foundation
import VideoPlayerCore
import LibraryIndex

// Detail page of one movie or episode: facts, the Play button, the versions of the file and the files that belong with it.

public struct VersionRow: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var detail: String?
    public var isPreferred: Bool
}

public struct ExtraRow: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var kindText: String
    public var sizeText: String?
}

public struct ItemDetailContent: Equatable, Sendable {
    public var itemID: Int64
    public var kind: ItemKind
    public var title: String
    public var seriesID: Int64?
    public var seriesTitle: String?
    /// "2020 · 1 h 52 min · ★ 7.8", or "S2 E4 · 41 min".
    public var facts: String
    public var badges: [String]
    public var playTitle: String
    public var canStartOver: Bool
    public var isWatched: Bool
    public var isFavorite: Bool
    public var progress: Double?
    /// #15 D3: the detail page says how much is left ("40 min left") instead of a full-width bar. Nil when not started.
    public var timeLeft: String? = nil
    public var versions: [VersionRow]
    public var extras: [ExtraRow]
    public var artworkKey: String
    /// #15 6.2: what the preferred file contains, always fully shown. Empty when the title has no file.
    public var mediaInfo: [MediaInfoRow] = []
}

public struct ItemDetailViewModel: Sendable {
    public let store: any LibraryStore
    public let itemID: Int64
    public private(set) var state: ViewState<ItemDetailContent> = .idle
    /// Reads the preferred file's header for Media Info (#21 C, `MediaTrackProbe`). Nil: the rows keep what the index has.
    public var trackReader: (@Sendable (StoredFile) async -> FileTrackDetails?)?
    /// The preferred file of the last load, so `loadTrackDetails` knows what to read.
    private var preferredFile: StoredFile?
    private var preferredSidecars: [StoredFile] = []
    private var preferredSourceName: String?

    public init(store: any LibraryStore, itemID: Int64, trackReader: (@Sendable (StoredFile) async -> FileTrackDetails?)? = nil) {
        self.store = store; self.itemID = itemID; self.trackReader = trackReader
    }

    public mutating func load() async {
        state = .loading
        do {
            guard let item = try await store.item(id: itemID) else {
                state = .empty(EmptyState(reason: .nothingIndexed, title: "Not in Your Library", message: "This title is no longer in your library."))
                return
            }
            let files = try await store.versions(of: itemID)
            let preferred = item.preferredFileID ?? files.first?.id
            var sidecars: [StoredFile] = []
            if let preferred { sidecars = try await store.sidecars(for: preferred) }
            let sources = (try? await store.sources()) ?? []
            let sourceNames = Dictionary(sources.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            preferredFile = files.first { $0.id == preferred }
            preferredSidecars = sidecars
            preferredSourceName = preferredFile.flatMap { sourceNames[$0.sourceID] }
            // What an earlier visit read from the header (dropped when the file's size changed).
            var cached: FileTrackDetails?
            if let preferred { cached = (try? await store.trackDetails(fileID: preferred)) ?? nil }
            state = .loaded(Self.content(item, files: files, sidecars: sidecars, sourceNames: sourceNames, tracks: cached))
        } catch {
            state = .failed(ErrorState.from(error, doing: "load this title"))
        }
    }

    /// Reads the preferred file's header when nothing is cached yet (#21 C), keeps it in the index and rebuilds the page.
    /// Called after `load()`; a failed or slow read leaves the rows at "Not checked yet" (#25 B6).
    public mutating func loadTrackDetails() async {
        guard let file = preferredFile, let reader = trackReader, case .loaded(let content) = state else { return }
        let alreadyRead = (try? await store.trackDetails(fileID: file.id)) ?? nil
        if alreadyRead != nil { return }
        guard let details = await reader(file) else { return }
        try? await store.setTrackDetails(fileID: file.id, details)
        var updated = content
        updated.mediaInfo = MediaInfo.rows(file: file, sidecars: preferredSidecars, sourceName: preferredSourceName, tracks: details)
        state = .loaded(updated)
    }

    static func content(_ item: LibraryItem, files: [StoredFile], sidecars: [StoredFile], sourceNames: [String: String] = [:],
                        tracks: FileTrackDetails? = nil) -> ItemDetailContent {
        let card = CardBuilder.card(item)
        var facts: [String] = []
        if item.kind == .episode, let code = DisplayText.episodeCode(season: item.season, episode: item.episode, episodeEnd: item.episodeEnd) { facts.append(code) }
        if item.kind == .movie, let y = item.year, y > 0 { facts.append(String(y)) }
        if let r = item.runtime ?? item.watch.duration, r > 0 { facts.append(DisplayText.runtime(r)) }
        if let rating = item.rating, rating > 0 { facts.append("★ " + String(format: "%.1f", rating)) }
        let progress = CardBuilder.progressFraction(item)
        let started = progress != nil
        let playTitle = started ? "Resume" : (item.watch.watched ? "Play Again" : "Play")
        let preferred = item.preferredFileID ?? files.first?.id
        let versions = files.map { f -> VersionRow in
            var parts: [String] = []
            if let t = f.technical {
                // Real format names (docs/NAMES.md): "HEVC · Dolby Vision Profile 8 / HDR10 · Dolby TrueHD with Dolby Atmos 7.1".
                if let h = t.height { parts.append("\(h)p") }
                if let c = t.videoCodec { parts.append(FormatNames.videoCodec(c)) }
                if let hdr = FormatNames.hdr(t.hdrFormats, dolbyVisionProfile: t.dolbyVisionProfile) { parts.append(hdr) }
                if let audio = FormatNames.audio(codec: t.audioCodec, channels: t.audioChannels, atmos: t.hasAtmos) { parts.append(audio) }
            }
            if let s = f.size { parts.append(DisplayText.fileSize(s)) }
            return VersionRow(id: f.id, title: f.versionLabel ?? f.name, detail: parts.isEmpty ? nil : parts.joined(separator: " · "), isPreferred: f.id == preferred)
        }
        let extras = sidecars.map { s in
            ExtraRow(id: s.id, name: s.name, kindText: Self.kindText(s.kind), sizeText: s.size.map(DisplayText.fileSize))
        }
        var timeLeft: String?
        if let progress, let duration = item.watch.duration ?? item.runtime, duration > 0 {
            timeLeft = DisplayText.remaining(duration * (1 - progress))
        }
        let mediaInfo = files.first { $0.id == preferred }.map { MediaInfo.rows(file: $0, sidecars: sidecars, sourceName: sourceNames[$0.sourceID], tracks: tracks) } ?? []
        return ItemDetailContent(itemID: item.id, kind: item.kind, title: card.title, seriesID: item.seriesID, seriesTitle: item.seriesTitle,
                                 facts: facts.joined(separator: " · "), badges: card.badges, playTitle: playTitle, canStartOver: started,
                                 isWatched: item.watch.watched, isFavorite: item.watch.favorite, progress: progress, timeLeft: timeLeft,
                                 versions: versions, extras: extras, artworkKey: card.artworkKey, mediaInfo: mediaInfo)
    }

    static func kindText(_ kind: FileKind) -> String {
        switch kind {
        case .subtitle: return "Subtitles"
        case .image: return "Artwork"
        case .nfo: return "Information"
        case .video: return "Video"
        case .directory: return "Folder"
        case .other: return "File"
        }
    }

    public mutating func setWatched(_ watched: Bool) async {
        do { try await store.markWatched(itemIDs: [itemID], watched: watched, at: Date()) } catch { return }
        await load()
    }

    public mutating func toggleFavorite() async {
        guard case .loaded(let c) = state else { return }
        do { try await store.setFavorite(itemID: itemID, favorite: !c.isFavorite) } catch { return }
        await load()
    }

    public mutating func choosePreferredVersion(_ fileID: Int64) async {
        do { try await store.setPreferredVersion(itemID: itemID, fileID: fileID) } catch { return }
        await load()
    }
}
