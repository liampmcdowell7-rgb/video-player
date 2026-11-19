import Foundation
import LibraryIndex

// Cards and the filter/sort vocabulary the library screens share. Library-only rule: a card can only be built from a
// `LibraryItem` that the index returned, so nothing promoted or third-party can reach a library screen (Discover is a
// separate feature with its own, clearly labeled screens).

public struct ItemCard: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var kind: ItemKind
    public var title: String
    /// Second line ("2020", "Dark Harbor · S1 E3 · 41 min left").
    public var subtitle: String?
    /// 0..<1 only while the item is in progress; nil when not started or finished.
    public var progress: Double?
    public var isWatched: Bool
    public var isFavorite: Bool
    /// "4K", "Dolby Vision", "HDR10+", "HDR10", "HLG", "Dolby Atmos", in that order (what the best version contains).
    public var badges: [String]
    /// Key the app resolves to a poster or still ("item-42").
    public var artworkKey: String
    /// The second line as prioritised segments (rule S1): `subtitle` is its full text.
    public var subtitleLine = ShortLine([])
    /// The badges as one line (rule S1): Dolby Atmos is left out first, then the HDR format, then 4K (#17 C).
    public var badgeLine = ShortLine([])
}

public enum CardStyle: Sendable {
    /// Continue Watching: shows what is left.
    case continueWatching
    /// Next Up: shows series and episode, no progress.
    case nextUp
    /// Grids and Recently Added.
    case standard
}

public enum CardBuilder {
    /// A started item counts as in progress between this fraction and the watched mark.
    static let minimumProgress = 0.005

    public static func card(_ item: LibraryItem, style: CardStyle = .standard) -> ItemCard {
        let code = DisplayText.episodeCode(season: item.season, episode: item.episode, episodeEnd: item.episodeEnd)
        // Second-line segments; the priority says what stays longest when the line is too long (rule S1).
        var parts: [ShortLine.Segment] = []
        var title = item.title
        switch item.kind {
        case .movie:
            if style == .standard, let year = item.year, year > 0 { parts.append(.init(String(year), priority: Priority.year)) }
        case .episode:
            // An episode card is titled with its show; the second line says which episode (screenshot review item 3b:
            // the card showed "S02E01" over "Sample Show 1 · S2 E1 · …"). "S2 E1 · Pilot", or "S2 E1" without a real title.
            let episodeTitle = episodeTitleIsReal(item) ? item.title : nil
            if let series = item.seriesTitle, !series.isEmpty { title = series } else if episodeTitle == nil, let code { title = code }
            // #17 C drop order: the episode title goes first; the episode number and the time left are dropped last.
            if let code, title != code { parts.append(.init(code, priority: Priority.episodeCode)) }
            if let episodeTitle, episodeTitle != title { parts.append(.init(episodeTitle, priority: Priority.episodeTitle)) }
        }
        let progress = progressFraction(item)
        if style == .continueWatching, let progress, let duration = item.watch.duration ?? item.runtime, duration > 0 {
            // Movies: the time left is the whole second line. Episodes: kept with the episode number (#17 C: the Larger
            // Text screenshot showed "S2 E1 · 31 min left" cut to "S2 E1").
            parts.append(.init(DisplayText.remaining(duration * (1 - progress)), priority: Priority.timeLeft))
        }
        let subtitleLine = ShortLine(parts)
        let badgeList = badges(item)
        return ItemCard(
            id: item.id, kind: item.kind, title: title.isEmpty ? "Untitled" : title,
            subtitle: subtitleLine.isEmpty ? nil : subtitleLine.full,
            progress: style == .nextUp ? nil : progress, isWatched: item.watch.watched, isFavorite: item.watch.favorite,
            badges: badgeList, artworkKey: "item-\(item.id)", subtitleLine: subtitleLine, badgeLine: badgeLine(badgeList))
    }

    /// How long each part of a card's lines is kept when the line does not fit (rule S1; #17 C). Higher is kept longer.
    public enum Priority {
        /// Second line: the episode title is dropped first; the year, the episode number and the time left stay.
        public static let episodeTitle = 1
        public static let year = 2
        public static let timeLeft = 3
        public static let episodeCode = 4
        /// Badge line, lowest first: the audio format (Dolby Atmos), then the HDR format, then the resolution.
        public static let audioBadge = 1
        public static let hdrBadge = 2
        public static let resolutionBadge = 3
    }

