import Foundation
import MetadataOnline
import UserData
import LibraryIndex

/// Where the Discover screen gets the user's library facts.
public protocol DiscoverLibraryProviding: Sendable {
    func discoverLibrary() async throws -> DiscoverLibrary
}

/// Reads the library index: which TMDB titles and episodes the user owns, and which owned titles to base suggestions on.
/// An item only counts when it has a TMDB id (set by Fix Match or by the background matcher); unmatched files are not guessed at.
public struct StoreDiscoverLibrary: DiscoverLibraryProviding {
    public let store: any LibraryStore
    public let pageSize: Int
    public init(store: any LibraryStore, pageSize: Int = 500) { self.store = store; self.pageSize = pageSize }

    public func discoverLibrary() async throws -> DiscoverLibrary {
        var movies: [LibraryItem] = []
        var episodesBySeries: [Int64: [LibraryItem]] = [:]
        var cursor: ItemCursor?
        repeat {
            let page = try await store.page(ItemQuery(), limit: pageSize, after: cursor)
            for item in page.items {
                guard item.tmdbID != nil else { continue }
                if item.kind == .movie { movies.append(item) } else if let sid = item.seriesID { episodesBySeries[sid, default: []].append(item) }
            }
            cursor = page.next
        } while cursor != nil
        return Self.assemble(movies: movies, episodesBySeries: episodesBySeries)
    }

    static func assemble(movies: [LibraryItem], episodesBySeries: [Int64: [LibraryItem]]) -> DiscoverLibrary {
        var library = DiscoverLibrary()
        var seedPool: [(seed: DiscoverSeed, favorite: Bool, played: Date?)] = []
        for m in movies {
            guard let id = m.tmdbID else { continue }
            library.ownedMovieIDs.insert(id)
            seedPool.append((DiscoverSeed(kind: .movie, tmdbID: id, title: m.title), m.watch.favorite, m.watch.lastPlayed))
        }
        for (_, items) in episodesBySeries {
            // One series can carry slightly different ids on different files; the most common one wins (ties: the smaller id).
            let counts = Dictionary(grouping: items.compactMap(\.tmdbID), by: { $0 }).mapValues(\.count)
            guard let seriesID = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else { continue }
            library.ownedSeriesIDs.insert(seriesID)
            var have = library.ownedEpisodes[seriesID] ?? []
            for e in items {
                guard let s = e.season, let n = e.episode else { continue }
                for number in n...max(n, e.episodeEnd ?? n) { have.insert(EpisodeKey(season: s, episode: number)) }
            }
            library.ownedEpisodes[seriesID] = have
            let title = items.first?.seriesTitle ?? items.first?.title ?? ""
            seedPool.append((DiscoverSeed(kind: .series, tmdbID: seriesID, title: title),
                             items.contains { $0.watch.favorite }, items.compactMap(\.watch.lastPlayed).max()))
        }
        // Favorites first, then most recently played; titles never played are not seeds (nothing says the user likes them).
        library.seeds = seedPool
            .filter { $0.favorite || $0.played != nil }
            .sorted { a, b in
                if a.favorite != b.favorite { return a.favorite }
                if a.played != b.played { return (a.played ?? .distantPast) > (b.played ?? .distantPast) }
                return a.seed.tmdbID < b.seed.tmdbID
            }
            .map(\.seed)
        return library
    }
}

/// The Discover screen. `source` nil means no key: the screen says exactly what is needed and sends nothing.
public struct DiscoverViewModel: Sendable {
    public let source: (any DiscoverDataSource)?
    public let library: any DiscoverLibraryProviding
    public let watchlist: any WatchlistStoring
    public let region: String
    public let limits: DiscoverLimits
    public private(set) var state: ViewState<DiscoverContent> = .idle

    public init(source: (any DiscoverDataSource)?, library: any DiscoverLibraryProviding, watchlist: any WatchlistStoring,
                region: String = OnlineLookupPrefs.defaultRegion, limits: DiscoverLimits = DiscoverLimits()) {
        self.source = source; self.library = library; self.watchlist = watchlist; self.region = region; self.limits = limits
    }

    public static let needsKey = EmptyState(reason: .nothingIndexed, title: OnlineLookupText.discoverNeedsKeyTitle, message: OnlineLookupText.discoverNeedsKey)
    public static let nothingYet = EmptyState(
        reason: .nothingIndexed, title: "Nothing to Suggest Yet",
        message: "Discover works from the titles in your library that have been matched online, and from your watchlist. Matching runs in the background once pictures are loading; play or favorite something and check again.")

    public mutating func load() async {
        guard let source else { state = .empty(Self.needsKey); return }
        state = .loading
        do {
            let facts = try await library.discoverLibrary()
            let list = watchlist.entries()
            if facts.isEmpty && list.isEmpty { state = .empty(Self.nothingYet); return }
            let engine = DiscoverEngine(source: source, region: region, limits: limits)
            let content = await engine.build(library: facts, watchlist: list)
            if content.isEmpty && !content.problems.isEmpty {
                state = .failed(ErrorState(title: "Couldn’t Load Discover", message: content.problems.joined(separator: " ")))
            } else if content.isEmpty {
                state = .empty(EmptyState(reason: .nothingIndexed, title: "Nothing New Found",
                                          message: "Every aired episode and collection part of the titles you own is in your library, and nothing similar turned up."))
            } else {
                state = .loaded(content)
            }
        } catch {
            state = .failed(ErrorState.from(error, doing: "load Discover"))
        }
    }

    /// Adds the title to the watchlist, or removes it when it is already there; the screen updates without asking the service again.
    public mutating func toggleWatchlist(_ title: DiscoverTitle, now: Date = Date()) {
        guard case .loaded(var content) = state else { return }
        let adding = !title.onWatchlist
        if adding {
            watchlist.add(UDWatchlistEntry(kind: title.kind.rawValue, tmdbID: title.tmdbID, title: title.title, year: title.year, posterPath: title.posterPath, addedAt: now))
        } else {
            watchlist.remove(kind: title.kind, tmdbID: title.tmdbID)
        }
        func flag(_ t: inout DiscoverTitle) { if t.kind == title.kind && t.tmdbID == title.tmdbID { t.onWatchlist = adding } }
        for i in content.similar.indices { flag(&content.similar[i]) }
        for g in content.collectionGaps.indices { for i in content.collectionGaps[g].missing.indices { flag(&content.collectionGaps[g].missing[i]) } }
        if adding {
            var added = title
            added.onWatchlist = true
            added.reason = "On your watchlist"
            if !content.watchlist.contains(where: { $0.id == added.id }) { content.watchlist.insert(added, at: 0) }
        } else {
            content.watchlist.removeAll { $0.kind == title.kind && $0.tmdbID == title.tmdbID }
        }
        state = .loaded(content)
    }
}
