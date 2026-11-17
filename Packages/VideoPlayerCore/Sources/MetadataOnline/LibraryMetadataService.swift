import Foundation

// "Your Library Only", enforced in types.
//
//  * Everything here starts from an item the user owns (`LibraryCatalog.contains`). An unknown id throws
//    `MetadataError.notInLibrary` before any provider is called.
//  * Details are fetched only for the title a library item matched.
//  * Library-facing results (`LibraryResolution`, `MatchedLibraryItem`, `OwnedCollection`) have no way to carry
//    a title the user does not own: a needs-review result carries no candidates, collections list only owned parts,
//    and `MatchedLibraryItem` can only be created inside this module.
//  * There is no recommendations, "similar titles", trending or watch-provider call in this target.
//    Those belong to Discover, which is a separate target.
//  * Fix Match candidates (`fixMatchCandidates`) are search results for one owned file, shown on the Fix Match
//    screen only; they are a different type (`ScoredCandidate`) from anything the library screens receive.

public typealias LibraryItemID = String

/// What the library knows about ownership. The app implements this over the library index.
public protocol LibraryCatalog: Sendable {
    func contains(itemID: LibraryItemID) async -> Bool
    /// TMDB ids of every title the user owns, used to cut collections down to owned parts.
    func ownedTMDBIDs() async -> Set<Int>
}

public protocol TitleDetailsProvider: Sendable {
    func movie(id: Int) async throws -> MovieMetadata
    func series(id: Int) async throws -> SeriesMetadata
    func season(seriesID: Int, number: Int) async throws -> SeasonMetadata
    func collection(id: Int) async throws -> CollectionMetadata
}

public protocol RatingsProvider: Sendable {
    func ratings(imdbID: String) async throws -> OMDbResult
}

extension TMDBClient: TitleDetailsProvider {}
extension OMDbClient: RatingsProvider {}

/// A library item together with the online metadata of the title it matched.
public struct MatchedLibraryItem: Sendable {
    public let itemID: LibraryItemID
    public let match: MatchResult
    public let movie: MovieMetadata?
    public let series: SeriesMetadata?
    /// The episode(s) this item holds, for series items.
    public let episodes: [EpisodeMetadata]
    /// Sidecar, TMDB and embedded values merged per field, with provenance.
    public let merged: MergedMetadata
    /// TMDB score plus the OMDb scores that exist. Missing scores are simply absent.
    public let ratings: RatingSet

    /// Only this module creates matched items.
    init(itemID: LibraryItemID, match: MatchResult, movie: MovieMetadata?, series: SeriesMetadata?, episodes: [EpisodeMetadata], merged: MergedMetadata, ratings: RatingSet) {
        self.itemID = itemID
        self.match = match
        self.movie = movie
        self.series = series
        self.episodes = episodes
        self.merged = merged
        self.ratings = ratings
    }
}

public enum LibraryResolution: Sendable {
    case matched(MatchedLibraryItem)
    /// The item is shown as "Needs review". The candidates are on the Fix Match screen, not here.
    case needsReview(itemID: LibraryItemID, reason: ReviewReason)
    case unmatched(itemID: LibraryItemID)
}

/// A film series reduced to the parts the user owns.
public struct OwnedCollection: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let overview: String?
    public let posterPath: String?
    public let backdropPath: String?
    public let ownedParts: [CollectionPart]

    init(id: Int, name: String, overview: String?, posterPath: String?, backdropPath: String?, ownedParts: [CollectionPart]) {
        self.id = id
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.ownedParts = ownedParts
    }
}

