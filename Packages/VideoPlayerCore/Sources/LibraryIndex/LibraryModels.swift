import Foundation
import VideoPlayerCore

// MARK: Technical facts about a file (filled by a probe; the index only stores and filters them)

public enum ResolutionClass: Int, Codable, Sendable, CaseIterable, Comparable {
    case sd = 0, hd720 = 1, hd1080 = 2, uhd4k = 3

    public static func < (a: ResolutionClass, b: ResolutionClass) -> Bool { a.rawValue < b.rawValue }

    /// Buckets by the larger of what the height and width say, so cropped scope films land correctly.
    public static func classify(width: Int?, height: Int?) -> ResolutionClass? {
        guard width != nil || height != nil else { return nil }
        let w = width ?? 0, h = height ?? 0
        if h >= 2000 || w >= 3500 { return .uhd4k }
        if h >= 1000 || w >= 1800 { return .hd1080 }
        if h >= 700 || w >= 1200 { return .hd720 }
        return .sd
    }
}

public enum HDRFormat: Int, Codable, Sendable, CaseIterable {
    case sdr = 0, hdr10 = 1, hdr10Plus = 2, hlg = 3, dolbyVision = 4
    var bit: Int { 1 << rawValue }
}

public enum ContainerFormat: Int, Codable, Sendable, CaseIterable {
    case mkv = 0, mp4, m4v, mov, ts, avi, wmv, webm, other
    var bit: Int { 1 << rawValue }

    public static func from(extension ext: String) -> ContainerFormat {
        switch ext.lowercased() {
        case "mkv": return .mkv
        case "mp4": return .mp4
        case "m4v": return .m4v
        case "mov": return .mov
        case "ts", "m2ts", "mts": return .ts
        case "avi": return .avi
        case "wmv": return .wmv
        case "webm": return .webm
        default: return .other
        }
    }
}

public struct FileTechnicalInfo: Equatable, Sendable, Codable {
    public var duration: Double?
    public var container: ContainerFormat?
    public var width: Int?
    public var height: Int?
    public var hdrFormats: Set<HDRFormat>
    public var dolbyVisionProfile: Int?
    public var videoCodec: String?
    public var audioCodec: String?
    public var audioChannels: Int?
    public var hasAtmos: Bool
    public var bitrate: Int64?

    public init(
        duration: Double? = nil, container: ContainerFormat? = nil, width: Int? = nil, height: Int? = nil,
        hdrFormats: Set<HDRFormat> = [], dolbyVisionProfile: Int? = nil, videoCodec: String? = nil,
        audioCodec: String? = nil, audioChannels: Int? = nil, hasAtmos: Bool = false, bitrate: Int64? = nil
    ) {
        self.duration = duration
        self.container = container
        self.width = width
        self.height = height
        self.hdrFormats = hdrFormats
        self.dolbyVisionProfile = dolbyVisionProfile
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.audioChannels = audioChannels
        self.hasAtmos = hasAtmos
        self.bitrate = bitrate
    }

    public var resolution: ResolutionClass? { ResolutionClass.classify(width: width, height: height) }
}

// MARK: Items

public enum ItemKind: String, Codable, Sendable { case movie, episode }

public struct WatchState: Equatable, Sendable {
    public var position: Double
    public var duration: Double?
    public var watched: Bool
    public var playCount: Int
    public var lastPlayed: Date?
    public var favorite: Bool
    public var hiddenFromContinue: Bool

    public static let none = WatchState(position: 0, duration: nil, watched: false, playCount: 0, lastPlayed: nil, favorite: false, hiddenFromContinue: false)

    public init(position: Double = 0, duration: Double? = nil, watched: Bool = false, playCount: Int = 0,
                lastPlayed: Date? = nil, favorite: Bool = false, hiddenFromContinue: Bool = false) {
        self.position = position
        self.duration = duration
        self.watched = watched
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.favorite = favorite
        self.hiddenFromContinue = hiddenFromContinue
    }
}

/// One film or episode, however many files (versions) it has.
public struct LibraryItem: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var kind: ItemKind
    public var title: String
    public var year: Int?
    public var rating: Double?
    public var seriesID: Int64?
    public var seriesTitle: String?
    public var season: Int?
    public var episode: Int?
    public var episodeEnd: Int?
    public var tmdbID: Int?
    public var addedAt: Date
    public var versionCount: Int
    public var preferredFileID: Int64?
    // Best values across versions (what the filters match on).
    public var maxResolution: ResolutionClass?
    public var hdrFormats: Set<HDRFormat>
    public var dolbyVisionProfiles: Set<Int>
    public var maxChannels: Int?
    public var hasAtmos: Bool
    public var containers: Set<ContainerFormat>
    public var runtime: Double?
    public var watch: WatchState
    /// R374: the content rating from the title's own NFO file, as written ("PG-13", "Rated R"). Nil: not read yet; "":
    /// read, and the file has none.
    public var contentRating: String? = nil
}

public struct ItemMetadata: Equatable, Sendable {
    public var title: String?
    public var year: Int?
    public var rating: Double?
    public var genres: [String]?
    public var tmdbID: Int?
    /// R374: the content rating read from the title's NFO file ("" records that the file has none).
    public var contentRating: String?

    public init(title: String? = nil, year: Int? = nil, rating: Double? = nil, genres: [String]? = nil, tmdbID: Int? = nil,
                contentRating: String? = nil) {
        self.title = title
        self.year = year
        self.rating = rating
        self.genres = genres
        self.tmdbID = tmdbID
        self.contentRating = contentRating
    }
}

public struct StoredFile: Equatable, Sendable, Identifiable {
    public var id: Int64
    public var sourceID: String
    public var path: String
    public var name: String
    public var parentPath: String
    public var kind: FileKind
    public var size: Int64?
    public var modified: Date?
    public var etag: String?
    public var serverToken: String?
    public var itemID: Int64?
    public var technical: FileTechnicalInfo?
    public var firstSeen: Date
    public var versionLabel: String?
    /// How the file was sorted (docs/SORTING.md); nil for files indexed before sorting was recorded, and for non-videos.
    public var sort: FileSortRecord? = nil

    public var version: FileVersion { FileVersion(etag: etag, modified: modified, size: size, serverToken: serverToken) }
}

public struct LibrarySourceRecord: Equatable, Sendable {
    public var id: String
    public var kind: SourceKind
    public var name: String
    public var addedAt: Date
    public init(id: String, kind: SourceKind, name: String, addedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.name = name
        self.addedAt = addedAt
    }
}

public struct StoredFolder: Equatable, Sendable {
    public var sourceID: String
    public var path: String
    public var observed: FileVersion
    public var scanned: FileVersion?
    public var emptyStrikes: Int
    public var lastError: String?
    public var lastScanned: Date?
}

public struct LibraryCounts: Equatable, Sendable {
    public var items: Int
    public var files: Int
    public var folders: Int
    public var series: Int
}
