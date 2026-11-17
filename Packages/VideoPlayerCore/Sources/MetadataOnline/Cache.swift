import Foundation

/// Key of one cached value: `provider/kind/id/variant`, for example `tmdb/movie/603/en-US`
/// or `tmdb/tv/1399/season-2/en-US`. The text form is what prefix invalidation works on.
public struct CacheKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public var provider: String
    public var kind: String
    public var id: String
    public var variant: String

    public init(provider: String, kind: String, id: String, variant: String = "") {
        self.provider = provider
        self.kind = kind
        self.id = id
        self.variant = variant
    }

    public var description: String { "\(provider)/\(kind)/\(id)/\(variant)" }
}

public struct CacheEntry: Codable, Sendable, Equatable {
    public var storedAt: Date
    /// Seconds the value counts as fresh.
    public var ttl: Double
    public var data: Data

    public init(storedAt: Date, ttl: Double, data: Data) {
        self.storedAt = storedAt
        self.ttl = ttl
        self.data = data
    }

    public func isFresh(at now: Date) -> Bool { now.timeIntervalSince(storedAt) < ttl }
}

/// Local cache so browsing is instant and works offline after the first match.
public protocol MetadataCache: Sendable {
    func entry(for key: CacheKey) async -> CacheEntry?
    func store(_ data: Data, for key: CacheKey, ttl: Double, at date: Date) async
    func remove(_ key: CacheKey) async
    /// Removes every entry whose text key starts with `prefix`. Returns how many were removed.
    @discardableResult func remove(prefix: String) async -> Int
    func removeAll() async
}

public struct CachePolicy: Sendable, Equatable {
    public var details: Double
    public var season: Double
    public var search: Double
    public var configuration: Double
    public var ratings: Double

    public init(details: Double = 14 * 86_400, season: Double = 3 * 86_400, search: Double = 86_400, configuration: Double = 7 * 86_400, ratings: Double = 7 * 86_400) {
        self.details = details
        self.season = season
        self.search = search
        self.configuration = configuration
        self.ratings = ratings
    }

    public static let standard = CachePolicy()
}

// MARK: In memory

public actor InMemoryMetadataCache: MetadataCache {
    private var entries: [String: CacheEntry] = [:]
    public init() {}

    public func entry(for key: CacheKey) -> CacheEntry? { entries[key.description] }
    public func store(_ data: Data, for key: CacheKey, ttl: Double, at date: Date) {
        entries[key.description] = CacheEntry(storedAt: date, ttl: ttl, data: data)
    }
    public func remove(_ key: CacheKey) { entries[key.description] = nil }
    @discardableResult public func remove(prefix: String) -> Int {
        let doomed = entries.keys.filter { $0.hasPrefix(prefix) }
        for k in doomed { entries[k] = nil }
        return doomed.count
    }
    public func removeAll() { entries.removeAll() }
    public var count: Int { entries.count }
    public var keys: [String] { entries.keys.sorted() }
}

// MARK: On disk

/// One small JSON file per key in a folder. Files that cannot be read are ignored and replaced.
public actor JSONFileMetadataCache: MetadataCache {
    private let directory: URL
    private let fileManager = FileManager.default
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(_ text: String) -> URL {
        let name = text.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? UUID().uuidString
        return directory.appendingPathComponent(name + ".json")
    }

    private static func decodeName(_ file: String) -> String? {
        guard file.hasSuffix(".json") else { return nil }
        return String(file.dropLast(5)).removingPercentEncoding
    }

    public func entry(for key: CacheKey) -> CacheEntry? {
        guard let data = try? Data(contentsOf: fileURL(key.description)) else { return nil }
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }

    public func store(_ data: Data, for key: CacheKey, ttl: Double, at date: Date) {
        let entry = CacheEntry(storedAt: date, ttl: ttl, data: data)
        guard let encoded = try? JSONEncoder().encode(entry) else { return }
        try? encoded.write(to: fileURL(key.description), options: .atomic)
    }

    public func remove(_ key: CacheKey) {
        try? fileManager.removeItem(at: fileURL(key.description))
    }

    @discardableResult public func remove(prefix: String) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for file in files {
            guard let name = Self.decodeName(file), name.hasPrefix(prefix) else { continue }
            if (try? fileManager.removeItem(at: directory.appendingPathComponent(file))) != nil { removed += 1 }
        }
        return removed
    }

    public func removeAll() {
        guard let files = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where file.hasSuffix(".json") {
            try? fileManager.removeItem(at: directory.appendingPathComponent(file))
        }
    }
}

// MARK: Refresh Metadata

/// What "Refresh Metadata" applies to: one item, a folder's items, or the whole library.
public enum RefreshScope: Sendable {
    /// One movie or series (a series also drops its seasons and episodes).
    case item(ProviderIDs, kind: TitleKind)
    /// Every matched item of a folder (the caller lists them).
    case folder([(ids: ProviderIDs, kind: TitleKind)])
    /// Everything this target cached, including search results.
    case library
}

public enum MetadataRefresh {
    /// Drops the cached values so the next read fetches fresh data. Nothing is fetched here.
    @discardableResult
    public static func invalidate(_ scope: RefreshScope, in cache: any MetadataCache) async -> Int {
        switch scope {
        case .item(let ids, let kind):
            return await invalidate(ids: ids, kind: kind, in: cache)
        case .folder(let items):
            var total = 0
            for item in items { total += await invalidate(ids: item.ids, kind: item.kind, in: cache) }
            return total
        case .library:
            let a = await cache.remove(prefix: "tmdb/")
            let b = await cache.remove(prefix: "omdb/")
            return a + b
        }
    }

    private static func invalidate(ids: ProviderIDs, kind: TitleKind, in cache: any MetadataCache) async -> Int {
        var total = 0
        if let tmdb = ids.tmdb {
            let segment = kind == .movie ? "movie" : "tv"
            total += await cache.remove(prefix: "tmdb/\(segment)/\(tmdb)/")
        }
        if let imdb = ids.imdb { total += await cache.remove(prefix: "omdb/title/\(imdb)/") }
        return total
    }
}
