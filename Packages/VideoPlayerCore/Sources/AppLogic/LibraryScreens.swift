import Foundation
import VideoPlayerCore
import LibraryIndex

// View models for the library screens, over `LibraryStore`. They are value types with async mutating methods: the app
// wraps one in an observable object and calls the methods from the view's `.task`. They never touch the network or
// the file system; everything comes from the index. Wording is final user-facing text.

// MARK: Home

public enum HomeRowID: String, CaseIterable, Sendable { case continueWatching, nextUp, recentlyAdded }

public struct HomeRow: Equatable, Sendable, Identifiable {
    public var id: HomeRowID
    public var title: String
    public var cards: [ItemCard]
}

/// Home: Continue Watching, Next Up, Recently Added. The set of rows is closed on purpose (library-only rule): there is no
/// way to add a row from outside, and an empty row is left out instead of shown empty.
public struct HomeViewModel: Sendable {
    public let store: any LibraryStore
    public let retentionDays: Int
    public let rowLimit: Int
    public private(set) var state: ViewState<[HomeRow]> = .idle

    /// Interpretation (PROVISIONAL): 90 days for Continue Watching and Next Up, 20 cards per row, 30 for Recently Added.
    public init(store: any LibraryStore, retentionDays: Int = 90, rowLimit: Int = 20) {
        self.store = store
        self.retentionDays = retentionDays
        self.rowLimit = rowLimit
    }

    public static func title(of id: HomeRowID) -> String {
        switch id {
        case .continueWatching: return "Continue Watching"
        case .nextUp: return "Next Up"
        case .recentlyAdded: return "Recently Added"
        }
    }

    public mutating func load(now: Date = Date()) async {
        state = .loading
        do {
            let sources = try await store.sources()
            if sources.isEmpty { state = .empty(Self.noSources); return }
            let counts = try await store.counts()
            if counts.items == 0 { state = .empty(Self.nothingIndexed); return }
            let cont = try await store.continueWatching(limit: rowLimit, now: now, retentionDays: retentionDays)
            let next = try await store.nextUp(limit: rowLimit, now: now, retentionDays: retentionDays)
            let recent = try await store.recentlyAdded(limit: 30, kind: nil)
            var rows: [HomeRow] = []
            func add(_ id: HomeRowID, _ cards: [ItemCard]) {
                if !cards.isEmpty { rows.append(HomeRow(id: id, title: Self.title(of: id), cards: cards)) }
            }
            add(.continueWatching, cont.map { CardBuilder.card($0, style: .continueWatching) })
            add(.nextUp, next.map { CardBuilder.card($0.item, style: .nextUp) })
            add(.recentlyAdded, recent.map { CardBuilder.card($0) })
            state = rows.isEmpty ? .empty(Self.nothingIndexed) : .loaded(rows)
        } catch {
            state = .failed(ErrorState.from(error, doing: "load your library"))
        }
    }

    public static let noSources = EmptyState(
        reason: .noSources, title: "No Sources Yet",
        message: "Add a server or a shared folder to see your movies and shows here.", actionTitle: "Add a Source")
    public static let nothingIndexed = EmptyState(
        reason: .nothingIndexed, title: "Nothing Here Yet",
        message: "Your sources are still being scanned, or no videos were found in them.")
    /// #15 10.2: the Files tab browses folders, so its empty state says that instead of "see your movies and shows here".
    public static let noSourcesForFiles = EmptyState(
        reason: .noSources, title: "No Sources Yet",
        message: "Add a server or a shared folder to browse its folders here.", actionTitle: "Add a Source")
}

// MARK: Grid (Movies, and any filtered list of items)

public struct GridContent: Equatable, Sendable {
    public var cards: [ItemCard]
    /// How many items match in total (the grid can show "212 movies" while only the first page is loaded).
    public var total: Int
    public var hasMore: Bool
    /// Letter jump list, only for title sorts.
    public var alphabet: [AlphabetEntry]
}

/// A paged, filterable, sortable grid with saved views. `base` is the part of the filter the screen owns (Movies: kinds
/// [.movie]); the user's filters add to it and "Clear Filters" goes back to it.
public struct ItemGridViewModel: QueryGridScreen {
    public let store: any LibraryStore
    public let base: ItemFilter
    public let pageSize: Int
    public let scope: ViewScope
    public let noun: String
    public private(set) var query: ItemQuery
    public private(set) var state: ViewState<GridContent> = .idle
    public private(set) var savedViews: [SavedView] = []

