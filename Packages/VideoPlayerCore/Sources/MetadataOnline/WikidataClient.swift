import Foundation
import VideoPlayerCore

/// #26 5b: Wikidata (query.wikidata.org), key-free structured facts released under CC0: title, year, cast names and the
/// IMDb and TMDB ids. Used as the fallback when no TMDB key is set, and to find an IMDb id for IntroDB. No images (no
/// Wikimedia Commons). Etiquette read 2026-11-19 (docs/DATA_SOURCES.md): a descriptive User-Agent, honour 429 Retry-After
/// (ProviderQueue does), keep requests few. maxlag belongs to the Action API (w/api.php), which this client does not use.
public struct WikidataTitle: Codable, Equatable, Sendable {
    public var qid: String
    public var label: String?
    public var year: Int?
    public var imdbID: String?
    public var tmdbID: Int?
    /// Cast member names in Wikidata's order (series ordinal when given), at most `WikidataClient.castLimit`.
    public var cast: [String]

    public init(qid: String, label: String? = nil, year: Int? = nil, imdbID: String? = nil, tmdbID: Int? = nil, cast: [String] = []) {
        self.qid = qid
        self.label = label
        self.year = year
        self.imdbID = imdbID
        self.tmdbID = tmdbID
        self.cast = cast
    }
}

public extension QueueConfiguration {
    /// One request per second at most, two retries, own cap of 300 per day per device (PROVISIONAL, OPEN_QUESTIONS R209).
    static let wikidata = QueueConfiguration(minInterval: 1.0, maxRetries: 2, baseBackoff: 2, maxBackoff: 60, dailyLimit: 300)
}

public final class WikidataClient: Sendable {
    public static let defaultEndpoint: URL = URL(string: "https://query.wikidata.org/sparql") ?? URL(fileURLWithPath: "/")
    /// Facts change rarely: 30 days; "nothing found" 7 days (PROVISIONAL, OPEN_QUESTIONS R209).
    public static let foundTTL: Double = 30 * 86_400
    public static let missingTTL: Double = 7 * 86_400
    public static let castLimit = 20

    private let queue: ProviderQueue
    private let cache: any MetadataCache
    private let clock: any MetadataClock
    private let endpoint: URL
    private let userAgent: String
    private let language: String

    public init(
        transport: any HTTPTransport,
        cache: any MetadataCache = InMemoryMetadataCache(),
        queueConfiguration: QueueConfiguration = .wikidata,
        clock: any MetadataClock = SystemMetadataClock(),
        userAgent: String,
        language: String = "en",
        endpoint: URL = WikidataClient.defaultEndpoint
    ) {
        self.queue = ProviderQueue(transport: transport, configuration: queueConfiguration, clock: clock)
        self.cache = cache
        self.clock = clock
        self.endpoint = endpoint
        self.userAgent = userAgent
        self.language = Self.safeLanguage(language)
    }

    public var requestsSent: Int { get async { await queue.requestsSent } }

    /// The title that carries this TMDB id (P4947 movie, P4983 series).
    public func title(tmdbID: Int, kind: TitleKind) async throws -> WikidataTitle? {
        let property = kind == .movie ? "P4947" : "P4983"
        let pattern = "?item wdt:\(property) \"\(tmdbID)\" ."
        return try await lookup(pattern: pattern, kind: kind, cacheID: "tmdb:\(kind.rawValue):\(tmdbID)")
    }

    /// The title with this IMDb id (P345).
    public func title(imdbID: String) async throws -> WikidataTitle? {
        guard IntroDBClient.isIMDbID(imdbID) else { return nil }
        return try await lookup(pattern: "?item wdt:P345 \"\(imdbID)\" .", kind: nil, cacheID: "imdb:\(imdbID)")
    }

