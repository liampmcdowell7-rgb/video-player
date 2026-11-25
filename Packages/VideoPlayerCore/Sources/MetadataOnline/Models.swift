import Foundation

// Metadata model types shown by the library screens ("Data to show" in the original spec).
// All plain values: Codable (for the cache), Sendable, Equatable.

/// A calendar day without a time zone ("1999-03-31"). TMDB sends "" for unknown dates.
public struct CalendarDate: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "yyyy-MM-dd", "yyyy-MM" or "yyyy". Returns nil for "" or anything else.
    public init?(_ text: String?) {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), let y = Int(parts[0]), (1800...2200).contains(y) else { return nil }
        let m = parts.count > 1 ? Int(parts[1]) : 1
        let d = parts.count > 2 ? Int(parts[2]) : 1
        guard let month = m, let day = d, (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: y, month: month, day: day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (a: CalendarDate, b: CalendarDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// What a library item is for metadata purposes: a movie, or a series (episodes belong to a series).
public enum TitleKind: String, Codable, Hashable, Sendable {
    case movie, series
}

public struct ProviderIDs: Codable, Hashable, Sendable {
    public var tmdb: Int?
    public var imdb: String?
    public var tvdb: Int?

    public init(tmdb: Int? = nil, imdb: String? = nil, tvdb: Int? = nil) {
        self.tmdb = tmdb
        self.imdb = imdb
        self.tvdb = tvdb
    }
}

public struct ImageRef: Codable, Hashable, Sendable {
    /// TMDB file path such as "/abc.jpg" (joined with the configuration's base URL and a size).
    public var path: String
    public var width: Int?
    public var height: Int?
    /// ISO 639-1 language of any text in the image, nil for textless images.
    public var language: String?
    public var voteAverage: Double?

    public init(path: String, width: Int? = nil, height: Int? = nil, language: String? = nil, voteAverage: Double? = nil) {
        self.path = path
        self.width = width
        self.height = height
        self.language = language
        self.voteAverage = voteAverage
    }
}

public struct ImageSet: Codable, Hashable, Sendable {
    public var posters: [ImageRef]
    public var backdrops: [ImageRef]
    public var logos: [ImageRef]

    public init(posters: [ImageRef] = [], backdrops: [ImageRef] = [], logos: [ImageRef] = []) {
        self.posters = posters
        self.backdrops = backdrops
        self.logos = logos
    }

    public static let empty = ImageSet()

    /// Best image for a language: that language first, then textless, then the rest; ties by rating.
    public static func best(_ images: [ImageRef], language: String?) -> ImageRef? {
        let lang = language.map { String($0.prefix(2)).lowercased() }
        func rank(_ i: ImageRef) -> Int {
            if let lang, i.language?.lowercased() == lang { return 0 }
            if i.language == nil { return 1 }
            if i.language?.lowercased() == "en" { return 2 }
            return 3
        }
        return images.enumerated().min { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            if ra != rb { return ra < rb }
            let (va, vb) = (a.element.voteAverage ?? 0, b.element.voteAverage ?? 0)
            if va != vb { return va > vb }
            return a.offset < b.offset
        }?.element
    }

    public func bestPoster(language: String?) -> ImageRef? { Self.best(posters, language: language) }
    public func bestBackdrop(language: String?) -> ImageRef? { Self.best(backdrops, language: language) }
    public func bestLogo(language: String?) -> ImageRef? { Self.best(logos, language: language) }
}

public struct Person: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    /// Role played (cast) or nil.
    public var character: String?
    /// Job such as "Director" (crew) or nil.
    public var job: String?
    public var department: String?
    public var profilePath: String?
    public var order: Int?

    public init(id: Int, name: String, character: String? = nil, job: String? = nil, department: String? = nil, profilePath: String? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.character = character
        self.job = job
        self.department = department
        self.profilePath = profilePath
        self.order = order
    }
}

public struct Credits: Codable, Hashable, Sendable {
    public var cast: [Person]
    public var crew: [Person]
    public init(cast: [Person] = [], crew: [Person] = []) {
        self.cast = cast
        self.crew = crew
    }
    public static let empty = Credits()

    public var directors: [Person] { crew.filter { $0.job == "Director" } }
}

/// A trailer or clip, as a link only (nothing is played inside the app from here).
public struct VideoLink: Codable, Hashable, Sendable {
    public var site: String
    public var key: String
    public var type: String
    public var name: String
    public var official: Bool

    public init(site: String, key: String, type: String, name: String, official: Bool) {
        self.site = site
        self.key = key
        self.type = type
        self.name = name
        self.official = official
    }

    public var url: URL? {
        switch site.lowercased() {
        case "youtube": return URL(string: "https://www.youtube.com/watch?v=\(key)")
        case "vimeo": return URL(string: "https://vimeo.com/\(key)")
        default: return nil
        }
    }
}

public struct CollectionRef: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var posterPath: String?
    public var backdropPath: String?
    public init(id: Int, name: String, posterPath: String? = nil, backdropPath: String? = nil) {
        self.id = id
        self.name = name
        self.posterPath = posterPath
        self.backdropPath = backdropPath
    }
}