    private var cards: [ItemCard] = []
    private var cursor: ItemCursor?
    private var total = 0
    private var alphabet: [AlphabetEntry] = []
    /// After a jump to a letter, paging continues by row number from here (the keyset cursor does not apply).
    private var offsetNext: Int?
    /// The letter the grid was last jumped to, nil after a normal load.
    public private(set) var jumpedTo: String?

    /// `noun` is plural, for the count line and messages ("movies").
    public init(store: any LibraryStore, base: ItemFilter, sort: ItemSort = ItemSort(), pageSize: Int = 60, scope: ViewScope = .library, noun: String = "items") {
        self.store = store
        self.base = base
        self.pageSize = max(1, pageSize)
        self.scope = scope
        self.noun = noun
        self.query = ItemQuery(filter: base, sort: sort)
    }

    public static func movies(store: any LibraryStore) -> ItemGridViewModel {
        var base = ItemFilter()
        base.kinds = [.movie]
        return ItemGridViewModel(store: store, base: base, noun: "movies")
    }

    // MARK: Reading

    public var chips: [FilterChip] { FilterDescriber.chips(for: query.filter, base: base) }
    public var isFiltered: Bool { query.filter != base }
    public var sortTitle: String { SortChoice.title(of: query.sort) }
    public var sortChoices: [SortChoice] { SortChoice.all }
    public var filterGroups: [FilterGroup] { FilterGroup.library }
    /// "212 movies" or "12 of 212 movies" while filtered.
    public var countText: String? {
        guard case .loaded(let c) = state else { return nil }
        return "\(c.total) \(c.total == 1 ? String(noun.dropLast(noun.hasSuffix("s") ? 1 : 0)) : noun)"
    }

    // MARK: Loading

    /// Loads the first page (also what a change of filter or sort does).
    public mutating func load() async {
        state = .loading
        cards = []
        cursor = nil
        offsetNext = nil
        jumpedTo = nil
        do {
            let page = try await store.page(query, limit: pageSize, after: nil)
            total = try await store.count(query)
            alphabet = query.sort.key == .title ? try await store.alphabetIndex(query) : []
            cards = page.items.map { CardBuilder.card($0) }
            cursor = page.next
            try await finishLoad()
        } catch {
            state = .failed(ErrorState.from(error, doing: "load \(noun)"))
        }
    }

    /// Call when the card at `id` comes into view; loads the next page when it is near the end.
    public mutating func loadMoreIfNeeded(visible id: Int64) async {
        guard let index = cards.firstIndex(where: { $0.id == id }), index >= cards.count - 10 else { return }
        await loadMore()
    }

    /// Alphabet jump list (Movies): starts the grid at the first title filed under `letter` ("#" for digits and symbols). The
    /// titles before that letter are not loaded; choosing another letter, or "All", goes back. Only for title sorts. PROVISIONAL.
    public mutating func jump(to letter: String) async {
        guard case .loaded = state, let entry = alphabet.first(where: { $0.letter == letter }) else { return }
        do {
            let rows = try await store.page(query, limit: pageSize, offset: entry.offset)
            guard !rows.isEmpty else { return }
            cards = rows.map { CardBuilder.card($0) }
            cursor = nil
            offsetNext = entry.offset + rows.count < total ? entry.offset + rows.count : nil
            jumpedTo = letter
            publish()
        } catch {
            // Keep what is on screen.
        }
    }

    public mutating func loadMore() async {
        if let next = offsetNext, case .loaded = state {
            do {
                let rows = try await store.page(query, limit: pageSize, offset: next)
                cards += rows.map { CardBuilder.card($0) }
                offsetNext = rows.count < pageSize || next + rows.count >= total ? nil : next + rows.count
                publish()
            } catch {
                // Keep what is on screen; the next scroll tries again.
            }
            return
        }
        guard let cursor, case .loaded = state else { return }
        do {
            let page = try await store.page(query, limit: pageSize, after: cursor)
            cards += page.items.map { CardBuilder.card($0) }
            self.cursor = page.next
            publish()
        } catch {
            // Keep what is on screen; the next scroll tries again.
        }
    }

