import Foundation

/// A subtitle file found next to a video, with what its name says about it.
public struct ExternalSubtitleCandidate: Equatable, Sendable {
    /// How the name relates to the video's name. Lower is a closer match.
    public enum MatchTier: Int, Sendable, Comparable {
        /// The subtitle name starts with the whole video name ("Movie.mkv" and "Movie.en.srt").
        case sameName = 1
        /// Different wording but the same title and the same season and episode.
        case sameEpisode = 2
        /// The folder holds one video only, so any subtitle in it belongs to that video.
        case onlyVideoInFolder = 3

        public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
    }

    /// The name as it appeared in the listing (a path such as "Subs/English.srt" is kept as given).
    public var fileName: String
    public var format: SubtitleFormat
    public var language: LanguageTag?
    public var isForced: Bool
    /// "sdh" in the name.
    public var isSDH: Bool
    /// "hi" in the name next to a language (hearing impaired).
    public var isHI: Bool
    /// "cc" in the name (closed captions).
    public var isCC: Bool
    public var isDefault: Bool
    public var tier: MatchTier
    /// For a VobSub `.idx`: the `.sub` that carries the bitmaps, when it is in the listing.
    public var companionFileName: String?
    /// False for a `.sub` without an `.idx` (could be MicroDVD text, which is not supported) and for an `.idx`
    /// without its `.sub`.
    public var isUsable: Bool

    /// True when the name marks the file as for deaf or hard-of-hearing viewers.
    public var isHearingImpairedVariant: Bool { isSDH || isHI || isCC }
}

/// Finds subtitle files that belong to a video, from names only (no file access).
public enum ExternalSubtitleMatcher {

    public static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sup", "sub", "idx"]
    public static let videoExtensions: Set<String> = [
        "mkv", "mp4", "m4v", "mov", "avi", "wmv", "ts", "m2ts", "mts", "webm", "flv", "mpg", "mpeg", "ogv", "3gp", "iso",
    ]

