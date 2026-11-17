import Foundation

// Maps TMDB v3 JSON to the model types. Every field is optional on read.
//
// The response shapes below are written from the public TMDB v3 documentation as remembered.
// They have NOT been checked against the real service (no provider is contacted by this project's
// tests); see docs/METADATA.md "Unverified".

/// One search result or looked-up title, before any details are fetched.
public struct SearchHit: Codable, Hashable, Sendable {
    public var tmdbID: Int
    public var kind: TitleKind
    public var title: String
    public var originalTitle: String?
    public var year: Int?
    public var overview: String?
    public var posterPath: String?
    public var popularity: Double?
    public var originalLanguage: String?

    public init(tmdbID: Int, kind: TitleKind, title: String, originalTitle: String? = nil, year: Int? = nil, overview: String? = nil, posterPath: String? = nil, popularity: Double? = nil, originalLanguage: String? = nil) {
        self.tmdbID = tmdbID
        self.kind = kind
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.overview = overview
        self.posterPath = posterPath
        self.popularity = popularity
        self.originalLanguage = originalLanguage
    }
}

/// One entry of a title's translation list.
public struct TitleTranslation: Codable, Hashable, Sendable {
    public var language: String
    public var region: String?
    public var title: String?
    public var overview: String?
    public var tagline: String?
}

enum TMDBMapper {
    static func hit(_ j: JSON, kind: TitleKind) -> SearchHit? {
        guard let id = j["id"].int else { return nil }
        let titleKey = kind == .movie ? "title" : "name"
        let originalKey = kind == .movie ? "original_title" : "original_name"
        let dateKey = kind == .movie ? "release_date" : "first_air_date"
        guard let title = j[titleKey].text ?? j[originalKey].text else { return nil }
        return SearchHit(
            tmdbID: id, kind: kind, title: title, originalTitle: j[originalKey].text,
            year: CalendarDate(j[dateKey].text)?.year, overview: j["overview"].text,
            posterPath: j["poster_path"].text, popularity: j["popularity"].double,
            originalLanguage: j["original_language"].text
        )
    }

    static func hits(_ j: JSON, kind: TitleKind) -> [SearchHit] {
        j["results"].array.compactMap { hit($0, kind: kind) }
    }

    static func imageRefs(_ j: JSON) -> [ImageRef] {
        j.array.compactMap { i in
            guard let path = i["file_path"].text else { return nil }
            return ImageRef(path: path, width: i["width"].int, height: i["height"].int, language: i["iso_639_1"].text, voteAverage: i["vote_average"].double)
        }
    }

    static func images(_ j: JSON) -> ImageSet {
        ImageSet(posters: imageRefs(j["posters"]), backdrops: imageRefs(j["backdrops"]), logos: imageRefs(j["logos"]))
    }

    static func person(_ j: JSON) -> Person? {
        guard let id = j["id"].int, let name = j["name"].text else { return nil }
        return Person(id: id, name: name, character: j["character"].text, job: j["job"].text, department: j["department"].text, profilePath: j["profile_path"].text, order: j["order"].int)
    }

    static func credits(_ j: JSON) -> Credits {
        let cast = j["cast"].array.compactMap(person).sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
        return Credits(cast: Array(cast.prefix(60)), crew: j["crew"].array.compactMap(person))
    }

    static func videos(_ j: JSON) -> [VideoLink] {
        j["results"].array.compactMap { v in
            guard let key = v["key"].text, let site = v["site"].text else { return nil }
            return VideoLink(site: site, key: key, type: v["type"].text ?? "", name: v["name"].text ?? "", official: v["official"].bool ?? false)
        }
    }

    static func genres(_ j: JSON) -> [String] { j["genres"].array.compactMap { $0["name"].text } }

    static func tmdbRating(_ j: JSON) -> Rating? {
        guard let average = j["vote_average"].double, let votes = j["vote_count"].int, votes > 0, average > 0 else { return nil }
        return Rating(source: .tmdb, percent: average * 10, display: String(format: "%.1f/10", average), votes: votes)
    }

    /// Certification for a region from a movie's `release_dates` block. Prefers theatrical (type 3), then any.
    static func movieCertification(_ j: JSON, region: String) -> String? {
        guard let entry = j["results"].array.first(where: { $0["iso_3166_1"].text == region }) else { return nil }
        let releases = entry["release_dates"].array
        let withCert = releases.filter { $0["certification"].text != nil }
        return (withCert.first { $0["type"].int == 3 } ?? withCert.first)?["certification"].text
    }

    static func tvCertification(_ j: JSON, region: String) -> String? {
        j["results"].array.first { $0["iso_3166_1"].text == region }?["rating"].text
    }