    private mutating func finishLoad() async throws {
        if cards.isEmpty {
            if isFiltered {
                state = .empty(EmptyState(reason: .noMatches, title: "No Matches",
                                          message: "Nothing matches these filters.", actionTitle: "Clear Filters"))
            } else if try await store.sources().isEmpty {
                state = .empty(HomeViewModel.noSources)
            } else {
                state = .empty(HomeViewModel.nothingIndexed)
            }
        } else {
            publish()
        }
    }

    private mutating func publish() {
        state = .loaded(GridContent(cards: cards, total: total, hasMore: cursor != nil || offsetNext != nil, alphabet: alphabet))
    }

    // MARK: Filters and sorts (each reloads)

    public mutating func toggle(_ option: FilterOption) async {
        option.toggle(in: &query.filter)
        await load()
    }

    public mutating func setFilter(_ filter: ItemFilter) async {
        query.filter = filter
        await load()
    }

    public mutating func removeChip(_ chip: FilterChip) async {
        FilterDescriber.remove(chip, from: &query.filter)
        await load()
    }

    public mutating func clearFilters() async {
        query.filter = base
        await load()
    }

    /// Picking the key that is already active flips the direction; a new key starts at its default direction.
    public mutating func chooseSort(_ key: ItemSortKey) async {
        if query.sort.key == key { query.sort.ascending.toggle() } else { query.sort = SortChoice.defaultSort(for: key) }
        await load()
    }

    public mutating func setSort(_ sort: ItemSort) async {
        query.sort = sort
        await load()
    }

    // MARK: Saved views (saved sorts and filters)

    public mutating func refreshSavedViews() async {
        do { savedViews = try await store.views(scope: scope) } catch { savedViews = [] }
    }

    @discardableResult
    public mutating func saveCurrentView(name: String, pinned: Bool = false) async throws -> SavedView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let view = try await store.saveView(name: trimmed.isEmpty ? "Saved View" : trimmed, scope: scope, query: query, pinned: pinned)
        await refreshSavedViews()
        return view
    }

    public mutating func apply(_ view: SavedView) async {
        query = view.query
        await load()
    }

    public mutating func deleteView(id: Int64) async {
        try? await store.deleteView(id: id)
        await refreshSavedViews()
    }

    // MARK: Selection actions

    /// Marks one item watched or unwatched and refreshes its card in place.
    public mutating func setWatched(_ watched: Bool, itemID: Int64) async {
        do {
            try await store.markWatched(itemIDs: [itemID], watched: watched, at: Date())
            await refreshCard(itemID)
        } catch {
            // The card stays as it was.
        }
    }

    public mutating func toggleWatched(itemID: Int64) async {
        guard let card = cards.first(where: { $0.id == itemID }) else { return }
        await setWatched(!card.isWatched, itemID: itemID)
    }

    public mutating func toggleFavorite(itemID: Int64) async {
        guard let card = cards.first(where: { $0.id == itemID }) else { return }
        do {
            try await store.setFavorite(itemID: itemID, favorite: !card.isFavorite)
            await refreshCard(itemID)
        } catch {}
    }

    private mutating func refreshCard(_ id: Int64) async {
        guard let index = cards.firstIndex(where: { $0.id == id }),
              let item = try? await store.item(id: id) else { return }
        cards[index] = CardBuilder.card(item)
        publish()
    }
}

// MARK: Shows

public struct SeriesSummary: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    public var episodeCount: Int
    public var unwatchedCount: Int
    public var seasonCount: Int
    public var artworkKey: String
    /// #21 F, for the Shows sorts and the watch filter: episodes started but not finished, the earliest episode year, the
    /// newest episode's date added and the last time any episode played.
    public var inProgressCount: Int = 0
    public var year: Int? = nil
    public var latestAdded: Date? = nil
    public var lastPlayed: Date? = nil

    /// "3 seasons", "1 season" (Season 0 specials do not count as a season).
    public var seasonsText: String { "\(seasonCount) \(seasonCount == 1 ? "season" : "seasons")" }

    /// The watch filter at show level (PROVISIONAL, matching the Movies meaning where Unwatched includes started items):
    /// Unwatched = at least one episode not watched; In Progress = something watched or started and something left;
    /// Watched = every episode watched.
    public func matches(_ watch: WatchFilter) -> Bool {
        switch watch {
        case .unwatched: return unwatchedCount > 0
        case .inProgress: return unwatchedCount > 0 && (inProgressCount > 0 || unwatchedCount < episodeCount)
        case .watched: return unwatchedCount == 0
        }
    }
}

