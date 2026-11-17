import Foundation
import VideoPlayerCore

// Decides which image files sitting next to a video (or in a show folder) belong to it.
// It only looks at names in a folder listing, so it works over any source and needs no network.
// Precedence, from strongest to weakest, is documented in docs/METADATA_LOCAL.md and tested.

public enum SidecarImageRole: String, Codable, Sendable, CaseIterable {
    case poster, backdrop, logo, banner, landscape, thumb
}

/// The images found for one item. Each value is the chosen folder entry.
public struct SidecarImages: Equatable, Sendable {
    public var poster: SourceEntry?
    public var backdrop: SourceEntry?
    public var logo: SourceEntry?
    public var banner: SourceEntry?
    public var landscape: SourceEntry?
    public var thumb: SourceEntry?

    public init() {}

    public subscript(role: SidecarImageRole) -> SourceEntry? {
        get {
            switch role {
            case .poster: return poster
            case .backdrop: return backdrop
            case .logo: return logo
            case .banner: return banner
            case .landscape: return landscape
            case .thumb: return thumb
            }
        }
        set {
            switch role {
            case .poster: poster = newValue
            case .backdrop: backdrop = newValue
            case .logo: logo = newValue
            case .banner: banner = newValue
            case .landscape: landscape = newValue
            case .thumb: thumb = newValue
            }
        }
    }

    public var isEmpty: Bool { SidecarImageRole.allCases.allSatisfy { self[$0] == nil } }
}

public enum SidecarImageFinder {
    /// Image extensions in order of preference when two files differ only by extension.
    public static let extensions = ["jpg", "jpeg", "png", "webp", "tbn"]

    // Role -> bare names (no extension), strongest first.
    private static let folderNames: [SidecarImageRole: [String]] = [
        .poster: ["poster", "folder", "cover", "movie", "show", "default"],
        .backdrop: ["fanart", "backdrop", "background", "art"],
        .logo: ["clearlogo", "logo"],
        .banner: ["banner"],
        .landscape: ["landscape"],
        .thumb: ["thumb"],
    ]
    // Role -> suffix after "<basename>-" (and "<basename>.") for same-name files.
    private static let sameNameSuffixes: [SidecarImageRole: [String]] = [
        .poster: ["poster", "folder", "cover"],
        .backdrop: ["fanart", "backdrop", "background"],
        .logo: ["clearlogo", "logo"],
        .banner: ["banner"],
        .landscape: ["landscape"],
        .thumb: ["thumb"],
    ]

