import Foundation

public struct AirDate: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
}

public struct ParsedMedia: Equatable, Sendable {
    public enum Kind: String, Sendable { case movie, episode }

    /// Which episode marker was found (docs/SORTING.md). The first three and `date` are strong; the others are weak and
    /// only count when something else (a season folder, other files of the same show) agrees.
    public enum EpisodeMarker: String, Sendable {
        /// S01E02, S1E2, S01E01-E03, S01E01E02
        case seasonEpisode
        /// 1x02
        case crossFormat
        /// "Season 1 Episode 2"
        case words
        /// 2024-03-05, 2024.03.05
        case date
        /// E05, Ep 5, Episode 5 (no season)
        case episodeOnly
        /// SP01, OVA 2
        case special
        /// S01 or "Season 1" without an episode number
        case seasonOnly
        /// "Show Name - 012"
        case absolute
        /// "05 - Title" inside a season folder
        case folderNumber

        public var isStrong: Bool { self == .seasonEpisode || self == .crossFormat || self == .words || self == .date }
    }

    public var kind: Kind = .movie
    public var episodeMarker: EpisodeMarker?
    public var title: String = ""
    public var year: Int?
    public var season: Int?
    public var episodes: [Int] = []
    public var absoluteEpisode: Int?
    public var airDate: AirDate?
    public var isSpecial = false
    public var edition: String?
    public var episodeTitle: String?
    /// Disc or part number from names like "CD1" or "Disc 2".
    public var part: Int?
    public var resolution: String?
    public var source: String?
    public var videoCodec: String?
    public var audioCodec: String?
    public var hdr: String?
    public var releaseGroup: String?
    public var tmdbID: Int?
    public var imdbID: String?

    public init() {}
}

/// Parses file and folder names into title, year, season and episode numbers, edition, and
/// technical tokens. Own implementation; the rule set is informed by public naming conventions.
public enum FilenameParser {

    /// - Parameters:
    ///   - fileName: the file name, with or without extension.
    ///   - folders: ancestor folder names, nearest first (for example ["Season 2", "Show Name (2015)"]).
    ///   - weakMarkers: false ignores the weak episode markers (episode number alone, special, season alone, absolute
    ///     number), for reading a file that was decided to be a movie (docs/SORTING.md).
    public static func parse(fileName: String, folders: [String] = [], weakMarkers: Bool = true) -> ParsedMedia {
        var p = parseName(fileName, weakMarkers: weakMarkers)
        let infos = folders.map(parseFolderName)

        // The nearest season folder, looking at the two closest folders.
        let seasonInfo = infos.prefix(2).first { $0.season != nil }
        // The nearest folder that names a show or movie.
        let titleInfo = infos.first { $0.season == nil && !$0.isGeneric && !$0.title.isEmpty }

        // Bare numbered files inside a season folder: "05 - Pilot.mkv".
        if p.episodes.isEmpty, p.airDate == nil, p.absoluteEpisode == nil, seasonInfo != nil {
            if let m = Rx.leadingNumber.firstMatch(in: p.title) {
                let ns = p.title as NSString
                if let n = Int(ns.substring(with: m.range(at: 1))) {
                    p.episodes = [n]
                    p.episodeMarker = .folderNumber
                    let rest = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
                    let cleaned = cleanTitle(rest)
                    p.episodeTitle = cleaned.isEmpty ? nil : cleaned
                    p.title = ""
                }
            }
        }

        let hasEpisodeInfo = !p.episodes.isEmpty || p.airDate != nil || p.absoluteEpisode != nil || p.season != nil
        if hasEpisodeInfo { p.kind = .episode }

        if p.kind == .episode {
            if p.season == nil, !p.episodes.isEmpty || p.airDate != nil {
                if let s = seasonInfo?.season { p.season = s }
            }
            if seasonInfo?.isSpecials == true, p.season == 0 || p.season == nil, !p.episodes.isEmpty {
                p.season = 0
            }
        }
        if p.season == 0 { p.isSpecial = true }

        if p.title.isEmpty || isGenericName(p.title) {
            if let t = titleInfo {
                p.title = t.title
                if p.year == nil { p.year = t.year }
            }
        } else if p.year == nil, let t = titleInfo, normalizedKey(t.title) == normalizedKey(p.title) {
            p.year = t.year
        }
        return p
    }