/// Where the Shows grid gets its series. `LibraryStore` has no series list yet (docs/APP_LOGIC.md "Gaps"); the default
/// implementation reads episodes page by page and groups them, which is O(episodes) and fine for tests and mid-size
/// libraries but should become one SQL query.
public protocol SeriesCatalog: Sendable {
    func allSeries() async throws -> [SeriesSummary]
}

public struct EpisodeGroupingCatalog: SeriesCatalog {
    public let store: any LibraryStore
    public let pageSize: Int
    public init(store: any LibraryStore, pageSize: Int = 500) {
        self.store = store
        self.pageSize = pageSize
    }

    public func allSeries() async throws -> [SeriesSummary] {
        var filter = ItemFilter()
        filter.kinds = [.episode]
        let query = ItemQuery(filter: filter, sort: ItemSort(key: .title, ascending: true))
        var byID: [Int64: SeriesSummary] = [:]
        var seasons: [Int64: Set<Int>] = [:]
        var cursor: ItemCursor?
        repeat {
            let page = try await store.page(query, limit: pageSize, after: cursor)
            for item in page.items {
                guard let sid = item.seriesID else { continue }
                var e = byID[sid] ?? SeriesSummary(id: sid, title: item.seriesTitle ?? item.title, episodeCount: 0, unwatchedCount: 0,
                                                   seasonCount: 0, artworkKey: "series-\(sid)")
                e.episodeCount += 1
                if !item.watch.watched { e.unwatchedCount += 1 }
                if !item.watch.watched && item.watch.position > 0 { e.inProgressCount += 1 }
                if let y = item.year { e.year = min(e.year ?? y, y) }
                e.latestAdded = max(e.latestAdded ?? item.addedAt, item.addedAt)
                if let p = item.watch.lastPlayed { e.lastPlayed = max(e.lastPlayed ?? p, p) }
                if let s = item.season, s > 0 { seasons[sid, default: []].insert(s) }
                byID[sid] = e
            }
            cursor = page.next
        } while cursor != nil
        return byID.values.map { s -> SeriesSummary in
            var s = s
            s.seasonCount = seasons[s.id]?.count ?? 0
            return s
        }
            .sorted { TitleLetter.sortKey($0.title) != TitleLetter.sortKey($1.title) ? TitleLetter.sortKey($0.title) < TitleLetter.sortKey($1.title) : $0.id < $1.id }
    }
}

/// Shows: one entry per series, with the same Sort, Filter and Saved Views menus as Movies (#21 F). The series list is built
/// in memory (`SeriesCatalog`), so sorting and the watch filter run here; the other filters (resolution, dynamic range,
/// sound, favourites) keep a show when at least one of its episodes matches, using the index's own episode filter.
public struct ShowsViewModel: QueryGridScreen {
    public let catalog: any SeriesCatalog
    public let store: any LibraryStore
    public let scope: ViewScope = .shows
    /// The screen's own part of the filter: episodes. "Clear Filters" goes back to it.
    public static let base: ItemFilter = {
        var f = ItemFilter()
        f.kinds = [.episode]
        return f
    }()
    public private(set) var state: ViewState<[SeriesSummary]> = .idle
    public private(set) var query = ItemQuery(filter: ShowsViewModel.base, sort: ItemSort(key: .title, ascending: true))
    public private(set) var savedViews: [SavedView] = []

    public init(store: any LibraryStore, catalog: (any SeriesCatalog)? = nil) {
        self.store = store
        self.catalog = catalog ?? EpisodeGroupingCatalog(store: store)
    }

    public var sortChoices: [SortChoice] { SortChoice.shows }
    public var filterGroups: [FilterGroup] { FilterGroup.library }
    public var chips: [FilterChip] { FilterDescriber.chips(for: query.filter, base: Self.base) }
    public var isFiltered: Bool { query.filter != Self.base }