    /// Lowercased file name without its extension, and the lowercased extension; nil when it is not an image.
    static func split(_ name: String) -> (stem: String, ext: String)? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = String(name[name.index(after: dot)...]).lowercased()
        guard extensions.contains(ext) else { return nil }
        return (String(name[..<dot]).lowercased(), ext)
    }

    private static func images(in entries: [SourceEntry]) -> [(entry: SourceEntry, stem: String, ext: String)] {
        entries.compactMap { entry in
            guard !entry.isDirectory, let parts = split(entry.name) else { return nil }
            return (entry, parts.stem, parts.ext)
        }
    }

    /// The best file whose stem equals `stem`, preferring `jpg` over `png` and so on.
    private static func best(stem: String, in images: [(entry: SourceEntry, stem: String, ext: String)]) -> SourceEntry? {
        let candidates = images.filter { $0.stem == stem }
        for ext in extensions {
            if let hit = candidates.first(where: { $0.ext == ext }) { return hit.entry }
        }
        return nil
    }

    /// Lowercased stem of a video file name ("Movie (2020).mkv" -> "movie (2020)").
    private static func baseStem(of fileName: String) -> String {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return fileName.lowercased() }
        return String(fileName[..<dot]).lowercased()
    }

    /// Images for a **movie** video file.
    ///
    /// Order for each role: same-name files (`<name>-poster.jpg`, `<name>.poster.jpg`, then for the poster
    /// also plain `<name>.jpg`), then, only when `folderHoldsOneVideo` is true, the folder-wide names
    /// (`poster.jpg`, `folder.jpg`, `fanart.jpg`, ...). A folder with several videos does not hand its
    /// generic `poster.jpg` to any of them.
    public static func images(forMovie fileName: String, in folder: [SourceEntry], folderHoldsOneVideo: Bool) -> SidecarImages {
        let all = images(in: folder)
        let base = baseStem(of: fileName)
        var result = SidecarImages()
        for role in SidecarImageRole.allCases {
            var names: [String] = []
            for suffix in sameNameSuffixes[role] ?? [] {
                names.append("\(base)-\(suffix)")
                names.append("\(base).\(suffix)")
            }
            if role == .poster { names.append(base) }
            if folderHoldsOneVideo { names.append(contentsOf: folderNames[role] ?? []) }
            for name in names {
                if let hit = best(stem: name, in: all) { result[role] = hit; break }
            }
        }
        return result
    }

    /// Images for an **episode** video file: only same-name files count. `<name>-thumb.jpg`,
    /// `<name>.thumb.jpg` or plain `<name>.jpg` is the episode still; `<name>-poster.jpg` is allowed too.
    /// Folder-wide images in an episode folder belong to the season or show, not to the episode.
    public static func images(forEpisode fileName: String, in folder: [SourceEntry]) -> SidecarImages {
        let all = images(in: folder)
        let base = baseStem(of: fileName)
        var result = SidecarImages()
        result.thumb = best(stem: "\(base)-thumb", in: all) ?? best(stem: "\(base).thumb", in: all) ?? best(stem: base, in: all)
        result.poster = best(stem: "\(base)-poster", in: all) ?? best(stem: "\(base).poster", in: all)
        result.backdrop = best(stem: "\(base)-fanart", in: all) ?? best(stem: "\(base)-backdrop", in: all)
        result.landscape = best(stem: "\(base)-landscape", in: all)
        result.logo = best(stem: "\(base)-clearlogo", in: all)
        return result
    }

    /// Images for a **show folder** (the folder that holds `Season 1`, `Season 2`, ...).
    public static func images(forShowFolder folder: [SourceEntry]) -> SidecarImages {
        let all = images(in: folder)
        var result = SidecarImages()
        for role in SidecarImageRole.allCases {
            for name in folderNames[role] ?? [] {
                if let hit = best(stem: name, in: all) { result[role] = hit; break }
            }
        }
        return result
    }

    /// Poster and other art for one season.
    ///
    /// Order: files in the show folder named `season01-poster.jpg` (also `season1-poster`, `season-01-poster`,
    /// `season 01-poster`), `season-specials-poster.jpg` for season 0, then, for the poster, `season01.jpg`;
    /// finally the images inside the season's own folder (`poster.jpg`, `folder.jpg`, `season01-poster.jpg`...).
    public static func images(forSeason season: Int, showFolder: [SourceEntry], seasonFolder: [SourceEntry]?) -> SidecarImages {
        let showImages = images(in: showFolder)
        var result = SidecarImages()
        let numbers: [String] = {
            if season == 0 { return ["-specials", "00", "0", "-00", " 00", " 0"] }
            return [String(format: "%02d", season), String(season), String(format: "-%02d", season),
                    String(format: " %02d", season), " \(season)"]
        }()
        let prefixes = season == 0
            ? ["season-specials", "season00", "season0", "season-00", "season 00", "season 0", "specials"]
            : numbers.map { "season" + $0 }
        for role in SidecarImageRole.allCases {
            let suffixes = sameNameSuffixes[role] ?? []
            var found: SourceEntry?
            outer: for prefix in prefixes {
                for suffix in suffixes {
                    if let hit = best(stem: "\(prefix)-\(suffix)", in: showImages) { found = hit; break outer }
                }
                if role == .poster, let hit = best(stem: prefix, in: showImages) { found = hit; break outer }
            }
            result[role] = found
        }
        if let folder = seasonFolder {
            let own = images(in: folder)
            for role in SidecarImageRole.allCases where result[role] == nil {
                for name in folderNames[role] ?? [] {
                    if let hit = best(stem: name, in: own) { result[role] = hit; break }
                }
                if result[role] == nil {
                    for prefix in prefixes {
                        for suffix in sameNameSuffixes[role] ?? [] {
                            if let hit = best(stem: "\(prefix)-\(suffix)", in: own) { result[role] = hit; break }
                        }
                        if result[role] != nil { break }
                    }
                }
            }
        }
        return result
    }

    /// The `Specials`/`Season 0` aware season number of a folder name ("Season 02", "S2", "Specials"), nil otherwise.
    public static func seasonNumber(ofFolder name: String) -> Int? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        if lower == "specials" { return 0 }
        if let r = lower.range(of: "^(?:season|series|staffel|saison|temporada)[ ._-]*([0-9]{1,3})$", options: .regularExpression) {
            return Int(lower[r].filter(\.isNumber))
        }
        if let r = lower.range(of: "^s([0-9]{1,3})$", options: .regularExpression) {
            return Int(lower[r].filter(\.isNumber))
        }
        return nil
    }
}
