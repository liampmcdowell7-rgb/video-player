import Foundation
import MetadataOnline
import UserData

// R455 (owner's request of 23 Nov 2026, "choices of artwork"; PROVISIONAL): every title has a gallery of candidate pictures per
// kind, and the user's choice is an artwork override of the user layer (`UDEditField` poster, backdrop, logo, seasonPoster,
// episodeStill). This file is the pure part: the kinds, the candidates, their plain-word labels, the filter, the order, and
// the rule that the override beats every source. The screens only draw it.

/// The kinds of picture a gallery chooses, one gallery screen each.
public enum ArtworkGalleryKind: String, CaseIterable, Sendable {
    case poster, background, logo, seasonPoster, episodeStill

    /// The user-layer field that stores the choice.
    public var field: UDEditField {
        switch self {
        case .poster: return .poster
        case .background: return .backdrop
        case .logo: return .logo
        case .seasonPoster: return .seasonPoster
        case .episodeStill: return .episodeStill
        }
    }

    public var title: String {
        switch self {
        case .poster: return "Poster"
        case .background: return "Background"
        case .logo: return "Logo"
        case .seasonPoster: return "Season Poster"
        case .episodeStill: return "Episode Still"
        }
    }

    /// R471 (36), PROVISIONAL (Plex Change Artwork photos: each kind says what it is used for): one sentence of our own,
    /// under the gallery's controls, saying where this app shows the picture.
    public var purpose: String {
        switch self {
        case .poster: return "Posters are shown in the library's grids and on shelves."
        case .background: return "The background is shown behind the title's page."
        case .logo: return "The logo is shown in place of the title's name on its page. One with a clear background works best."
        case .seasonPoster: return "The season poster is shown beside the season on the show's page."
        case .episodeStill: return "The still is shown on the episode's card and behind the episode's page."
        }
    }

    /// Width over height of a candidate's tile: posters 2:3, backgrounds and stills 16:9 (the owner's spec). A logo tile is
    /// drawn wide (16:9) so its lettering has room; the logo itself keeps its own shape inside.
    public var aspectRatio: Double {
        switch self {
        case .poster, .seasonPoster: return 2.0 / 3.0
        case .background, .episodeStill, .logo: return 16.0 / 9.0
        }
    }

    /// The small size name used for thumbnails (TMDB's size lists: poster w342, backdrop w780, logo w185, still w300). The
    /// full size is fetched only for the chosen picture. PROVISIONAL (R455).
    public var thumbnailSize: String {
        switch self {
        case .poster, .seasonPoster: return "w342"
        case .background: return "w780"
        case .logo: return "w185"
        case .episodeStill: return "w300"
        }
    }

    /// The kinds a level offers: movie and show have poster, background and logo; a season only its poster; an episode only
    /// its still (16:9).
    public static func kinds(for level: Level) -> [ArtworkGalleryKind] {
        switch level {
        case .movie, .show: return [.poster, .background, .logo]
        case .season: return [.seasonPoster]
        case .episode: return [.episodeStill]
        }
    }

    public enum Level: Sendable { case movie, show, season, episode }
}

/// Where a candidate comes from, in the order the gallery lists them, with the source named in plain text.
public enum ArtworkSourceKind: Int, CaseIterable, Comparable, Sendable {
    case online = 0, yourFiles, server, webAddress
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var title: String {
        switch self {
        case .online: return "Online"
        case .yourFiles: return "From Your Files"
        case .server: return "From the Server"
        case .webAddress: return "Web Address"
        }
    }
}

/// One candidate picture.
public struct ArtworkCandidate: Identifiable, Hashable, Sendable {
    public enum Origin: Hashable, Sendable {
        /// The supplier's file path ("/abc.jpg"); the thumbnail and the full size are built from it.
        case online(String)
        /// A picture next to the media: source and path.
        case yourFile(sourceID: String, path: String)
        /// A picture the media server holds, by its cache key.
        case server(String)
    }

    public var id: String
    public var source: ArtworkSourceKind
    public var origin: Origin
    /// ISO 639-1 code as the source gave it; nil for a picture without text.
    public var languageCode: String?
    public var width: Int?
    public var height: Int?
    /// The source's own rating (TMDB vote average), 0 when it has none.
    public var rating: Double

