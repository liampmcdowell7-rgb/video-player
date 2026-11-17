import Foundation
import VideoPlayerCore

/// The user's own TMDB credentials. They are passed in by the caller (read from the Keychain by the app),
/// held only by the client instance, never written to disk, the cache or any description.
public enum TMDBCredentials: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The v3 "API Key".
    case apiKey(String)
    /// The v4 "API Read Access Token", sent as a Bearer header.
    case readAccessToken(String)

    public var description: String { "TMDBCredentials(redacted)" }
    public var debugDescription: String { description }
    /// `dump` and the debugger show no children, so the secret is not printed by accident.
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// What the matcher needs from a catalogue. `TMDBClient` is the real one; tests use fakes.
public protocol CatalogProvider: Sendable {
    func searchMovies(query: String, year: Int?) async throws -> [SearchHit]
    func searchSeries(query: String, firstAirYear: Int?) async throws -> [SearchHit]
    /// A single title by TMDB id. Throws `MetadataError.notFound` when it does not exist.
    func hit(tmdbID: Int, kind: TitleKind) async throws -> SearchHit
    /// Titles that carry an IMDb id (movie and series results together).
    func find(imdbID: String) async throws -> [SearchHit]
    func alternativeTitles(kind: TitleKind, id: Int) async throws -> [String]
    func movieRuntime(id: Int) async throws -> Int?
    func seriesSeasons(id: Int) async throws -> [SeasonSummary]
    func season(seriesID: Int, number: Int) async throws -> SeasonMetadata
}

/// TMDB v3 client. All requests go through a per-provider queue (spacing, back-off, retries) and a cache.
/// Network use needs the user's key; nothing here runs unless the app calls it for a matched library item.
public final class TMDBClient: Sendable {
    public static let defaultBaseURL: URL = URL(string: "https://api.themoviedb.org/3") ?? URL(fileURLWithPath: "/")

    private let credentials: TMDBCredentials
    private let queue: ProviderQueue
    private let cache: any MetadataCache
    private let clock: any MetadataClock
    let policy: CachePolicy   // internal: TMDBDiscover.swift (same module) reads the cache TTLs
    private let baseURL: URL
    /// Language for text, such as "en-US" or "de-DE".
    public let language: String
    /// Region for content ratings, such as "US".
    public let region: String

    public init(
        credentials: TMDBCredentials,
        transport: any HTTPTransport,
        cache: any MetadataCache = InMemoryMetadataCache(),
        language: String = "en-US",
        region: String = "US",
        queueConfiguration: QueueConfiguration = .tmdb,
        policy: CachePolicy = .standard,
        clock: any MetadataClock = SystemMetadataClock(),
        baseURL: URL = TMDBClient.defaultBaseURL
    ) {
        self.credentials = credentials
        self.queue = ProviderQueue(transport: transport, configuration: queueConfiguration, clock: clock)
        self.cache = cache
        self.clock = clock
        self.policy = policy
        self.baseURL = baseURL
        self.language = language
        self.region = region
    }

    public var requestsSent: Int { get async { await queue.requestsSent } }

    // MARK: Request plumbing

    static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    func makeRequest(path: String, query: [(String, String)]) throws -> HTTPRequest {
        var items = query
        var headers = ["Accept": "application/json"]
        switch credentials {
        case .apiKey(let key):
            guard !key.isEmpty else { throw MetadataError.missingCredentials }
            items.append(("api_key", key))
        case .readAccessToken(let token):
            guard !token.isEmpty else { throw MetadataError.missingCredentials }
            headers["Authorization"] = "Bearer \(token)"
        }
        let encoded = items.map { name, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? ""
            return "\(name)=\(v)"
        }.joined(separator: "&")
        guard let url = URL(string: baseURL.absoluteString + path + (encoded.isEmpty ? "" : "?" + encoded)) else {
            throw MetadataError.decoding("could not build the request address")
        }
        return HTTPRequest(url: url, method: "GET", headers: headers)
    }

