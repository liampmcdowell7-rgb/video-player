import Foundation
import VideoPlayerCore

/// Which rule put a file where it is. Stored in the index and shown in the item info; never rename a raw value.
public enum SortSignal: String, Sendable, CaseIterable {
    /// a. A clear episode pattern in the file name (S01E02, 1x02, "Season 1 Episode 2", a date after the show name,
    /// or "Show - 012" when other files of the same show are in the folder).
    case episodePattern
    /// b. A clear movie pattern: a year and no episode pattern.
    case moviePattern
    /// c. A folder hint broke the tie (a season folder, other files of the same show, a folder named with a year).
    case folderHint
    /// d. The TMDB title search (own key, online lookup on) said movie or show with confidence 0.8 or more.
    case onlineLookup
    /// The media server's item type (Jellyfin, Emby), where the file name was not clear.
    case serverType
    /// The media server's item type contradicted a clear file name; the file name won.
    case filenameOverServer
    /// "Move to Movies" / "Move to Shows".
    case manual
    /// e. Nothing decided: the file is in Needs Review.
    case undecided
}

public enum SortOutcome: String, Equatable, Sendable {
    case movie, episode, needsReview
}

/// The other video files in one folder, read once per folder listing (sorting never depends on the folder layout
/// alone: this is about files, wherever they sit).
public struct SiblingIndex: Equatable, Sendable {
    /// Show key -> number of files in the folder with that show name and an episode marker.
    var marked: [String: Int] = [:]

    public init(names: [String] = []) {
        for name in names {
            let p = FilenameParser.parse(fileName: name)
            guard let marker = p.episodeMarker, marker != .seasonOnly else { continue }
            let key = MediaSorter.showKey(p.title)
            if !key.isEmpty { marked[key, default: 0] += 1 }
        }
    }

    /// Files in the folder other than this one that have this show name and an episode marker.
    func others(showKey key: String, selfMarked: Bool) -> Int {
        guard !key.isEmpty else { return 0 }
        return max(0, (marked[key] ?? 0) - (selfMarked ? 1 : 0))
    }
}

public struct SortContext: Equatable, Sendable {
    /// Ancestor folder names, nearest first.
    public var folders: [String]
    public var siblings: SiblingIndex
    public var serverType: ServerItemType?
    /// The source setting "Sort by filename instead of server library types" (PROVISIONAL, default off).
    public var preferFilename: Bool

    public init(folders: [String] = [], siblings: SiblingIndex = SiblingIndex(), serverType: ServerItemType? = nil, preferFilename: Bool = false) {
        self.folders = folders
        self.siblings = siblings
        self.serverType = serverType
        self.preferFilename = preferFilename
    }
}

public struct SortDecision: Equatable, Sendable {
    public var outcome: SortOutcome
    public var signal: SortSignal
    /// The parsed name as it will be filed (kind, title, season and episode numbers already final).
    public var parsed: ParsedMedia
    /// One plain sentence for the item info and the log.
    public var note: String
}

/// Decides, file by file, whether a video is a movie, an episode, or needs review (docs/SORTING.md). Signals in order:
/// a. clear episode pattern, b. clear movie pattern, c. folder hints as a tie-breaker; d. (the online check) and manual
/// overrides are applied by the caller; e. anything left is Needs Review. A media server's item type is used where the
/// file name is not clear.
public enum MediaSorter {
    /// Raised when the rules change, so files sorted by older rules are sorted again on the next scan.
    public static let revision = 2

    public static let filenameOverServerNote = "Sorted by filename, not by the server."

    /// The show name as a grouping key: case, accents, dots, underscores and punctuation ignored. Release tags are already
    /// cut from the title by the parser.
    public static func showKey(_ title: String) -> String { LibraryText.normalize(title) }