    /// The badges as one line with the #17 C drop order: Dolby Atmos first, then the HDR format, then 4K. Unknown texts
    /// count as audio (dropped first). Used by the cards and the detail page.
    public static func badgeLine(_ badges: [String]) -> ShortLine {
        ShortLine(badges.map { text -> ShortLine.Segment in
            switch text {
            case "4K": return .init(text, priority: Priority.resolutionBadge)
            case "Dolby Vision", "HDR10+", "HDR10", "HLG": return .init(text, priority: Priority.hdrBadge)
            default: return .init(text, priority: Priority.audioBadge)
            }
        })
    }

    /// False when an episode has no title of its own: empty, the same as its show, or only an episode code taken from the
    /// file name ("S02E01", "s2e1", "2x01", "Episode 3").
    static func episodeTitleIsReal(_ item: LibraryItem) -> Bool {
        let t = item.title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        if let series = item.seriesTitle, series.trimmingCharacters(in: .whitespaces).compare(t, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return false }
        let codeOnly = #"^(s\d{1,3}\s*e\d{1,4}(\s*-?\s*e?\d{1,4})?|\d{1,2}x\d{1,4}|e(p(isode)?)?\.?\s*\d{1,4})$"#
        return t.range(of: codeOnly, options: [.regularExpression, .caseInsensitive]) == nil
    }

    static func progressFraction(_ item: LibraryItem) -> Double? {
        guard !item.watch.watched, item.watch.position > 0 else { return nil }
        guard let duration = item.watch.duration ?? item.runtime, duration > 0 else { return nil }
        let f = item.watch.position / duration
        return f >= minimumProgress && f < 1 ? f : nil
    }

    static func badges(_ item: LibraryItem) -> [String] {
        var b: [String] = []
        if item.maxResolution == .uhd4k { b.append("4K") }
        if item.hdrFormats.contains(.dolbyVision) { b.append("Dolby Vision") }
        else if item.hdrFormats.contains(.hdr10Plus) { b.append("HDR10+") }
        else if item.hdrFormats.contains(.hdr10) { b.append("HDR10") }
        else if item.hdrFormats.contains(.hlg) { b.append("HLG") }
        if item.hasAtmos { b.append("Dolby Atmos") }
        return b
    }
}

// MARK: Filters

/// One switch in the filter menu.
public enum FilterOption: Hashable, Sendable {
    case resolution(ResolutionClass)
    case hdr(HDRFormat)
    case atmos
    case minChannels(Int)
    case container(ContainerFormat)
    case watch(WatchFilter)
    case favorites
    case genre(String)

    public var title: String {
        switch self {
        case .resolution(let r):
            switch r { case .sd: return "SD"; case .hd720: return "720p"; case .hd1080: return "1080p"; case .uhd4k: return "4K" }
        case .hdr(let f):
            switch f { case .sdr: return "SDR"; case .hdr10: return "HDR10"; case .hdr10Plus: return "HDR10+"; case .hlg: return "HLG"; case .dolbyVision: return "Dolby Vision" }
        case .atmos: return "Dolby Atmos"
        case .minChannels(let n): return n >= 8 ? "7.1 or more" : (n >= 6 ? "5.1 or more" : "Stereo or more")
        case .container(let c): return String(describing: c).uppercased()
        case .watch(let w):
            switch w { case .unwatched: return "Unwatched"; case .watched: return "Watched"; case .inProgress: return "In Progress" }
        case .favorites: return "Favorites"
        case .genre(let g): return g
        }
    }

    public func isOn(in f: ItemFilter) -> Bool {
        switch self {
        case .resolution(let r): return f.resolutions.contains(r)
        case .hdr(let h): return f.hdrFormats.contains(h)
        case .atmos: return f.dolbyAtmos == true
        case .minChannels(let n): return f.minChannels == n
        case .container(let c): return f.containers.contains(c)
        case .watch(let w): return f.watch == w
        case .favorites: return f.favoritesOnly
        case .genre(let g): return f.genres.contains(g)
        }
    }

