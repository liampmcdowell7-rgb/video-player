import Foundation
import LibraryIndex

/// R319 (owner's request of 21 Nov 2026): the player's Info tab shows the title's content rating, as Apple's TV app does.
/// It is the system's own metadata item, `AVMetadataIdentifier.iTunesMetadataContentRating` (a String; Apple's
/// "Customizing the tvOS playback experience" lists it among the values the player presents in its Info tab), added to the
/// item's external metadata. The rating is R371's: the same layered details as the product page (source, then TMDB, then
/// Wikidata), never invented. Now Playing gets no rating: `MPNowPlayingInfoCenter` has no content-rating key, and on tvOS
/// the system player owns the Now Playing entry (R317).
public enum PlayerRating {
    /// The details key whose rating the player shows: an episode uses its show's ("series-N"), as the show page and the Home
    /// featured title do (no source gives an episode its own rating yet); a film, or an episode without a show, its own
    /// ("item-N").
    public static func detailsKey(itemID: Int64, isEpisode: Bool, seriesID: Int64?) -> String {
        if isEpisode, let seriesID { return "series-\(seriesID)" }
        return "item-\(itemID)"
    }

    public static func detailsKey(for item: LibraryItem) -> String {
        detailsKey(itemID: item.id, isEpisode: item.kind == .episode, seriesID: item.seriesID)
    }

    /// The metadata item's value: the rating as the badge shows it ("PG-13", "TV-MA", "15"). Nil, so no item is added, when
    /// there is no rating or the value only says there is none ("NR", "Not Rated").
    public static func metadataValue(_ rating: String?) -> String? {
        ContentRating.clean(rating)
    }
}
