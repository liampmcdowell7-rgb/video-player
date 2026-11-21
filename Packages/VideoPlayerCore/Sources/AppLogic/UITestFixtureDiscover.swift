#if DEBUG
import Foundation
import MetadataOnline

/// R342: an invented Discover for the screenshot job, so the Discover card, its context menu and the title's page can be
/// photographed without a key or network. Used only with `-UITestFakeDiscover` in a UI-test mode (Debug builds only; this
/// whole file is inside `#if DEBUG`). Invented titles only, no real title, person or picture.
public enum UITestFixtureDiscover {
    /// The seed the suggestions are "similar to": Sample Movie 1 under an invented online id.
    public static let seed = DiscoverSeed(kind: .movie, tmdbID: 900_001, title: "Sample Movie 1")

    /// Three invented suggestions, no pictures (the card shows the system symbol), in this order (popularity).
    public static let suggestions: [SearchHit] = [
        SearchHit(tmdbID: 900_101, kind: .movie, title: "Sample Suggestion 1", year: 2020, popularity: 3),
        SearchHit(tmdbID: 900_102, kind: .movie, title: "Sample Suggestion 2", year: 2022, popularity: 2),
        SearchHit(tmdbID: 900_103, kind: .series, title: "Sample Suggested Show", year: 2019, popularity: 1),
    ]

    public struct Library: DiscoverLibraryProviding {
        public init() {}
        public func discoverLibrary() async throws -> DiscoverLibrary {
            // One owned movie (the seed) and no show, so Discover asks only for that movie (no collection) and "similar".
            DiscoverLibrary(ownedMovieIDs: [seed.tmdbID], seeds: [seed])
        }
    }

    /// Answers the seed movie (in no collection) and "similar" with the invented suggestions; nothing else is asked.
    public struct Source: DiscoverDataSource {
        public struct NotInFixture: Error {}
        public init() {}
        public func series(id: Int) async throws -> SeriesMetadata { throw NotInFixture() }
        public func season(seriesID: Int, number: Int) async throws -> SeasonMetadata { throw NotInFixture() }
        public func movie(id: Int) async throws -> MovieMetadata {
            guard id == seed.tmdbID else { throw NotInFixture() }
            return MovieMetadata(ids: ProviderIDs(tmdb: id), title: seed.title)
        }
        public func collection(id: Int) async throws -> CollectionMetadata { throw NotInFixture() }
        public func similar(kind: TitleKind, id: Int) async throws -> [SearchHit] { id == seed.tmdbID ? suggestions : [] }
        public func watchProviders(kind: TitleKind, id: Int) async throws -> [String: WatchAvailability] { [:] }
    }
}
#endif
