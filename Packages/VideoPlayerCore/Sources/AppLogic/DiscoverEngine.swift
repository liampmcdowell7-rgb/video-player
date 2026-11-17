import Foundation
import MetadataOnline
import UserData
import LibraryIndex

/// Limits that keep Discover polite to the data supplier (every call also goes through the request queue and the cache).
/// PROVISIONAL numbers (docs/ARTWORK_DISCOVER.md): they cap how many calls one refresh makes.
public struct DiscoverLimits: Equatable, Sendable {
    public var maxSeries = 20
    public var maxMovieLookups = 40
    public var maxSeeds = 4
    public var maxSimilar = 24
    public var maxWatchLookups = 40
    public init() {}
}

/// Builds the four Discover sections. Library only goes in as `DiscoverLibrary`; online data only through `DiscoverDataSource`.
public struct DiscoverEngine: Sendable {
    public let source: any DiscoverDataSource
    public let region: String
    public let limits: DiscoverLimits
    public let now: @Sendable () -> Date

    public init(source: any DiscoverDataSource, region: String = OnlineLookupPrefs.defaultRegion, limits: DiscoverLimits = DiscoverLimits(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.region = region.uppercased()
        self.limits = limits
        self.now = now
    }

    static func today(_ date: Date) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return CalendarDate(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    public func build(library: DiscoverLibrary, watchlist: [UDWatchlistEntry]) async -> DiscoverContent {
        var content = DiscoverContent(region: region)
        let owned = Set(library.ownedMovieIDs.map { "movie-\($0)" } + library.ownedSeriesIDs.map { "series-\($0)" })
        let listed = Set(watchlist.map { "\($0.kind)-\($0.tmdbID)" })
        var problems = ProblemCollector()

        content.missingEpisodes = await missingEpisodes(library, &problems)
        content.collectionGaps = await collectionGaps(library, listed: listed, &problems)
        content.similar = await similar(library, owned: owned, listed: listed, &problems)
        content.watchlist = await watchlistTitles(watchlist, owned: owned)
        content.problems = problems.sentences
        return content
    }

    // MARK: Missing episodes

    /// Aired episodes of series the user owns that are not in the library. Only seasons the user has at least one episode of
    /// count (a season the user never collected is not a "gap"); specials (season 0), unaired and undated episodes are left out.
    func missingEpisodes(_ library: DiscoverLibrary, _ problems: inout ProblemCollector) async -> [MissingEpisodesGroup] {
        var groups: [MissingEpisodesGroup] = []
        let today = Self.today(now())
        for seriesID in library.ownedSeriesIDs.sorted().prefix(limits.maxSeries) {
            if Task.isCancelled { break }
            let have = library.ownedEpisodes[seriesID] ?? []
            let seasonsOwned = Set(have.map(\.season)).filter { $0 > 0 }
            guard !seasonsOwned.isEmpty else { continue }
            do {
                let series = try await source.series(id: seriesID)
                var missing: [MissingEpisode] = []
                for number in seasonsOwned.sorted() {
                    let season = try await source.season(seriesID: seriesID, number: number)
                    for e in season.episodes {
                        guard let air = e.airDate, air <= today, !have.contains(EpisodeKey(season: number, episode: e.episodeNumber)) else { continue }
                        missing.append(MissingEpisode(season: number, episode: e.episodeNumber, name: e.name, airDate: air))
                    }
                }
                guard !missing.isEmpty else { continue }
                missing.sort { ($0.season, $0.episode) < ($1.season, $1.episode) }
                groups.append(MissingEpisodesGroup(seriesTMDBID: seriesID, seriesTitle: series.name, episodes: missing, watch: await watch(.series, seriesID)))
            } catch {
                problems.note(error, section: "Missing Episodes")
                if problems.isFatal(error) { break }
            }
        }
        return groups.sorted { $0.seriesTitle.lowercased() < $1.seriesTitle.lowercased() }
    }

    // MARK: Collection gaps

    /// Parts of a film collection the user owns at least one of, listing the released parts they do not own.
    func collectionGaps(_ library: DiscoverLibrary, listed: Set<String>, _ problems: inout ProblemCollector) async -> [CollectionGap] {
        var seen = Set<Int>()
        var gaps: [CollectionGap] = []
        let today = Self.today(now())
        for movieID in library.ownedMovieIDs.sorted().prefix(limits.maxMovieLookups) {
            if Task.isCancelled { break }
            do {
                guard let ref = try await source.movie(id: movieID).collection, seen.insert(ref.id).inserted else { continue }
                let collection = try await source.collection(id: ref.id)
                let ownedCount = collection.parts.filter { library.ownedMovieIDs.contains($0.tmdbID) }.count
                var missing: [DiscoverTitle] = []
                for part in collection.parts where !library.ownedMovieIDs.contains(part.tmdbID) {
                    if let date = part.releaseDate, date > today { continue }   // unreleased: not a gap yet
                    missing.append(DiscoverTitle(kind: .movie, tmdbID: part.tmdbID, title: part.title, year: part.releaseDate?.year, posterPath: part.posterPath,
                                                 reason: "Part of \(collection.name)", watch: await watch(.movie, part.tmdbID), onWatchlist: listed.contains("movie-\(part.tmdbID)")))
                }
                if !missing.isEmpty {
                    missing.sort { ($0.year ?? Int.max, $0.title) < ($1.year ?? Int.max, $1.title) }
                    gaps.append(CollectionGap(collectionID: collection.id, name: collection.name, ownedCount: ownedCount, missing: missing))
                }
            } catch {
                problems.note(error, section: "Collection Gaps")
                if problems.isFatal(error) { break }
            }
        }
        return gaps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: Similar to your library

    func similar(_ library: DiscoverLibrary, owned: Set<String>, listed: Set<String>, _ problems: inout ProblemCollector) async -> [DiscoverTitle] {
        var out: [DiscoverTitle] = []
        var seen = Set<String>()
        for seed in library.seeds.prefix(limits.maxSeeds) {
            if Task.isCancelled { break }
            do {
                let hits = try await source.similar(kind: seed.kind, id: seed.tmdbID)
                for hit in hits.sorted(by: { ($0.popularity ?? 0) > ($1.popularity ?? 0) }) {
                    let key = "\(hit.kind.rawValue)-\(hit.tmdbID)"
                    guard !owned.contains(key), seen.insert(key).inserted else { continue }
                    out.append(DiscoverTitle(kind: hit.kind, tmdbID: hit.tmdbID, title: hit.title, year: hit.year, posterPath: hit.posterPath,
                                             reason: "Similar to \(seed.title)", onWatchlist: listed.contains(key)))
                }
            } catch {
                problems.note(error, section: "Similar to Your Library")
                if problems.isFatal(error) { break }
            }
        }
        var capped = Array(out.prefix(limits.maxSimilar))
        for i in capped.indices where i < limits.maxWatchLookups {
            capped[i].watch = await watch(capped[i].kind, capped[i].tmdbID)
        }
        return capped
    }

    // MARK: Watchlist

    func watchlistTitles(_ list: [UDWatchlistEntry], owned: Set<String>) async -> [DiscoverTitle] {
        var out: [DiscoverTitle] = []
        for e in list where !owned.contains("\(e.kind)-\(e.tmdbID)") {
            let kind = TitleKind(rawValue: e.kind) ?? .movie
            out.append(DiscoverTitle(kind: kind, tmdbID: e.tmdbID, title: e.title, year: e.year, posterPath: e.posterPath,
                                     reason: "On your watchlist", watch: await watch(kind, e.tmdbID), onWatchlist: true))
        }
        return out
    }

    // MARK: Where to watch

    /// nil when the region has no providers or the lookup failed (the card then says nothing is known, never guesses).
    func watch(_ kind: TitleKind, _ id: Int) async -> WhereToWatch? {
        guard let all = try? await source.watchProviders(kind: kind, id: id) else { return nil }
        return WhereToWatchBuilder.build(all, region: region)
    }
}

/// Turns thrown errors into at most one plain sentence per section.
struct ProblemCollector {
    private(set) var sentences: [String] = []

    mutating func note(_ error: Error, section: String) {
        let sentence = "\(section): \(Self.text(error))"
        if !sentences.contains(sentence) { sentences.append(sentence) }
    }

    /// A bad key or a used-up quota will fail every other call too: stop asking.
    func isFatal(_ error: Error) -> Bool {
        switch error as? MetadataError {
        case .invalidAPIKey?, .missingCredentials?, .quotaExhausted?: return true
        default: return false
        }
    }

    static func text(_ error: Error) -> String {
        switch error as? MetadataError {
        case .invalidAPIKey?, .missingCredentials?: return OnlineLookupText.keyRejected
        case .rateLimited?, .quotaExhausted?: return "The lookup service asked the app to slow down. Try again later."
        case .network?, .server?: return "The lookup service could not be reached. Check the connection and try again."
        default: return "The lookup did not work this time. Try again later."
        }
    }
}