    public static func decide(fileName: String, context c: SortContext) -> SortDecision {
        let byName = byFileName(fileName, c)
        guard let server = c.serverType, !c.preferFilename else { return byName }
        let serverOutcome: SortOutcome = server == .movie ? .movie : .episode
        let clear = byName.signal == .episodePattern || byName.signal == .moviePattern
        if byName.outcome == serverOutcome {
            var d = byName
            d.signal = .serverType
            d.note = "The server says \(server == .movie ? "movie" : "episode"), and the file name agrees."
            return d
        }
        if clear {
            var d = byName
            d.signal = .filenameOverServer
            d.note = filenameOverServerNote + " The server says \(server == .movie ? "movie" : "episode"); " + lowerFirst(byName.note)
            return d
        }
        // The file name is not clear: the server's type decides, if the file can be filed that way.
        if server == .movie {
            var p = FilenameParser.parse(fileName: fileName, folders: c.folders, weakMarkers: false)
            p.kind = .movie
            if showKey(p.title).isEmpty { return review(p, "The server says movie, but the file name has no title.") }
            return SortDecision(outcome: .movie, signal: .serverType, parsed: p, note: "The server says movie.")
        }
        var p = FilenameParser.parse(fileName: fileName, folders: c.folders)
        if !p.episodes.isEmpty || p.absoluteEpisode != nil || p.airDate != nil, !showKey(p.title).isEmpty {
            p.kind = .episode
            return SortDecision(outcome: .episode, signal: .serverType, parsed: p, note: "The server says episode.")
        }
        p.kind = .movie
        return review(p, "The server says episode, but the file name has no show name or episode number.")
    }

    private static func byFileName(_ name: String, _ c: SortContext) -> SortDecision {
        let own = FilenameParser.parse(fileName: name)
        var p = FilenameParser.parse(fileName: name, folders: c.folders)
        let key = showKey(p.title)
        let folderInfos = c.folders.map(FilenameParser.parseFolderName)
        let seasonFolder = folderInfos.prefix(2).first { $0.season != nil }
        let others = c.siblings.others(showKey: showKey(own.title), selfMarked: own.episodeMarker != nil && own.episodeMarker != .seasonOnly)
        let hasNumber = !p.episodes.isEmpty || p.absoluteEpisode != nil

        func episode(_ signal: SortSignal, _ note: String) -> SortDecision {
            p.kind = .episode
            if key.isEmpty { return review(p, note + " But there is no show name.") }
            return SortDecision(outcome: .episode, signal: signal, parsed: p, note: note)
        }
        func movieOrReview(_ fallbackNote: String) -> SortDecision {
            // b. A year in the file name and no clear episode pattern: a movie (weak markers are read as part of the title).
            var m = FilenameParser.parse(fileName: name, folders: c.folders, weakMarkers: false)
            m.kind = .movie
            let ownYear = FilenameParser.parse(fileName: name, weakMarkers: false).year
            if ownYear != nil, !showKey(m.title).isEmpty {
                return SortDecision(outcome: .movie, signal: .moviePattern, parsed: m, note: "A year in the file name and no episode pattern.")
            }
            // c. A folder named like a movie, with a year ("Sample Movie (2019)").
            if let titled = folderInfos.first(where: { $0.season == nil && !$0.isGeneric && !$0.title.isEmpty }), titled.year != nil,
               !showKey(m.title).isEmpty {
                return SortDecision(outcome: .movie, signal: .folderHint, parsed: m, note: "The folder is named like a movie, with a year.")
            }
            return review(m, fallbackNote)
        }

        switch p.episodeMarker {
        case .seasonEpisode?:
            return episode(.episodePattern, "Season and episode numbers in the file name (S01E02).")
        case .crossFormat?:
            return episode(.episodePattern, "Season and episode numbers in the file name (1x02).")
        case .words?:
            return episode(.episodePattern, "\"Season … Episode …\" in the file name.")
        case .date?:
            if !showKey(own.title).isEmpty { return episode(.episodePattern, "An air date after the show name.") }
            if !key.isEmpty { return episode(.folderHint, "An air date; the show name comes from the folder.") }
            return review(p, "An air date but no show name.")
        case .absolute? where others > 0:
            return episode(.episodePattern, "An episode number after the show name, and \(others) other file\(others == 1 ? "" : "s") of this show in the folder.")
        case .folderNumber?:
            return episode(.folderHint, "A number at the start of the name, inside a season folder.")
        case .absolute?, .episodeOnly?, .special?:
            if seasonFolder != nil, hasNumber { return episode(.folderHint, "An episode number, inside a season folder.") }
            if others > 0, hasNumber { return episode(.folderHint, "An episode number, and \(others) other file\(others == 1 ? "" : "s") of this show in the folder.") }
            return movieOrReview("An episode-like number, but nothing else says this is a show.")
        case .seasonOnly?:
            return movieOrReview("A season number but no episode number.")
        case nil:
            return movieOrReview("No year and no episode pattern in the file name.")
        }
    }

