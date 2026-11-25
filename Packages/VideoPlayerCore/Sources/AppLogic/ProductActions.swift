import Foundation
import LibraryIndex

/// R471 Part 3 (PROVISIONAL): the actions list behind a product page's details button, per kind of page, in the owner's
/// order (functionality after the media-server apps the owner named, wording our own). One list feeds the details button,
/// a long press on a poster or card, and the context menu, so the three never differ.
///
/// An action is listed only when it works: `ProductAction.isBuilt` is false for the actions this app does not have yet
/// (they are recorded in OPEN_QUESTIONS R471 (8), never shown as dead buttons).
public enum ProductAction: String, CaseIterable, Sendable {
    case resume, restart, play
    case audio, subtitles
    case addToWatchlist, removeFromWatchlist
    case addToList, addToPlaylistOrCollection
    case rate
    case markWatched, markUnwatched, markAllWatched, markAllUnwatched
    case goToShow, goToSeason
    case manage
    case fileInfo, moreWaysToWatch
    // Manage
    case changeArtwork, editMetadata, refreshMetadata, analyze, fixMatch, unmatch, playHistory, delete

    public var title: String {
        switch self {
        case .resume: return "Resume"
        case .restart: return "Start Over"
        case .play: return "Play"
        case .audio: return "Audio"
        case .subtitles: return "Subtitles"
        case .addToWatchlist: return "Add to Watchlist"
        case .removeFromWatchlist: return "Remove from Watchlist"
        case .addToList: return "Add to List"
        case .addToPlaylistOrCollection: return "Add to Playlist or Collection"
        case .rate: return "Rate"
        case .markWatched: return "Mark as Watched"
        case .markUnwatched: return "Mark as Unwatched"
        case .markAllWatched: return "Mark All as Watched"
        case .markAllUnwatched: return "Mark All as Unwatched"
        case .goToShow: return "Go to Show"
        case .goToSeason: return "Go to Season"
        case .manage: return "Manage"
        case .fileInfo: return "File Info"
        case .moreWaysToWatch: return "Versions"
        case .changeArtwork: return "Change Artwork"
        case .editMetadata: return "Edit Details"
        case .refreshMetadata: return "Refresh Details"
        case .analyze: return "Analyze File"
        case .fixMatch: return "Fix Match"
        case .unmatch: return "Unmatch"
        case .playHistory: return "Play History"
        case .delete: return "Delete from Library"
        }
    }

    public var symbol: String {
        switch self {
        case .resume, .play: return "play.fill"
        case .restart: return "arrow.counterclockwise"
        case .audio: return "speaker.wave.2"
        case .subtitles: return "captions.bubble"
        case .addToWatchlist: return "plus"
        case .removeFromWatchlist: return "checkmark"
        case .addToList: return "list.bullet"
        case .addToPlaylistOrCollection: return "rectangle.stack.badge.plus"
        case .rate: return "star"
        case .markWatched, .markAllWatched: return "eye"
        case .markUnwatched, .markAllUnwatched: return "eye.slash"
        case .goToShow: return "tv"
        case .goToSeason: return "square.stack"
        case .manage: return "slider.horizontal.3"
        case .fileInfo: return "info.circle"
        case .moreWaysToWatch: return "square.stack"
        case .changeArtwork: return "photo"
        case .editMetadata: return "pencil"
        case .refreshMetadata: return "arrow.clockwise"
        case .analyze: return "waveform"
        case .fixMatch: return "magnifyingglass"
        case .unmatch: return "xmark.circle"
        case .playHistory: return "clock"
        case .delete: return "trash"
        }
    }

