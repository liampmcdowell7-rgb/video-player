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

    public static func merge(_ layers: [(DetailsLayer, TitleDetails?)]) -> LayeredDetails {
        var overview: String?
        var cast: [TitleDetails.CastMember] = []
        var used: [DetailsLayer] = []
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
            if gave { used.append(layer) }
        }
        guard overview != nil || !cast.isEmpty else { return LayeredDetails(details: nil, used: []) }
        return LayeredDetails(details: TitleDetails(overview: overview, cast: cast), used: used)
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Wikidata's facts as details: names only (no synopsis, no roles, no photos: Commons images are not used).
    public static func details(from title: WikidataTitle) -> TitleDetails? {
        guard !title.cast.isEmpty else { return nil }
        let cast = title.cast.prefix(TitleDetails.castLimit).enumerated().map { index, name in
            TitleDetails.CastMember(id: 1_000_000 + index, name: name, role: nil)
        }
        return TitleDetails(overview: nil, cast: Array(cast))
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
            // Stop early when nothing is left to fill: a synopsis and a cast where everyone has a role.
            let merged = LayeredDetails.merge(layers)
            if let d = merged.details, d.overview != nil, !d.cast.isEmpty, d.cast.allSatisfy({ $0.role != nil }) { return merged }
        }
        return LayeredDetails.merge(layers)
    }
}

/// The Wikidata layer for a movie page ("item-N") or a show page ("series-N").
public struct WikidataDetailsLayer: Sendable {
    private let store: any LibraryStore
    private let client: WikidataClient

    public init(store: any LibraryStore, client: WikidataClient) {
        self.store = store
        self.client = client
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
            return found.flatMap(LayeredDetails.details(from:))
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
            return found.flatMap(LayeredDetails.details(from:))
        default:
            return nil
        }
    }
}