    /// Cache first (fresh), then the network. When the network fails and an older copy exists, the older copy is used (offline use).
    func fetch(path: String, query: [(String, String)] = [], key: CacheKey, ttl: Double) async throws -> JSON {
        let cached = await cache.entry(for: key)
        if let cached, cached.isFresh(at: clock.now()), let json = try? JSON(data: cached.data) { return json }

        let request = try makeRequest(path: path, query: query)
        do {
            let response = try await queue.send(request)
            switch response.statusCode {
            case 200...299:
                let json = try JSON(data: response.body)
                await cache.store(response.body, for: key, ttl: ttl, at: clock.now())
                return json
            case 401, 403: throw MetadataError.invalidAPIKey
            case 404: throw MetadataError.notFound
            default: throw MetadataError.unexpectedStatus(response.statusCode)
            }
        } catch let error as MetadataError {
            switch error {
            case .network, .server, .rateLimited, .quotaExhausted:
                if let cached, let json = try? JSON(data: cached.data) { return json }
            default: break
            }
            throw error
        }
    }

    private func key(_ kind: String, _ id: String, _ variant: String) -> CacheKey {
        CacheKey(provider: "tmdb", kind: kind, id: id, variant: variant)
    }

    private var imageLanguages: String {
        let short = String(language.prefix(2)).lowercased()
        return short == "en" ? "en,null" : "\(short),en,null"
    }

    // MARK: Configuration

    public func configuration() async throws -> ImageConfiguration {
        let json = try await fetch(path: "/configuration", key: key("configuration", "-", ""), ttl: policy.configuration)
        return TMDBMapper.imageConfiguration(json) ?? .fallback
    }

    public func imageURLBuilder() async -> ImageURLBuilder {
        ImageURLBuilder(configuration: (try? await configuration()) ?? .fallback)
    }

    // MARK: Search

    public func searchMovies(query: String, year: Int? = nil) async throws -> [SearchHit] {
        var q: [(String, String)] = [("query", query), ("language", language), ("include_adult", "false"), ("page", "1")]
        if let year { q.append(("year", String(year))) }
        let id = "\(query.lowercased())|\(year.map(String.init) ?? "")"
        let json = try await fetch(path: "/search/movie", query: q, key: key("search-movie", id, language), ttl: policy.search)
        return TMDBMapper.hits(json, kind: .movie)
    }

    public func searchSeries(query: String, firstAirYear: Int? = nil) async throws -> [SearchHit] {
        var q: [(String, String)] = [("query", query), ("language", language), ("include_adult", "false"), ("page", "1")]
        if let firstAirYear { q.append(("first_air_date_year", String(firstAirYear))) }
        let id = "\(query.lowercased())|\(firstAirYear.map(String.init) ?? "")"
        let json = try await fetch(path: "/search/tv", query: q, key: key("search-tv", id, language), ttl: policy.search)
        return TMDBMapper.hits(json, kind: .series)
    }

    /// `/find/{imdb_id}` (external_source=imdb_id).
    public func find(imdbID: String) async throws -> [SearchHit] {
        let json = try await fetch(path: "/find/\(imdbID)", query: [("external_source", "imdb_id"), ("language", language)], key: key("find", imdbID, language), ttl: policy.details)
        return TMDBMapper.hits(JSON(raw: ["results": json["movie_results"].raw ?? []]), kind: .movie)
            + TMDBMapper.hits(JSON(raw: ["results": json["tv_results"].raw ?? []]), kind: .series)
    }

    // MARK: Details

    /// Movie details with credits, images, videos, release dates (certification) and external ids in one request.
    public func movie(id: Int) async throws -> MovieMetadata {
        let json = try await fetch(path: "/movie/\(id)", query: [("language", language), ("append_to_response", "credits,images,videos,release_dates,external_ids"), ("include_image_language", imageLanguages)], key: key("movie", String(id), language), ttl: policy.details)
        guard var movie = TMDBMapper.movie(json, language: language, region: region) else { throw MetadataError.decoding("movie \(id) has no id or title") }
        if movie.overview == nil, !language.lowercased().hasPrefix("en"), let en = try? await fetchEnglish(path: "/movie/\(id)", kind: "movie", id: String(id)) {
            movie.overview = en["overview"].text
            if movie.tagline == nil { movie.tagline = en["tagline"].text }
        }
        return movie
    }

    public func series(id: Int) async throws -> SeriesMetadata {
        let json = try await fetch(path: "/tv/\(id)", query: [("language", language), ("append_to_response", "credits,images,videos,content_ratings,external_ids"), ("include_image_language", imageLanguages)], key: key("tv", String(id), language), ttl: policy.details)
        guard var series = TMDBMapper.series(json, language: language, region: region) else { throw MetadataError.decoding("series \(id) has no id or name") }
        if series.overview == nil, !language.lowercased().hasPrefix("en"), let en = try? await fetchEnglish(path: "/tv/\(id)", kind: "tv", id: String(id)) {
            series.overview = en["overview"].text
            if series.tagline == nil { series.tagline = en["tagline"].text }
        }
        return series
    }