    /// The letter jump list, only for the title sort (as on Movies).
    public var jumpTargets: [JumpTarget] {
        guard query.sort.key == .title, case .loaded(let series) = state else { return [] }
        return AlphabetJump.targets(for: series)
    }

    public mutating func load() async {
        state = .loading
        do {
            let all = try await catalog.allSeries()
            if all.isEmpty {
                state = .empty(try await store.sources().isEmpty ? HomeViewModel.noSources : HomeViewModel.nothingIndexed)
                return
            }
            let shown = try await Self.matching(query, in: all, store: store)
            state = shown.isEmpty ? .empty(Self.noMatches) : .loaded(shown)
        } catch {
            state = .failed(ErrorState.from(error, doing: "load your shows"))
        }
    }

    public static let noMatches = EmptyState(reason: .noMatches, title: "No Matches",
                                             message: "No shows match these filters.", actionTitle: "Clear Filters")

    /// "2 shows" or "1 show", in the same place as the Movies count (#15 4.5).
    public var countText: String? {
        guard case .loaded(let series) = state else { return nil }
        return series.count == 1 ? "1 show" : "\(series.count) shows"
    }

    /// The shows `query` keeps, in its order.
    static func matching(_ query: ItemQuery, in all: [SeriesSummary], store: any LibraryStore) async throws -> [SeriesSummary] {
        var list = all
        if let w = query.filter.watch { list = list.filter { $0.matches(w) } }
        var episodes = query.filter
        episodes.watch = nil
        episodes.kinds = [.episode]
        if episodes != base {
            var ids: Set<Int64> = []
            var cursor: ItemCursor?
            let q = ItemQuery(filter: episodes, sort: ItemSort(key: .title, ascending: true))
            repeat {
                let page = try await store.page(q, limit: 500, after: cursor)
                for item in page.items { if let sid = item.seriesID { ids.insert(sid) } }
                cursor = page.next
            } while cursor != nil
            list = list.filter { ids.contains($0.id) }
        }
        return sorted(list, by: query.sort)
    }

    /// Title: by the letter key. Year: the earliest episode year. Date Added: the newest episode. Last Played: the last
    /// time any episode played. Shows without a value go last in both directions; ties fall back to the title.
    static func sorted(_ list: [SeriesSummary], by sort: ItemSort) -> [SeriesSummary] {
        func titleOrder(_ a: SeriesSummary, _ b: SeriesSummary) -> Bool {
            let ka = TitleLetter.sortKey(a.title), kb = TitleLetter.sortKey(b.title)
            return ka != kb ? ka < kb : a.id < b.id
        }
        func valueOrder<T: Comparable>(_ a: T?, _ b: T?, _ x: SeriesSummary, _ y: SeriesSummary) -> Bool {
            switch (a, b) {
            case let (a?, b?) where a != b: return sort.ascending ? a < b : a > b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return titleOrder(x, y)
            }
        }
        switch sort.key {
        case .year: return list.sorted { valueOrder($0.year, $1.year, $0, $1) }
        case .added: return list.sorted { valueOrder($0.latestAdded, $1.latestAdded, $0, $1) }
        case .lastPlayed: return list.sorted { valueOrder($0.lastPlayed, $1.lastPlayed, $0, $1) }
        default:
            let up = list.sorted(by: titleOrder)
            return sort.ascending ? up : up.reversed()
        }
    }

    // MARK: Filters, sorts, saved views (each reloads)

    public mutating func toggle(_ option: FilterOption) async {
        option.toggle(in: &query.filter)
        await load()
    }

    public mutating func removeChip(_ chip: FilterChip) async {
        FilterDescriber.remove(chip, from: &query.filter)
        await load()
    }

    public mutating func clearFilters() async {
        query.filter = Self.base
        await load()
    }

    public mutating func chooseSort(_ key: ItemSortKey) async {
        if query.sort.key == key { query.sort.ascending.toggle() } else { query.sort = SortChoice.defaultSort(for: key) }
        await load()
    }

    public mutating func refreshSavedViews() async {
        do { savedViews = try await store.views(scope: scope) } catch { savedViews = [] }
    }