    /// Switches this option on or off in `f`. Options of one group combine with OR, groups with AND (the index's rule).
    public func toggle(in f: inout ItemFilter) {
        let on = isOn(in: f)
        switch self {
        case .resolution(let r): if on { f.resolutions.remove(r) } else { f.resolutions.insert(r) }
        case .hdr(let h): if on { f.hdrFormats.remove(h) } else { f.hdrFormats.insert(h) }
        case .atmos: f.dolbyAtmos = on ? nil : true
        case .minChannels(let n): f.minChannels = on ? nil : n
        case .container(let c): if on { f.containers.remove(c) } else { f.containers.insert(c) }
        case .watch(let w): f.watch = on ? nil : w
        case .favorites: f.favoritesOnly = !on
        case .genre(let g): if on { f.genres.remove(g) } else { f.genres.insert(g) }
        }
    }
}

public struct FilterChip: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
}

public enum FilterDescriber {
    /// The chips under the grid title, one per active setting, in a fixed order.
    public static func chips(for f: ItemFilter, base: ItemFilter = ItemFilter()) -> [FilterChip] {
        var chips: [FilterChip] = []
        func add(_ id: String, _ title: String) { chips.append(FilterChip(id: id, title: title)) }
        if let text = f.text, !text.isEmpty, text != base.text { add("text", "“\(text)”") }
        if f.watch != base.watch, let w = f.watch { add("watch", FilterOption.watch(w).title) }
        for r in f.resolutions.sorted() where !base.resolutions.contains(r) { add("res-\(r.rawValue)", FilterOption.resolution(r).title) }
        for h in f.hdrFormats.sorted(by: { $0.rawValue < $1.rawValue }) where !base.hdrFormats.contains(h) { add("hdr-\(h.rawValue)", FilterOption.hdr(h).title) }
        if f.dolbyAtmos == true { add("atmos", "Dolby Atmos") }
        if let n = f.minChannels { add("channels", FilterOption.minChannels(n).title) }
        for c in f.containers.sorted(by: { $0.rawValue < $1.rawValue }) { add("container-\(c.rawValue)", FilterOption.container(c).title) }
        for g in f.genres.sorted() { add("genre-\(g)", g) }
        switch (f.yearMin, f.yearMax) {
        case (let a?, let b?): add("year", a == b ? "\(a)" : "\(a)–\(b)")
        case (let a?, nil): add("year", "\(a) and later")
        case (nil, let b?): add("year", "\(b) and earlier")
        default: break
        }
        if let r = f.minRating { add("rating", "Rating \(r == r.rounded() ? String(Int(r)) : String(r))+") }
        if f.favoritesOnly { add("favorites", "Favorites") }
        return chips
    }

    /// Removes the setting a chip stands for.
    public static func remove(_ chip: FilterChip, from f: inout ItemFilter) {
        switch chip.id {
        case "text": f.text = nil
        case "watch": f.watch = nil
        case "atmos": f.dolbyAtmos = nil
        case "channels": f.minChannels = nil
        case "year": f.yearMin = nil; f.yearMax = nil
        case "rating": f.minRating = nil
        case "favorites": f.favoritesOnly = false
        default:
            if chip.id.hasPrefix("res-"), let n = Int(chip.id.dropFirst(4)), let r = ResolutionClass(rawValue: n) { f.resolutions.remove(r) }
            else if chip.id.hasPrefix("hdr-"), let n = Int(chip.id.dropFirst(4)), let h = HDRFormat(rawValue: n) { f.hdrFormats.remove(h) }
            else if chip.id.hasPrefix("container-"), let n = Int(chip.id.dropFirst(10)), let c = ContainerFormat(rawValue: n) { f.containers.remove(c) }
            else if chip.id.hasPrefix("genre-") { f.genres.remove(String(chip.id.dropFirst(6))) }
        }
    }
}

// MARK: Sorts

public struct SortChoice: Equatable, Sendable, Identifiable {
    public var key: ItemSortKey
    public var title: String
    public var id: String { key.rawValue }

    public static let all: [SortChoice] = [
        SortChoice(key: .title, title: "Title"), SortChoice(key: .year, title: "Year"), SortChoice(key: .rating, title: "Rating"),
        SortChoice(key: .added, title: "Date Added"), SortChoice(key: .lastPlayed, title: "Last Played"), SortChoice(key: .runtime, title: "Runtime"),
    ]

    /// Interpretation (PROVISIONAL): Title sorts A to Z, every other key starts with the largest or newest first.
    public static func defaultSort(for key: ItemSortKey) -> ItemSort { ItemSort(key: key, ascending: key == .title) }

    public static func title(of sort: ItemSort) -> String {
        let name = all.first { $0.key == sort.key }?.title ?? sort.key.rawValue
        return "\(name), \(sort.ascending ? "ascending" : "descending")"
    }
}
