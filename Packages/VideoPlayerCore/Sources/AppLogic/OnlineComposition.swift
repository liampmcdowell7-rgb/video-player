import Foundation
import LibraryIndex
import PlaybackLogic
import MetadataOnline

// #29 (PROVISIONAL, OPEN_QUESTIONS R226): the closures the app hands to the layered details service, the IMDb id resolver and
// the segment provider are built here, each as one typed `@Sendable` constant, so the Linux type-checker and the package
// tests cover them. The App side calls these in one line each. Before #29 the app built them inline (a closure returned from
// `Optional.map`, a nested closure using `$0`, a ternary between a closure and nil); Xcode's type-checker gave up on that
// expression in App/Support/OnlineServices.swift ("failed to produce diagnostic for expression").

/// Anything that gives a title's synopsis and cast for an artwork key ("item-N", "series-N").
public protocol TitleDetailsSource: Sendable {
    func details(key: String) async -> TitleDetails?
}

extension WikidataDetailsLayer: TitleDetailsSource {}

extension LayeredDetailsService {
    /// The layer closure for one source; nil when the source is off.
    public static func layer(_ source: (any TitleDetailsSource)?) -> Layer? {
        guard let source else { return nil }
        let layer: Layer = { @Sendable (key: String) async -> TitleDetails? in
            await source.details(key: key)
        }
        return layer
    }

    /// The app's service (#26 item 6, R210): no source layer yet, Wikidata while Free Data Sources is on (`wikidata` not nil),
    /// then TMDB when the user's key is set (`tmdb` not nil).
    public static func online(store: any LibraryStore, wikidata: WikidataClient?,
                              tmdb: (any TitleDetailsSource)?) -> LayeredDetailsService {
        var wikidataSource: (any TitleDetailsSource)? = nil
        if let wikidata {
            wikidataSource = WikidataDetailsLayer(store: store, client: wikidata)
        }
        let wikidataLayer: Layer? = layer(wikidataSource)
        let tmdbLayer: Layer? = layer(tmdb)
        return LayeredDetailsService(source: nil, wikidata: wikidataLayer, tmdb: tmdbLayer)
    }
}

extension IMDbIDResolver {
    /// TMDB's external ids as the resolver's first layer; nil without a TMDB client (no key).
    public static func tmdbExternal(_ client: TMDBClient?) -> TMDBExternal? {
        guard let client else { return nil }
        let external: TMDBExternal = { @Sendable (kind: TitleKind, id: Int) async throws -> String? in
            let ids: ProviderIDs = try await client.externalIDs(kind: kind, id: id)
            return ids.imdb
        }
        return external
    }
}

extension SegmentProvider {
    /// IntroDB timings for the provider; nil when Free Data Sources is off (no lookup).
    public static func onlineTimings(_ lookup: OnlineSegmentLookup?) -> OnlineTimings? {
        guard let lookup else { return nil }
        let timings: OnlineTimings = { @Sendable (item: LibraryItem, file: PlaybackLogic.FileIdentity) async -> OnlineSegmentResult in
            await lookup.segments(for: item, file: file)
        }
        return timings
    }
}