    @discardableResult
    public mutating func saveCurrentView(name: String, pinned: Bool = false) async throws -> SavedView {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let view = try await store.saveView(name: trimmed.isEmpty ? "Saved View" : trimmed, scope: scope, query: query, pinned: pinned)
        await refreshSavedViews()
        return view
    }

    public mutating func apply(_ view: SavedView) async {
        query = view.query
        query.filter.kinds = [.episode]
        await load()
    }

    public mutating func deleteView(id: Int64) async {
        try? await store.deleteView(id: id)
        await refreshSavedViews()
    }
}

public struct EpisodeRow: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    /// R453: the episode's number in its season (0 when the file has none), for the card caption "4. Title".
    public var number: Int = 0
    /// "S2 E4".
    public var code: String
    public var runtimeText: String?
    public var progress: Double?
    public var isWatched: Bool
    public var artworkKey: String
    /// R370: the episode's badges (`FormatBadges.item`: resolution, HDR, Dolby Atmos).
    public var badges: [FormatBadgeItem] = []

    /// R453: the card's caption, "4. Title" (the number, then the title); only the title when the file gives no number.
    public var cardCaption: String { number > 0 ? "\(number). \(title)" : title }
}

public struct SeasonSection: Equatable, Sendable, Identifiable {
    public var season: Int
    public var id: Int { season }
    /// "Season 2", "Specials".
    public var title: String
    public var episodes: [EpisodeRow]
    public var watchedCount: Int
    public var summary: String { "\(watchedCount) of \(episodes.count) watched" }
}

public struct SeasonsContent: Equatable, Sendable {
    public var seriesTitle: String
    public var seasons: [SeasonSection]
    /// The episode the Play button starts: the one in progress, else the first unwatched regular episode, else the first one.
    public var resumeEpisodeID: Int64?
    /// "Play", "Resume", or "Play Again" when everything is watched.
    public var playTitle: String

    /// #15 5.1: the show page offers only the mark that changes something. Mark Show as Watched while any episode is unwatched,
    /// Mark Show as Unwatched while any is watched (both in the middle of a show).
    public var canMarkWatched: Bool { seasons.contains { $0.watchedCount < $0.episodes.count } }
    public var canMarkUnwatched: Bool { seasons.contains { $0.watchedCount > 0 } }
}

public struct SeasonsViewModel: Sendable {
    public let store: any LibraryStore
    public let seriesID: Int64
    public private(set) var state: ViewState<SeasonsContent> = .idle

    public init(store: any LibraryStore, seriesID: Int64) {
        self.store = store
        self.seriesID = seriesID
    }

    public mutating func load() async {
        state = .loading
        do {
            let episodes = try await store.episodes(ofSeries: seriesID)
            guard !episodes.isEmpty else {
                state = .empty(EmptyState(reason: .nothingIndexed, title: "No Episodes", message: "No episodes of this show are in your library."))
                return
            }
            state = .loaded(Self.content(episodes))
        } catch {
            state = .failed(ErrorState.from(error, doing: "load this show"))
        }
    }

    static func content(_ episodes: [LibraryItem]) -> SeasonsContent {
        let grouped = Dictionary(grouping: episodes) { $0.season ?? 1 }
        // Regular seasons ascending, then Specials (Season 0) last.
        let order = grouped.keys.sorted { a, b in (a == 0) != (b == 0) ? b == 0 : a < b }
        let sections = order.map { season -> SeasonSection in
            let rows = (grouped[season] ?? []).sorted { ($0.episode ?? 0, $0.id) < ($1.episode ?? 0, $1.id) }.map { item in
                // #25 B7: a title that is only the code again ("S01E01") or the show's name is no title: "Episode 1" instead,
                // so the card never reads "S1 E1 · S01E01".
                EpisodeRow(id: item.id, title: CardBuilder.episodeTitleIsReal(item) ? item.title : "Episode \(item.episode ?? 0)",
                           number: item.episode ?? 0,
                           code: DisplayText.episodeCode(season: item.season, episode: item.episode, episodeEnd: item.episodeEnd) ?? "",
                           runtimeText: (item.runtime ?? item.watch.duration).map(DisplayText.runtime),
                           progress: CardBuilder.progressFraction(item), isWatched: item.watch.watched, artworkKey: "item-\(item.id)",
                           badges: FormatBadges.item(item))
            }
            return SeasonSection(season: season, title: season == 0 ? "Specials" : "Season \(season)", episodes: rows,
                                 watchedCount: rows.filter(\.isWatched).count)
        }
        let flat = order.flatMap { grouped[$0] ?? [] }.sorted { a, b in
            let sa = a.season ?? 1, sb = b.season ?? 1
            if sa != sb { return (sa == 0) != (sb == 0) ? sb == 0 : sa < sb }
            return (a.episode ?? 0, a.id) < (b.episode ?? 0, b.id)
        }
        let inProgress = flat.first { CardBuilder.progressFraction($0) != nil }
        let firstUnwatched = flat.first { !$0.watch.watched && ($0.season ?? 1) > 0 }
        let resume = inProgress ?? firstUnwatched ?? flat.first
        let allWatched = flat.allSatisfy { $0.watch.watched }
        let title = inProgress != nil ? "Resume" : (allWatched ? "Play Again" : (flat.contains { $0.watch.watched } ? "Resume" : "Play"))
        return SeasonsContent(seriesTitle: episodes.first?.seriesTitle ?? episodes.first?.title ?? "", seasons: sections,
                              resumeEpisodeID: resume?.id, playTitle: title)
    }