    private func fetchEnglish(path: String, kind: String, id: String) async throws -> JSON {
        try await fetch(path: path, query: [("language", "en-US")], key: key(kind, id, "en-US"), ttl: policy.details)
    }

    public func season(seriesID: Int, number: Int) async throws -> SeasonMetadata {
        let json = try await fetch(path: "/tv/\(seriesID)/season/\(number)", query: [("language", language)], key: key("tv", String(seriesID), "season-\(number)/\(language)"), ttl: policy.season)
        return TMDBMapper.season(json, seriesID: seriesID, number: number)
    }

    public func episode(seriesID: Int, season: Int, episode: Int) async throws -> EpisodeMetadata {
        let json = try await fetch(path: "/tv/\(seriesID)/season/\(season)/episode/\(episode)", query: [("language", language), ("append_to_response", "credits")], key: key("tv", String(seriesID), "season-\(season)/episode-\(episode)/\(language)"), ttl: policy.season)
        guard let ep = TMDBMapper.episode(json, seriesID: seriesID, fallbackSeason: season) else { throw MetadataError.decoding("episode \(season)x\(episode) has no number") }
        return ep
    }

    public func collection(id: Int) async throws -> CollectionMetadata {
        let json = try await fetch(path: "/collection/\(id)", query: [("language", language)], key: key("collection", String(id), language), ttl: policy.details)
        guard let c = TMDBMapper.collection(json) else { throw MetadataError.decoding("collection \(id) has no id or name") }
        return c
    }

    private func segment(_ kind: TitleKind) -> String { kind == .movie ? "movie" : "tv" }

    /// Posters, backdrops and logos (all languages listed in `include_image_language`).
    public func images(kind: TitleKind, id: Int) async throws -> ImageSet {
        let json = try await fetch(path: "/\(segment(kind))/\(id)/images", query: [("include_image_language", imageLanguages)], key: key(segment(kind), String(id), "images"), ttl: policy.details)
        return TMDBMapper.images(json)
    }

    public func credits(kind: TitleKind, id: Int) async throws -> Credits {
        let json = try await fetch(path: "/\(segment(kind))/\(id)/credits", query: [("language", language)], key: key(segment(kind), String(id), "credits/\(language)"), ttl: policy.details)
        return TMDBMapper.credits(json)
    }

    public func externalIDs(kind: TitleKind, id: Int) async throws -> ProviderIDs {
        let json = try await fetch(path: "/\(segment(kind))/\(id)/external_ids", key: key(segment(kind), String(id), "external_ids"), ttl: policy.details)
        return ProviderIDs(tmdb: id, imdb: json["imdb_id"].text, tvdb: json["tvdb_id"].int)
    }

    public func translations(kind: TitleKind, id: Int) async throws -> [TitleTranslation] {
        let json = try await fetch(path: "/\(segment(kind))/\(id)/translations", key: key(segment(kind), String(id), "translations"), ttl: policy.details)
        return TMDBMapper.translations(json)
    }

    public func alternativeTitles(kind: TitleKind, id: Int) async throws -> [String] {
        let json = try await fetch(path: "/\(segment(kind))/\(id)/alternative_titles", key: key(segment(kind), String(id), "alternative_titles"), ttl: policy.details)
        let list = kind == .movie ? json["titles"].array : json["results"].array
        return list.compactMap { $0["title"].text }
    }
}

extension TMDBClient: CatalogProvider {
    public func hit(tmdbID: Int, kind: TitleKind) async throws -> SearchHit {
        switch kind {
        case .movie:
            let m = try await movie(id: tmdbID)
            return SearchHit(tmdbID: tmdbID, kind: .movie, title: m.title, originalTitle: m.originalTitle, year: m.year, overview: m.overview, posterPath: m.posterPath, popularity: nil, originalLanguage: m.originalLanguage)
        case .series:
            let s = try await series(id: tmdbID)
            return SearchHit(tmdbID: tmdbID, kind: .series, title: s.name, originalTitle: s.originalName, year: s.year, overview: s.overview, posterPath: s.posterPath, popularity: nil, originalLanguage: s.originalLanguage)
        }
    }

    public func movieRuntime(id: Int) async throws -> Int? { try await movie(id: id).runtimeMinutes }
    public func seriesSeasons(id: Int) async throws -> [SeasonSummary] { try await series(id: id).seasons }
}
