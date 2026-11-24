import Foundation
import VideoPlayerCore
import LibraryIndex

// Detail page of one movie or episode: facts, the Play button, the versions of the file and the files that belong with it.

public struct VersionRow: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var detail: String?
    public var isPreferred: Bool

    /// #33 J: the Versions menu item, each fact once. The title (from the file name: "2160p · BluRay · HDR10 · HEVC") and
    /// the detail (from the file: "2160p · HEVC · HDR10 · … · 4.2 GB") repeated the resolution, codec and HDR, which made the
    /// item too long for the menu ("…"). Facts of the detail that the title already has (same text, ignoring case, or the
    /// same codec under another name) are left out.
    public var label: String {
        let titleParts: [String] = title.components(separatedBy: " · ")
        let known: Set<String> = Set(titleParts.map(Self.key))
        let extra: [String] = (detail ?? "").components(separatedBy: " · ").filter { !$0.isEmpty && !known.contains(Self.key($0)) }
        return extra.isEmpty ? title : title + " · " + extra.joined(separator: " · ")
    }

    /// One spelling per fact: case folded, and the codec aliases a file name uses for the names the file reports.
    static func key(_ fact: String) -> String {
        let folded: String = fact.lowercased().trimmingCharacters(in: .whitespaces)
        let aliases: [String: String] = ["x265": "hevc", "h265": "hevc", "h.265": "hevc", "x264": "avc", "h264": "avc", "h.264": "avc",
                                         "4k": "2160p", "uhd": "2160p"]
        return aliases[folded] ?? folded
    }
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
    /// "2020 · 1 h 52 min · ★ 7.8", or "41 min · ★ 7.8" for an episode (R387: its code is `episodeCode`, its own line).
    public var facts: String
    /// R370: the headline badges of the metadata line (resolution, HDR, audio format).
    public var badges: [FormatBadgeItem]
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
    /// R370: every badge of the preferred file, for the top of Information.
    public var allBadges: [FormatBadgeItem] = []
    /// R387: an episode's "S1, E3" (R358's form), the line above its title; nil for a movie or without numbers.
    public var episodeCode: String? = nil
    /// R387: an episode's season number, to find the row of the season's other episodes.
    public var season: Int? = nil
    /// R396 (audit E1): an episode's OWN title, the page's large title ("A quiet beginning"; "Episode 3" when the file
    /// names none). `title` is the card's title, which for an episode is its show's name. Nil for a movie.
    public var episodeTitle: String? = nil
    /// R453: the runtime as its own part of the typed metadata line ("1 h 52 min"); nil when unknown.
    public var runtimeText: String? = nil
    /// R453: the library's year (movies), shown alone only when no full date is known.
    public var year: Int? = nil
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

    /// R370: the page's badges are the preferred file's (`FormatBadges.all`), each group with its Information row; with no
    /// facts for that file, what the library item knows (resolution, HDR, Dolby Atmos) and its best channel layout.
    static func badges(item: LibraryItem, file: StoredFile?) -> (headline: [FormatBadgeItem], all: [FormatBadgeItem]) {
        let all: [FormatBadgeItem]
        if let file, let technical = file.technical {
            let ext = (file.name as NSString).pathExtension
            all = FormatBadges.all(technical: technical, fileExtension: ext, maxChannels: item.maxChannels)
        } else {
            all = FormatBadges.item(item) + [FormatBadges.channels(item.maxChannels)].compactMap { $0 }
        }
        return (FormatBadges.headline(all), all)
    }

    static func content(_ item: LibraryItem, files: [StoredFile], sidecars: [StoredFile], sourceNames: [String: String] = [:],
                        tracks: FileTrackDetails? = nil) -> ItemDetailContent {
        let card = CardBuilder.card(item)
        var facts: [String] = []
        // R387: an episode's code is no longer the first fact; the page draws it as its own line above the title.
        let episodeCode = item.kind == .episode ? DisplayText.episodeCode(season: item.season, episode: item.episode, episodeEnd: item.episodeEnd) : nil
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
        // #33 J: Extras lists the information files only. Subtitle files belong to the player's Subtitles menu and pictures are
        // the item's artwork; neither is an "extra".
        let extras = sidecars.filter { $0.kind != .subtitle && $0.kind != .image }.map { s in
            ExtraRow(id: s.id, name: s.name, kindText: Self.kindText(s.kind), sizeText: s.size.map(DisplayText.fileSize))
        }
        var timeLeft: String?
        if let progress, let duration = item.watch.duration ?? item.runtime, duration > 0 {
            timeLeft = DisplayText.remaining(duration * (1 - progress))
        }
        let badges = Self.badges(item: item, file: files.first { $0.id == preferred })
        let mediaInfo = files.first { $0.id == preferred }.map { MediaInfo.rows(file: $0, sidecars: sidecars, sourceName: sourceNames[$0.sourceID], tracks: tracks) } ?? []
        return ItemDetailContent(itemID: item.id, kind: item.kind, title: card.title, seriesID: item.seriesID, seriesTitle: item.seriesTitle,
                                 facts: facts.joined(separator: " · "),
                                 badges: badges.headline,
                                 playTitle: playTitle, canStartOver: started,
                                 isWatched: item.watch.watched, isFavorite: item.watch.favorite, progress: progress, timeLeft: timeLeft,
                                 versions: versions, extras: extras, artworkKey: card.artworkKey, mediaInfo: mediaInfo,
                                 allBadges: badges.all, episodeCode: episodeCode, season: item.kind == .episode ? item.season : nil,
                                 episodeTitle: Self.episodeTitle(item),
                                 runtimeText: (item.runtime ?? item.watch.duration).flatMap { $0 > 0 ? DisplayText.runtime($0) : nil },
                                 year: item.kind == .movie ? item.year.flatMap { $0 > 0 ? $0 : nil } : nil)
    }

    /// R396 (audit E1): the episode's own name; "Episode 3" when its title is empty, only its code or its show's name;
    /// nil for a movie, or for an episode with neither a name nor a number.
    static func episodeTitle(_ item: LibraryItem) -> String? {
        guard item.kind == .episode else { return nil }
        if CardBuilder.episodeTitleIsReal(item) { return item.title.trimmingCharacters(in: .whitespaces) }
        if let number = item.episode { return "Episode \(number)" }
        return nil
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