    /// A film (Q11424) or TV series (Q5398426) whose label in the app's language is exactly this title, nearest the year.
    public func title(named name: String, year: Int?, kind: TitleKind) async throws -> WikidataTitle? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return nil }
        let klass = kind == .movie ? "Q11424" : "Q5398426"
        let pattern = "?item wdt:P31 wd:\(klass) ; rdfs:label \(Self.literal(trimmed))@\(language) ."
        let cacheID = "name:\(kind.rawValue):\(trimmed.lowercased())|\(year.map(String.init) ?? "")"
        return try await lookup(pattern: pattern, kind: kind, cacheID: cacheID, year: year)
    }

    // MARK: Query

    private func lookup(pattern: String, kind: TitleKind?, cacheID: String, year: Int? = nil) async throws -> WikidataTitle? {
        let key = CacheKey(provider: "wikidata", kind: "title", id: cacheID, variant: language)
        let cached = await cache.entry(for: key)
        if let cached, cached.isFresh(at: clock.now()) { return Self.decodeCached(cached.data) }

        let query = Self.query(pattern: pattern, language: language)
        guard let url = Self.url(endpoint: endpoint, query: query) else { throw MetadataError.decoding("could not build the request address") }
        let request = HTTPRequest(url: url, method: "GET", headers: [
            "Accept": "application/sparql-results+json",
            "User-Agent": userAgent,
        ])
        do {
            let response = try await queue.send(request)
            guard (200...299).contains(response.statusCode) else { throw MetadataError.unexpectedStatus(response.statusCode) }
            let found = try Self.decode(response.body, preferringYear: year)
            let data = found.flatMap { try? JSONEncoder().encode($0) } ?? Data()
            await cache.store(data, for: key, ttl: found == nil ? Self.missingTTL : Self.foundTTL, at: clock.now())
            return found
        } catch let error as MetadataError {
            switch error {
            case .network, .server, .rateLimited, .quotaExhausted:
                if let cached { return Self.decodeCached(cached.data) }
            default: break
            }
            throw error
        }
    }

    static func decodeCached(_ data: Data) -> WikidataTitle? {
        data.isEmpty ? nil : try? JSONDecoder().decode(WikidataTitle.self, from: data)
    }

    /// One query returns each candidate title with its facts; cast rows repeat the title (one row per cast member).
    static func query(pattern: String, language: String) -> String {
        """
        SELECT ?item ?itemLabel ?imdb ?tmdbMovie ?tmdbSeries ?date ?start ?castLabel ?order WHERE {
          \(pattern)
          OPTIONAL { ?item wdt:P345 ?imdb . }
          OPTIONAL { ?item wdt:P4947 ?tmdbMovie . }
          OPTIONAL { ?item wdt:P4983 ?tmdbSeries . }
          OPTIONAL { ?item wdt:P577 ?date . }
          OPTIONAL { ?item wdt:P580 ?start . }
          OPTIONAL { ?item p:P161 ?st . ?st ps:P161 ?cast . OPTIONAL { ?st pq:P1545 ?order . } }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "\(language),mul,en" . }
        } LIMIT 400
        """
    }

    static func url(endpoint: URL, query: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let q = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: endpoint.absoluteString + "?format=json&query=" + q)
    }

    /// A SPARQL string literal: backslash, quote and line breaks are escaped, so a title can never change the query.
    static func literal(_ text: String) -> String {
        var out = "\""
        for c in text {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        return out + "\""
    }

    static func safeLanguage(_ code: String) -> String {
        let lower = code.lowercased()
        let ok = !lower.isEmpty && lower.count <= 12 && lower.allSatisfy { ("a"..."z").contains($0) || $0 == "-" }
        return ok ? lower : "en"
    }

    static func decode(_ body: Data, preferringYear year: Int?) throws -> WikidataTitle? {
        guard let json = try? JSON(data: body), json.isObject else { throw MetadataError.decoding("Wikidata response is not an object") }
        struct Building { var title: WikidataTitle; var cast: [(name: String, order: Int)] = [] }
        var byQID: [String: Building] = [:]
        var order: [String] = []
        for row in json["results"]["bindings"].array {
            guard let uri = row["item"]["value"].text, let qid = uri.split(separator: "/").last.map(String.init),
                  qid.hasPrefix("Q") else { continue }
            if byQID[qid] == nil {
                order.append(qid)
                let label = row["itemLabel"]["value"].text.flatMap { $0 == qid ? nil : $0 }
                let date = row["date"]["value"].text ?? row["start"]["value"].text
                let tmdb = (row["tmdbMovie"]["value"].text ?? row["tmdbSeries"]["value"].text).flatMap(Int.init)
                let imdb = row["imdb"]["value"].text.flatMap { IntroDBClient.isIMDbID($0) ? $0 : nil }
                byQID[qid] = Building(title: WikidataTitle(qid: qid, label: label, year: date.flatMap(Self.year), imdbID: imdb, tmdbID: tmdb))
            } else if let date = row["date"]["value"].text ?? row["start"]["value"].text, let y = Self.year(date),
                      let current = byQID[qid]?.title.year, y < current {
                byQID[qid]?.title.year = y // the earliest release date is the year
            }
            if let name = row["castLabel"]["value"].text, !name.hasPrefix("http"), !(name.first == "Q" && name.dropFirst().allSatisfy(\.isNumber)),
               byQID[qid]?.cast.contains(where: { $0.name == name }) == false {
                byQID[qid]?.cast.append((name, row["order"]["value"].text.flatMap(Int.init) ?? Int.max))
            }
        }
        var titles: [WikidataTitle] = order.compactMap { qid in
            guard var b = byQID[qid] else { return nil }
            b.title.cast = b.cast.enumerated()
                .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
                .prefix(castLimit).map(\.element.name)
            return b.title
        }
        if let year {
            titles.sort { abs(($0.year ?? 9999) - year) < abs(($1.year ?? 9999) - year) }
            // A different year by more than one is a different title with the same name.
            if let first = titles.first, let y = first.year, abs(y - year) > 1 { return nil }
        }
        return titles.first
    }

    static func year(_ isoDate: String) -> Int? {
        let digits = isoDate.drop { $0 == "+" }.prefix(4)
        guard digits.count == 4, let y = Int(digits), (1870...2200).contains(y) else { return nil }
        return y
    }
}
