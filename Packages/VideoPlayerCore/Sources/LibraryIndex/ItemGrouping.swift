import Foundation
import VideoPlayerCore

/// Text helpers shared by the index and its queries.
enum LibraryText {
    /// Lower case, accents removed, anything that is not a letter or digit becomes one space.
    static func normalize(_ s: String) -> String {
        let folded = s.precomposedStringWithCanonicalMapping.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var out = ""
        out.reserveCapacity(folded.count)
        var lastSpace = true
        for ch in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    private static let articles: [String] = ["the ", "a ", "an "]

    /// Sort key where digit runs are zero padded, so "Apollo 13" sorts before "Apollo 100".
    static func sortKey(_ s: String, dropArticle: Bool) -> String {
        var n = normalize(s)
        if dropArticle {
            for a in articles where n.hasPrefix(a) && n.count > a.count {
                n.removeFirst(a.count)
                break
            }
        }
        var out = ""
        out.reserveCapacity(n.count + 8)
        var digits = ""
        for ch in n {
            if ch.isASCII, ch.isNumber {
                digits.append(ch)
            } else {
                if !digits.isEmpty { out += pad(digits); digits = "" }
                out.append(ch)
            }
        }
        if !digits.isEmpty { out += pad(digits) }
        return out
    }

    private static func pad(_ digits: String) -> String {
        digits.count >= 8 ? digits : String(repeating: "0", count: 8 - digits.count) + digits
    }

    /// "#" for titles that do not start with A to Z, else the upper case letter.
    static func letter(forSortKey key: String) -> String {
        guard let first = key.unicodeScalars.first, first.value >= 97, first.value <= 122 else { return "#" }
        return String(Character(UnicodeScalar(first.value - 32) ?? first))
    }

    /// Items starting with "#" sort first; the prefix keeps the alphabet index and the sort order in step.
    static func titleSortValue(_ title: String) -> (value: String, letter: String) {
        let key = sortKey(title, dropArticle: true)
        let bucket = letter(forSortKey: key)
        return ((bucket == "#" ? "0" : "1") + key, bucket)
    }
}

enum LibraryPath {
    /// "/a/b.mkv" -> "/a", "/a.mkv" -> "/", "/" -> "".
    static func parent(of path: String) -> String {
        if path == "/" { return "" }
        guard let slash = path.lastIndex(of: "/") else { return "/" }
        if slash == path.startIndex { return "/" }
        return String(path[path.startIndex..<slash])
    }

    static func ancestorNames(of path: String) -> [String] {
        Array(path.split(separator: "/").dropLast().reversed()).map(String.init)
    }

    static func stem(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[name.startIndex..<dot])
    }

    /// Bounds such that every path below `folder` has a parent in [lower, upper) (the folder itself is separate).
    static func descendantBounds(of folder: String) -> (lower: String, upper: String)? {
        if folder == "/" || folder.isEmpty { return nil }
        return (folder + "/", folder + "0")
    }
}

/// Decides which film or episode a video file belongs to. Files with the same key become versions of one item.
public enum ItemGrouping {
    public static func seed(fileName: String, path: String) -> ItemSeed {
        let parsed = FilenameParser.parse(fileName: fileName, folders: LibraryPath.ancestorNames(of: path))
        return seed(parsed: parsed, fileName: fileName)
    }

