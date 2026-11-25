import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal
import MetadataOnline

/// Online artwork through the metadata matcher: a library item with a stored online id uses it; one without is matched from its
/// file name (saved Fix Match choice first, then the automatic matcher with the 0.8 threshold). An accepted match is written back
/// as the item's id so the next look needs no search. A match that "needs review" gives no picture: nothing is guessed.
/// Only runs when the user entered their own key (the app builds this provider only then).
public struct TMDBArtworkProvider: OnlineArtworkProviding {
    public let client: TMDBClient
    public let matcher: FixMatchService
    public let store: any LibraryStore

    public init(client: TMDBClient, matcher: FixMatchService, store: any LibraryStore) {
        self.client = client
        self.matcher = matcher
        self.store = store
    }

    /// The identity under which Fix Match choices are saved for a file (docs/METADATA.md: keyed by path, so a rename loses it).
    public static func identity(of file: StoredFile) -> FileIdentity { FileIdentity(path: file.sourceID + file.path, size: file.size) }

    public static func matchInput(for item: LibraryItem, file: StoredFile) -> MatchInput {
        let folders = Array(file.parentPath.split(separator: "/").reversed()).map(String.init)
        let parsed = FilenameParser.parse(fileName: file.name, folders: folders)
        return MatchInput(parsed: parsed, folderNames: folders, fileDurationSeconds: item.runtime)
    }

    public func posterURL(forItem item: LibraryItem, file: StoredFile?) async -> URL? {
        let kind: TitleKind = item.kind == .movie ? .movie : .series
        var id = item.tmdbID
        if id == nil, let file {
            let input = Self.matchInput(for: item, file: file)
            if case .matched(let match)? = try? await matcher.resolve(file: Self.identity(of: file), input: input) {
                id = match.tmdbID
                try? await store.setMetadata(itemID: item.id, ItemMetadata(tmdbID: match.tmdbID))
            }
        }
        guard let id else { return nil }
        return await poster(kind: kind, id: id)
    }

    public func posterURL(forSeriesID tmdbID: Int) async -> URL? { await poster(kind: .series, id: tmdbID) }

    public func imageURL(path: String) async -> URL? {
        await client.imageURLBuilder().url(path: path, kind: .poster)
    }

    /// #15 Part 9: the picture sets come with the title details (`append_to_response=images`), the same cached request as the
    /// poster, so asking for logos sends nothing new. Only an item that is already matched has an id.
    public func images(forItem item: LibraryItem) async -> ImageSet? {
        guard let id = item.tmdbID else { return nil }
        switch item.kind {
        case .movie: return (try? await client.movie(id: id))?.images
        case .episode: return (try? await client.series(id: id))?.images
        }
    }

    public func images(forSeriesID tmdbID: Int) async -> ImageSet? { (try? await client.series(id: tmdbID))?.images }

    public func logoURL(path: String) async -> URL? { await client.imageURLBuilder().url(path: path, kind: .logo) }

    public func backdropURL(path: String) async -> URL? { await client.imageURLBuilder().url(path: path, kind: .backdrop) }

    /// R455: gallery thumbnails use the small size of the kind (`ArtworkGalleryKind.thumbnailSize`).
    public func thumbnailURL(path: String, kind: ArtworkGalleryKind) async -> URL? {
        let imageKind: ImageKind
        switch kind {
        case .poster, .seasonPoster: imageKind = .poster
        case .background: imageKind = .backdrop
        case .logo: imageKind = .logo
        case .episodeStill: imageKind = .still
        }
        return await client.imageURLBuilder().url(path: path, kind: imageKind, size: kind.thumbnailSize)
    }