    public mutating func markSeason(_ season: Int, watched: Bool) async {
        do { try await store.markSeries(seriesID: seriesID, season: season, watched: watched, at: Date()) } catch { return }
        await load()
    }

    public mutating func markSeries(watched: Bool) async {
        do { try await store.markSeries(seriesID: seriesID, season: nil, watched: watched, at: Date()) } catch { return }
        await load()
    }

    public mutating func setWatched(_ watched: Bool, episodeID: Int64) async {
        do { try await store.markWatched(itemIDs: [episodeID], watched: watched, at: Date()) } catch { return }
        await load()
    }
}

// MARK: Files

public struct FileRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var isDirectory: Bool
    public var kind: FileKind
    /// "3.1 GB" for files, nil for folders.
    public var sizeText: String?
    /// The view formats it for the user's locale.
    public var modified: Date?
    /// #15 7.3: the second line. A folder: how many items it holds ("12 items"); a file: size and format ("3.1 GB · MKV").
    public var detail: String? = nil
}

/// The second lines of the Files tab (#15 7.3, PROVISIONAL, OPEN_QUESTIONS R187).
public enum FilesText {
    /// Folders count up to this many items; a fuller folder says "999+ items".
    public static let countLimit = 999

    /// The left column of the Files tab.
    public static let rootSummary = "Your servers and shared folders, with their folders exactly as they are on the server."

    /// A source row: its protocol ("SMB", "WebDAV").
    public static func sourceDetail(_ kind: SourceKind) -> String { SourceCatalog.info(for: kind).title }

    /// "Empty", "1 item", "12 items", "999+ items".
    public static func itemCount(_ count: Int) -> String {
        if count <= 0 { return "Empty" }
        if count > countLimit { return "\(countLimit)+ items" }
        return count == 1 ? "1 item" : "\(count) items"
    }