    // MARK: Name parsing

    static func parseName(_ raw: String, weakMarkers: Bool = true) -> ParsedMedia {
        var p = ParsedMedia()
        // Servers may return decomposed (NFD) names; compare everything in composed (NFC) form.
        var s = stripExtension(raw.precomposedStringWithCanonicalMapping)

        // External IDs and Plex-style edition tags.
        if let m = Rx.tmdbID.firstMatch(in: s) {
            p.tmdbID = Int((s as NSString).substring(with: m.range(at: 1)))
            s = Rx.tmdbID.replace(in: s, with: " ")
        }
        if let m = Rx.imdbID.firstMatch(in: s) {
            p.imdbID = (s as NSString).substring(with: m.range(at: 1)).lowercased()
            s = Rx.imdbID.replace(in: s, with: " ")
        }
        if let m = Rx.editionBrace.firstMatch(in: s) {
            p.edition = (s as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            s = Rx.editionBrace.replace(in: s, with: " ")
        }

        // Square brackets: hashes are dropped, technical ones kept as words, anything else is a release group.
        var leadingGroup: String?
        var trailingGroup: String?
        let nsOriginal = s as NSString
        var rebuilt = ""
        var cursor = 0
        for m in Rx.squareBracket.matches(in: s) {
            let content = nsOriginal.substring(with: m.range(at: 1))
            rebuilt += nsOriginal.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            cursor = m.range.location + m.range.length
            if Rx.crcHash.matches(whole: content) {
                rebuilt += " "
            } else if Rx.tech.containsTechOrYear(content) {
                rebuilt += " " + content + " "
            } else if m.range.location == 0 {
                leadingGroup = content
                rebuilt += " "
            } else {
                trailingGroup = content
                rebuilt += " "
            }
        }
        rebuilt += nsOriginal.substring(from: cursor)
        s = rebuilt

        // Years in parentheses are preferred when several years are present.
        var parenYears = Set<Int>()
        for m in Rx.parenYear.matches(in: s) {
            if let y = Int((s as NSString).substring(with: m.range(at: 1))) { parenYears.insert(y) }
        }

        s = protectCompounds(s)
        s = s.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")
        for ch in ["(", ")", "[", "]", "{", "}"] { s = s.replacingOccurrences(of: ch, with: " ") }
        s = Rx.spaces.replace(in: s, with: " ").trimmingCharacters(in: .whitespaces)

        // Trailing "-GROUP" after a technical token.
        if let m = Rx.trailingGroup.firstMatch(in: s) {
            let ns = s as NSString
            let group = ns.substring(with: m.range(at: 1))
            let before = ns.substring(to: m.range.location)
            if let lastWord = before.split(separator: " ").last, Rx.tech.matches(whole: String(lastWord)) {
                p.releaseGroup = group
                s = before
            }
        }
        if p.releaseGroup == nil { p.releaseGroup = trailingGroup ?? leadingGroup }

        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Technical details (anywhere in the string).
        fillTechnical(&p, from: s)

        // Edition.
        var markers: [Int] = []
        if p.edition == nil || true {
            for (rx, canonical) in Rx.editions {
                if let m = rx.firstMatch(in: s), m.range.location > 0 {
                    if p.edition == nil { p.edition = canonical }
                    markers.append(m.range.location)
                    break
                }
            }
        }

        // Technical markers: strong ones (not at the very start), weak ones only when a strong one follows.
        let strong = Rx.tech.matches(in: s).filter { $0.range.location > 0 }
        let strongAll = Rx.tech.matches(in: s)
        for m in strong { markers.append(m.range.location) }
        if let lastStrong = strongAll.map({ $0.range.location }).max() {
            for m in Rx.weak.matches(in: s) where m.range.location > 0 && m.range.location < lastStrong {
                markers.append(m.range.location)
            }
        }
        if let m = Rx.multipart.firstMatch(in: s), m.range.location > 0 {
            p.part = Int(ns.substring(with: m.range(at: 1)))
            markers.append(m.range.location)
        }

        // Episode information.
        var maskedRanges: [NSRange] = []
        var episodeEnd: Int?
        var foundEpisode = false

        if let hit = findSxxEyy(in: s) {
            p.season = hit.season; p.episodes = hit.episodes
            markers.append(hit.range.location); maskedRanges.append(hit.range); episodeEnd = hit.range.location + hit.range.length
            foundEpisode = true; p.episodeMarker = .seasonEpisode
        } else if let hit = findNxNN(in: s) {
            p.season = hit.season; p.episodes = hit.episodes
            markers.append(hit.range.location); maskedRanges.append(hit.range); episodeEnd = hit.range.location + hit.range.length
            foundEpisode = true; p.episodeMarker = .crossFormat
        } else if let m = Rx.seasonEpisodeWords.firstMatch(in: s) {
            p.season = Int(ns.substring(with: m.range(at: 1)))
            if let e = Int(ns.substring(with: m.range(at: 2))) { p.episodes = [e] }
            markers.append(m.range.location); maskedRanges.append(m.range); episodeEnd = m.range.location + m.range.length
            foundEpisode = true; p.episodeMarker = .words
        } else if let m = Rx.date.firstMatch(in: s), let d = validDate(m, in: ns) {
            p.airDate = d
            markers.append(m.range.location); maskedRanges.append(m.range); episodeEnd = m.range.location + m.range.length
            foundEpisode = true; p.episodeMarker = .date
        } else if weakMarkers, let m = Rx.episodeOnly.firstMatch(in: s) {
            if let e = Int(ns.substring(with: m.range(at: 1))) { p.episodes = [e] }
            markers.append(m.range.location); maskedRanges.append(m.range); episodeEnd = m.range.location + m.range.length
            foundEpisode = true; p.episodeMarker = .episodeOnly
        } else if weakMarkers, let m = Rx.special.firstMatch(in: s), m.range.location > 0 {
            p.season = 0
            if let e = Int(ns.substring(with: m.range(at: 1))) { p.episodes = [e] }
            markers.append(m.range.location); maskedRanges.append(m.range); episodeEnd = m.range.location + m.range.length
            foundEpisode = true; p.episodeMarker = .special
        } else if weakMarkers, let m = Rx.seasonOnlyWord.firstMatch(in: s) ?? Rx.seasonOnlyShort.firstMatch(in: s) {
            p.season = Int(ns.substring(with: m.range(at: 1)))
            markers.append(m.range.location); maskedRanges.append(m.range); episodeEnd = m.range.location + m.range.length
            foundEpisode = true; p.episodeMarker = .seasonOnly
        } else if weakMarkers, let m = Rx.absolute.firstMatch(in: s), m.range.location > 0,
                  let n = Int(ns.substring(with: m.range(at: 1))), !(1900...2035).contains(n) || ns.substring(with: m.range(at: 1)).count < 4 {
            p.absoluteEpisode = n
            markers.append(m.range.location); maskedRanges.append(m.range); episodeEnd = m.range.location + m.range.length
            foundEpisode = true; p.episodeMarker = .absolute
        }
        if foundEpisode { p.kind = .episode }
        if p.season == 0 { p.isSpecial = true }

        // Year.
        let firstMarker = markers.min()
        var yearStart: Int?
        var candidates: [(start: Int, value: Int)] = []
        for m in Rx.year.matches(in: s) {
            if maskedRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            if let v = Int(ns.substring(with: m.range(at: 1))) { candidates.append((m.range.location, v)) }
        }
        let before = candidates.filter { firstMarker == nil || $0.start < firstMarker! }
        if !before.isEmpty {
            var chosen = before.last(where: { parenYears.contains($0.value) }) ?? before.last!
            if chosen.start == 0 {
                if let other = before.last(where: { $0.start != 0 }) {
                    chosen = other
                } else if ns.length > 4 {
                    // Only a leading number, and more text follows: it is part of the title.
                    yearStart = nil
                    chosen = (-1, 0)
                }
            }
            if chosen.start >= 0 { p.year = chosen.value; yearStart = chosen.start }
        } else if let after = candidates.first(where: { firstMarker != nil && $0.start > firstMarker! }) {
            p.year = after.value
        }

        // Title.
        var cut = ns.length
        if let m = firstMarker { cut = min(cut, m) }
        if let y = yearStart { cut = min(cut, y) }
        p.title = cleanTitle(ns.substring(to: cut))

        // Episode title: text after the episode marker, up to the next marker.
        if let end = episodeEnd, end < ns.length {
            var stop = ns.length
            for m in markers where m > end { stop = min(stop, m) }
            for c in candidates where c.start > end { stop = min(stop, c.start) }
            let text = cleanTitle(ns.substring(with: NSRange(location: end, length: stop - end)))
            if !text.isEmpty { p.episodeTitle = text }
        }
        _ = full
        return p
    }

    // MARK: Folder names

    public struct FolderInfo: Equatable, Sendable {
        public var title: String
        public var year: Int?
        public var season: Int?
        public var isSpecials: Bool
        public var isGeneric: Bool
    }

    /// What a folder name says: a season ("Season 2", "S02", "Specials"), a generic name ("Movies", "Downloads"), or a
    /// title with an optional year.
    public static func parseFolderName(_ name: String) -> FolderInfo {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if Rx.specialsFolder.matches(whole: trimmed) {
            return FolderInfo(title: "", year: nil, season: 0, isSpecials: true, isGeneric: false)
        }
        if let m = Rx.seasonFolder.firstMatch(in: trimmed), let n = Int((trimmed as NSString).substring(with: m.range(at: 1))) {
            return FolderInfo(title: "", year: nil, season: n, isSpecials: n == 0, isGeneric: false)
        }
        if Rx.genericFolder.matches(whole: trimmed) {
            return FolderInfo(title: "", year: nil, season: nil, isSpecials: false, isGeneric: true)
        }
        let p = parseName(trimmed)
        return FolderInfo(title: p.title, year: p.year, season: nil, isSpecials: false, isGeneric: false)
    }

    // MARK: Helpers

    static func stripExtension(_ name: String) -> String {
        let ext = FileClassifier.fileExtension(of: name)
        let known = FileClassifier.videoExtensions.union(FileClassifier.subtitleExtensions).union(["nfo"])
        if !ext.isEmpty, known.contains(ext) { return String(name.dropLast(ext.count + 1)) }
        return name
    }

    static func protectCompounds(_ input: String) -> String {
        var s = input
        let replacements: [(String, String)] = [
            (#"(?<![a-z0-9])h[ .]?26([45])(?![0-9])"#, "h26$1"),
            (#"(?<![a-z0-9])x[ .]?26([45])(?![0-9])"#, "x26$1"),
            (#"dts[-. ]?hd(?:[-. ]?ma)?"#, "DTSHD"),
            (#"dts[-. ]?x(?![a-z0-9])"#, "DTSX"),
            (#"dts[-. ]?es(?![a-z0-9])"#, "DTSES"),
            (#"web[-. ]?dl"#, "WEBDL"),
            (#"web[-. ]?rip"#, "WEBRip"),
            (#"blu[-. ]?ray"#, "BluRay"),
            (#"bd[-. ]?(rip|remux)"#, "BD$1"),
            (#"(?<![a-z0-9])hd[-. ]?tv"#, "HDTV"),
            (#"dd\+"#, "DDP"),
            (#"e-?ac-?3"#, "EAC3"),
            (#"dolby[ .]?vision"#, "DolbyVision"),
            (#"hdr10\+"#, "HDR10Plus"),
            (#"(?<![0-9])([1-9])\.([0-2])(?![0-9])"#, "$1ch$2"),
            (#"([A-Za-z])([1-9]ch[0-2])"#, "$1 $2")
        ]
        for (pattern, template) in replacements {
            s = Rx(pattern).replace(in: s, with: template)
        }
        return s
    }

    static func cleanTitle(_ text: String) -> String {
        var s = Rx.spaces.replace(in: text, with: " ")
        let trim = CharacterSet(charactersIn: " \t-–—:,;.[({")
        s = s.trimmingCharacters(in: trim)
        return s
    }

    static func isGenericName(_ title: String) -> Bool {
        let key = normalizedKey(title)
        return key.isEmpty || ["movie", "film", "video", "main", "sample", "feature", "cd1", "cd2", "disc1", "disc2"].contains(key)
    }

    static func normalizedKey(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func fillTechnical(_ p: inout ParsedMedia, from s: String) {
        func has(_ pattern: String) -> Bool { Rx("(?<![a-z0-9])(?:" + pattern + ")(?![a-z0-9])").firstMatch(in: s) != nil }
        if has("2160p|4k|uhd|8k") { p.resolution = "2160p" }
        else if has("1080p|1080i") { p.resolution = "1080p" }
        else if has("720p") { p.resolution = "720p" }
        else if has("576p") { p.resolution = "576p" }
        else if has("480p") { p.resolution = "480p" }
        if has("remux|bdremux") { p.source = "Remux" }
        else if has("bluray|bdrip|brrip") { p.source = "Blu-ray" }
        else if has("webdl") { p.source = "WEB-DL" }
        else if has("webrip") { p.source = "WEBRip" }
        else if has("hdtv|pdtv") { p.source = "HDTV" }
        else if has("dvdrip|dvdscr") { p.source = "DVD" }
        if has("hevc|x265|h265") { p.videoCodec = "HEVC" }
        else if has("x264|h264|avc") { p.videoCodec = "H.264" }
        else if has("av1") { p.videoCodec = "AV1" }
        else if has("xvid") { p.videoCodec = "Xvid" }
        else if has("divx") { p.videoCodec = "DivX" }
        if has("atmos") { p.audioCodec = "Atmos" }
        else if has("truehd") { p.audioCodec = "TrueHD" }
        else if has("dtshd") { p.audioCodec = "DTS-HD" }
        else if has("dtsx") { p.audioCodec = "DTS:X" }
        else if has("dts|dtses") { p.audioCodec = "DTS" }
        else if has("ddp|eac3") { p.audioCodec = "DD+" }
        else if has("dd|ac3") { p.audioCodec = "DD" }
        else if has("aac") { p.audioCodec = "AAC" }
        else if has("flac") { p.audioCodec = "FLAC" }
        if has("dolbyvision|dovi|dv") { p.hdr = "Dolby Vision" }
        else if has("hdr10plus") { p.hdr = "HDR10+" }
        else if has("hdr10") { p.hdr = "HDR10" }
        else if has("hdr") { p.hdr = "HDR" }
        else if has("hlg") { p.hdr = "HLG" }
    }

    private struct EpisodeHit {
        var range: NSRange
        var season: Int
        var episodes: [Int]
    }

    private static func findSxxEyy(in s: String) -> EpisodeHit? {
        let ns = s as NSString
        guard let m = Rx.sxxexx.firstMatch(in: s),
              let season = Int(ns.substring(with: m.range(at: 1))),
              let first = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return extend(EpisodeHit(range: m.range, season: season, episodes: [first]), in: ns)
    }

    private static func findNxNN(in s: String) -> EpisodeHit? {
        let ns = s as NSString
        guard let m = Rx.nxnn.firstMatch(in: s),
              let season = Int(ns.substring(with: m.range(at: 1))),
              let first = Int(ns.substring(with: m.range(at: 2))) else { return nil }
        return extend(EpisodeHit(range: m.range, season: season, episodes: [first]), in: ns)
    }

    /// Reads continuation such as "E02", "-E04", "-04", "+E03" right after the first episode number.
    private static func extend(_ hit: EpisodeHit, in ns: NSString) -> EpisodeHit {
        var hit = hit
        var position = hit.range.location + hit.range.length
        while position < ns.length {
            guard let m = Rx.continuation.firstMatch(in: ns as String, from: position), m.range.location == position,
                  let value = Int(ns.substring(with: m.range(at: 2))) else { break }
            let isRange = ns.substring(with: m.range(at: 1)).contains("-")
            if isRange, let last = hit.episodes.last, value > last, value - last <= 30 {
                hit.episodes.append(contentsOf: (last + 1)...value)
            } else {
                hit.episodes.append(value)
            }
            position = m.range.location + m.range.length
            hit.range = NSRange(location: hit.range.location, length: position - hit.range.location)
        }
        return hit
    }

    private static func validDate(_ m: NSTextCheckingResult, in ns: NSString) -> AirDate? {
        guard let y = Int(ns.substring(with: m.range(at: 1))),
              let mo = Int(ns.substring(with: m.range(at: 2))),
              let d = Int(ns.substring(with: m.range(at: 3))),
              (1...12).contains(mo), (1...31).contains(d) else { return nil }
        return AirDate(year: y, month: mo, day: d)
    }
}

// MARK: - Regular expressions

struct Rx {
    let re: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = true) {
        // Patterns are compile-time constants; a failure here is a programming error caught by tests.
        re = try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    func firstMatch(in s: String, from: Int = 0) -> NSTextCheckingResult? {
        let length = (s as NSString).length
        guard from <= length else { return nil }
        return re.firstMatch(in: s, options: [.withTransparentBounds, .withoutAnchoringBounds], range: NSRange(location: from, length: length - from))
    }

    func matches(in s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
    }

    func replace(in s: String, with template: String) -> String {
        re.stringByReplacingMatches(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    /// True when the whole string matches the pattern.
    func matches(whole s: String) -> Bool {
        let length = (s as NSString).length
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: length)) else { return false }
        return m.range.location == 0 && m.range.length == length
    }

    func containsTechOrYear(_ s: String) -> Bool {
        firstMatch(in: s) != nil || Rx.year.firstMatch(in: s) != nil || Rx.resolution.firstMatch(in: s) != nil
    }

    // Boundaries: a word here is a run of letters and digits.
    private static let strongWords =
        "bluray|bdrip|brrip|bdremux|bdmv|remux|webdl|webrip|hdtv|pdtv|dvdrip|dvdscr|hddvd|hdrip|hevc|x264|x265|h264|h265|avc|xvid|divx|av1|vp9|"
        + "hdr10plus|hdr10|hdr|hlg|dovi|dv|dolbyvision|atmos|dtshd|dtsx|dtses|dts|truehd|ddp|dd|eac3|ac3|aac|flac|opus|10bit|8bit|"
        + "[1-9]ch[0-2]|2160p|1080p|1080i|720p|576p|480p|360p|4k|8k|uhd|[0-9]{3,4}x[0-9]{3,4}"

    static let tech = Rx("(?<![a-z0-9])(" + strongWords + ")(?![a-z0-9])")
    static let resolution = Rx("(?<![a-z0-9])(2160p|1080[pi]|720p|576p|480p|360p|4k|8k|uhd)(?![a-z0-9])")
    static let weak = Rx("(?<![a-z0-9])(nf|amzn|dsnp|hmax|atvp|hulu|pcok|itunes|web|dvd|cam|hdcam|hq|proper|repack|internal|multi|dual|subbed|dubbed|limited)(?![a-z0-9])")
    static let year = Rx("(?<![0-9a-z])(19[0-9]{2}|20[0-3][0-9])(?![0-9a-z])")
    static let parenYear = Rx("\\(((?:19[0-9]{2}|20[0-3][0-9]))\\)")
    static let spaces = Rx("\\s+")
    static let squareBracket = Rx("\\[([^\\]]*)\\]")
    static let crcHash = Rx("[0-9a-f]{8}")
    static let tmdbID = Rx("[\\[{(]\\s*tmdb(?:id)?[- =]?([0-9]+)\\s*[\\]})]")
    static let imdbID = Rx("(?<![a-z0-9])(tt[0-9]{7,9})(?![0-9a-z])")
    static let editionBrace = Rx("\\{edition-([^}]+)\\}")
    static let trailingGroup = Rx("(?<=[A-Za-z0-9])-([A-Za-z0-9]{2,})$")
    static let multipart = Rx("(?<![a-z0-9])(?:cd|disc|disk)[ ]?([0-9])(?![0-9a-z])")

    static let sxxexx = Rx("(?<![a-z0-9])s([0-9]{1,2})[ ]?e(?:p)?([0-9]{1,3})(?![0-9])")
    static let nxnn = Rx("(?<![0-9a-z])([0-9]{1,2})x([0-9]{2,3})(?![0-9a-z])")
    static let continuation = Rx("[ ]?((?:[-+&][ ]?e?p?)|(?:e|ep))([0-9]{1,3})(?![0-9a-z])")
    static let seasonEpisodeWords = Rx("(?<![a-z0-9])season[ ]?([0-9]{1,2})[ ,\\-]*(?:episode|ep|e)[ ]?([0-9]{1,3})(?![0-9a-z])")
    static let date = Rx("(?<![0-9])((?:19|20)[0-9]{2})[ \\-/]([0-9]{1,2})[ \\-/]([0-9]{1,2})(?![0-9])")
    static let episodeOnly = Rx("(?<![a-z0-9])(?:episode|ep|e)[ ]?([0-9]{1,3})(?![0-9a-z])")
    static let special = Rx("(?<![a-z0-9])(?:special|sp|ova|oad|ona)[ ]?([0-9]{1,3})(?![0-9a-z])")
    static let seasonOnlyWord = Rx("(?<![a-z0-9])(?:season|series|staffel|saison|temporada|stagione)[ ]?([0-9]{1,2})(?![0-9a-z])")
    static let seasonOnlyShort = Rx("(?<![a-z0-9])s([0-9]{1,2})(?![0-9a-z])")
    static let absolute = Rx("(?<=[ ])-[ ]([0-9]{2,4})(?:v[0-9])?(?=[ ]|$)")

    static let leadingNumber = Rx("^([0-9]{1,3})(?![0-9a-z])(?:[ ]*[-–.][ ]*|[ ]+)?(.*)$")
    static let seasonFolder = Rx("^(?:season|series|staffel|saison|temporada|stagione|s)[ ._-]*([0-9]{1,2})(?![0-9a-z]).*$")
    static let specialsFolder = Rx("^specials?$")
    static let genericFolder = Rx("^(?:movies?|films?|tv|tv[ ._-]?shows?|shows?|series|anime|videos?|media|downloads?|library|files|unsorted|new|complete|1080p|720p|2160p|4k|uhd)$")

    static let editions: [(Rx, String)] = [
        (Rx("director'?s[ ]cut"), "Director's Cut"),
        (Rx("(?<![a-z0-9])extended(?:[ ](?:edition|cut|version))?(?![a-z0-9])"), "Extended"),
        (Rx("(?<![a-z0-9])unrated(?![a-z0-9])"), "Unrated"),
        (Rx("theatrical(?:[ ](?:cut|edition|version))?"), "Theatrical Cut"),
        (Rx("final[ ]cut"), "Final Cut"),
        (Rx("ultimate(?:[ ](?:edition|cut))"), "Ultimate Edition"),
        (Rx("special[ ]edition"), "Special Edition"),
        (Rx("collector'?s[ ]edition"), "Collector's Edition"),
        (Rx("anniversary[ ]edition"), "Anniversary Edition"),
        (Rx("(?<![a-z0-9])remastered(?![a-z0-9])"), "Remastered"),
        (Rx("(?<![a-z0-9])restored(?![a-z0-9])"), "Restored"),
        (Rx("(?<![a-z0-9])imax(?![a-z0-9])"), "IMAX"),
        (Rx("(?<![a-z0-9])uncut(?![a-z0-9])"), "Uncut"),
        (Rx("(?<![a-z0-9])redux(?![a-z0-9])"), "Redux"),
        (Rx("open[ ]matte"), "Open Matte"),
        (Rx("criterion(?:[ ]collection)?"), "Criterion")
    ]
}
