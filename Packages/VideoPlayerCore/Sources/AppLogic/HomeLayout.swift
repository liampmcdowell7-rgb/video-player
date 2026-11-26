import Foundation
import LibraryIndex
import VideoPlayerCore

/// R349 (owner's device test of build 5, 21 Nov 2026, item C; PROVISIONAL): Home follows the Home screen of Apple's TV app
/// on tvOS 27 (written description of the owner's request; the owner's photos of the TV app replace it as the reference
/// when they come, docs/DESIGN_SYSTEM.md "Reference screens"): a full-width FEATURED area at the top (large artwork of one
/// title, its title logo or name, one line of metadata, Play and More), then the shelves. Continue Watching and Next Up use
/// landscape thumbnails, as the TV app's "Continue Watching" / "Up Next"; Recently Added keeps posters. The owner's Home
/// Screen settings still decide which shelves show; the featured title is picked from the shelves that show.
public struct HomeFeatured: Equatable, Sendable {
    /// The featured title's card (the same card as in its shelf).
    public var card: ItemCard
    /// The shelf it was picked from.
    public var shelf: HomeRowID

    /// "Resume" for a started title (Continue Watching), "Play" otherwise: the TV app's button names.
    public var playTitle: String { card.progress == nil ? "Play" : "Resume" }

    /// The artwork key of the large picture and the logo: the show's for an episode (an episode has no logo of its own),
    /// the movie's own otherwise.
    public var titleArtworkKey: String {
        if card.kind == .episode, let series = card.seriesID { return "series-\(series)" }
        return card.artworkKey
    }

    /// The one metadata line: the card's second line ("2021", "S1 E3 · Pilot · 41 min left") followed by its format
    /// badges, as prioritised segments (rule S1: the badges are dropped first when the line is too long).
    public var metadata: ShortLine {
        let lowest: Int = (card.subtitleLine.segments.map(\.priority).min() ?? 1) - 1
        let badges: [ShortLine.Segment] = card.badges.map { ShortLine.Segment($0, priority: lowest) }
        return ShortLine(card.subtitleLine.segments + badges)
    }

    /// R471 (46), PROVISIONAL (Home hero photo): the featured title's kind line, as on its page: "Movie" or "TV Show" (an
    /// episode is shown as its show), its genres, then the rating's box. R471 (86): led by the source's generic glyph, as
    /// the product pages' kind line is (the card's file's source; nil, no glyph, until it is known).
    public func kindLine(source: SourceKind? = nil, genres: [String], rating: String?) -> [HeroLines.Segment] {
        HeroLines.kindLine(kind: card.kind == .movie ? .movie : .show, source: source, genres: genres, rating: rating)
    }

    /// R471 (46): how many lines of the synopsis Home shows under the featured title (the photo shows three).
    public static let synopsisLines = 3

    /// Which shelf gives the featured title, first one with a card wins: Continue Watching (what the person is in the
    /// middle of, as the TV app's Home leads with it), then Recently Added, then Next Up.
    public static let order: [HomeRowID] = [.continueWatching, .recentlyAdded, .nextUp]

    /// The featured title of the shelves that show (`rows` already filtered by the Home Screen settings); nil when none
    /// has a card (Home then shows its shelves only, or its empty state).
    public static func pick(from rows: [HomeRow]) -> HomeFeatured? {
        for shelf in order {
            if let card = rows.first(where: { $0.id == shelf })?.cards.first { return HomeFeatured(card: card, shelf: shelf) }
        }
        return nil
    }
}

extension HomeRowID {
    /// R349: landscape (16:9) thumbnails on Continue Watching and Next Up, as the TV app's "Continue Watching" and
    /// "Up Next"; posters on Recently Added.
    public var usesLandscapeCards: Bool {
        switch self {
        case .continueWatching, .nextUp: true
        case .recentlyAdded: false
        }
    }
}
