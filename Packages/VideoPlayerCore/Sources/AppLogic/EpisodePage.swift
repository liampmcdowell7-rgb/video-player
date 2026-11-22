import Foundation
import LibraryIndex

/// R387 (PROVISIONAL; owner's device test, item A: the episode page was "just a list of specs"): the episode page is the
/// product page (R350) with an episode's parts, reusing its views. These are the choices the views draw from, kept here so
/// the Linux tests cover them. Every part with no data is left out (no empty labels).
public enum EpisodePage {
    /// The row of the season's other episodes: the season the episode belongs to (found by the episode's id, else by its
    /// season number), without the episode itself, in the season's order. Nil when the season has no other episode, so
    /// the page draws no empty row.
    public static func otherEpisodes(in seasons: [SeasonSection], season: Int?, currentID: Int64) -> SeasonSection? {
        let found = seasons.first { $0.episodes.contains { $0.id == currentID } }
            ?? season.flatMap { number in seasons.first { $0.season == number } }
        guard var section = found else { return nil }
        section.episodes.removeAll { $0.id == currentID }
        guard !section.episodes.isEmpty else { return nil }
        section.watchedCount = section.episodes.filter(\.isWatched).count
        return section
    }

    /// The age rating on the metadata line: the episode's own (its source's), else the show's. Nil (nothing drawn) when
    /// neither has one. An empty text counts as none.
    public static func rating(episode: String?, series: String?) -> String? {
        if let own = episode?.trimmingCharacters(in: .whitespaces), !own.isEmpty { return own }
        if let show = series?.trimmingCharacters(in: .whitespaces), !show.isEmpty { return show }
        return nil
    }

    /// Whether the page asks for the show's details to borrow its rating: an episode with a show, whose own details gave
    /// no rating.
    public static func needsSeriesRating(kind: ItemKind, seriesID: Int64?, ownRating: String?) -> Bool {
        kind == .episode && seriesID != nil && rating(episode: ownRating, series: nil) == nil
    }
}