    /// #15 6.2: overview and cast come with the same cached title details (`append_to_response=credits`).
    public func details(forItem item: LibraryItem) async -> TitleDetails? {
        guard item.kind == .movie, let id = item.tmdbID, let movie = try? await client.movie(id: id) else { return nil }
        var details = TitleDetails(overview: movie.overview, people: movie.credits.cast)
        // R371: TMDB's certification for the Region setting (the client's region), the rating's second layer.
        details.contentRating = ContentRating.clean(movie.certification)
        // R453: the full release date (TMDB's own), the genres and the runtime, for the typed metadata line.
        details.releaseDate = movie.releaseDate.map { PartialDate(year: $0.year, month: $0.month, day: $0.day) }
        details.genres = movie.genres
        details.runtimeMinutes = movie.runtimeMinutes
        // R471 item 5: Director, Region of Origin and Original Audio, from the same cached details.
        details.addCatalogueFacts(crew: movie.credits.crew, countries: movie.countries, originalLanguage: movie.originalLanguage)
        return details
    }

    /// #22 B: the same for a show page, from the cached series details (`append_to_response=credits`, already requested for
    /// the show's poster and pictures).
    public func details(forSeriesID tmdbID: Int) async -> TitleDetails? {
        guard let series = try? await client.series(id: tmdbID) else { return nil }
        var details = TitleDetails(overview: series.overview, people: series.credits.cast)
        details.contentRating = ContentRating.clean(series.certification)
        // R453: the first air date and the genres of the show.
        details.releaseDate = series.firstAirDate.map { PartialDate(year: $0.year, month: $0.month, day: $0.day) }
        details.genres = series.genres
        details.addCatalogueFacts(crew: series.credits.crew, countries: series.countries, originalLanguage: series.originalLanguage)
        return details
    }

    private func poster(kind: TitleKind, id: Int) async -> URL? {
        let path: String?
        switch kind {
        case .movie: path = (try? await client.movie(id: id))?.posterPath
        case .series: path = (try? await client.series(id: id))?.posterPath
        }
        guard let path else { return nil }
        return await client.imageURLBuilder().url(path: path, kind: .poster)
    }
}

/// Fix Match search and saved choices over the matcher, for the Fix Match screen.
public struct TMDBMatchSearcher: MatchSearching {
    public let client: TMDBClient
    public init(client: TMDBClient) { self.client = client }

    public func search(title: String, year: Int?, kind: ItemKind) async throws -> [MatchCandidate] {
        let hits = kind == .movie ? try await client.searchMovies(query: title, year: year) : try await client.searchSeries(query: title, firstAirYear: year)
        return hits.prefix(10).map { MatchCandidate(id: $0.tmdbID, title: $0.title, year: $0.year, overview: $0.overview) }
    }
}

/// Saves a Fix Match choice permanently in the match store so the automatic matcher never overrides it (R37).
public struct StoredMatchRecorder: MatchChoiceRecording {
    public let service: FixMatchService
    public let store: any LibraryStore

    public init(service: FixMatchService, store: any LibraryStore) {
        self.service = service
        self.store = store
    }

    public func record(itemID: Int64, candidate: MatchCandidate, scope: FixMatchScope) async throws {
        guard let item = try await store.item(id: itemID), let file = try await store.versions(of: itemID).first else { return }
        let hit = SearchHit(tmdbID: candidate.id, kind: item.kind == .movie ? .movie : .series, title: candidate.title, year: candidate.year, overview: candidate.overview)
        let input = TMDBArtworkProvider.matchInput(for: item, file: file)
        let matchScope: MatchScope
        var identity = TMDBArtworkProvider.identity(of: file)
        switch scope {
        case .thisFile: matchScope = .file
        case .thisSeason: matchScope = .season(input.parsed.season ?? item.season ?? 1)
        case .wholeShow:
            matchScope = .folder
            // The folder scope covers a folder and everything below it: use the show folder (above the season folder), not the season's.
            let last = String(file.parentPath.split(separator: "/").last ?? "")
            if SidecarImageFinder.seasonNumber(ofFolder: last) != nil {
                identity = FileIdentity(path: file.sourceID + ArtworkEngine.parent(of: file.parentPath) + "/" + file.name, size: file.size)
            }
        }
        _ = try await service.choose(hit, for: identity, input: input, scope: matchScope)
    }
}
