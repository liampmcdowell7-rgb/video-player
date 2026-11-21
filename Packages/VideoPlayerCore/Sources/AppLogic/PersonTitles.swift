import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataOnline

// R341 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T8): selecting a cast member opens a page of that person's
// titles from the owner's own library, in the same poster grid. "No online lookup beyond what is already stored": the page
// reads the title details already kept on this device (the same answers the movie and show pages showed) through clients
// whose transport never sends anything, so an answer that is not stored is simply missing.

/// A transport that never sends. Every request fails at once, so a metadata client built on it answers only from its cache
/// (`TMDBClient.fetch` and `WikidataClient.lookup` return the stored copy, fresh or old, when the network fails).
public struct NoNetworkTransport: HTTPTransport {
    public struct NotSent: Error, Equatable {}
    public init() {}
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse { throw NotSent() }
}

extension QueueConfiguration {
    /// No waiting and no retry: with `NoNetworkTransport` a missing answer fails at once instead of backing off.
    public static let storedOnly = QueueConfiguration(minInterval: 0, maxRetries: 0)
}

/// A movie's or show's cast from the stored TMDB details only (the same entries `TMDBArtworkProvider` reads for the pages).
public struct StoredTMDBDetails: TitleDetailsSource {
    private let store: any LibraryStore
    private let client: TMDBClient

    /// `client` must be built on `NoNetworkTransport` (see `PersonTitles.storedClient`).
    public init(store: any LibraryStore, client: TMDBClient) {
        self.store = store
        self.client = client
    }

    public func details(key: String) async -> TitleDetails? {
        switch ArtworkKey(key) {
        case .item(let id)?:
            guard let item = try? await store.item(id: id), item.kind == .movie, let tmdb = item.tmdbID,
                  let movie = try? await client.movie(id: tmdb) else { return nil }
            return TitleDetails(overview: movie.overview, people: movie.credits.cast)
        case .series(let seriesID)?:
            guard let episodes = try? await store.episodes(ofSeries: seriesID) else { return nil }
            let counts = Dictionary(grouping: episodes.compactMap(\.tmdbID), by: { $0 }).mapValues(\.count)
            guard let tmdb = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key,
                  let series = try? await client.series(id: tmdb) else { return nil }
            return TitleDetails(overview: series.overview, people: series.credits.cast)
        default:
            return nil
        }
    }
}

/// The titles in the library with one person in their cast (R341).
public enum PersonTitles {
    public struct Content: Equatable, Sendable {
        public var movies: [ItemCard]
        public var shows: [SeriesSummary]
        public init(movies: [ItemCard], shows: [SeriesSummary]) {
            self.movies = movies
            self.shows = shows
        }
        public var isEmpty: Bool { movies.isEmpty && shows.isEmpty }
        /// "3 titles" or "1 title", in the place of the Movies count.
        public var countText: String {
            let n = movies.count + shows.count
            return n == 1 ? "1 title" : "\(n) titles"
        }
    }

    /// The details of one title by artwork key ("item-N", "series-N"), from what is stored only.
    public typealias Details = @Sendable (String) async -> TitleDetails?

    /// A name compared without case, accents or extra spaces ("Zoë  Doe" and "zoe doe" are the same person). TMDB and
    /// Wikidata give names only in the shelf, so the name is the key.
    public static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// True when `name` is in `cast`.
    public static func contains(_ cast: [TitleDetails.CastMember], name: String) -> Bool {
        let wanted = normalized(name)
        guard !wanted.isEmpty else { return false }
        return cast.contains { normalized($0.name) == wanted }
    }

    /// Every movie and show in the library whose stored cast lists `name`: movies in title order, then shows in title
    /// order. One stored read per title; nothing is requested online.
    public static func load(name: String, store: any LibraryStore, catalog: (any SeriesCatalog)? = nil,
                            details: Details) async throws -> Content {
        var movies: [ItemCard] = []
        var filter = ItemFilter()
        filter.kinds = [.movie]
        let query = ItemQuery(filter: filter, sort: ItemSort(key: .title, ascending: true))
        var cursor: ItemCursor?
        repeat {
            try Task.checkCancellation()
            let page = try await store.page(query, limit: 500, after: cursor)
            for item in page.items {
                if let found = await details("item-\(item.id)"), contains(found.cast, name: name) {
                    movies.append(CardBuilder.card(item))
                }
            }
            cursor = page.next
        } while cursor != nil
        var shows: [SeriesSummary] = []
        let all = try await (catalog ?? EpisodeGroupingCatalog(store: store)).allSeries()
        for show in all.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
            try Task.checkCancellation()
            if let found = await details("series-\(show.id)"), contains(found.cast, name: name) { shows.append(show) }
        }
        return Content(movies: movies, shows: shows)
    }

    /// The page's state: the titles, or "No Titles" when the stored details name this person nowhere (for example after
    /// the stored answers were cleared in Settings > Storage).
    public static func state(name: String, store: any LibraryStore, catalog: (any SeriesCatalog)? = nil,
                             details: Details) async -> ViewState<Content> {
        do {
            let content = try await load(name: name, store: store, catalog: catalog, details: details)
            return content.isEmpty ? .empty(noTitles(name)) : .loaded(content)
        } catch {
            return .failed(ErrorState.from(error, doing: "load the titles with \(name)"))
        }
    }

    public static func noTitles(_ name: String) -> EmptyState {
        EmptyState(reason: .noMatches, title: "No Titles",
                   message: "No title in your library lists \(name) in the details stored on this Apple TV.")
    }

    /// The stored-only TMDB client: the same cache folder and language as the app's own client, a transport that never
    /// sends, and no retries. `credentials` is the user's key; it is never sent because nothing is.
    public static func storedClient(credentials: TMDBCredentials, cache: any MetadataCache, region: String) -> TMDBClient {
        TMDBClient(credentials: credentials, transport: NoNetworkTransport(), cache: cache, region: region, queueConfiguration: .storedOnly)
    }

    /// The stored-only Wikidata client, with the language the app's own client uses.
    public static func storedWikidata(cache: any MetadataCache, userAgent: String, language: String) -> WikidataClient {
        WikidataClient(transport: NoNetworkTransport(), cache: cache, queueConfiguration: .storedOnly, userAgent: userAgent, language: language)
    }
}
