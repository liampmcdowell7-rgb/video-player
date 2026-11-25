import Foundation
import LibraryIndex
import MetadataOnline

/// R471 (18), PROVISIONAL: Refresh Details for one title. A real refetch, not a page reload: the online answers kept for
/// this title only (TMDB's movie or show entries, a show's seasons and episodes with it; the free data source's entries for
/// the title) are dropped, then the page's details and picture are fetched again through the same providers in the same
/// order (`LayeredDetailsService`, the artwork engine). The user's own edits, chosen pictures and Fix Match live in the user
/// layer, never in this cache, so they stay on top (R449 to R451). Other titles are not touched.
public enum TitleRefresh {
    public enum Target: Equatable, Sendable {
        case movie(itemID: Int64)
        case episode(itemID: Int64)
        case show(seriesID: Int64)

        /// The page's details key ("item-N", "series-N").
        public var detailsKey: String {
            switch self {
            case let .movie(id), let .episode(id): return "item-\(id)"
            case let .show(id): return "series-\(id)"
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// Details came back from at least one layer.
        case refreshed
        /// Nothing answered (no match, no key, offline): the page keeps what the file and the source give.
        case nothingFound
    }

    /// The cache key prefixes of one title: the catalogue's entries by its online id, and the free source's entries by that
    /// id and by its name (every year).
    public static func prefixes(tmdbID: Int?, kind: TitleKind, name: String) -> [String] {
        var out: [String] = []
        if let tmdbID {
            out.append("tmdb/\(kind == .movie ? "movie" : "tv")/\(tmdbID)/")
            out.append("wikidata/title/tmdb:\(kind.rawValue):\(tmdbID)/")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty { out.append("wikidata/title/name:\(kind.rawValue):\(trimmed)|") }
        return out
    }

    public static func result(_ outcome: Outcome) -> (title: String, message: String) {
        switch outcome {
        case .refreshed:
            return ("Details Refreshed", "The description, cast and pictures were fetched again. Your own edits and choices stay.")
        case .nothingFound:
            return ("Nothing New Found",
                    "No online details answered for this title. The page shows what the file and its source give, with your own edits.")
        }
    }
}

/// Runs Refresh Details for one title against a metadata cache and the page's fetch.
public struct TitleRefresher: Sendable {
    public let store: any LibraryStore
    public let cache: any MetadataCache
    /// Fetches the page's details again (the layered providers) and says whether any layer answered.
    public let refetch: @Sendable (String) async -> Bool

    public init(store: any LibraryStore, cache: any MetadataCache, refetch: @escaping @Sendable (String) async -> Bool) {
        self.store = store; self.cache = cache; self.refetch = refetch
    }

    /// Drops the title's kept answers and fetches again. Returns how many kept answers were dropped and the outcome.
    @discardableResult
    public func run(_ target: TitleRefresh.Target) async -> (dropped: Int, outcome: TitleRefresh.Outcome) {
        var dropped = 0
        for prefix in await prefixes(target) { dropped += await cache.remove(prefix: prefix) }
        let found = await refetch(target.detailsKey)
        return (dropped, found ? .refreshed : .nothingFound)
    }

    func prefixes(_ target: TitleRefresh.Target) async -> [String] {
        switch target {
        case let .movie(id):
            guard let item = try? await store.item(id: id) else { return [] }
            return TitleRefresh.prefixes(tmdbID: item.tmdbID, kind: .movie, name: item.title)
        case let .episode(id):
            // An episode's online entries are kept under its show's.
            guard let item = try? await store.item(id: id) else { return [] }
            return TitleRefresh.prefixes(tmdbID: item.tmdbID, kind: .series, name: item.seriesTitle ?? "")
        case let .show(seriesID):
            let episodes = (try? await store.episodes(ofSeries: seriesID)) ?? []
            let ids = episodes.compactMap(\.tmdbID)
            let counts = Dictionary(grouping: ids, by: { $0 }).mapValues(\.count)
            let tmdbID = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key
            return TitleRefresh.prefixes(tmdbID: tmdbID, kind: .series, name: episodes.first?.seriesTitle ?? "")
        }
    }
}