    /// Whether the app has this action today. The others are left out of every list (R471 (8)).
    public var isBuilt: Bool {
        switch self {
        // R471 (13): Change Artwork is built (the edit screen's Artwork group, R455).
        // R471 (14): Unmatch is built (movie and show; asks first).
        // R471 (15): Delete from Library is built (the library only; the file stays on the source; asks first).
        // R471 (16): Rate is built (1 to 5 stars in the user layer; sent to Plex where its sync is on).
        // R471 (17): Add to List and Add to Playlist or Collection are built (the user's own lists in the user layer).
        // R471 (18): Refresh Details is built (one title's kept online answers dropped and fetched again).
        // R471 (19): Analyze File is built (streams read again; an episode's intro and credits found again).
        // R471 (20): Play History is built (one entry per playback in the user layer; Clear asks first).
        case .audio, .subtitles:
            return false
        default:
            return true
        }
    }

    /// Asks before it acts (the system confirmation dialog).
    public var needsConfirmation: Bool { self == .unmatch || self == .delete || self == .markAllWatched || self == .markAllUnwatched }

    /// Inside Manage rather than on the first level.
    public var isManage: Bool {
        [.changeArtwork, .editMetadata, .refreshMetadata, .analyze, .fixMatch, .unmatch, .playHistory, .delete].contains(self)
    }
}

extension ProductAction {
    /// R471 (31), PROVISIONAL (Plex episode menu): Go to Season names the season it opens, "Go to Season 4", or
    /// "Go to Specials" for season 0; the plain title when the file gives no season.
    public static func goToSeasonTitle(_ season: Int?) -> String {
        guard let season, season >= 0 else { return ProductAction.goToSeason.title }
        return season == 0 ? "Go to Specials" : "Go to Season \(season)"
    }

    /// R471 (34), PROVISIONAL (Plex movie menu with a resume point): the menu's Resume says how much is left, "Resume ·
    /// 41 min left" (`DisplayText.remaining`); the plain title when the time left is unknown.
    public static func resumeTitle(timeLeft: String?) -> String {
        guard let left = timeLeft?.trimmingCharacters(in: .whitespaces), !left.isEmpty else { return ProductAction.resume.title }
        return ProductAction.resume.title + " · " + left
    }
}

/// The facts the list depends on.
public struct ProductActionContext: Equatable, Sendable {
    public enum Kind: Sendable { case movie, episode, show, season }
    public var kind: Kind
    public var started: Bool = false
    public var watched: Bool = false
    /// Show or season: some episode unwatched / some watched.
    public var someUnwatched: Bool = false
    public var someWatched: Bool = false
    public var onWatchlist: Bool = false
    /// Matched to the catalogue (TMDB id known): the watchlist and Unmatch need it.
    public var matched: Bool = false
    public var hasFile: Bool = false
    public var versionCount: Int = 0
    /// Fix Match is off while Restrictions are on (R460).
    public var fixMatchAllowed: Bool = true
    /// R471 (15): Delete from Library is off while Restrictions are on (as Fix Match).
    public var deleteAllowed: Bool = true

    public init(kind: Kind) { self.kind = kind }
}

public enum ProductActions {
    /// Every action of the page, in order, built or not (the owner's full list; `list` drops the unbuilt ones).
    public static func all(_ c: ProductActionContext) -> [ProductAction] {
        var out: [ProductAction] = []
        switch c.kind {
        case .movie:
            out += c.started ? [.resume, .restart] : []
            if c.matched { out.append(c.onWatchlist ? .removeFromWatchlist : .addToWatchlist) }
            out += [.addToList, .addToPlaylistOrCollection, .rate]
            out.append(c.watched ? .markUnwatched : .markWatched)
        case .episode:
            out += [.audio, .subtitles]
            out += c.started ? [.restart] : []
            out += [.addToList, .addToPlaylistOrCollection, .rate]
            out.append(c.watched ? .markUnwatched : .markWatched)
            out += [.goToShow, .goToSeason]
        case .show, .season:
            if c.kind == .show, c.matched { out.append(c.onWatchlist ? .removeFromWatchlist : .addToWatchlist) }
            // R471 (17): a list holds movies, shows and episodes; a season is not a title of its own there (OPEN_QUESTIONS R471 (17)).
            out += c.kind == .season ? [.rate] : [.addToList, .addToPlaylistOrCollection, .rate]
            if c.someUnwatched { out.append(.markAllWatched) }
            if c.someWatched { out.append(.markAllUnwatched) }
            if c.kind == .season { out.append(.goToShow) }
        }
        out.append(.manage)
        if c.hasFile { out.append(.fileInfo) }
        if c.versionCount > 1 { out.append(.moreWaysToWatch) }
        return out
    }