    static func movie(_ j: JSON, language: String?, region: String) -> MovieMetadata? {
        guard let id = j["id"].int, let title = j["title"].text ?? j["original_title"].text else { return nil }
        let coll = j["belongs_to_collection"]
        var collection: CollectionRef?
        if let cid = coll["id"].int, let cname = coll["name"].text {
            collection = CollectionRef(id: cid, name: cname, posterPath: coll["poster_path"].text, backdropPath: coll["backdrop_path"].text)
        }
        let imdb = j["imdb_id"].text ?? j["external_ids"]["imdb_id"].text
        var ratings = RatingSet.empty
        ratings.tmdb = tmdbRating(j)
        return MovieMetadata(
            ids: ProviderIDs(tmdb: id, imdb: imdb, tvdb: nil),
            title: title, originalTitle: j["original_title"].text, originalLanguage: j["original_language"].text,
            tagline: j["tagline"].text, overview: j["overview"].text,
            releaseDate: CalendarDate(j["release_date"].text),
            runtimeMinutes: (j["runtime"].int).flatMap { $0 > 0 ? $0 : nil },
            genres: genres(j), certification: movieCertification(j["release_dates"], region: region),
            posterPath: j["poster_path"].text, backdropPath: j["backdrop_path"].text,
            images: images(j["images"]), credits: credits(j["credits"]), videos: videos(j["videos"]),
            collection: collection, ratings: ratings, language: language
        )
    }

    static func series(_ j: JSON, language: String?, region: String) -> SeriesMetadata? {
        guard let id = j["id"].int, let name = j["name"].text ?? j["original_name"].text else { return nil }
        let seasons: [SeasonSummary] = j["seasons"].array.compactMap { s in
            guard let n = s["season_number"].int else { return nil }
            return SeasonSummary(seasonNumber: n, name: s["name"].text, episodeCount: s["episode_count"].int ?? 0, airDate: CalendarDate(s["air_date"].text), posterPath: s["poster_path"].text)
        }.sorted { $0.seasonNumber < $1.seasonNumber }
        var ratings = RatingSet.empty
        ratings.tmdb = tmdbRating(j)
        return SeriesMetadata(
            ids: ProviderIDs(tmdb: id, imdb: j["external_ids"]["imdb_id"].text, tvdb: j["external_ids"]["tvdb_id"].int),
            name: name, originalName: j["original_name"].text, originalLanguage: j["original_language"].text,
            tagline: j["tagline"].text, overview: j["overview"].text,
            firstAirDate: CalendarDate(j["first_air_date"].text), lastAirDate: CalendarDate(j["last_air_date"].text),
            status: j["status"].text, genres: genres(j), networks: j["networks"].array.compactMap { $0["name"].text },
            certification: tvCertification(j["content_ratings"], region: region),
            posterPath: j["poster_path"].text, backdropPath: j["backdrop_path"].text, seasons: seasons,
            images: images(j["images"]), credits: credits(j["credits"]), videos: videos(j["videos"]),
            ratings: ratings, language: language
        )
    }

    static func episode(_ j: JSON, seriesID: Int, fallbackSeason: Int? = nil) -> EpisodeMetadata? {
        guard let number = j["episode_number"].int else { return nil }
        let season = j["season_number"].int ?? fallbackSeason ?? 0
        return EpisodeMetadata(
            tmdbID: j["id"].int, seriesID: seriesID, seasonNumber: season, episodeNumber: number,
            name: j["name"].text ?? "Episode \(number)", overview: j["overview"].text,
            airDate: CalendarDate(j["air_date"].text),
            runtimeMinutes: (j["runtime"].int).flatMap { $0 > 0 ? $0 : nil },
            stillPath: j["still_path"].text, voteAverage: j["vote_average"].double,
            guestStars: j["guest_stars"].array.compactMap(person), crew: j["crew"].array.compactMap(person)
        )
    }

    static func season(_ j: JSON, seriesID: Int, number: Int) -> SeasonMetadata {
        let n = j["season_number"].int ?? number
        let episodes = j["episodes"].array.compactMap { episode($0, seriesID: seriesID, fallbackSeason: n) }.sorted { $0.episodeNumber < $1.episodeNumber }
        return SeasonMetadata(seriesID: seriesID, seasonNumber: n, name: j["name"].text, overview: j["overview"].text, airDate: CalendarDate(j["air_date"].text), posterPath: j["poster_path"].text, episodes: episodes)
    }

    static func collection(_ j: JSON) -> CollectionMetadata? {
        guard let id = j["id"].int, let name = j["name"].text else { return nil }
        let parts = j["parts"].array.compactMap { p -> CollectionPart? in
            guard let pid = p["id"].int, let title = p["title"].text else { return nil }
            return CollectionPart(tmdbID: pid, title: title, releaseDate: CalendarDate(p["release_date"].text), posterPath: p["poster_path"].text)
        }.sorted { ($0.releaseDate ?? CalendarDate(year: 9999, month: 1, day: 1)) < ($1.releaseDate ?? CalendarDate(year: 9999, month: 1, day: 1)) }
        return CollectionMetadata(id: id, name: name, overview: j["overview"].text, posterPath: j["poster_path"].text, backdropPath: j["backdrop_path"].text, parts: parts)
    }

