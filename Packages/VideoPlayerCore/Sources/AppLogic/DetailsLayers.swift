import Foundation
import LibraryIndex
import MetadataOnline

/// #26 item 6 (PROVISIONAL, OPEN_QUESTIONS R210): where a title's synopsis and cast come from, in this order:
///   1. the source itself (a Jellyfin, Emby or Plex server, an NFO file, embedded tags);
///   2. Wikidata (key-free, CC0), only while Free Data Sources is on;
///   3. TMDB, only with the user's own key.
/// A later layer only fills what the earlier ones left empty: the synopsis, the cast list, and a cast member's role or photo
/// (matched by name). Alternative on the open list: TMDB first.
///
/// Layer 1 is filled for Plex files only (the server's synopsis, R307); for every other source it stays empty (the NFO
/// reader, Jellyfin and Emby do not keep a synopsis), so their order is unchanged (docs/DATA_SOURCES.md).
public enum DetailsLayer: String, CaseIterable, Sendable {
    case source, wikidata, tmdb
}

public struct LayeredDetails: Equatable, Sendable {
    public var details: TitleDetails?
    /// The layers that gave something used, in order. For tests and the coverage count on the device checklist.
    public var used: [DetailsLayer]
    /// R371: the layer the content rating came from, nil without one.
    public var ratingLayer: DetailsLayer? = nil

    public static func merge(_ layers: [(DetailsLayer, TitleDetails?)]) -> LayeredDetails {
        var overview: String?
        var cast: [TitleDetails.CastMember] = []
        var used: [DetailsLayer] = []
        // R371: the rating follows its own order (`ContentRating.order`: source, TMDB, Wikidata), whatever order the layers
        // were asked in. R372: the content descriptors belong to a rating, so they come only from the layer whose rating is
        // shown (only Wikidata gives them): none next to TMDB's or the source's rating.
        let rating = ContentRating.pick(layers.map { ($0.0, $0.1?.contentRating) })
        var descriptors: [String] = []
        for (layer, found) in layers {
            guard let found else { continue }
            var gave = false
            if overview == nil, let text = found.overview { overview = text; gave = true }
            if cast.isEmpty, !found.cast.isEmpty {
                cast = Array(found.cast.prefix(TitleDetails.castLimit))
                gave = true
            } else if !cast.isEmpty {
                for index in cast.indices {
                    guard let match = found.cast.first(where: { Self.sameName($0.name, cast[index].name) }) else { continue }
                    if cast[index].role == nil, let role = match.role { cast[index].role = role; gave = true }
                    if cast[index].photo == nil, let photo = match.photo { cast[index].photo = photo; gave = true }
                }
            }
            if rating?.layer == layer { gave = true }
            if rating?.layer == layer, !found.contentDescriptors.isEmpty { descriptors = found.contentDescriptors }
            if gave { used.append(layer) }
        }
        guard overview != nil || !cast.isEmpty || rating != nil || !descriptors.isEmpty else { return LayeredDetails(details: nil, used: []) }
        var details = TitleDetails(overview: overview, cast: cast)
        details.contentRating = rating?.rating
        details.contentDescriptors = descriptors
        return LayeredDetails(details: details, used: used, ratingLayer: rating?.layer)
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Wikidata's facts as details: names only (no synopsis, no roles, no photos: Commons images are not used). R372: also
    /// the official rating for the Region setting (`ContentRating.wikidata`) and that rating's content descriptors.
    public static func details(from title: WikidataTitle, region: String? = nil) -> TitleDetails? {
        let cast = title.cast.prefix(TitleDetails.castLimit).enumerated().map { index, name in
            TitleDetails.CastMember(id: 1_000_000 + index, name: name, role: nil)
        }
        let rating = ContentRating.wikidata(title.ratings ?? [], region: region)
        let shown = rating.flatMap { ContentRating.clean($0.label) }
        guard !cast.isEmpty || shown != nil else { return nil }
        var details = TitleDetails(overview: nil, cast: Array(cast))
        details.contentRating = shown
        details.contentDescriptors = shown == nil ? [] : (rating?.descriptors ?? [])
        return details
    }
}

/// Asks each layer in order and merges. A layer that is off is a nil closure and is never asked.
public struct LayeredDetailsService: Sendable {
    public typealias Layer = @Sendable (String) async -> TitleDetails?

    private let source: Layer?
    private let wikidata: Layer?
    private let tmdb: Layer?

    public init(source: Layer?, wikidata: Layer?, tmdb: Layer?) {
        self.source = source
        self.wikidata = wikidata
        self.tmdb = tmdb
    }

    public func details(key: String) async -> LayeredDetails {
        var layers: [(DetailsLayer, TitleDetails?)] = []
        for (layer, ask) in [(DetailsLayer.source, source), (.wikidata, wikidata), (.tmdb, tmdb)] {
            guard let ask else { continue }
            layers.append((layer, await ask(key)))
            // Stop early when nothing is left to fill: a synopsis, a cast where everyone has a role, and (R371) a rating no
            // later layer can beat (the source's own), and (R372) no Wikidata layer still to ask for descriptors.
            let merged = LayeredDetails.merge(layers)
            let wikidataPending = wikidata != nil && !layers.contains { $0.0 == .wikidata }
            if let d = merged.details, d.overview != nil, !d.cast.isEmpty, d.cast.allSatisfy({ $0.role != nil }),
               merged.ratingLayer == .source, !wikidataPending { return merged }
        }
        return LayeredDetails.merge(layers)
    }
}

/// The Wikidata layer for a movie page ("item-N") or a show page ("series-N").
public struct WikidataDetailsLayer: Sendable {
    private let store: any LibraryStore
    private let client: WikidataClient
    /// R372: the Region setting, to pick that region's rating system first.
    private let region: String?

    public init(store: any LibraryStore, client: WikidataClient, region: String? = nil) {
        self.store = store
        self.client = client
        self.region = region
    }

    public func details(key: String) async -> TitleDetails? {
        switch ArtworkKey(key) {
        case .item(let id)?:
            guard let item = try? await store.item(id: id), item.kind == .movie else { return nil }
            let found: WikidataTitle?
            if let tmdb = item.tmdbID, let byID = try? await client.title(tmdbID: tmdb, kind: .movie) {
                found = byID
            } else {
                found = try? await client.title(named: item.title, year: item.year, kind: .movie)
            }
            return found.flatMap { LayeredDetails.details(from: $0, region: region) }
        case .series(let seriesID)?:
            guard let episodes = try? await store.episodes(ofSeries: seriesID), let first = episodes.first else { return nil }
            let ids = episodes.compactMap(\.tmdbID)
            let common = Dictionary(grouping: ids, by: { $0 }).max { $0.value.count < $1.value.count }?.key
            let found: WikidataTitle?
            if let common, let byID = try? await client.title(tmdbID: common, kind: .series) {
                found = byID
            } else if let name = first.seriesTitle {
                found = try? await client.title(named: name, year: nil, kind: .series)
            } else {
                found = nil
            }
            return found.flatMap { LayeredDetails.details(from: $0, region: region) }
        default:
            return nil
        }
    }
}
