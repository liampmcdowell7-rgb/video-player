import Foundation

/// R371 (owner's request of 21 Nov 2026): a title's content (age) rating, shown as an outlined text badge ("PG-13", "R",
/// "TV-MA", "TV-14", "12", "15"), never a rating board's logo. Where it comes from, first found wins:
///   1. the source's own rating (Plex `contentRating`, R307's layering; Jellyfin and Emby when their clients carry one);
///   2. TMDB's certification for the Region setting (only with the user's key);
///   3. Wikidata's official rating (R372), only while Free Data Sources is on.
/// Never invented: an empty value, or one that only says there is no rating, gives no badge.
public enum ContentRating {
    /// The order of the layers for the rating. Not the synopsis order (source, Wikidata, TMDB; R210): for a rating the
    /// owner put TMDB's regional certification before Wikidata.
    public static let order: [DetailsLayer] = [.source, .tmdb, .wikidata]

    /// Values that say a title has no rating: no badge for them.
    static let noRating: Set<String> = ["nr", "notrated", "unrated", "na", "none", "unknown"]

    /// The rating as it is shown: trimmed, a leading "Rated " and a country prefix ("US:", "gb/") removed, as the sources
    /// write them ("Rated R", "US:TV-MA", "gb/15"). Nil for empty text or a value that says there is no rating.
    public static func clean(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("rated ") { text = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        if let sep = text.firstIndex(where: { $0 == ":" || $0 == "/" }), text.distance(from: text.startIndex, to: sep) == 2,
           text[text.startIndex..<sep].allSatisfy(\.isLetter) {
            text = String(text[text.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
        }
        let key = text.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !text.isEmpty, !noRating.contains(key) else { return nil }
        return text
    }

    /// The rating to show from what each layer gave, in `order`; nil when none gave one.
    public static func pick(_ found: [(DetailsLayer, String?)]) -> (rating: String, layer: DetailsLayer)? {
        for layer in order {
            for (l, raw) in found where l == layer {
                if let rating = clean(raw) { return (rating, layer) }
            }
        }
        return nil
    }
}

public extension MediaInfo {
    /// R371: Information starts with the title's rating ("Rating: PG-13") when a layer gave one; nothing is added without.
    static func withRating(_ rows: [MediaInfoRow], details: TitleDetails?) -> [MediaInfoRow] {
        guard let rating = details?.contentRating else { return rows }
        return [MediaInfoRow(label: "Rating", value: rating)] + rows
    }
}
