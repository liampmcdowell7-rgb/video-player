import Foundation
import VideoPlayerCore
import LibraryIndex
import PlaybackLogic
import MetadataOnline

/// #26 5a: Skip Intro timings from IntroDB when the file, its sidecars and the user marks have none.
///
/// The IMDb id comes from (in this order): TMDB's external ids when a TMDB key is set, else Wikidata by the TMDB id (P4947
/// movie, P4983 series → P345), else a Wikidata title search. The library keeps no IMDb id of its own today (the NFO's
/// `<imdbid>` and the servers' provider ids are not stored), so a server-supplied id is not used yet (docs/DATA_SOURCES.md).
public struct OnlineSegmentResult: Equatable, Sendable {
    public var segments: [SkipSegment]
    /// One line for File Details.
    public var note: String

    public init(segments: [SkipSegment], note: String) {
        self.segments = segments
        self.note = note
    }
}

/// The facts of a library item the online lookups need, as plain values (tests build them directly).
public struct OnlineTitleRef: Equatable, Sendable {
    public var isEpisode: Bool
    public var title: String
    public var year: Int?
    public var seriesTitle: String?
    public var season: Int?
    public var episode: Int?
    /// The movie's TMDB id, or the series' for an episode.
    public var tmdbID: Int?

    public init(isEpisode: Bool, title: String, year: Int? = nil, seriesTitle: String? = nil, season: Int? = nil, episode: Int? = nil, tmdbID: Int? = nil) {
        self.isEpisode = isEpisode
        self.title = title
        self.year = year
        self.seriesTitle = seriesTitle
        self.season = season
        self.episode = episode
        self.tmdbID = tmdbID
    }

    public init(_ item: LibraryItem) {
        self.init(isEpisode: item.kind == .episode, title: item.title, year: item.year, seriesTitle: item.seriesTitle,
                  season: item.season, episode: item.episode, tmdbID: item.tmdbID)
    }
}

public struct IMDbIDResolver: Sendable {
    public typealias TMDBExternal = @Sendable (TitleKind, Int) async throws -> String?

    private let tmdbExternal: TMDBExternal?
    private let wikidata: WikidataClient?

    public init(tmdbExternal: TMDBExternal?, wikidata: WikidataClient?) {
        self.tmdbExternal = tmdbExternal
        self.wikidata = wikidata
    }

    /// The movie's IMDb id, or the series' for an episode. Nil when no layer knows it or every lookup failed.
    public func imdbID(for item: OnlineTitleRef) async -> String? {
        let kind: TitleKind = item.isEpisode ? .series : .movie
        if let tmdb = item.tmdbID {
            if let tmdbExternal, let id = try? await tmdbExternal(kind, tmdb), IntroDBClient.isIMDbID(id) { return id }
            if let wikidata, let found = try? await wikidata.title(tmdbID: tmdb, kind: kind), let id = found.imdbID { return id }
        }
        guard let wikidata else { return nil }
        let name = item.isEpisode ? (item.seriesTitle ?? "") : item.title
        // An episode's year is its own air year, not the series' first year, so episodes search by name only.
        let year = item.isEpisode ? nil : item.year
        return (try? await wikidata.title(named: name, year: year, kind: kind))?.imdbID
    }
}

public struct OnlineSegmentLookup: Sendable {
    public typealias Timings = @Sendable (IntroDBTitle) async throws -> IntroDBTimings?

    private let resolver: IMDbIDResolver
    private let timings: Timings

    public init(resolver: IMDbIDResolver, timings: @escaping Timings) {
        self.resolver = resolver
        self.timings = timings
    }

    public init(resolver: IMDbIDResolver, client: IntroDBClient) {
        self.init(resolver: resolver, timings: { try await client.timings(for: $0) })
    }

    public func segments(for item: LibraryItem, file: PlaybackLogic.FileIdentity) async -> OnlineSegmentResult {
        await segments(for: OnlineTitleRef(item), file: file)
    }

    public func segments(for item: OnlineTitleRef, file: PlaybackLogic.FileIdentity) async -> OnlineSegmentResult {
        guard let imdb = await resolver.imdbID(for: item) else {
            return OnlineSegmentResult(segments: [], note: "Online timings: no IMDb id known for this title; none asked")
        }
        let title: IntroDBTitle
        if item.isEpisode {
            guard let season = item.season, let episode = item.episode else {
                return OnlineSegmentResult(segments: [], note: "Online timings: season or episode number unknown; none asked")
            }
            title = .episode(seriesIMDbID: imdb, season: season, episode: episode)
        } else {
            title = .movie(imdbID: imdb)
        }
        do {
            guard let found = try await timings(title) else {
                return OnlineSegmentResult(segments: [], note: "Online timings (IntroDB): none for this title")
            }
            let segments = Self.segments(from: found, file: file)
            return OnlineSegmentResult(segments: segments, note: "Online timings (IntroDB): \(segments.count) found")
        } catch {
            return OnlineSegmentResult(segments: [], note: "Online timings (IntroDB): not reached (\(Self.reason(error))); none used")
        }
    }

    /// IntroDB gives no release duration, so these are `.onlineDatabase` candidates without a reference duration: an intro or
    /// recap may pass (SegmentLimits R208), credits are rejected by B1. A span without confidence gets 0 and is not used.
    public static func segments(from timings: IntroDBTimings, file: PlaybackLogic.FileIdentity) -> [SkipSegment] {
        let pairs: [(SegmentType, IntroDBTimings.Span?)] = [(.recap, timings.recap), (.intro, timings.intro), (.credits, timings.outro)]
        return pairs.compactMap { type, span in
            guard let span else { return nil }
            return SkipSegment(type: type, start: span.start, end: span.end, source: .onlineDatabase,
                               confidence: span.confidence ?? 0, file: file)
        }
    }

    static func reason(_ error: Error) -> String {
        switch error as? MetadataError {
        case .network?: return "offline or no answer"
        case .rateLimited?, .quotaExhausted?: return "request limit reached"
        case .server?: return "server error"
        default: return "unexpected answer"
        }
    }
}