    public init(source: ArtworkSourceKind, origin: Origin, languageCode: String? = nil, width: Int? = nil, height: Int? = nil, rating: Double = 0) {
        self.source = source
        self.origin = origin
        self.languageCode = languageCode
        self.width = width
        self.height = height
        self.rating = rating
        switch origin {
        case let .online(p): id = "online:" + p
        case let .yourFile(s, p): id = "file:" + s + "|" + p
        case let .server(k): id = "server:" + k
        }
    }

    /// The value stored in the user layer when this candidate is chosen and it is an online picture. A picture of any other
    /// origin is copied into the user-artwork folder first (the app does that) and stored as `.file(name)`.
    public var onlineChoice: UDEditArtwork? {
        if case let .online(p) = origin { return .online(p) }
        return nil
    }

    /// "English", "No Text", or the language's name in the user's language. Never a code alone.
    public func languageName(locale: Locale = .current) -> String { ArtworkCandidates.languageName(code: languageCode, locale: locale) }

    /// "2000 × 3000" as plain text, or nil when the source gave no size.
    public var pixelSizeText: String? {
        guard let w = width, let h = height, w > 0, h > 0 else { return nil }
        return "\(w) × \(h)"
    }
}

/// The language filter at the top of the gallery (a system menu): the user's language and No Text first, then All Languages.
public enum ArtworkLanguageFilter: Hashable, Sendable {
    case all
    case noText
    case language(String)

    public func includes(_ candidate: ArtworkCandidate) -> Bool {
        switch self {
        case .all: return true
        case .noText: return ArtworkCandidates.normalized(candidate.languageCode) == nil
        case let .language(code): return ArtworkCandidates.normalized(candidate.languageCode) == code.lowercased()
        }
    }

    public func title(locale: Locale = .current) -> String {
        switch self {
        case .all: return "All Languages"
        case .noText: return "No Text"
        case let .language(code): return ArtworkCandidates.languageName(code: code, locale: locale)
        }
    }
}

public enum ArtworkCandidates {
    /// "xx" is TMDB's textless marker in some lists; an empty code is none.
    static func normalized(_ code: String?) -> String? {
        guard let code = code?.trimmingCharacters(in: .whitespaces).lowercased(), !code.isEmpty, code != "xx", code != "none" else { return nil }
        return code
    }

    public static func languageName(code: String?, locale: Locale = .current) -> String {
        guard let code = normalized(code) else { return "No Text" }
        return locale.localizedString(forLanguageCode: code)?.localizedCapitalized ?? "Other Language"
    }

    /// The online candidates of one kind from the supplier's list. Nothing is invented for a kind with no pictures.
    public static func online(_ refs: [ImageRef]) -> [ArtworkCandidate] {
        var seen = Set<String>()
        return refs.compactMap { ref in
            guard seen.insert(ref.path).inserted else { return nil }
            return ArtworkCandidate(source: .online, origin: .online(ref.path), languageCode: ref.language, width: ref.width, height: ref.height, rating: ref.voteAverage ?? 0)
        }
    }

    /// The online candidates of a kind from an image set.
    public static func online(_ set: ImageSet, kind: ArtworkGalleryKind) -> [ArtworkCandidate] {
        switch kind {
        case .poster, .seasonPoster: return online(set.posters)
        case .background: return online(set.backdrops)
        case .logo: return online(set.logos)
        case .episodeStill: return []
        }
    }