    /// - Parameters:
    ///   - videoFileName: the video's file name, such as "Movie (2019).mkv".
    ///   - folderListing: names of the files in the same folder (and, if you like, in a "Subs" folder below it).
    /// - Returns: candidates ordered by tier, then language, forced after normal, SDH after plain, text formats first, name.
    public static func candidates(videoFileName: String, folderListing: [String]) -> [ExternalSubtitleCandidate] {
        let videoBase = fold(stem(of: lastComponent(videoFileName)))
        let videoEpisode = episodeKey(videoBase)
        let videoCount = Set(folderListing.map { lastComponent($0).lowercased() }.filter { videoExtensions.contains(ext(of: $0)) }).count
        let onlyVideo = videoCount <= 1

        // Group .idx/.sub pairs by their stem.
        let lowerNames = Set(folderListing.map { $0.lowercased() })

        var out: [ExternalSubtitleCandidate] = []
        for entry in folderListing {
            let name = lastComponent(entry)
            if name.hasPrefix(".") || name.hasPrefix("._") { continue }
            let extension_ = ext(of: name)
            guard subtitleExtensions.contains(extension_) else { continue }
            let entryStem = stem(of: name)
            let folded = fold(entryStem)

            var tier: ExternalSubtitleCandidate.MatchTier?
            var remainder: [String] = []
            if !videoBase.isEmpty, folded.hasPrefix(videoBase), isBoundary(folded, after: videoBase.count) {
                tier = .sameName
                remainder = tokens(String(entryStem.dropFirst(videoBase.count)))
            } else if let ve = videoEpisode, let ce = episodeKey(folded), ve.key == ce.key, !ve.title.isEmpty, ve.title == ce.title || ve.title.hasPrefix(ce.title) || ce.title.hasPrefix(ve.title) {
                tier = .sameEpisode
                remainder = Array(tokens(entryStem).suffix(4))
            } else if onlyVideo {
                tier = .onlyVideoInFolder
                remainder = Array(tokens(entryStem).suffix(4))
            }
            guard let matchTier = tier else { continue }

            var flags = Flags()
            let parsed = readTokens(remainder, into: &flags)
            let format: SubtitleFormat
            switch extension_ {
            case "srt": format = .srt
            case "ass": format = .ass
            case "ssa": format = .ssa
            case "vtt": format = .webVTT
            case "sup": format = .pgs
            default: format = .vobSub
            }

            var companion: String?
            var usable = true
            if extension_ == "idx" {
                let want = (entry as NSString).deletingPathExtension.lowercased() + ".sub"
                if lowerNames.contains(want) { companion = folderListing.first { $0.lowercased() == want } } else { usable = false }
            } else if extension_ == "sub" {
                let want = (entry as NSString).deletingPathExtension.lowercased() + ".idx"
                if lowerNames.contains(want) { continue }   // the .idx represents the pair
                usable = false
            }
            out.append(ExternalSubtitleCandidate(
                fileName: entry, format: format, language: parsed, isForced: flags.forced, isSDH: flags.sdh, isHI: flags.hi,
                isCC: flags.cc, isDefault: flags.isDefault, tier: matchTier, companionFileName: companion, isUsable: usable
            ))
        }
        out.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            switch (a.language?.description, b.language?.description) {
            case let (x?, y?): if x != y { return x < y }
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): break
            }
            if a.isForced != b.isForced { return !a.isForced }
            if a.isHearingImpairedVariant != b.isHearingImpairedVariant { return !a.isHearingImpairedVariant }
            if rank(a.format) != rank(b.format) { return rank(a.format) < rank(b.format) }
            return a.fileName < b.fileName
        }
        return out
    }

    private static func rank(_ f: SubtitleFormat) -> Int {
        switch f {
        case .srt: return 0
        case .ass: return 1
        case .ssa: return 2
        case .webVTT: return 3
        case .pgs: return 4
        case .vobSub: return 5
        }
    }

    // MARK: Names

    private struct Flags {
        var forced = false, sdh = false, hi = false, cc = false, isDefault = false
    }

    /// Reads language and flag words. "hi" is a flag when a language is also present, else it is Hindi.
    private static func readTokens(_ tokens: [String], into flags: inout Flags) -> LanguageTag? {
        var language: LanguageTag?
        var sawHI = false
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            let low = t.lowercased()
            switch low {
            case "forced", "force", "foreign": flags.forced = true; i += 1; continue
            case "sdh": flags.sdh = true; i += 1; continue
            case "cc": flags.cc = true; i += 1; continue
            case "default": flags.isDefault = true; i += 1; continue
            case "hi": sawHI = true; i += 1; continue
            case "hearing", "impaired", "closed", "captions", "caption", "subs", "sub", "subtitle", "subtitles": i += 1; continue
            default: break
            }
            if language == nil {
                if i + 1 < tokens.count, let two = LanguageTag(t + "-" + tokens[i + 1]), two.region != nil || two.script != nil {
                    language = two
                    i += 2
                    continue
                }
                if t.count >= 2, let one = LanguageTag(t) { language = one }
            }
            i += 1
        }
        if sawHI {
            if language == nil { language = LanguageTag("hi") } else { flags.hi = true }
        }
        return language
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { ".-_ []()".contains($0) }).map(String.init)
    }

    private static func fold(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.lowercased() }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
    }

    private static func ext(of name: String) -> String { (name as NSString).pathExtension.lowercased() }

    private static func stem(of name: String) -> String { (name as NSString).deletingPathExtension }

    private static func isBoundary(_ s: String, after count: Int) -> Bool {
        if s.count == count { return true }
        let idx = s.index(s.startIndex, offsetBy: count)
        return ".-_ [](),".contains(s[idx])
    }

    private static let episodePattern = try? NSRegularExpression(pattern: "(?i)(?:^|[^a-z0-9])s(\\d{1,3})[ ._-]?e(\\d{1,4})(?:[^0-9]|$)|(?:^|[^a-z0-9])(\\d{1,2})x(\\d{2,3})(?:[^0-9]|$)")

    /// Title (letters and digits only) before a "S01E02" or "1x02" marker, plus the marker as a key.
    private static func episodeKey(_ folded: String) -> (title: String, key: String)? {
        guard let re = episodePattern else { return nil }
        let ns = folded as NSString
        guard let m = re.firstMatch(in: folded, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> Int? {
            let r = m.range(at: i)
            if r.location == NSNotFound { return nil }
            return Int(ns.substring(with: r))
        }
        let season = group(1) ?? group(3)
        let episode = group(2) ?? group(4)
        guard let s = season, let e = episode else { return nil }
        let titlePart = ns.substring(to: m.range.location)
        let title = titlePart.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        return (title, "s\(s)e\(e)")
    }
}
