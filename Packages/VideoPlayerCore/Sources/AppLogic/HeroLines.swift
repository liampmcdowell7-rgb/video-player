import Foundation
import VideoPlayerCore
import LibraryIndex

/// R471 item 2 (owner's request R471, Part 2 (c), (e), (f); frames of the Apple TV app on tvOS 27: episode t00s, show t08s
/// and t10s, movie t00s; PROVISIONAL): the lines of text in a product page's hero, in the frames' order:
///
/// 1. (an episode) the show's name, small, above the large title;
/// 2. the title (or clear logo);
/// 3. the KIND line: the source's glyph, "Movie" or "TV Show" (none for an episode), the genres, the age rating in an
///    outlined box;
/// 4. the description, an episode's starting with its code ("S4, E4:");
/// 5. the FACTS line: the date (an episode's full air date, a movie's or show's year) and the duration, then the format
///    badges as small outlined glyph badges.
///
/// Our own wording, no brand marks: the source glyph is a generic system symbol per kind of source, never a service's logo.
/// Pure logic; App/Shared/HeroLinesView.swift draws it.
public enum HeroLines {
    public enum Kind: Sendable { case movie, show, episode }

    /// One part of a hero line.
    public enum Segment: Equatable, Hashable, Sendable {
        /// A system symbol and what VoiceOver says for it.
        case glyph(symbol: String, spoken: String)
        case text(String)
        /// The age rating, the line's only box (R371's rating, R471 (f)).
        case ratingBox(String)
    }

    /// The word for the kind, as the frames show it; nil for an episode (its show's name is above its title).
    public static func kindWord(_ kind: Kind) -> String? {
        switch kind {
        case .movie: return "Movie"
        case .show: return "TV Show"
        case .episode: return nil
        }
    }

    /// At most this many genres on the kind line (the frames show two or three). The rest are in About.
    public static let genreLimit = 3

    /// Line 3: glyph, kind word, genres, rating box. Parts with no data are left out; empty when nothing is known.
    public static func kindLine(kind: Kind, source: SourceKind?, genres: [String], rating: String?) -> [Segment] {
        var out: [Segment] = []
        if let source { out.append(.glyph(symbol: SourceGlyph.symbol(source), spoken: SourceGlyph.spoken(source))) }
        if let word = kindWord(kind) { out.append(.text(word)) }
        var seen: Set<String> = []
        for genre in genres {
            let g = genre.trimmingCharacters(in: .whitespaces)
            guard !g.isEmpty, seen.insert(g.lowercased()).inserted else { continue }
            out.append(.text(g))
            if seen.count == genreLimit { break }
        }
        if let rating = rating?.trimmingCharacters(in: .whitespaces), !rating.isEmpty { out.append(.ratingBox(rating)) }
        // A glyph alone says nothing.
        if out.count == 1, case .glyph = out[0] { return [] }
        return out
    }

    /// Line 5's text part: the date and the duration ("Aug 26, 2026 · 43m", "1973 · 25m"). An episode gives its full date
    /// when known; a movie and a show give the year only, as the frames do.
    public static func factsText(kind: Kind, date: PartialDate?, year: Int?, durationSeconds: Double?, locale: Locale = .current) -> [String] {
        var out: [String] = []
        switch kind {
        case .episode:
            if let date { out.append(InfoDateText.text(date, locale: locale)) } else if let year, year > 0 { out.append(String(year)) }
        case .movie, .show:
            if let y = date?.year ?? year, y > 0 { out.append(String(y)) }
        }
        if let d = durationSeconds, d > 0 { out.append(ShortDuration.text(d)) }
        return out
    }

    /// Line 4: an episode's description starts with its code and a colon ("S4, E4:"), drawn in the semibold weight; nil
    /// prefix for a movie or a show's own description. The text itself is never invented: no text, no line.
    public static func episodePrefix(code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespaces), !code.isEmpty else { return nil }
        return code + ":"
    }

    /// The show page's next-up description starts with the episode's code and title ("S4, E4 · Title:").
    public static func nextUpPrefix(code: String?, title: String?) -> String? {
        let parts = [code, title].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + ":"
    }
}

/// R471 item 2: a generic system symbol for each kind of source, never a service's logo (rule: real names as text only).
public enum SourceGlyph {
    public static func symbol(_ kind: SourceKind) -> String {
        switch kind {
        case .plex, .jellyfin, .emby: return "server.rack"
        case .smb, .nfs, .webdav, .sftp, .ftp: return "externaldrive.connected.to.line.below"
        case .upnp: return "network"
        case .googleDrive, .oneDrive, .dropbox: return "cloud"
        case .directLink: return "link"
        }
    }

