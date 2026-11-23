import Foundation

// Precedence per field: local sidecar > TMDB > the file's own embedded tags (the spec's order:
// "Local sidecar data wins over online data"). A value counts as missing when it is nil, blank, or an empty list.

public enum FieldSource: String, Codable, Hashable, Sendable {
    /// R449: the user's own edit (UserData record "edit"); beats every other layer.
    case user, sidecar, tmdb, embedded
}

public enum MetadataField: String, Codable, Hashable, Sendable, CaseIterable {
    case title, originalTitle, tagline, overview, releaseDate, runtime, genres, certification, poster, backdrop, logo, cast
}

/// Where an image comes from: a file next to the video (poster.jpg ...) or a TMDB file path.
public enum ArtworkRef: Codable, Hashable, Sendable {
    case local(String)
    case tmdb(String)
}

/// One layer of metadata. Local sidecar data, TMDB data and embedded tags all use this shape.
/// `LocalMetadataInput` is what a sidecar reader (the MetadataLocal work) fills in; this target does not read files.
public struct MetadataFields: Codable, Hashable, Sendable {
    public var title: String?
    public var originalTitle: String?
    public var tagline: String?
    public var overview: String?
    public var releaseDate: CalendarDate?
    public var runtimeMinutes: Int?
    public var genres: [String]
    public var certification: String?
    public var poster: ArtworkRef?
    public var backdrop: ArtworkRef?
    public var logo: ArtworkRef?
    public var cast: [Person]

    public init(title: String? = nil, originalTitle: String? = nil, tagline: String? = nil, overview: String? = nil, releaseDate: CalendarDate? = nil, runtimeMinutes: Int? = nil, genres: [String] = [], certification: String? = nil, poster: ArtworkRef? = nil, backdrop: ArtworkRef? = nil, logo: ArtworkRef? = nil, cast: [Person] = []) {
        self.title = title
        self.originalTitle = originalTitle
        self.tagline = tagline
        self.overview = overview
        self.releaseDate = releaseDate
        self.runtimeMinutes = runtimeMinutes
        self.genres = genres
        self.certification = certification
        self.poster = poster
        self.backdrop = backdrop
        self.logo = logo
        self.cast = cast
    }
}

public typealias LocalMetadataInput = MetadataFields
public typealias EmbeddedMetadataInput = MetadataFields

public struct MergedMetadata: Hashable, Sendable {
    public var fields: MetadataFields
    /// Which layer each present field came from. A field that no layer has is absent here.
    public var provenance: [MetadataField: FieldSource]

    public func source(of field: MetadataField) -> FieldSource? { provenance[field] }
}

public enum MetadataMerger {
    public static func merge(user: MetadataFields? = nil, sidecar: LocalMetadataInput? = nil, tmdb: MetadataFields? = nil, embedded: EmbeddedMetadataInput? = nil) -> MergedMetadata {
        var layers: [(FieldSource, MetadataFields)] = []
        if let user { layers.append((.user, user)) }
        if let sidecar { layers.append((.sidecar, sidecar)) }
        if let tmdb { layers.append((.tmdb, tmdb)) }
        if let embedded { layers.append((.embedded, embedded)) }
        var out = MetadataFields()
        var provenance: [MetadataField: FieldSource] = [:]

        func pick<T>(_ field: MetadataField, _ value: (MetadataFields) -> T?, _ set: (inout MetadataFields, T) -> Void) {
            for (source, fields) in layers {
                if let v = value(fields) {
                    set(&out, v)
                    provenance[field] = source
                    return
                }
            }
        }
        func text(_ keyPath: KeyPath<MetadataFields, String?>) -> (MetadataFields) -> String? {
            { f in
                guard let s = f[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
                return s
            }
        }
        func nonEmpty<T>(_ keyPath: KeyPath<MetadataFields, [T]>) -> (MetadataFields) -> [T]? {
            { f in f[keyPath: keyPath].isEmpty ? nil : f[keyPath: keyPath] }
        }

        pick(.title, text(\.title)) { $0.title = $1 }
        pick(.originalTitle, text(\.originalTitle)) { $0.originalTitle = $1 }
        pick(.tagline, text(\.tagline)) { $0.tagline = $1 }
        pick(.overview, text(\.overview)) { $0.overview = $1 }
        pick(.releaseDate, { $0.releaseDate }) { $0.releaseDate = $1 }
        pick(.runtime, { f in f.runtimeMinutes.flatMap { $0 > 0 ? $0 : nil } }) { $0.runtimeMinutes = $1 }
        pick(.genres, nonEmpty(\.genres)) { $0.genres = $1 }
        pick(.certification, text(\.certification)) { $0.certification = $1 }
        pick(.poster, { $0.poster }) { $0.poster = $1 }
        pick(.backdrop, { $0.backdrop }) { $0.backdrop = $1 }
        pick(.logo, { $0.logo }) { $0.logo = $1 }
        pick(.cast, nonEmpty(\.cast)) { $0.cast = $1 }
        return MergedMetadata(fields: out, provenance: provenance)
    }

    // MARK: TMDB layers

    public static func fields(from movie: MovieMetadata, language: String? = nil) -> MetadataFields {
        MetadataFields(
            title: movie.title, originalTitle: movie.originalTitle, tagline: movie.tagline, overview: movie.overview,
            releaseDate: movie.releaseDate, runtimeMinutes: movie.runtimeMinutes, genres: movie.genres, certification: movie.certification,
            poster: (movie.images.bestPoster(language: language ?? movie.language)?.path ?? movie.posterPath).map(ArtworkRef.tmdb),
            backdrop: (movie.images.bestBackdrop(language: language ?? movie.language)?.path ?? movie.backdropPath).map(ArtworkRef.tmdb),
            logo: movie.images.bestLogo(language: language ?? movie.language).map { ArtworkRef.tmdb($0.path) },
            cast: movie.credits.cast
        )
    }

    public static func fields(from series: SeriesMetadata, language: String? = nil) -> MetadataFields {
        MetadataFields(
            title: series.name, originalTitle: series.originalName, tagline: series.tagline, overview: series.overview,
            releaseDate: series.firstAirDate, runtimeMinutes: nil, genres: series.genres, certification: series.certification,
            poster: (series.images.bestPoster(language: language ?? series.language)?.path ?? series.posterPath).map(ArtworkRef.tmdb),
            backdrop: (series.images.bestBackdrop(language: language ?? series.language)?.path ?? series.backdropPath).map(ArtworkRef.tmdb),
            logo: series.images.bestLogo(language: language ?? series.language).map { ArtworkRef.tmdb($0.path) },
            cast: series.credits.cast
        )
    }

    public static func fields(from episode: EpisodeMetadata) -> MetadataFields {
        MetadataFields(title: episode.name, overview: episode.overview, releaseDate: episode.airDate, runtimeMinutes: episode.runtimeMinutes, poster: episode.stillPath.map(ArtworkRef.tmdb), cast: episode.guestStars)
    }
}
