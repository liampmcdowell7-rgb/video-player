import Foundation
import LibraryIndex

/// R319 (owner's request of 21 Nov 2026): the player's Info tab shows the title's content rating, as Apple's TV app does.
/// It is the system's own metadata item, `AVMetadataIdentifier.iTunesMetadataContentRating` (a String; Apple's
/// "Customizing the tvOS playback experience" lists it among the values the player presents in its Info tab), added to the
/// item's external metadata. The rating is R371's: the same layered details as the product page (source, then TMDB, then
/// Wikidata), never invented. Now Playing gets no rating: `MPNowPlayingInfoCenter` has no content-rating key, and on tvOS
/// the system player owns the Now Playing entry (R317). R380: a rating on hand is set before playback starts; the online
/// lookup after the start replaces it only when stronger (`atStart`, `afterLookup`).
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

    // MARK: R380: a rating before playback starts, replaced only by a stronger one

    /// The rating on the item and the R371 layer it came from.
    public struct Choice: Equatable, Sendable {
        public var value: String
        public var layer: DetailsLayer?

        public init(value: String, layer: DetailsLayer?) {
            self.value = value
            self.layer = layer
        }
    }

    /// R380 (PROVISIONAL): the rating set on the item BEFORE playback starts, so the Apple TV's content restrictions can use
    /// it (WWDC19 session 503: give the rating "at the start of playback"). Only what is on hand without a request: the
    /// source's own rating from the listing its client already holds, then the rating already stored in the library (the
    /// NFO file's, or the server's single-item answer, R374). Both are R371's source layer. Nil when neither gives one
    /// ("NR", "Not Rated" and "" count as none): then nothing is set at start.
    public static func atStart(sourceRating: String?, storedRating: String?) -> Choice? {
        if let value = metadataValue(sourceRating) { return Choice(value: value, layer: .source) }
        if let value = metadataValue(storedRating) { return Choice(value: value, layer: .source) }
        return nil
    }

    /// R380: what the online lookup's answer (the layered details, R371: source, then TMDB, then Wikidata) does to the
    /// rating on the item. Returns the new choice to set, or nil to leave the item as it is. The answer replaces the item's
    /// rating when the item has none, or when the answer's layer ranks at least as high in `ContentRating.order` as the
    /// item's (a source answer can update a source rating; TMDB's or Wikidata's never replaces the source's). An answer
    /// without a rating, or with the same value, changes nothing. An answer of unknown layer ranks lowest.
    public static func afterLookup(current: Choice?, answer: String?, answerLayer: DetailsLayer?) -> Choice? {
        guard let value = metadataValue(answer) else { return nil }
        let candidate = Choice(value: value, layer: answerLayer)
        guard let current else { return candidate }
        guard rank(answerLayer) <= rank(current.layer), value != current.value else { return nil }
        return candidate
    }

    /// The place of a layer in the rating order (0 is the strongest); an unknown layer comes after all of them.
    static func rank(_ layer: DetailsLayer?) -> Int {
        guard let layer, let index = ContentRating.order.firstIndex(of: layer) else { return ContentRating.order.count }
        return index
    }
}
