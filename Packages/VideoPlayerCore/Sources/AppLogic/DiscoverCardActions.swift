import Foundation
import MetadataOnline

// R342 (Decided by the owner, 21 Nov 2026; docs/HIG_AUDIT.md T12): Select on a Discover card opens the title's page, as
// Select on a poster does everywhere else; adding to or removing from the watchlist moves into the card's context menu
// (press and hold) and onto the page.

extension DiscoverContent {
    /// The title with this id wherever it is listed (watchlist, a collection, similar), with its current watchlist flag;
    /// nil when it is no longer listed.
    public func title(id: String) -> DiscoverTitle? {
        if let hit = watchlist.first(where: { $0.id == id }) { return hit }
        for gap in collectionGaps { if let hit = gap.missing.first(where: { $0.id == id }) { return hit } }
        return similar.first { $0.id == id }
    }
}

/// The texts of the Discover card's context menu and of the title's page.
public enum DiscoverCardText {
    /// The watchlist action for a title: its label and SF Symbol.
    public static func watchlistAction(_ title: DiscoverTitle) -> (label: String, symbol: String) {
        title.onWatchlist ? ("Remove from Watchlist", "minus.circle") : ("Add to Watchlist", "plus.circle")
    }

    /// The card's VoiceOver hint: what Select does now.
    public static let cardHint = "Opens the title. Press and hold for the watchlist."

    /// "2021 · Similar to Sample Movie 1": the year goes first when the line is too long (rule S1).
    public static func detailLine(_ title: DiscoverTitle) -> ShortLine {
        ShortLine([.init(title.year.map(String.init) ?? "", priority: 1), .init(title.reason, priority: 2)])
    }

    /// "Movie" or "Show", for the page.
    public static func kindText(_ title: DiscoverTitle) -> String { title.kind == .movie ? "Movie" : "Show" }
}
