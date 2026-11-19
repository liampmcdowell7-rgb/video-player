import Foundation
import VideoPlayerCore

/// #26 5a: IntroDB (api.introdb.app), a key-free database of intro, recap and credits timings looked up by IMDb id.
/// Terms read 2026-11-19 (docs/DATA_SOURCES.md): commercial apps with reasonable use are allowed, no bulk crawling,
/// attribution optional for API use. The app asks only for the one title being played, never in bulk, caches every answer
/// (also "not in the database") and keeps a slow pace with its own daily cap.
public struct IntroDBTimings: Codable, Equatable, Sendable {
    public struct Span: Codable, Equatable, Sendable {
        public var start: Double
        public var end: Double
        /// 0...1, nil when the database gave none (the app then does not use the span: below the 0.7 threshold).
        public var confidence: Double?
        public var submissions: Int?

        public init(start: Double, end: Double, confidence: Double?, submissions: Int? = nil) {
            self.start = start
            self.end = end
            self.confidence = confidence
            self.submissions = submissions
        }
    }

    public var intro: Span?
    public var recap: Span?
    /// IntroDB's "outro": the end credits.
    public var outro: Span?

    public init(intro: Span? = nil, recap: Span? = nil, outro: Span? = nil) {
        self.intro = intro
        self.recap = recap
        self.outro = outro
    }

    public var isEmpty: Bool { intro == nil && recap == nil && outro == nil }
}

public enum IntroDBTitle: Equatable, Sendable {
    case movie(imdbID: String)
    case episode(seriesIMDbID: String, season: Int, episode: Int)

    var imdbID: String {
        switch self {
        case .movie(let id), .episode(let id, _, _): return id
        }
    }

    var cacheID: String {
        switch self {
        case .movie(let id): return id
        case .episode(let id, let s, let e): return "\(id)/s\(s)e\(e)"
        }
    }
}

public extension QueueConfiguration {
    /// IntroDB publishes no numeric limit (unverified). One request per second at most, one retry, and an own cap of 300
    /// requests per day per device, far below anything a person watching would need.
    static let introDB = QueueConfiguration(minInterval: 1.0, maxRetries: 1, baseBackoff: 2, maxBackoff: 30, dailyLimit: 300)
}

public final class IntroDBClient: Sendable {
    public static let defaultBaseURL: URL = URL(string: "https://api.introdb.app/") ?? URL(fileURLWithPath: "/")
    /// A found answer is kept 7 days, "not in the database" 1 day (both PROVISIONAL, OPEN_QUESTIONS R209).
    public static let foundTTL: Double = 7 * 86_400
    public static let missingTTL: Double = 86_400

    private let queue: ProviderQueue
    private let cache: any MetadataCache
    private let clock: any MetadataClock
    private let baseURL: URL
    private let userAgent: String

    public init(
        transport: any HTTPTransport,
        cache: any MetadataCache = InMemoryMetadataCache(),
        queueConfiguration: QueueConfiguration = .introDB,
        clock: any MetadataClock = SystemMetadataClock(),
        userAgent: String,
        baseURL: URL = IntroDBClient.defaultBaseURL
    ) {
        self.queue = ProviderQueue(transport: transport, configuration: queueConfiguration, clock: clock)
        self.cache = cache
        self.clock = clock
        self.baseURL = baseURL
        self.userAgent = userAgent
    }

    public var requestsSent: Int { get async { await queue.requestsSent } }

    /// Only well-formed IMDb ids ("tt" and 7 to 10 digits) are ever sent.
    public static func isIMDbID(_ text: String) -> Bool {
        guard text.hasPrefix("tt") else { return false }
        let digits = text.dropFirst(2)
        return (7...10).contains(digits.count) && digits.allSatisfy(\.isASCIIDigit)
    }

    /// Timings for one movie or episode; nil when IntroDB has none. Errors (offline, server, quota) are thrown; a stale
    /// cached answer is returned instead when there is one.
    public func timings(for title: IntroDBTitle) async throws -> IntroDBTimings? {
        guard Self.isIMDbID(title.imdbID) else { throw MetadataError.decoding("not an IMDb id") }
        let key = CacheKey(provider: "introdb", kind: "segments", id: title.cacheID)
        let cached = await cache.entry(for: key)
        if let cached, cached.isFresh(at: clock.now()) { return Self.decodeCached(cached.data) }

        var items: [(String, String)] = [("imdb_id", title.imdbID)]
        switch title {
        case .movie: items.append(("is_movie", "true"))
        case .episode(_, let s, let e): items += [("season", String(s)), ("episode", String(e))]
        }
        let query = items.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        guard let url = URL(string: baseURL.absoluteString + "segments?" + query) else {
            throw MetadataError.decoding("could not build the request address")
        }
        let request = HTTPRequest(url: url, method: "GET", headers: ["Accept": "application/json", "User-Agent": userAgent])

        do {
            let response = try await queue.send(request)
            switch response.statusCode {
            case 200...299:
                let timings = try Self.decode(response.body)
                let stored = timings.isEmpty ? Data() : (try? JSONEncoder().encode(timings)) ?? Data()
                await cache.store(stored, for: key, ttl: timings.isEmpty ? Self.missingTTL : Self.foundTTL, at: clock.now())
                return timings.isEmpty ? nil : timings
            case 404:
                await cache.store(Data(), for: key, ttl: Self.missingTTL, at: clock.now())
                return nil
            default:
                throw MetadataError.unexpectedStatus(response.statusCode)
            }
        } catch let error as MetadataError {
            switch error {
            case .network, .server, .rateLimited, .quotaExhausted:
                if let cached { return Self.decodeCached(cached.data) }
            default: break
            }
            throw error
        }
    }

    static func decodeCached(_ data: Data) -> IntroDBTimings? {
        data.isEmpty ? nil : try? JSONDecoder().decode(IntroDBTimings.self, from: data)
    }

    /// The response fields as documented on introdb.app (read 2026-11-19): intro, recap, outro, each null or an object
    /// with start_sec/end_sec (or start_ms/end_ms), confidence and submission_count.
    static func decode(_ body: Data) throws -> IntroDBTimings {
        guard let json = try? JSON(data: body), json.isObject else { throw MetadataError.decoding("IntroDB response is not an object") }
        return IntroDBTimings(intro: span(json["intro"]), recap: span(json["recap"]), outro: span(json["outro"]))
    }

    static func span(_ j: JSON) -> IntroDBTimings.Span? {
        guard j.isObject else { return nil }
        let start = j["start_ms"].double.map { $0 / 1000 } ?? j["start_sec"].double
        let end = j["end_ms"].double.map { $0 / 1000 } ?? j["end_sec"].double
        guard let start, let end, start.isFinite, end.isFinite, start >= 0, end > start else { return nil }
        // Unverified scale: a value above 1 is read as a percentage.
        let confidence = j["confidence"].double.map { $0 > 1 ? $0 / 100 : $0 }.map { min(1, max(0, $0)) }
        return .init(start: start, end: end, confidence: confidence, submissions: j["submission_count"].int)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
