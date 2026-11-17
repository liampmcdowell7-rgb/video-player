import Foundation
import MetadataOnline
import UserData

// Discover (docs/ARTWORK_DISCOVER.md): the one tab that lists titles the user does NOT own. Pure logic, no network:
// the data comes through `DiscoverDataSource` (the real one is the TMDB client, tests use fakes) and the library facts come
// in as a plain `DiscoverLibrary` value. Nothing here runs unless the user entered their own key (see `OnlineLookupText`).

/// What the Discover screens need from TMDB (where-to-watch data from JustWatch, through TMDB).
public protocol DiscoverDataSource: Sendable {
    func series(id: Int) async throws -> SeriesMetadata
    func season(seriesID: Int, number: Int) async throws -> SeasonMetadata
    func movie(id: Int) async throws -> MovieMetadata
    func collection(id: Int) async throws -> CollectionMetadata
    func similar(kind: TitleKind, id: Int) async throws -> [SearchHit]
    func watchProviders(kind: TitleKind, id: Int) async throws -> [String: WatchAvailability]
}

extension TMDBClient: DiscoverDataSource {}

public struct EpisodeKey: Hashable, Sendable {
    public var season: Int
    public var episode: Int
    public init(season: Int, episode: Int) { self.season = season; self.episode = episode }
}

/// A title the user owns and wants suggestions around ("Similar to Your Library").
public struct DiscoverSeed: Equatable, Sendable {
    public var kind: TitleKind
    public var tmdbID: Int
    public var title: String
    public init(kind: TitleKind, tmdbID: Int, title: String) { self.kind = kind; self.tmdbID = tmdbID; self.title = title }
}

/// Everything Discover needs to know about the user's library, as plain values.
public struct DiscoverLibrary: Equatable, Sendable {
    public var ownedMovieIDs: Set<Int>
    public var ownedSeriesIDs: Set<Int>
    /// Series TMDB id -> the (season, episode) pairs the user owns (a double episode lists both numbers).
    public var ownedEpisodes: [Int: Set<EpisodeKey>]
    public var seeds: [DiscoverSeed]

    public init(ownedMovieIDs: Set<Int> = [], ownedSeriesIDs: Set<Int> = [], ownedEpisodes: [Int: Set<EpisodeKey>] = [:], seeds: [DiscoverSeed] = []) {
        self.ownedMovieIDs = ownedMovieIDs
        self.ownedSeriesIDs = ownedSeriesIDs
        self.ownedEpisodes = ownedEpisodes
        self.seeds = seeds
    }

    public var isEmpty: Bool { ownedMovieIDs.isEmpty && ownedSeriesIDs.isEmpty }
}

/// Where one title can be watched in the user's region. Names only; the data supplier's page address is the link back.
public struct WhereToWatch: Equatable, Sendable {
    public var region: String
    public var link: String?
    public var stream: [String]
    public var rent: [String]
    public var buy: [String]

    public init(region: String, link: String?, stream: [String], rent: [String], buy: [String]) {
        self.region = region; self.link = link; self.stream = stream; self.rent = rent; self.buy = buy
    }

    /// "Stream: A, B. Rent: C. Buy: D." for one line under a card.
    public var summary: String {
        var parts: [String] = []
        if !stream.isEmpty { parts.append("Stream: " + stream.prefix(3).joined(separator: ", ")) }
        if !rent.isEmpty { parts.append("Rent: " + rent.prefix(2).joined(separator: ", ")) }
        if !buy.isEmpty { parts.append("Buy: " + buy.prefix(2).joined(separator: ", ")) }
        return parts.isEmpty ? "" : parts.joined(separator: ". ") + "."
    }
}

public struct DiscoverTitle: Equatable, Sendable, Identifiable {
    public var kind: TitleKind
    public var tmdbID: Int
    public var title: String
    public var year: Int?
    public var posterPath: String?
    /// Why it is listed ("Similar to Arrival", "Part of The Matrix Collection").
    public var reason: String
    /// nil = no where-to-watch data for the user's region (or it could not be looked up).
    public var watch: WhereToWatch?
    public var onWatchlist: Bool

