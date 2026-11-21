import Foundation
import VideoPlayerCore

/// #26 5b: Wikidata (query.wikidata.org), key-free structured facts released under CC0: title, year, cast names and the
/// IMDb and TMDB ids. Used as the fallback when no TMDB key is set, and to find an IMDb id for IntroDB. No images (no
/// Wikimedia Commons). Etiquette read 2026-11-19 (docs/DATA_SOURCES.md): a descriptive User-Agent, honour 429 Retry-After
/// (ProviderQueue does), keep requests few. maxlag belongs to the Action API (w/api.php), which this client does not use.
/// R372 (owner's request of 21 Nov 2026): one official rating of a title on Wikidata, with the content descriptors that
/// qualify it. Property ids read on Wikidata's property pages on 21 Nov 2026: P1657 "MPA film rating", P2629 "BBFC
/// rating", P1981 "FSK film rating", P3156 "Australian Classification", P3216 "ClassInd rating" (all of data type Item);
/// P7367 "content descriptor" (Item; its scope is "as qualifier", so it qualifies a rating statement). No property for the
/// US TV Parental Guidelines was found on Wikidata (property search, 21 Nov 2026), so TV ratings come from the source or
/// TMDB only.
public struct WikidataRating: Codable, Equatable, Sendable {
    /// The rating system: "MPA", "BBFC", "FSK", "ACB", "ClassInd" (`WikidataClient.ratingSystems`).
    public var system: String
    /// The rating item's label in the app's language ("R", "PG-13", "15").
    public var label: String
    /// The labels of its content descriptors (P7367), in Wikidata's order ("Violence", "Strong Language").
    public var descriptors: [String]

    public init(system: String, label: String, descriptors: [String] = []) {
        self.system = system
        self.label = label
        self.descriptors = descriptors
    }
}

public struct WikidataTitle: Codable, Equatable, Sendable {
    public var qid: String
    public var label: String?
    public var year: Int?
    public var imdbID: String?
    public var tmdbID: Int?
    /// Cast member names in Wikidata's order (series ordinal when given), at most `WikidataClient.castLimit`.
    public var cast: [String]
    /// R372: the official ratings found (nil when none; optional so entries cached before R372 still decode).
    public var ratings: [WikidataRating]?

    public init(qid: String, label: String? = nil, year: Int? = nil, imdbID: String? = nil, tmdbID: Int? = nil, cast: [String] = [],
                ratings: [WikidataRating]? = nil) {
        self.qid = qid
        self.label = label
        self.year = year
        self.imdbID = imdbID
        self.tmdbID = tmdbID
        self.cast = cast
        self.ratings = ratings
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
    /// R372: the rating properties read, with the region each system belongs to (for the Region setting).
    public static let ratingSystems: [(system: String, property: String, region: String)] = [
        ("MPA", "P1657", "US"), ("BBFC", "P2629", "GB"), ("FSK", "P1981", "DE"), ("ACB", "P3156", "AU"), ("ClassInd", "P3216", "BR"),
    ]
    /// R372: the cache variant changed when the query gained the ratings, so a title cached before is asked once more.
    static let cacheVersion = "ratings1"

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
        let key = CacheKey(provider: "wikidata", kind: "title", id: cacheID, variant: language + "|" + Self.cacheVersion)
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

    /// One query returns each candidate title with its facts; cast rows repeat the title (one row per cast member). R372:
    /// the same query also returns one row per official rating and content descriptor, in a UNION with the cast so the two
    /// never multiply each other's rows. Same request, same endpoint: nothing else is sent.
    static func query(pattern: String, language: String) -> String {
        let systems = ratingSystems.map { "(p:\($0.property) ps:\($0.property) \"\($0.system)\")" }.joined(separator: " ")
        return """
        SELECT ?item ?itemLabel ?imdb ?tmdbMovie ?tmdbSeries ?date ?start ?castLabel ?order ?board ?ratingLabel ?descriptorLabel WHERE {
          \(pattern)
          OPTIONAL { ?item wdt:P345 ?imdb . }
          OPTIONAL { ?item wdt:P4947 ?tmdbMovie . }
          OPTIONAL { ?item wdt:P4983 ?tmdbSeries . }
          OPTIONAL { ?item wdt:P577 ?date . }
          OPTIONAL { ?item wdt:P580 ?start . }
          OPTIONAL {
            { ?item p:P161 ?st . ?st ps:P161 ?cast . OPTIONAL { ?st pq:P1545 ?order . } }
            UNION
            { VALUES (?rp ?rps ?board) { \(systems) }
              ?item ?rp ?rst . ?rst ?rps ?rating . OPTIONAL { ?rst pq:P7367 ?descriptor . } }
          }
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
        struct Building { var title: WikidataTitle; var cast: [(name: String, order: Int)] = []; var ratings: [WikidataRating] = [] }
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
            // R372: a rating row: its system, the rating's label and (when the statement has one) a descriptor's label.
            if let board = row["board"]["value"].text, let rating = row["ratingLabel"]["value"].text, Self.isLabel(rating) {
                let descriptor = row["descriptorLabel"]["value"].text.flatMap { Self.isLabel($0) ? $0 : nil }
                if let i = byQID[qid]?.ratings.firstIndex(where: { $0.system == board && $0.label == rating }) {
                    if let descriptor, byQID[qid]?.ratings[i].descriptors.contains(descriptor) == false {
                        byQID[qid]?.ratings[i].descriptors.append(descriptor)
                    }
                } else {
                    byQID[qid]?.ratings.append(WikidataRating(system: board, label: rating, descriptors: descriptor.map { [$0] } ?? []))
                }
            }
        }
        var titles: [WikidataTitle] = order.compactMap { qid in
            guard var b = byQID[qid] else { return nil }
            b.title.cast = b.cast.enumerated()
                .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
                .prefix(castLimit).map(\.element.name)
            b.title.ratings = b.ratings.isEmpty ? nil : b.ratings
            return b.title
        }
        if let year {
            titles.sort { abs(($0.year ?? 9999) - year) < abs(($1.year ?? 9999) - year) }
            // A different year by more than one is a different title with the same name.
            if let first = titles.first, let y = first.year, abs(y - year) > 1 { return nil }
        }
        return titles.first
    }

    /// A label, not an address or a bare item id (the label service answers the id when an item has no label).
    static func isLabel(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("http") && !(text.first == "Q" && text.dropFirst().allSatisfy(\.isNumber))
    }

    static func year(_ isoDate: String) -> Int? {
        let digits = isoDate.drop { $0 == "+" }.prefix(4)
        guard digits.count == 4, let y = Int(digits), (1870...2200).contains(y) else { return nil }
        return y
    }
}