    /// Manage's own list, per kind (episodes and seasons get the shorter one).
    public static func manage(_ c: ProductActionContext) -> [ProductAction] {
        var out: [ProductAction]
        switch c.kind {
        case .movie, .show:
            out = [.changeArtwork, .editMetadata, .refreshMetadata, .analyze, .fixMatch, .unmatch, .playHistory, .fileInfo, .delete]
        case .episode, .season:
            out = [.changeArtwork, .editMetadata, .analyze, .playHistory, .fileInfo, .delete]
        }
        // R471 (20): Play History lists the playbacks of a file; a show or a season has none of its own (its episodes do).
        if c.kind == .show || c.kind == .season { out.removeAll { $0 == .playHistory } }
        if !c.fixMatchAllowed { out.removeAll { $0 == .fixMatch } }
        if !c.deleteAllowed { out.removeAll { $0 == .delete } }
        if !c.matched { out.removeAll { $0 == .unmatch } }
        if !c.hasFile { out.removeAll { $0 == .fileInfo || $0 == .analyze } }
        return out
    }

    /// What the details button shows: the built actions only; Manage only when something inside it is built.
    public static func list(_ c: ProductActionContext) -> [ProductAction] {
        let builtManage = manage(c).filter(\.isBuilt)
        return all(c).filter { $0 == .manage ? !builtManage.isEmpty : $0.isBuilt }
    }

    public static func manageList(_ c: ProductActionContext) -> [ProductAction] { manage(c).filter(\.isBuilt) }

    /// The actions a long press on a poster or card can run without opening the page (R471 (10)). R471 (23): Mark All as
    /// Watched or Unwatched for a show's poster and a season (they appear only in a show's or a season's list).
    public static let cardSupported: Set<ProductAction> = [.addToList, .addToPlaylistOrCollection, .rate, .markWatched, .markUnwatched,
                                                           .markAllWatched, .markAllUnwatched, .changeArtwork, .editMetadata, .unmatch, .delete]

    /// A long press on a card: the page's own list (Manage opened out), kept to what the card can run, in the page's order.
    /// So a card never offers an action the page does not, and both use the same words.
    public static func cardList(_ c: ProductActionContext) -> [ProductAction] {
        (list(c).filter { $0 != .manage } + manageList(c)).filter { cardSupported.contains($0) }
    }
}

public extension ItemCard {
    /// The facts the actions list needs, as far as a card knows them.
    var actionContext: ProductActionContext {
        var c = ProductActionContext(kind: kind == .movie ? .movie : .episode)
        c.started = progress != nil
        c.watched = isWatched
        c.matched = isMatched
        c.hasFile = true
        return c
    }
}

public extension SeriesSummary {
    /// R471 (23): the facts a show's poster knows. Whether the show is matched is not known without a library read, so a
    /// poster's list has no Unmatch (the page has it).
    var actionContext: ProductActionContext {
        var c = ProductActionContext(kind: .show)
        c.someUnwatched = unwatchedCount > 0
        c.someWatched = episodeCount > unwatchedCount
        return c
    }
}

public extension SeasonSection {
    /// R471 (23): the facts of one season for a long press on it (its own episodes' watch state).
    var actionContext: ProductActionContext {
        var c = ProductActionContext(kind: .season)
        c.someUnwatched = watchedCount < episodes.count
        c.someWatched = watchedCount > 0
        return c
    }
}