public actor LibraryMetadataService {
    private let library: any LibraryCatalog
    private let fixMatch: FixMatchService
    private let details: any TitleDetailsProvider
    private let ratingsProvider: (any RatingsProvider)?
    private let cache: any MetadataCache

    public init(library: any LibraryCatalog, fixMatch: FixMatchService, details: any TitleDetailsProvider, ratings: (any RatingsProvider)? = nil, cache: any MetadataCache = InMemoryMetadataCache()) {
        self.library = library
        self.fixMatch = fixMatch
        self.details = details
        self.ratingsProvider = ratings
        self.cache = cache
    }

    private func requireOwned(_ itemID: LibraryItemID) async throws {
        guard await library.contains(itemID: itemID) else { throw MetadataError.notInLibrary }
    }

    /// Matches one library file (a saved Fix Match choice first) and fetches the matched title's details.
    public func resolve(itemID: LibraryItemID, file: FileIdentity, input: MatchInput, local: LocalMetadataInput? = nil, embedded: EmbeddedMetadataInput? = nil) async throws -> LibraryResolution {
        try await requireOwned(itemID)
        switch try await fixMatch.resolve(file: file, input: input) {
        case .unmatched: return .unmatched(itemID: itemID)
        case .needsReview(let reason, _): return .needsReview(itemID: itemID, reason: reason)
        case .matched(let match): return .matched(try await load(itemID: itemID, match: match, local: local, embedded: embedded))
        }
    }

    /// Search for the Fix Match screen of one owned file.
    public func fixMatchCandidates(itemID: LibraryItemID, query: String, year: Int?, kind: TitleKind, input: MatchInput?) async throws -> [ScoredCandidate] {
        try await requireOwned(itemID)
        return try await fixMatch.search(query: query, year: year, kind: kind, input: input)
    }

    /// Saves the user's Fix Match choice for an owned file and returns the item loaded with it.
    public func choose(itemID: LibraryItemID, candidate: SearchHit, file: FileIdentity, input: MatchInput, scope: MatchScope, local: LocalMetadataInput? = nil, embedded: EmbeddedMetadataInput? = nil) async throws -> (change: FixMatchChange, item: MatchedLibraryItem) {
        try await requireOwned(itemID)
        let change = try await fixMatch.choose(candidate, for: file, input: input, scope: scope)
        let item = try await load(itemID: itemID, match: change.result, local: local, embedded: embedded)
        return (change, item)
    }

    public func undo(_ change: FixMatchChange) async throws {
        try await fixMatch.undo(change)
    }

    /// The collection of a matched movie, cut down to the parts the user owns.
    public func collection(for item: MatchedLibraryItem) async throws -> OwnedCollection? {
        try await requireOwned(item.itemID)
        guard let ref = item.movie?.collection else { return nil }
        let all = try await details.collection(id: ref.id)
        let owned = await library.ownedTMDBIDs()
        return OwnedCollection(id: all.id, name: all.name, overview: all.overview, posterPath: all.posterPath, backdropPath: all.backdropPath, ownedParts: all.parts.filter { owned.contains($0.tmdbID) })
    }

    /// "Refresh Metadata": drops cached data for an item, a folder's items or the whole library. Nothing is fetched until the next `resolve`.
    @discardableResult
    public func refresh(_ scope: RefreshScope) async -> Int {
        await MetadataRefresh.invalidate(scope, in: cache)
    }

    // MARK: Loading

    private func load(itemID: LibraryItemID, match: MatchResult, local: LocalMetadataInput?, embedded: EmbeddedMetadataInput?) async throws -> MatchedLibraryItem {
        switch match.kind {
        case .movie:
            let movie = try await details.movie(id: match.tmdbID)
            let ratings = await combinedRatings(movie.ratings, imdbID: movie.ids.imdb)
            var enriched = movie
            enriched.ratings = ratings
            let merged = MetadataMerger.merge(sidecar: local, tmdb: MetadataMerger.fields(from: enriched), embedded: embedded)
            return MatchedLibraryItem(itemID: itemID, match: match, movie: enriched, series: nil, episodes: [], merged: merged, ratings: ratings)
        case .series:
            let series = try await details.series(id: match.tmdbID)
            let ratings = await combinedRatings(series.ratings, imdbID: series.ids.imdb)
            var enriched = series
            enriched.ratings = ratings
            var episodes: [EpisodeMetadata] = []
            if let resolved = match.episodes {
                if let season = try? await details.season(seriesID: match.tmdbID, number: resolved.seasonNumber) {
                    episodes = resolved.episodeNumbers.compactMap { n in season.episodes.first { $0.episodeNumber == n } }
                }
            }
            let tmdbFields = episodes.first.map { MetadataMerger.fields(from: $0) } ?? MetadataMerger.fields(from: enriched)
            let merged = MetadataMerger.merge(sidecar: local, tmdb: tmdbFields, embedded: embedded)
            return MatchedLibraryItem(itemID: itemID, match: match, movie: nil, series: enriched, episodes: episodes, merged: merged, ratings: ratings)
        }
    }

    /// OMDb scores are optional: no key, a quota that is used up, or a title OMDb does not know all leave the TMDB score alone.
    private func combinedRatings(_ tmdb: RatingSet, imdbID: String?) async -> RatingSet {
        guard let provider = ratingsProvider, let imdbID, !imdbID.isEmpty else { return tmdb }
        guard let omdb = try? await provider.ratings(imdbID: imdbID) else { return tmdb }
        return tmdb.merging(omdb.ratings)
    }
}