    static func imageConfiguration(_ j: JSON) -> ImageConfiguration? {
        let images = j["images"]
        guard let base = images["secure_base_url"].text else { return nil }
        func sizes(_ key: String, _ fallback: [String]) -> [String] {
            let s = images[key].array.compactMap { $0.text }
            return s.isEmpty ? fallback : s
        }
        let f = ImageConfiguration.fallback
        return ImageConfiguration(baseURL: base, posterSizes: sizes("poster_sizes", f.posterSizes), backdropSizes: sizes("backdrop_sizes", f.backdropSizes), logoSizes: sizes("logo_sizes", f.logoSizes), profileSizes: sizes("profile_sizes", f.profileSizes), stillSizes: sizes("still_sizes", f.stillSizes))
    }

    static func translations(_ j: JSON) -> [TitleTranslation] {
        j["translations"].array.compactMap { t in
            guard let lang = t["iso_639_1"].text else { return nil }
            let data = t["data"]
            return TitleTranslation(language: lang, region: t["iso_3166_1"].text, title: data["title"].text ?? data["name"].text, overview: data["overview"].text, tagline: data["tagline"].text)
        }
    }
}

// MARK: Image URLs

public struct ImageConfiguration: Codable, Sendable, Equatable {
    public var baseURL: String
    public var posterSizes: [String]
    public var backdropSizes: [String]
    public var logoSizes: [String]
    public var profileSizes: [String]
    public var stillSizes: [String]

    public init(baseURL: String, posterSizes: [String], backdropSizes: [String], logoSizes: [String], profileSizes: [String], stillSizes: [String]) {
        self.baseURL = baseURL
        self.posterSizes = posterSizes
        self.backdropSizes = backdropSizes
        self.logoSizes = logoSizes
        self.profileSizes = profileSizes
        self.stillSizes = stillSizes
    }

    /// Used until (or unless) `/configuration` has been read.
    public static let fallback = ImageConfiguration(
        baseURL: "https://image.tmdb.org/t/p/",
        posterSizes: ["w92", "w154", "w185", "w342", "w500", "w780", "original"],
        backdropSizes: ["w300", "w780", "w1280", "original"],
        logoSizes: ["w45", "w92", "w154", "w185", "w300", "w500", "original"],
        profileSizes: ["w45", "w185", "h632", "original"],
        stillSizes: ["w92", "w185", "w300", "original"]
    )
}

public enum ImageKind: Sendable { case poster, backdrop, logo, profile, still }

/// Builds full image URLs from TMDB file paths, with sizes suited to a 1080p/4K television.
public struct ImageURLBuilder: Sendable {
    public var configuration: ImageConfiguration
    public init(configuration: ImageConfiguration = .fallback) { self.configuration = configuration }

    /// Quality principle (R98), changed 2026-11-17 (was poster w500, backdrop w1280, logo w500, profile w185, still w300).
    /// The app's poster grid has five columns: 320 pt wide unfocused (HIG Layout, tvOS grids), drawn at @2x on a 4K screen
    /// (HIG Images: tvOS uses @1x and @2x) = 640 px, more when focused, so w500 was upscaled. w780 is the smallest size at or
    /// above that. Full-screen kinds (backdrop, still) and logos use "original" (a 3840 px wide screen at @2x is larger
    /// than any fixed size offered). PROVISIONAL: "original" posters too (largest files, and full-size decoding of a grid
    /// of 2000x3000 posters without a downsampling loader risks memory; docs/COVERAGE.md "Defaults changed").
    static let preferred: [ImageKind: String] = [.poster: "w780", .backdrop: "original", .logo: "original", .profile: "h632", .still: "original"]

    /// - Parameter size: a size name such as "w780" or "original"; nil uses the default for the kind
    ///   (poster w780, backdrop original, logo original, profile h632, still original), falling back to "original"
    ///   when the configured list lacks it.
    public func url(path: String?, kind: ImageKind, size: String? = nil) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let sizes: [String]
        switch kind {
        case .poster: sizes = configuration.posterSizes
        case .backdrop: sizes = configuration.backdropSizes
        case .logo: sizes = configuration.logoSizes
        case .profile: sizes = configuration.profileSizes
        case .still: sizes = configuration.stillSizes
        }
        let wanted = size ?? Self.preferred[kind] ?? "original"
        let chosen = sizes.contains(wanted) ? wanted : "original"
        let base = configuration.baseURL.hasSuffix("/") ? configuration.baseURL : configuration.baseURL + "/"
        let tail = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: base + chosen + "/" + tail)
    }
}
