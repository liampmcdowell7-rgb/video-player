import Foundation

// Discover calls: recommendations, similar titles and watch-provider data. These are the only calls in this target that
// return titles the user does NOT own, so they live in this separate file and are reached only from the Discover screens
// (AppLogic `DiscoverEngine`); the library-facing `LibraryMetadataService` never uses them (docs/METADATA.md section 2).
//
// Response shapes are written from TMDB's public documentation (read 2026-11-17: developer.themoviedb.org
// /reference/movie-watch-providers). NOT verified against the live service (no provider is contacted by tests).

/// One service that carries a title in one region.
public struct WatchProvider: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var logoPath: String?
    public var displayPriority: Int?

    public init(id: Int, name: String, logoPath: String? = nil, displayPriority: Int? = nil) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.displayPriority = displayPriority
    }
}

/// Where one title can be watched in one region. `link` is the provider's page address on the data supplier's site
/// (the required "link back" of the watch-provider data terms).
public struct WatchAvailability: Codable, Hashable, Sendable {
    public var region: String
    public var link: String?
    public var flatrate: [WatchProvider]
    public var rent: [WatchProvider]
    public var buy: [WatchProvider]

    public init(region: String, link: String? = nil, flatrate: [WatchProvider] = [], rent: [WatchProvider] = [], buy: [WatchProvider] = []) {
        self.region = region
        self.link = link
        self.flatrate = flatrate
        self.rent = rent
        self.buy = buy
    }

    public var isEmpty: Bool { flatrate.isEmpty && rent.isEmpty && buy.isEmpty }
}

enum TMDBDiscoverMapper {
    static func providers(_ j: JSON) -> [WatchProvider] {
        let list = j.array.compactMap { p -> WatchProvider? in
            guard let id = p["provider_id"].int, let name = p["provider_name"].text else { return nil }
            return WatchProvider(id: id, name: name, logoPath: p["logo_path"].text, displayPriority: p["display_priority"].int)
        }
        return list.enumerated().sorted { a, b in
            let (pa, pb) = (a.element.displayPriority ?? Int.max, b.element.displayPriority ?? Int.max)
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    /// Every region in the reply, keyed by upper-case country code.
    static func watchProviders(_ j: JSON) -> [String: WatchAvailability] {
        guard let results = j["results"].raw as? [String: Any] else { return [:] }
        var out: [String: WatchAvailability] = [:]
        for (code, value) in results {
            let entry = JSON(raw: value)
            let region = code.uppercased()
            out[region] = WatchAvailability(region: region, link: entry["link"].text, flatrate: providers(entry["flatrate"]),
                                            rent: providers(entry["rent"]), buy: providers(entry["buy"]))
        }
        return out
    }
}

extension TMDBClient {
    private func discoverSegment(_ kind: TitleKind) -> String { kind == .movie ? "movie" : "tv" }

    /// Titles TMDB lists as similar to one title (`/similar`).
    public func similar(kind: TitleKind, id: Int) async throws -> [SearchHit] {
        let seg = discoverSegment(kind)
        let json = try await fetch(path: "/\(seg)/\(id)/similar", query: [("language", language), ("page", "1")],
                                   key: CacheKey(provider: "tmdb", kind: seg, id: String(id), variant: "similar/\(language)"), ttl: policy.search)
        return TMDBMapper.hits(json, kind: kind)
    }

    /// Titles TMDB recommends for one title (`/recommendations`).
    public func recommendations(kind: TitleKind, id: Int) async throws -> [SearchHit] {
        let seg = discoverSegment(kind)
        let json = try await fetch(path: "/\(seg)/\(id)/recommendations", query: [("language", language), ("page", "1")],
                                   key: CacheKey(provider: "tmdb", kind: seg, id: String(id), variant: "recommendations/\(language)"), ttl: policy.search)
        return TMDBMapper.hits(json, kind: kind)
    }

    /// Watch-provider data for every region TMDB returns. Callers pick the region (`WatchAvailability` for the user's region).
    public func watchProviders(kind: TitleKind, id: Int) async throws -> [String: WatchAvailability] {
        let seg = discoverSegment(kind)
        let json = try await fetch(path: "/\(seg)/\(id)/watch/providers", key: CacheKey(provider: "tmdb", kind: seg, id: String(id), variant: "watch-providers"), ttl: policy.search)
        return TMDBDiscoverMapper.watchProviders(json)
    }
}