    private static func review(_ p: ParsedMedia, _ note: String) -> SortDecision {
        SortDecision(outcome: .needsReview, signal: .undecided, parsed: p, note: note)
    }

    private static func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }

    /// The file as the override says: a movie with this title and year, or an episode of this show.
    public static func apply(_ o: SortOverride, to name: String, folders: [String]) -> SortDecision {
        let signal = SortSignal(rawValue: o.signal) ?? .manual
        let note = signal == .onlineLookup ? "Moved by the online lookup." : "Moved by hand."
        switch o.kind {
        case .movie:
            var p = FilenameParser.parse(fileName: name, folders: folders, weakMarkers: false)
            p.kind = .movie
            p.title = o.title
            p.year = o.year
            p.season = nil; p.episodes = []; p.absoluteEpisode = nil; p.airDate = nil
            return SortDecision(outcome: .movie, signal: signal, parsed: p, note: note)
        case .episode:
            var p = FilenameParser.parse(fileName: name, folders: folders)
            p.kind = .episode
            p.title = o.title
            p.year = o.year
            p.season = o.season ?? 1
            let first = o.episode ?? 1
            p.episodes = (o.episodeEnd ?? first) > first ? Array(first...(o.episodeEnd ?? first)) : [first]
            p.absoluteEpisode = nil
            p.airDate = nil
            if p.season == 0 { p.isSpecial = true }
            return SortDecision(outcome: .episode, signal: signal, parsed: p, note: note)
        }
    }
}

/// A file put in Movies or Shows by hand (or by the online check). The library's view of `UDSortOverrideValue`.
public struct SortOverride: Equatable, Sendable {
    public enum Kind: String, Sendable { case movie, episode }
    public var kind: Kind
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var episodeEnd: Int?
    public var signal: String

    public init(kind: Kind, title: String, year: Int? = nil, season: Int? = nil, episode: Int? = nil, episodeEnd: Int? = nil, signal: String = SortSignal.manual.rawValue) {
        self.kind = kind
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.episodeEnd = episodeEnd
        self.signal = signal
    }

    /// Stored with the file, so a scan can tell the override changed without the file changing.
    public var fingerprint: String {
        [kind.rawValue, title, year.map(String.init) ?? "", season.map(String.init) ?? "", episode.map(String.init) ?? "",
         episodeEnd.map(String.init) ?? "", signal].joined(separator: "\u{1F}")
    }
}

/// Where the scan reads overrides from: the user-data ledger in the app, a dictionary in tests.
public protocol SortOverrideProviding: Sendable {
    /// Overrides for one source, by path.
    func overrides(sourceID: String) -> [String: SortOverride]
}

public struct NoSortOverrides: SortOverrideProviding {
    public init() {}
    public func overrides(sourceID: String) -> [String: SortOverride] { [:] }
}

public struct FixedSortOverrides: SortOverrideProviding {
    public var bySource: [String: [String: SortOverride]]
    public init(_ bySource: [String: [String: SortOverride]]) { self.bySource = bySource }
    public func overrides(sourceID: String) -> [String: SortOverride] { bySource[sourceID] ?? [:] }
}