    /// What the glyph means, spoken.
    public static func spoken(_ kind: SourceKind) -> String {
        switch kind {
        case .plex, .jellyfin, .emby: return "Media server"
        case .smb, .nfs, .webdav, .sftp, .ftp: return "Network folder"
        case .upnp: return "Network media"
        case .googleDrive, .oneDrive, .dropbox: return "Cloud storage"
        case .directLink: return "Link"
        }
    }
}

/// R471 (d) and item 2: a duration in the short form of the frames' hero and Play button ("43m", "1h 52m", "2h").
public enum ShortDuration {
    public static func text(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0m" }
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// The time left, rounded UP to the minute so a few seconds left still say "1m", for the Play button.
    public static func left(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

/// R471 item 2 (e): the access features a file offers, from its own tracks. Never guessed beyond what the tracks say.
public enum AccessFeature: String, CaseIterable, Hashable, Sendable {
    /// Closed captions carried as a caption track (CEA-608 or CEA-708).
    case cc
    /// Subtitles for the deaf and hard of hearing: a subtitle track the file marks as such.
    case sdh
    /// Audio description: an audio track the file names as a description of what is on screen.
    case ad

    public var badgeText: String {
        switch self {
        case .cc: return "CC"
        case .sdh: return "SDH"
        case .ad: return "AD"
        }
    }

    public var spoken: String {
        switch self {
        case .cc: return "Closed captions"
        case .sdh: return "Subtitles for the deaf and hard of hearing"
        case .ad: return "Audio description"
        }
    }

    /// Our own sentence for the Accessibility column (R471 item 4), what the badge means.
    public var explanation: String {
        switch self {
        case .cc: return "Closed captions (CC) show the dialogue and other sounds as text, carried in the video."
        case .sdh: return "Subtitles for the deaf and hard of hearing (SDH) add sounds and speaker names to the dialogue."
        case .ad: return "Audio description (AD) is a soundtrack with a voice that describes what happens on screen."
        }
    }

    /// The features of a file, in the frames' order (CC, SDH, AD). Nil tracks (not read yet) give none.
    public static func detect(_ tracks: FileTrackDetails?) -> [AccessFeature] {
        guard let tracks else { return [] }
        var found: Set<AccessFeature> = []
        for s in tracks.subtitles {
            let codec = s.codec.lowercased()
            if codec.contains("608") || codec.contains("708") { found.insert(.cc) }
            if s.isHearingImpaired { found.insert(.sdh) }
        }
        for a in tracks.audio where isDescription(a.name) { found.insert(.ad) }
        return allCases.filter { found.contains($0) }
    }

    /// An audio track's name that says it describes the picture ("Audio Description", "Descriptive Audio", "English AD").
    static func isDescription(_ name: String?) -> Bool {
        guard let n = name?.lowercased(), !n.isEmpty else { return false }
        if n.contains("audio description") || n.contains("descriptive") || n.contains("described video") || n.contains("visually impaired") { return true }
        return n.split(whereSeparator: { !$0.isLetter }).contains("ad")
    }
}

/// R471 item 2 (e): one small outlined glyph badge of the facts line. A two-word name is two short lines ("Dolby" over
/// "Vision"), so every badge is about one text line tall, as the frames' glyphs are; never a logo, the names as text.
public struct HeroBadge: Hashable, Sendable {
    public var lines: [String]
    public var spoken: String

    public init(lines: [String], spoken: String) {
        self.lines = lines
        self.spoken = spoken
    }
}

public enum HeroBadges {
    /// The resolution as the frames name it: "4K", "HD" (1080p and 720p), "SD". Not "1080p" (owner, R471 (e)).
    public static func resolutionText(_ text: String) -> String {
        switch text {
        case "1080p", "720p": return "HD"
        default: return text
        }
    }

    /// The badges of the facts line: resolution, HDR, audio format (the headline groups, R370), then CC, SDH, AD.
    public static func make(format: [FormatBadgeItem], access: [AccessFeature]) -> [HeroBadge] {
        var out: [HeroBadge] = []
        for item in format where FormatBadges.headlineGroups.contains(item.group) {
            let text = item.group == .resolution ? resolutionText(item.text) : item.text
            out.append(HeroBadge(lines: lines(text), spoken: FormatBadgeItem(item.group, text).spokenLabel))
        }
        out += access.map { HeroBadge(lines: [$0.badgeText], spoken: $0.spoken) }
        return out
    }

    /// "Dolby Vision" → ["Dolby", "Vision"]; one word stays one line.
    static func lines(_ text: String) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 2 else { return [text] }
        return words
    }
}
