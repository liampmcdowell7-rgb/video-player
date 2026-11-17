import Foundation
import VideoPlayerCore

/// What OMDb returned for one title: its IMDb id and the scores it has.
public struct OMDbResult: Codable, Hashable, Sendable {
    public var imdbID: String?
    public var title: String?
    public var year: String?
    public var ratings: RatingSet
}

public enum OMDbScoreParser {
    /// "8.7/10", "73/100", "87%" to (percent 0...100, display text). "N/A", empty and nonsense give nil.
    public static func parse(_ text: String?) -> (percent: Double, display: String)? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.uppercased() != "N/A" else { return nil }
        if t.hasSuffix("%") {
            guard let v = Double(t.dropLast().trimmingCharacters(in: .whitespaces)), (0...100).contains(v) else { return nil }
            return (v, t)
        }
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2, let a = Double(parts[0].trimmingCharacters(in: .whitespaces)), let b = Double(parts[1].trimmingCharacters(in: .whitespaces)), b > 0, a >= 0, a <= b {
            return (a / b * 100, t)
        }
        return nil
    }

    static func votes(_ text: String?) -> Int? {
        guard let t = text?.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return Int(t)
    }

    static func ratingSet(_ j: JSON) -> RatingSet {
        var set = RatingSet.empty
        for r in j["Ratings"].array {
            guard let source = r["Source"].text, let parsed = parse(r["Value"].text) else { continue }
            switch source {
            case "Internet Movie Database": set.imdb = Rating(source: .imdb, percent: parsed.percent, display: parsed.display, votes: votes(j["imdbVotes"].text))
            case "Rotten Tomatoes": set.rottenTomatoes = Rating(source: .rottenTomatoes, percent: parsed.percent, display: parsed.display)
            case "Metacritic": set.metacritic = Rating(source: .metacritic, percent: parsed.percent, display: parsed.display)
            default: break
            }
        }
        // Older or shorter responses carry the same scores in flat fields.
        if set.imdb == nil, let text = j["imdbRating"].text, let v = Double(text), (0...10).contains(v) {
            set.imdb = Rating(source: .imdb, percent: v * 10, display: "\(text)/10", votes: votes(j["imdbVotes"].text))
        }
        if set.metacritic == nil, let text = j["Metascore"].text, let v = Double(text), (0...100).contains(v) {
            set.metacritic = Rating(source: .metacritic, percent: v, display: "\(text)/100")
        }
        return set
    }
}

/// OMDb client (IMDb, Rotten Tomatoes and Metacritic scores). The user's own key is passed in and never stored.
public final class OMDbClient: Sendable {
    public static let defaultBaseURL: URL = URL(string: "https://www.omdbapi.com/") ?? URL(fileURLWithPath: "/")

    private let apiKey: String
    private let queue: ProviderQueue
    private let cache: any MetadataCache
    private let clock: any MetadataClock
    private let policy: CachePolicy
    private let baseURL: URL

    public init(
        apiKey: String,
        transport: any HTTPTransport,
        cache: any MetadataCache = InMemoryMetadataCache(),
        queueConfiguration: QueueConfiguration = .omdb,
        policy: CachePolicy = .standard,
        clock: any MetadataClock = SystemMetadataClock(),
        baseURL: URL = OMDbClient.defaultBaseURL
    ) {
        self.apiKey = apiKey
        self.queue = ProviderQueue(transport: transport, configuration: queueConfiguration, clock: clock)
        self.cache = cache
        self.clock = clock
        self.policy = policy
        self.baseURL = baseURL
    }

    public var requestsSent: Int { get async { await queue.requestsSent } }

    /// Scores for an IMDb id such as "tt0133093".
    public func ratings(imdbID: String) async throws -> OMDbResult {
        try await lookup(query: [("i", imdbID)], key: CacheKey(provider: "omdb", kind: "title", id: imdbID, variant: ""), alsoStoreUnder: nil)
    }

    /// Scores by title and optional year (used only when no IMDb id is known).
    public func ratings(title: String, year: Int?, kind: TitleKind) async throws -> OMDbResult {
        var q: [(String, String)] = [("t", title), ("type", kind == .movie ? "movie" : "series")]
        if let year { q.append(("y", String(year))) }
        let id = "t:\(title.lowercased())|\(year.map(String.init) ?? "")|\(kind.rawValue)"
        return try await lookup(query: q, key: CacheKey(provider: "omdb", kind: "title", id: id, variant: ""), alsoStoreUnder: true)
    }

    private func lookup(query: [(String, String)], key: CacheKey, alsoStoreUnder: Bool?) async throws -> OMDbResult {
        guard !apiKey.isEmpty else { throw MetadataError.missingCredentials }
        let cached = await cache.entry(for: key)
        if let cached, cached.isFresh(at: clock.now()), let result = try? Self.decode(cached.data) { return result }

        var items = query
        items.append(("apikey", apiKey))
        items.append(("plot", "short"))
        let encoded = items.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: TMDBClient.queryAllowed) ?? "")" }.joined(separator: "&")
        guard let url = URL(string: baseURL.absoluteString + "?" + encoded) else { throw MetadataError.decoding("could not build the request address") }
        let request = HTTPRequest(url: url, method: "GET", headers: ["Accept": "application/json"])

        do {
            let response = try await queue.send(request)
            // OMDb reports problems inside the body, often with status 401 (bad key and quota) or 200 (not found).
            let result = try Self.decodeResponse(response)
            await cache.store(response.body, for: key, ttl: policy.ratings, at: clock.now())
            if alsoStoreUnder == true, let imdb = result.imdbID {
                await cache.store(response.body, for: CacheKey(provider: "omdb", kind: "title", id: imdb, variant: ""), ttl: policy.ratings, at: clock.now())
            }
            return result
        } catch let error as MetadataError {
            switch error {
            case .network, .server, .rateLimited, .quotaExhausted:
                if let cached, let result = try? Self.decode(cached.data) { return result }
            default: break
            }
            throw error
        }
    }

    static func decodeResponse(_ response: HTTPResponse) throws -> OMDbResult {
        if let json = try? JSON(data: response.body), json.isObject {
            if json["Response"].text?.lowercased() == "false" || (json["Response"].bool == false) {
                throw error(for: json["Error"].text ?? "", status: response.statusCode)
            }
            if (200...299).contains(response.statusCode) { return result(json) }
        }
        switch response.statusCode {
        case 401, 403: throw MetadataError.invalidAPIKey
        case 429: throw MetadataError.rateLimited(retryAfter: nil)
        case 500...599: throw MetadataError.server(response.statusCode)
        case 200...299: throw MetadataError.decoding("OMDb response is not an object")
        default: throw MetadataError.unexpectedStatus(response.statusCode)
        }
    }

    static func decode(_ data: Data) throws -> OMDbResult {
        try decodeResponse(HTTPResponse(statusCode: 200, body: data))
    }

    private static func error(for message: String, status: Int) -> MetadataError {
        let m = message.lowercased()
        if m.contains("invalid api key") || m.contains("no api key") { return .invalidAPIKey }
        if m.contains("request limit") { return .quotaExhausted }
        if m.contains("not found") || m.contains("incorrect imdb id") { return .notFound }
        if status == 401 || status == 403 { return .invalidAPIKey }
        return .decoding("OMDb: \(message)")
    }

    private static func result(_ json: JSON) -> OMDbResult {
        OMDbResult(imdbID: json["imdbID"].text, title: json["Title"].text, year: json["Year"].text, ratings: OMDbScoreParser.ratingSet(json))
    }
}