    public var id: String { "\(kind.rawValue)-\(tmdbID)" }
    public var artworkKey: String { posterPath.map { "remote:" + $0 } ?? "remote:" }

    public init(kind: TitleKind, tmdbID: Int, title: String, year: Int? = nil, posterPath: String? = nil, reason: String, watch: WhereToWatch? = nil, onWatchlist: Bool = false) {
        self.kind = kind; self.tmdbID = tmdbID; self.title = title; self.year = year; self.posterPath = posterPath
        self.reason = reason; self.watch = watch; self.onWatchlist = onWatchlist
    }
}

public struct MissingEpisode: Equatable, Sendable, Identifiable {
    public var season: Int
    public var episode: Int
    public var name: String
    public var airDate: CalendarDate?
    public var id: String { "\(season)x\(episode)" }
    public var code: String { "S\(season) E\(episode)" }
    public init(season: Int, episode: Int, name: String, airDate: CalendarDate? = nil) {
        self.season = season; self.episode = episode; self.name = name; self.airDate = airDate
    }
}

public struct MissingEpisodesGroup: Equatable, Sendable, Identifiable {
    public var seriesTMDBID: Int
    public var seriesTitle: String
    public var episodes: [MissingEpisode]
    public var watch: WhereToWatch?
    public var id: Int { seriesTMDBID }
    public init(seriesTMDBID: Int, seriesTitle: String, episodes: [MissingEpisode], watch: WhereToWatch? = nil) {
        self.seriesTMDBID = seriesTMDBID; self.seriesTitle = seriesTitle; self.episodes = episodes; self.watch = watch
    }
}

public struct CollectionGap: Equatable, Sendable, Identifiable {
    public var collectionID: Int
    public var name: String
    public var ownedCount: Int
    public var missing: [DiscoverTitle]
    public var id: Int { collectionID }
    public init(collectionID: Int, name: String, ownedCount: Int, missing: [DiscoverTitle]) {
        self.collectionID = collectionID; self.name = name; self.ownedCount = ownedCount; self.missing = missing
    }
}

public struct DiscoverContent: Equatable, Sendable {
    public var missingEpisodes: [MissingEpisodesGroup]
    public var collectionGaps: [CollectionGap]
    public var similar: [DiscoverTitle]
    public var watchlist: [DiscoverTitle]
    /// One plain sentence per section that could not be filled (a bad key, no connection). Never hides the sections that worked.
    public var problems: [String]
    public var region: String

    public init(missingEpisodes: [MissingEpisodesGroup] = [], collectionGaps: [CollectionGap] = [], similar: [DiscoverTitle] = [],
                watchlist: [DiscoverTitle] = [], problems: [String] = [], region: String = "US") {
        self.missingEpisodes = missingEpisodes; self.collectionGaps = collectionGaps; self.similar = similar
        self.watchlist = watchlist; self.problems = problems; self.region = region
    }

    public var isEmpty: Bool { missingEpisodes.isEmpty && collectionGaps.isEmpty && similar.isEmpty && watchlist.isEmpty }
}

/// The user's watchlist as the engine sees it (the real one is the ledger, `LedgerWatchlist`).
public protocol WatchlistStoring: Sendable {
    func entries() -> [UDWatchlistEntry]
    func add(_ entry: UDWatchlistEntry)
    func remove(kind: TitleKind, tmdbID: Int)
}

/// Picks one region's providers out of the per-region reply. nil when the region has none.
public enum WhereToWatchBuilder {
    public static func build(_ all: [String: WatchAvailability], region: String) -> WhereToWatch? {
        guard let a = all[region.uppercased()], !a.isEmpty else { return nil }
        return WhereToWatch(region: a.region, link: a.link, stream: a.flatrate.map(\.name), rent: a.rent.map(\.name), buy: a.buy.map(\.name))
    }
}
