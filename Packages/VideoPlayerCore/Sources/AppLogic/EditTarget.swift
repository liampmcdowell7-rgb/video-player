import Foundation
import LibraryIndex
import UserData

/// R449: which edit records belong to one library item, and the user layer applied to the details a page shows.
public enum EditTarget {
    /// The keys an item's edits can live under, preferred first: the online id (movie or show) when the item has one, then
    /// the file (source plus path) of the preferred version, then the show's name for a series row. Reads merge them per field.
    public static func keys(for item: LibraryItem, files: [StoredFile]) -> [UDEditKey] {
        var out: [UDEditKey] = []
        let file: StoredFile? = files.first { $0.id == item.preferredFileID } ?? files.first
        if item.kind == .episode {
            if let tmdb = item.tmdbID, let season = item.season, let episode = item.episode {
                out.append(UDEditKey.show(tmdbID: tmdb).episode(season: season, episode: episode))
            }
        } else if let tmdb = item.tmdbID {
            out.append(UDEditKey.movie(tmdbID: tmdb))
        }
        if let file { out.append(UDEditKey.file(sourceID: file.sourceID, path: file.path)) }
        return out
    }

    /// The show page's key: the online id when known, else the show's name (PROVISIONAL, R449).
    public static func showKeys(tmdbID: Int?, title: String) -> [UDEditKey] {
        var out: [UDEditKey] = []
        if let tmdbID { out.append(UDEditKey.show(tmdbID: tmdbID)) }
        out.append(UDEditKey(recordID: "showname-" + title.precomposedStringWithCanonicalMapping.lowercased()))
        return out
    }

    /// R471 (11): one season of the show page: the show's keys with the season number, so a season's edits follow the show's
    /// online id when known and its name otherwise ("show-1399-s2", "showname-…-s2").
    public static func seasonKeys(tmdbID: Int?, title: String, season: Int) -> [UDEditKey] {
        showKeys(tmdbID: tmdbID, title: title).map { $0.season(season) }
    }

    /// The synopsis, cast and content rating of a page with the user's edits on top (an edited field replaces the layers').
    public static func apply(_ edits: UDEditValues, to details: TitleDetails?) -> TitleDetails? {
        guard !edits.isEmpty else { return details }
        var d: TitleDetails = details ?? TitleDetails(overview: nil, cast: [])
        if let text = edits[.overview]?.text { d.overview = text }
        if let rating = edits[.certification]?.text { d.contentRating = rating }
        // R453: an edited date, genres or runtime replace what the layers gave (the same fields the edit screens write).
        if let text = edits[.releaseDate]?.text, let date = PartialDate(iso: text) { d.releaseDate = date }
        else if let y = edits[.year]?.number, (1800...2200).contains(Int(y)) { d.releaseDate = PartialDate(year: Int(y)) }
        if let text = edits[.airDate]?.text, let date = PartialDate(iso: text) { d.releaseDate = date }
        if let genres = edits[.genres]?.list, !genres.isEmpty { d.genres = genres }
        if let minutes = edits[.runtime]?.number, minutes > 0 { d.runtimeMinutes = Int(minutes) }
        if let people = edits[.cast]?.people {
            d.cast = people.enumerated().map { TitleDetails.CastMember(id: 2_000_000 + $0, name: $1.name, role: $1.role.isEmpty ? nil : $1.role) }
        }
        return d.isEmpty ? nil : d
    }
}