public struct CollectionPart: Codable, Hashable, Sendable {
    public var tmdbID: Int
    public var title: String
    public var releaseDate: CalendarDate?
    public var posterPath: String?
    public init(tmdbID: Int, title: String, releaseDate: CalendarDate? = nil, posterPath: String? = nil) {
        self.tmdbID = tmdbID
        self.title = title
        self.releaseDate = releaseDate
        self.posterPath = posterPath
    }
}

/// A film series. Parts are listed so the library can mark the ones the user owns;
/// the parts the user does not own are never shown from here (Discover is separate).
public struct CollectionMetadata: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var overview: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var parts: [CollectionPart]
    public init(id: Int, name: String, overview: String? = nil, posterPath: String? = nil, backdropPath: String? = nil, parts: [CollectionPart] = []) {
        self.id = id
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.parts = parts
    }
}

// MARK: Ratings

public enum RatingSource: String, Codable, Hashable, Sendable, CaseIterable {
    case tmdb, imdb, rottenTomatoes, metacritic

    /// The label shown next to the score.
    public var label: String {
        switch self {
        case .tmdb: return "TMDB"
        case .imdb: return "IMDb"
        case .rottenTomatoes: return "Rotten Tomatoes"
        case .metacritic: return "Metacritic"
        }
    }
}

public struct Rating: Codable, Hashable, Sendable {
    public var source: RatingSource
    /// 0 to 100 on one scale, for sorting and filtering.
    public var percent: Double
    /// As shown: "8.7/10", "87%", "73/100".
    public var display: String
    public var votes: Int?

    public init(source: RatingSource, percent: Double, display: String, votes: Int? = nil) {
        self.source = source
        self.percent = percent
        self.display = display
        self.votes = votes
    }

    public var label: String { source.label }
}

public struct RatingSet: Codable, Hashable, Sendable {
    public var tmdb: Rating?
    public var imdb: Rating?
    public var rottenTomatoes: Rating?
    public var metacritic: Rating?

    public init(tmdb: Rating? = nil, imdb: Rating? = nil, rottenTomatoes: Rating? = nil, metacritic: Rating? = nil) {
        self.tmdb = tmdb
        self.imdb = imdb
        self.rottenTomatoes = rottenTomatoes
        self.metacritic = metacritic
    }

    public static let empty = RatingSet()

    /// Only the scores that exist, in a fixed order. A missing score is simply absent (hidden cleanly).
    public var visible: [Rating] { [tmdb, imdb, rottenTomatoes, metacritic].compactMap { $0 } }

    public func merging(_ other: RatingSet) -> RatingSet {
        RatingSet(
            tmdb: other.tmdb ?? tmdb,
            imdb: other.imdb ?? imdb,
            rottenTomatoes: other.rottenTomatoes ?? rottenTomatoes,
            metacritic: other.metacritic ?? metacritic
        )
    }
}

// MARK: Titles

public struct MovieMetadata: Codable, Hashable, Sendable {
    public var ids: ProviderIDs
    public var title: String
    public var originalTitle: String?
    public var originalLanguage: String?
    public var tagline: String?
    public var overview: String?
    public var releaseDate: CalendarDate?
    public var runtimeMinutes: Int?
    public var genres: [String]
    /// Content rating for the requested region ("PG-13"), nil if none.
    public var certification: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var images: ImageSet
    public var credits: Credits
    public var videos: [VideoLink]
    public var collection: CollectionRef?
    public var ratings: RatingSet
    /// The language the text was requested in.
    public var language: String?
    /// R471 item 5: the production countries (ISO 3166-1 codes, "US"), TMDB's `production_countries`, else its
    /// `origin_country`. Optional so details cached before this field decode unchanged.
    public var countries: [String]?

    public init(
        ids: ProviderIDs, title: String, originalTitle: String? = nil, originalLanguage: String? = nil,
        tagline: String? = nil, overview: String? = nil, releaseDate: CalendarDate? = nil, runtimeMinutes: Int? = nil,
        genres: [String] = [], certification: String? = nil, posterPath: String? = nil, backdropPath: String? = nil,
        images: ImageSet = .empty, credits: Credits = .empty, videos: [VideoLink] = [],
        collection: CollectionRef? = nil, ratings: RatingSet = .empty, language: String? = nil, countries: [String]? = nil
    ) {
        self.countries = countries
        self.ids = ids
        self.title = title
        self.originalTitle = originalTitle
        self.originalLanguage = originalLanguage
        self.tagline = tagline
        self.overview = overview
        self.releaseDate = releaseDate
        self.runtimeMinutes = runtimeMinutes
        self.genres = genres
        self.certification = certification
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.images = images
        self.credits = credits
        self.videos = videos
        self.collection = collection
        self.ratings = ratings
        self.language = language
    }

    public var year: Int? { releaseDate?.year }
}

