import Foundation
import VideoPlayerCore
@testable import MetadataOnline

/// Never touches the network. Answers from a handler and records every request.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) throws -> HTTPResponse
    private let lock = NSLock()
    private var _requests: [HTTPRequest] = []
    private var handler: Handler

    init(_ handler: @escaping Handler = { _ in HTTPResponse(statusCode: 404) }) { self.handler = handler }

    var requests: [HTTPRequest] { lock.lock(); defer { lock.unlock() }; return _requests }
    var count: Int { requests.count }
    func setHandler(_ h: @escaping Handler) { lock.lock(); handler = h; lock.unlock() }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let h: Handler = lock.withLock {
            _requests.append(request)
            return handler
        }
        return try h(request)
    }

    /// Routes by the URL path (everything after the API base) and answers with the first matching JSON.
    static func routes(_ table: [String: String], status: Int = 200) -> MockTransport {
        MockTransport { request in
            let path = request.url.path
            for (suffix, body) in table where path.hasSuffix(suffix) {
                return HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
            }
            return HTTPResponse(statusCode: 404, body: Data(Fixtures.tmdbNotFound.utf8))
        }
    }
}

/// A clock that never waits: `sleep` moves the time forward and records the request.
final class FakeClock: MetadataClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private var _sleeps: [Double] = []

    init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }

    func now() -> Date { lock.lock(); defer { lock.unlock() }; return current }
    var sleeps: [Double] { lock.lock(); defer { lock.unlock() }; return _sleeps }
    var totalSlept: Double { sleeps.reduce(0, +) }
    func advance(_ seconds: Double) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }

    func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        lock.withLock {
            _sleeps.append(seconds)
            current = current.addingTimeInterval(seconds)
        }
    }
}

func response(_ status: Int, _ body: String = "", headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(statusCode: status, headers: headers, body: Data(body.utf8))
}

/// A queue configuration for tests: no spacing, no jitter.
func plainQueue(retries: Int = 3, base: Double = 1, max: Double = 30, minInterval: Double = 0, jitter: Double = 0, daily: Int? = nil) -> QueueConfiguration {
    QueueConfiguration(minInterval: minInterval, maxRetries: retries, baseBackoff: base, maxBackoff: max, jitter: jitter, dailyLimit: daily)
}

func tempDirectory(_ name: String = "mo") -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: Parsed names

enum P {
    static func movie(_ title: String, year: Int? = nil, edition: String? = nil) -> ParsedMedia {
        var p = ParsedMedia()
        p.kind = .movie
        p.title = title
        p.year = year
        p.edition = edition
        return p
    }

    static func episode(_ title: String, year: Int? = nil, season: Int? = nil, episodes: [Int] = [], absolute: Int? = nil, special: Bool = false) -> ParsedMedia {
        var p = ParsedMedia()
        p.kind = .episode
        p.title = title
        p.year = year
        p.season = season
        p.episodes = episodes
        p.absoluteEpisode = absolute
        p.isSpecial = special
        return p
    }
}

// MARK: Fake catalogue

/// A catalogue that answers from lists and records each call, so tests can say what was (not) asked.
final class FakeCatalog: CatalogProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var movies: [SearchHit] = []
    var series: [SearchHit] = []
    var runtimes: [Int: Int] = [:]
    var alternatives: [Int: [String]] = [:]
    var seasonSummaries: [Int: [SeasonSummary]] = [:]
    var seasons: [String: SeasonMetadata] = [:]
    var imdbToHits: [String: [SearchHit]] = [:]
    var failingSearch: MetadataError?

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
    private func record(_ s: String) { lock.lock(); _calls.append(s); lock.unlock() }
    func calls(withPrefix p: String) -> [String] { calls.filter { $0.hasPrefix(p) } }

    /// Roughly what TMDB does: loose title matching, and an exact year filter when a year is sent.
    private func filter(_ hits: [SearchHit], query: String, year: Int?) -> [SearchHit] {
        hits.filter { h in
            let names = [h.title] + (h.originalTitle.map { [$0] } ?? [])
            let loose = names.contains { TitleText.similarity(query, $0) >= 0.5 }
            return loose && (year == nil || h.year == year)
        }
    }

    func searchMovies(query: String, year: Int?) async throws -> [SearchHit] {
        record("searchMovies:\(query)|\(year.map(String.init) ?? "-")")
        if let failingSearch { throw failingSearch }
        return filter(movies, query: query, year: year)
    }

    func searchSeries(query: String, firstAirYear: Int?) async throws -> [SearchHit] {
        record("searchSeries:\(query)|\(firstAirYear.map(String.init) ?? "-")")
        if let failingSearch { throw failingSearch }
        return filter(series, query: query, year: firstAirYear)
    }

    func hit(tmdbID: Int, kind: TitleKind) async throws -> SearchHit {
        record("hit:\(kind.rawValue):\(tmdbID)")
        let found = (kind == .movie ? movies : series).first { $0.tmdbID == tmdbID }
        guard let found else { throw MetadataError.notFound }
        return found
    }

    func find(imdbID: String) async throws -> [SearchHit] {
        record("find:\(imdbID)")
        return imdbToHits[imdbID] ?? []
    }

    func alternativeTitles(kind: TitleKind, id: Int) async throws -> [String] {
        record("alt:\(id)")
        return alternatives[id] ?? []
    }

    func movieRuntime(id: Int) async throws -> Int? {
        record("runtime:\(id)")
        return runtimes[id]
    }

    func seriesSeasons(id: Int) async throws -> [SeasonSummary] {
        record("seasons:\(id)")
        guard let s = seasonSummaries[id] else { throw MetadataError.notFound }
        return s
    }

    func season(seriesID: Int, number: Int) async throws -> SeasonMetadata {
        record("season:\(seriesID):\(number)")
        guard let s = seasons["\(seriesID)/\(number)"] else { throw MetadataError.notFound }
        return s
    }

    // Builders
    func addSeason(series id: Int, number: Int, episodes: [(Int, String, Int?, CalendarDate?)], startDate: CalendarDate? = nil) {
        let eps = episodes.map { EpisodeMetadata(seriesID: id, seasonNumber: number, episodeNumber: $0.0, name: $0.1, airDate: $0.3, runtimeMinutes: $0.2) }
        seasons["\(id)/\(number)"] = SeasonMetadata(seriesID: id, seasonNumber: number, episodes: eps)
        var list = seasonSummaries[id] ?? []
        list.removeAll { $0.seasonNumber == number }
        list.append(SeasonSummary(seasonNumber: number, episodeCount: episodes.count, airDate: startDate))
        seasonSummaries[id] = list.sorted { $0.seasonNumber < $1.seasonNumber }
    }
}

extension SearchHit {
    static func movie(_ id: Int, _ title: String, year: Int?, original: String? = nil, popularity: Double = 10) -> SearchHit {
        SearchHit(tmdbID: id, kind: .movie, title: title, originalTitle: original ?? title, year: year, popularity: popularity)
    }
    static func show(_ id: Int, _ title: String, year: Int?, original: String? = nil, popularity: Double = 10) -> SearchHit {
        SearchHit(tmdbID: id, kind: .series, title: title, originalTitle: original ?? title, year: year, popularity: popularity)
    }
}

/// A library that owns exactly the listed items and TMDB ids.
struct FakeLibrary: LibraryCatalog {
    var items: Set<String>
    var tmdbIDs: Set<Int> = []
    func contains(itemID: LibraryItemID) async -> Bool { items.contains(itemID) }
    func ownedTMDBIDs() async -> Set<Int> { tmdbIDs }
}