    static func seed(parsed p: ParsedMedia, fileName: String) -> ItemSeed {
        let label = versionLabel(p)
        let stem = LibraryPath.stem(fileName)
        let title = p.title.trimmingCharacters(in: .whitespaces)
        let normTitle = LibraryText.normalize(title)

        if p.kind == .episode, !normTitle.isEmpty {
            let seriesKey = "s|" + normTitle
            let season = p.season ?? (p.airDate != nil ? 0 : 1)
            let first = p.episodes.first ?? p.absoluteEpisode
            if let first {
                let last = p.episodes.last ?? first
                return ItemSeed(
                    key: "e|\(normTitle)|\(season)|\(first)", kind: .episode, title: p.episodeTitle ?? "", year: p.year,
                    seriesKey: seriesKey, seriesTitle: title, season: season, episode: first,
                    episodeEnd: last != first ? last : nil, tmdbID: p.tmdbID, versionLabel: label, seriesYear: p.year
                )
            }
            if let d = p.airDate {
                // The air date's year is not the show's year; only a different year in the name counts.
                return ItemSeed(
                    key: "e|\(normTitle)|d|\(d.year)-\(d.month)-\(d.day)", kind: .episode, title: p.episodeTitle ?? "", year: d.year,
                    seriesKey: seriesKey, seriesTitle: title, season: p.season ?? 0, episode: 0, episodeEnd: nil,
                    tmdbID: p.tmdbID, versionLabel: label, seriesYear: p.year == d.year ? nil : p.year
                )
            }
        }
        if !normTitle.isEmpty {
            let part = p.part.map { "|p\($0)" } ?? ""
            return ItemSeed(
                key: "m|\(normTitle)|\(p.year ?? 0)\(part)", kind: .movie, title: title, year: p.year,
                seriesKey: nil, seriesTitle: nil, season: nil, episode: nil, episodeEnd: nil, tmdbID: p.tmdbID, versionLabel: label
            )
        }
        // Nothing usable in the name: the file stands alone under its own name.
        let fallback = stem.isEmpty ? fileName : stem
        return ItemSeed(
            key: "f|" + LibraryText.normalize(fallback), kind: .movie, title: fallback, year: nil,
            seriesKey: nil, seriesTitle: nil, season: nil, episode: nil, episodeEnd: nil, tmdbID: nil, versionLabel: label
        )
    }

    /// A file in Needs Review is its own item (one per file, never grouped), so moving it later never drags other files.
    static func reviewSeed(sourceID: String, path: String, fileName: String, parsed p: ParsedMedia) -> ItemSeed {
        let stem = LibraryPath.stem(fileName)
        let title = p.title.trimmingCharacters(in: .whitespaces)
        return ItemSeed(
            key: "r|\(sourceID)|\(path)", kind: .movie, title: title.isEmpty ? (stem.isEmpty ? fileName : stem) : title, year: p.year,
            seriesKey: nil, seriesTitle: nil, season: nil, episode: nil, episodeEnd: nil, tmdbID: p.tmdbID, versionLabel: versionLabel(p),
            needsReview: true
        )
    }

    static func versionLabel(_ p: ParsedMedia) -> String? {
        var parts: [String] = []
        if let e = p.edition { parts.append(e) }
        if let r = p.resolution { parts.append(r) }
        if let s = p.source { parts.append(s) }
        if let h = p.hdr { parts.append(h) }
        if let v = p.videoCodec { parts.append(v) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Fills in what can be known without opening the file. Real probing (container headers, stream info) happens
/// elsewhere and is stored with `LibraryStore.setTechnicalInfo`.
public protocol FileAnnotator: Sendable {
    func technicalInfo(for entry: SourceEntry, parsed: ParsedMedia) -> FileTechnicalInfo?
}

/// Container from the extension; resolution, HDR and Atmos from tokens in the file name.
public struct FilenameAnnotator: FileAnnotator {
    public init() {}

    public func technicalInfo(for entry: SourceEntry, parsed p: ParsedMedia) -> FileTechnicalInfo? {
        var info = FileTechnicalInfo(container: ContainerFormat.from(extension: FileClassifier.fileExtension(of: entry.name)))
        if let r = p.resolution?.lowercased() {
            let digits = r.prefix { $0.isNumber }
            if let h = Int(digits), h > 0 {
                info.height = h
                info.width = h * 16 / 9
            } else if r.contains("4k") || r.contains("uhd") {
                info.height = 2160
                info.width = 3840
            }
        }
        if let h = p.hdr?.lowercased() {
            if h.contains("dv") || h.contains("dolby") || h.contains("dovi") { info.hdrFormats.insert(.dolbyVision) }
            if h.contains("10+") || h.contains("10plus") { info.hdrFormats.insert(.hdr10Plus) } else if h.contains("hdr") { info.hdrFormats.insert(.hdr10) }
            if h.contains("hlg") { info.hdrFormats.insert(.hlg) }
        }
        info.videoCodec = p.videoCodec
        info.audioCodec = p.audioCodec
        if let a = p.audioCodec?.lowercased(), a.contains("atmos") { info.hasAtmos = true }
        return info
    }
}