    /// "3.1 GB · MKV" for a video, "12 KB · Subtitles" for anything else. The duration is not in the folder listing, so it
    /// is not shown here (it is on the title's page).
    public static func fileDetail(name: String, kind: FileKind, size: Int64?) -> String? {
        var parts: [String] = []
        if let size { parts.append(DisplayText.fileSize(size)) }
        let ext = (name as NSString).pathExtension
        switch kind {
        case .video: if !ext.isEmpty { parts.append(ext.uppercased()) }
        case .subtitle: parts.append("Subtitles")
        case .image: parts.append("Picture")
        case .nfo: parts.append("Information")
        case .directory, .other: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public struct FilesContent: Equatable, Sendable {
    public var rows: [FileRow]
    public var hasMore: Bool
    /// Folder names from the source root, for the title ("Movies > 2020").
    public var breadcrumb: [String]
}

public struct FilesBrowserViewModel: Sendable {
    public let store: any LibraryStore
    public let sourceID: String
    public let sourceName: String
    public let pageSize: Int
    public private(set) var folder: String
    public private(set) var sort: FileSort
    public private(set) var state: ViewState<FilesContent> = .idle
    private var rows: [FileRow] = []
    private var more = false

    public init(store: any LibraryStore, sourceID: String, sourceName: String, folder: String = "/", sort: FileSort = FileSort(), pageSize: Int = 200) {
        self.store = store
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.folder = folder
        self.sort = sort
        self.pageSize = max(1, pageSize)
    }

    public var isAtRoot: Bool { folder == "/" }
    public var breadcrumb: [String] { [sourceName] + folder.split(separator: "/").map(String.init) }

    public mutating func load() async {
        state = .loading
        rows = []
        do {
            let children = try await store.children(sourceID: sourceID, folder: folder, sort: sort, limit: pageSize + 1, offset: 0)
            more = children.count > pageSize
            rows = await withCounts(children.prefix(pageSize).map(Self.row))
            publish()
        } catch {
            state = .failed(ErrorState.from(error, doing: "open this folder"))
        }
    }

    public mutating func loadMore() async {
        guard more, case .loaded = state else { return }
        do {
            let children = try await store.children(sourceID: sourceID, folder: folder, sort: sort, limit: pageSize + 1, offset: rows.count)
            more = children.count > pageSize
            rows += await withCounts(children.prefix(pageSize).map(Self.row))
            publish()
        } catch {}
    }

    /// Opens a folder row. Files are not opened here (the app starts playback or shows File Details).
    public mutating func enter(_ row: FileRow) async {
        guard row.isDirectory else { return }
        folder = row.id
        await load()
    }

    /// Menu on the remote: goes up one level and returns true; at the root returns false so the app leaves the screen.
    public mutating func up() async -> Bool {
        guard !isAtRoot else { return false }
        let parent = folder.split(separator: "/").dropLast().joined(separator: "/")
        folder = "/" + parent
        await load()
        return true
    }

    public mutating func setSort(_ newSort: FileSort) async {
        sort = newSort
        await load()
    }

    private mutating func publish() {
        if rows.isEmpty {
            state = .empty(EmptyState(reason: .emptyFolder, title: "Empty Folder", message: "There is nothing in this folder."))
        } else {
            state = .loaded(FilesContent(rows: rows, hasMore: more, breadcrumb: breadcrumb))
        }
    }

    static func row(_ c: FolderChild) -> FileRow {
        FileRow(id: c.path, name: c.name, isDirectory: c.isDirectory, kind: c.kind,
                sizeText: c.isDirectory ? nil : c.size.map(DisplayText.fileSize), modified: c.modified,
                detail: c.isDirectory ? nil : FilesText.fileDetail(name: c.name, kind: c.kind, size: c.size))
    }

    /// #15 7.3: each folder row's item count, from the index (no server call). A folder that fails to count shows no line.
    private func withCounts(_ rows: [FileRow]) async -> [FileRow] {
        var out = rows
        for i in out.indices where out[i].isDirectory {
            if let n = try? await store.children(sourceID: sourceID, folder: out[i].id, sort: FileSort(), limit: FilesText.countLimit + 1, offset: 0).count {
                out[i].detail = FilesText.itemCount(n)
            }
        }
        return out
    }
}

// MARK: Search

public struct SearchViewModel: Sendable {
    public let store: any LibraryStore
    public let limit: Int
    public private(set) var text = ""
    public private(set) var state: ViewState<[ItemCard]> = .empty(SearchViewModel.prompt)

    public static let prompt = EmptyState(reason: .noQuery, title: "Search Your Library", message: "Type a movie or show title.")

    public init(store: any LibraryStore, limit: Int = 100) {
        self.store = store
        self.limit = limit
    }

    /// Searches the library only (titles and series titles). An empty text clears the results.
    public mutating func search(_ newText: String) async {
        text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { state = .empty(Self.prompt); return }
        state = .loading
        var filter = ItemFilter()
        filter.text = text
        do {
            let page = try await store.page(ItemQuery(filter: filter, sort: ItemSort(key: .title, ascending: true)), limit: limit, after: nil)
            state = page.items.isEmpty
                ? .empty(EmptyState(reason: .noMatches, title: "No Results for “\(text)”", message: "Check the spelling or try fewer words."))
                : .loaded(page.items.map { CardBuilder.card($0) })
        } catch {
            state = .failed(ErrorState.from(error, doing: "search"))
        }
    }
}
