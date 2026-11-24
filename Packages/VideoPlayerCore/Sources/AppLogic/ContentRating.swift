import Foundation
import MetadataOnline

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

    /// R372: Wikidata's rating to use: the Region setting's system first ("GB" picks BBFC), else the first found in
    /// `WikidataClient.ratingSystems` order (MPA, BBFC, FSK, ACB, ClassInd). Nil without any.
    public static func wikidata(_ ratings: [WikidataRating], region: String?) -> WikidataRating? {
        let regional = WikidataClient.ratingSystems.first { $0.region == region?.uppercased() }?.system
        if let regional, let match = ratings.first(where: { $0.system == regional }) { return match }
        for system in WikidataClient.ratingSystems.map(\.system) {
            if let match = ratings.first(where: { $0.system == system }) { return match }
        }
        return nil
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
    /// R372: then the content advice in full ("Content Advice: Violence · Strong Language") when Wikidata gave any.
    static func withRating(_ rows: [MediaInfoRow], details: TitleDetails?) -> [MediaInfoRow] {
        var top: [MediaInfoRow] = []
        if let rating = details?.contentRating { top.append(MediaInfoRow(label: "Rating", value: rating)) }
        // R453: the release date (an episode's air date, a show's first air date) as the date formatter writes it.
        if let date = details?.releaseDate { top.append(MediaInfoRow(label: "Release Date", value: InfoDateText.text(date))) }
        if let advice = details?.contentDescriptors, !advice.isEmpty {
            top.append(MediaInfoRow(label: "Content Advice", value: advice.joined(separator: ShortLine.separator)))
        }
        return top + rows
    }
}