    /// The gallery's order: the sources in their fixed order (Online, From Your Files, From the Server, Web Address); inside a
    /// source the user's language first, then No Text, then the other languages; then the source's own rating, then the
    /// larger size. Ties keep the source's own order (stable).
    public static func sorted(_ candidates: [ArtworkCandidate], userLanguage: String?) -> [ArtworkCandidate] {
        let user = userLanguage.flatMap { normalized(String($0.prefix(2))) }
        func languageRank(_ c: ArtworkCandidate) -> Int {
            let code = normalized(c.languageCode)
            if let user, code == user { return 0 }
            if code == nil { return 1 }
            return 2
        }
        return candidates.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.source != y.source { return x.source < y.source }
            let (lx, ly) = (languageRank(x), languageRank(y))
            if lx != ly { return lx < ly }
            if x.rating != y.rating { return x.rating > y.rating }
            let (ax, ay) = ((x.width ?? 0) * (x.height ?? 0), (y.width ?? 0) * (y.height ?? 0))
            if ax != ay { return ax > ay }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The filter choices for a list: the user's language and No Text first (when present), then the other languages that
    /// occur, then All Languages last in the menu's order of use (the default selection is the first entry).
    public static func filters(for candidates: [ArtworkCandidate], userLanguage: String?, locale: Locale = .current) -> [ArtworkLanguageFilter] {
        var out: [ArtworkLanguageFilter] = []
        let present = Set(candidates.compactMap { normalized($0.languageCode) })
        let hasNoText = candidates.contains { normalized($0.languageCode) == nil }
        if let user = userLanguage.flatMap({ normalized(String($0.prefix(2))) }), present.contains(user) { out.append(.language(user)) }
        if hasNoText { out.append(.noText) }
        let others = present.subtracting(out.compactMap { if case let .language(c) = $0 { return c } else { return nil } })
            .sorted { languageName(code: $0, locale: locale) < languageName(code: $1, locale: locale) }
        out += others.map { .language($0) }
        out.append(.all)
        return out
    }

    /// The filter a gallery opens with: the first entry that has candidates (the user's language, then No Text), else All.
    public static func defaultFilter(for candidates: [ArtworkCandidate], userLanguage: String?, locale: Locale = .current) -> ArtworkLanguageFilter {
        filters(for: candidates, userLanguage: userLanguage, locale: locale).first ?? .all
    }

    public static func filtered(_ candidates: [ArtworkCandidate], by filter: ArtworkLanguageFilter) -> [ArtworkCandidate] {
        candidates.filter { filter.includes($0) }
    }
}

/// What a gallery screen says: its candidates, why it may be empty, and the line about the Online Lookup switch.
public struct ArtworkGallery: Equatable, Sendable {
    public var kind: ArtworkGalleryKind
    public var candidates: [ArtworkCandidate]
    /// Settings > Online Lookup was off, so the online pictures were not asked for (R209).
    public var onlineSwitchOff: Bool

    public init(kind: ArtworkGalleryKind, candidates: [ArtworkCandidate], onlineSwitchOff: Bool) {
        self.kind = kind
        self.candidates = candidates
        self.onlineSwitchOff = onlineSwitchOff
    }

    public static let onlineOffLine = "Online pictures need Online Lookup in Settings."

    public var isEmpty: Bool { candidates.isEmpty }

    /// The empty state's sentence: what the kind lacks, in plain words.
    public var emptyText: String {
        "No \(kind.title.lowercased()) pictures were found for this title. You can add one from a web address."
    }
}

/// The override beats every source (R455 item 4): a stored choice that can be shown wins, otherwise the automatic rule shows.
public enum ArtworkOverride {
    /// What a stored choice draws, given what the app can reach. `nil` means "no override": the automatic rule decides.
    public enum Resolved: Equatable, Sendable {
        case file(String)
        case online(String)
    }

    public static func resolve(_ value: UDEditValue?, onlineAvailable: Bool) -> Resolved? {
        switch value?.artwork {
        case let .file(name)?: return .file(name)
        // An online choice is copied into the artwork store when it is made, so it normally arrives as a file; one that was
        // synced from another device before its file arrived still shows online, when the switch is on.
        case let .online(path)? where onlineAvailable: return .online(path)
        default: return nil
        }
    }

    /// The picture to draw: the override when there is one, else the automatic result.
    public static func pick<T>(override: T?, automatic: () async -> T) async -> T {
        if let override { return override }
        return await automatic()
    }
}

/// The artwork override the engine asks for before any source. The app implements it with the user layer and the user-artwork
/// folder (AppLogic has no folder): the key is the artwork key ("item-42", "series-7").
public protocol ArtworkOverriding: Sendable {
    func override(key: String, field: UDEditField) async -> ArtworkResult?
}
