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
public struct ItemGridViewModel: Sendable {
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

    /// "3 seasons", "1 season" (Season 0 specials do not count as a season).
    public var seasonsText: String { "\(seasonCount) \(seasonCount == 1 ? "season" : "seasons")" }
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
        var byID: [Int64: (title: String, episodes: Int, unwatched: Int, seasons: Set<Int>)] = [:]
        var cursor: ItemCursor?
        repeat {
            let page = try await store.page(query, limit: pageSize, after: cursor)
            for item in page.items {
                guard let sid = item.seriesID else { continue }
                var e = byID[sid] ?? (item.seriesTitle ?? item.title, 0, 0, [])
                e.episodes += 1
                if !item.watch.watched { e.unwatched += 1 }
                if let s = item.season, s > 0 { e.seasons.insert(s) }
                byID[sid] = e
            }
            cursor = page.next
        } while cursor != nil
        return byID.map { SeriesSummary(id: $0.key, title: $0.value.title, episodeCount: $0.value.episodes, unwatchedCount: $0.value.unwatched,
                                        seasonCount: $0.value.seasons.count, artworkKey: "series-\($0.key)") }
            .sorted { TitleLetter.sortKey($0.title) != TitleLetter.sortKey($1.title) ? TitleLetter.sortKey($0.title) < TitleLetter.sortKey($1.title) : $0.id < $1.id }
    }
}

public struct ShowsViewModel: Sendable {
    public let catalog: any SeriesCatalog
    public let store: any LibraryStore
    public private(set) var state: ViewState<[SeriesSummary]> = .idle

    public init(store: any LibraryStore, catalog: (any SeriesCatalog)? = nil) {
        self.store = store
        self.catalog = catalog ?? EpisodeGroupingCatalog(store: store)
    }

    public mutating func load() async {
        state = .loading
        do {
            let series = try await catalog.allSeries()
            if series.isEmpty {
                state = .empty(try await store.sources().isEmpty ? HomeViewModel.noSources : HomeViewModel.nothingIndexed)
            } else {
                state = .loaded(series)
            }
        } catch {
            state = .failed(ErrorState.from(error, doing: "load your shows"))
        }
    }
}

public struct EpisodeRow: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var title: String
    /// "S2 E4".
    public var code: String
    public var runtimeText: String?
    public var progress: Double?
    public var isWatched: Bool
    public var artworkKey: String
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
                EpisodeRow(id: item.id, title: item.title.isEmpty ? "Episode \(item.episode ?? 0)" : item.title,
                           code: DisplayText.episodeCode(season: item.season, episode: item.episode, episodeEnd: item.episodeEnd) ?? "",
                           runtimeText: (item.runtime ?? item.watch.duration).map(DisplayText.runtime),
                           progress: CardBuilder.progressFraction(item), isWatched: item.watch.watched, artworkKey: "item-\(item.id)")
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
            rows = children.prefix(pageSize).map(Self.row)
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
            rows += children.prefix(pageSize).map(Self.row)
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
                sizeText: c.isDirectory ? nil : c.size.map(DisplayText.fileSize), modified: c.modified)
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