public struct SeasonSummary: Codable, Hashable, Sendable {
    public var seasonNumber: Int
    public var name: String?
    public var episodeCount: Int
    public var airDate: CalendarDate?
    public var posterPath: String?
    public init(seasonNumber: Int, name: String? = nil, episodeCount: Int, airDate: CalendarDate? = nil, posterPath: String? = nil) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.episodeCount = episodeCount
        self.airDate = airDate
        self.posterPath = posterPath
    }
}

public struct SeriesMetadata: Codable, Hashable, Sendable {
    public var ids: ProviderIDs
    public var name: String
    public var originalName: String?
    public var originalLanguage: String?
    public var tagline: String?
    public var overview: String?
    public var firstAirDate: CalendarDate?
    public var lastAirDate: CalendarDate?
    public var status: String?
    public var genres: [String]
    public var networks: [String]
    public var certification: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var seasons: [SeasonSummary]
    public var images: ImageSet
    public var credits: Credits
    public var videos: [VideoLink]
    public var ratings: RatingSet
    public var language: String?
    /// R471 item 5: the show's countries of origin (ISO 3166-1 codes), TMDB's `origin_country`. Optional (older caches).
    public var countries: [String]?

    public init(
        ids: ProviderIDs, name: String, originalName: String? = nil, originalLanguage: String? = nil,
        tagline: String? = nil, overview: String? = nil, firstAirDate: CalendarDate? = nil, lastAirDate: CalendarDate? = nil,
        status: String? = nil, genres: [String] = [], networks: [String] = [], certification: String? = nil,
        posterPath: String? = nil, backdropPath: String? = nil, seasons: [SeasonSummary] = [],
        images: ImageSet = .empty, credits: Credits = .empty, videos: [VideoLink] = [],
        ratings: RatingSet = .empty, language: String? = nil, countries: [String]? = nil
    ) {
        self.countries = countries
        self.ids = ids
        self.name = name
        self.originalName = originalName
        self.originalLanguage = originalLanguage
        self.tagline = tagline
        self.overview = overview
        self.firstAirDate = firstAirDate
        self.lastAirDate = lastAirDate
        self.status = status
        self.genres = genres
        self.networks = networks
        self.certification = certification
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.seasons = seasons
        self.images = images
        self.credits = credits
        self.videos = videos
        self.ratings = ratings
        self.language = language
    }

    public var year: Int? { firstAirDate?.year }
    public var numberOfSeasons: Int { seasons.filter { $0.seasonNumber > 0 }.count }
}

public struct EpisodeMetadata: Codable, Hashable, Sendable {
    public var tmdbID: Int?
    public var seriesID: Int
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var name: String
    public var overview: String?
    public var airDate: CalendarDate?
    public var runtimeMinutes: Int?
    public var stillPath: String?
    public var voteAverage: Double?
    public var guestStars: [Person]
    public var crew: [Person]

    public init(
        tmdbID: Int? = nil, seriesID: Int, seasonNumber: Int, episodeNumber: Int, name: String, overview: String? = nil,
        airDate: CalendarDate? = nil, runtimeMinutes: Int? = nil, stillPath: String? = nil, voteAverage: Double? = nil,
        guestStars: [Person] = [], crew: [Person] = []
    ) {
        self.tmdbID = tmdbID
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.runtimeMinutes = runtimeMinutes
        self.stillPath = stillPath
        self.voteAverage = voteAverage
        self.guestStars = guestStars
        self.crew = crew
    }
}

public struct SeasonMetadata: Codable, Hashable, Sendable {
    public var seriesID: Int
    public var seasonNumber: Int
    public var name: String?
    public var overview: String?
    public var airDate: CalendarDate?
    public var posterPath: String?
    public var episodes: [EpisodeMetadata]

    public init(seriesID: Int, seasonNumber: Int, name: String? = nil, overview: String? = nil, airDate: CalendarDate? = nil, posterPath: String? = nil, episodes: [EpisodeMetadata] = []) {
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.posterPath = posterPath
        self.episodes = episodes
    }
}

// MARK: Errors and attribution

public enum MetadataError: Error, Equatable, Sendable {
    case invalidAPIKey
    case notFound
    case rateLimited(retryAfter: Double?)
    /// A daily or similar quota is used up. Retrying today will not help.
    case quotaExhausted
    case server(Int)
    case network(String)
    case decoding(String)
    case unexpectedStatus(Int)
    case missingCredentials
    /// The item is not in the user's library (library-facing API only).
    case notInLibrary
    case scopeNotAllowed(String)
}

/// The TMDB and JustWatch notices, kept equal to the app's own copy in App/Support/Attribution.swift (the app shows that copy; this
/// one is not shown anywhere). Wording read from the TMDB API terms, section 3, and its watch-provider page on
/// 2026-11-17 (docs/ARTWORK_DISCOVER.md section 5a). `AttributionNoticeTests` (AppLogicTests) checks the two copies match.
public enum MetadataAttribution {
    public static let tmdbNotice = "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB."
    /// Required wherever watch-provider data is shown (Discover).
    public static let justWatchNotice = "Where-to-watch data is provided by JustWatch."
}
