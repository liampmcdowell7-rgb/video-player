import Foundation

// Sidecar `.nfo` files (the common NFO layout that Jellyfin and Emby also write). Pure parsing: no file or network access.
// Verified by tests with hand-written samples that follow the publicly documented NFO conventions;
// real-world files from other tools are untested (see docs/METADATA_LOCAL.md).

public enum NFOKind: String, Codable, Sendable {
    case movie, tvshow, episode
}

public struct CalendarDay: Equatable, Hashable, Codable, Sendable, Comparable {
    public var year: Int
    public var month: Int?
    public var day: Int?

    public init(year: Int, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month ?? 0, a.day ?? 0) < (b.year, b.month ?? 0, b.day ?? 0)
    }

    /// Reads "2019-04-26", "2019-04-26 00:00:00", "2019/4/26", "26.04.2019" or "2019".
    public init?(parsing raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = text.split(whereSeparator: { "-/. T:".contains($0) }).compactMap { Int($0) }
        guard let first = parts.first else { return nil }
        if first >= 1000, first <= 9999 {
            self.init(year: first, month: parts.count > 1 && (1...12).contains(parts[1]) ? parts[1] : nil,
                      day: parts.count > 2 && (1...31).contains(parts[2]) ? parts[2] : nil)
        } else if parts.count >= 3, parts[2] >= 1000, parts[2] <= 9999, (1...31).contains(first), (1...12).contains(parts[1]) {
            self.init(year: parts[2], month: parts[1], day: first)
        } else {
            return nil
        }
    }
}

public struct NFORating: Equatable, Codable, Sendable {
    /// "imdb", "themoviedb", "critic", "user" ... lowercased. Nil for the legacy single `<rating>`.
    public var name: String?
    public var value: Double
    public var votes: Int?
    /// The top of the scale (10 for most, 100 for critic scores).
    public var max: Double?
    public var isDefault: Bool

    public init(name: String?, value: Double, votes: Int? = nil, max: Double? = nil, isDefault: Bool = false) {
        self.name = name
        self.value = value
        self.votes = votes
        self.max = max
        self.isDefault = isDefault
    }
}

public struct NFOPerson: Equatable, Codable, Sendable {
    public var name: String
    public var role: String?
    public var order: Int?
    public var thumb: String?

    public init(name: String, role: String? = nil, order: Int? = nil, thumb: String? = nil) {
        self.name = name
        self.role = role
        self.order = order
        self.thumb = thumb
    }
}

public struct NFOUniqueID: Equatable, Codable, Sendable {
    /// "tmdb", "imdb", "tvdb" ... lowercased.
    public var type: String
    public var value: String
    public var isDefault: Bool

    public init(type: String, value: String, isDefault: Bool = false) {
        self.type = type
        self.value = value
        self.isDefault = isDefault
    }
}

public enum NFOArtworkKind: String, Codable, Sendable {
    case poster, banner, landscape, clearlogo, clearart, discart, fanart, thumb, other
}

public struct NFOArtwork: Equatable, Codable, Sendable {
    public var kind: NFOArtworkKind
    /// A URL or a path relative to the nfo, exactly as written.
    public var location: String
    /// For season posters. 0 is specials, -1 is "all seasons" (NFO files write `season="-1"`).
    public var season: Int?

    public init(kind: NFOArtworkKind, location: String, season: Int? = nil) {
        self.kind = kind
        self.location = location
        self.season = season
    }
}

/// An nfo that only holds a link, which the NFO conventions allow (`https://www.themoviedb.org/movie/603`).
public struct NFOLink: Equatable, Codable, Sendable {
    public enum Service: String, Codable, Sendable { case tmdb, imdb, tvdb, other }
    public var url: String
    public var service: Service
    public var id: String?
    /// "movie" or "tv" when the link says so.
    public var mediaType: String?

    public init(url: String, service: Service, id: String?, mediaType: String?) {
        self.url = url
        self.service = service
        self.id = id
        self.mediaType = mediaType
    }
}

public struct NFOMetadata: Equatable, Codable, Sendable {
    public var kind: NFOKind
    public var title: String?
    public var originalTitle: String?
    public var sortTitle: String?
    /// For episodes: the series title, when written.
    public var showTitle: String?
    public var year: Int?
    /// `<premiered>` or `<releasedate>` for movies and shows, `<aired>` for episodes.
    public var premiered: CalendarDay?
    public var plot: String?
    public var outline: String?
    public var tagline: String?
    public var runtimeMinutes: Int?
    public var genres: [String] = []
    public var studios: [String] = []
    public var countries: [String] = []
    public var tags: [String] = []
    /// `<mpaa>` or `<certification>`, as written ("PG-13", "Rated R", "US:TV-MA").
    public var certification: String?
    public var ratings: [NFORating] = []
    public var uniqueIDs: [NFOUniqueID] = []
    public var tmdbID: Int?
    public var imdbID: String?
    public var tvdbID: Int?
    /// Collection (the NFO `<set>` element): its name and, when given, its TMDB id.
    public var collectionName: String?
    public var collectionTMDBID: Int?
    public var actors: [NFOPerson] = []
    public var directors: [String] = []
    public var writers: [String] = []
    public var artwork: [NFOArtwork] = []
    public var trailer: String?
    public var season: Int?
    public var episode: Int?
    /// Shown-as numbers for specials placement (`displayseason` / `displayepisode`).
    public var displaySeason: Int?
    public var displayEpisode: Int?
    public var playCount: Int?
    public var resumePositionSeconds: Double?
    public var resumeTotalSeconds: Double?

    public init(kind: NFOKind) { self.kind = kind }

    public func uniqueID(_ type: String) -> String? {
        let wanted = type.lowercased()
        let matches = uniqueIDs.filter { $0.type == wanted }
        return (matches.first { $0.isDefault } ?? matches.first)?.value
    }
}

public struct NFOFile: Equatable, Codable, Sendable {
    /// One entry per `<movie>`, `<tvshow>` or `<episodedetails>` element, in file order.
    public var documents: [NFOMetadata]
    /// A link found in the file: either the whole file, or text after the XML.
    public var link: NFOLink?
    /// Plain-language notes about anything that had to be repaired or ignored.
    public var warnings: [String]

    public init(documents: [NFOMetadata] = [], link: NFOLink? = nil, warnings: [String] = []) {
        self.documents = documents
        self.link = link
        self.warnings = warnings
    }
}

public enum NFOParser {
    /// Never throws: an unreadable file gives an empty result with a warning.
    public static func parse(_ data: Data) -> NFOFile {
        parse(text: NFOXML.decode(data))
    }

    public static func parse(text: String) -> NFOFile {
        var file = NFOFile()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            file.warnings.append("The nfo file is empty.")
            return file
        }
        if !trimmed.contains("<") {
            if let link = parseLink(trimmed) {
                file.link = link
            } else {
                file.warnings.append("The nfo file has no XML and no recognised link.")
            }
            return file
        }

        let (root, wellFormed) = NFOXML.tree(from: text)
        if !wellFormed { file.warnings.append("The nfo XML is malformed; the part that could be read was used.") }

        for node in root.children {
            switch node.name {
            case "movie": file.documents.append(makeMetadata(node, kind: .movie))
            case "tvshow": file.documents.append(makeMetadata(node, kind: .tvshow))
            case "episodedetails": file.documents.append(makeMetadata(node, kind: .episode))
            default: continue
            }
        }
        // Text left outside every element, for example a trailing "https://www.themoviedb.org/movie/603".
        if let link = parseLink(root.trimmed) { file.link = link }
        if file.documents.isEmpty, file.link == nil {
            file.warnings.append("The nfo file has no movie, tvshow or episodedetails element.")
        }
        return file
    }

    // MARK: link

    private static let urlRegex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+")

    static func parseLink(_ text: String) -> NFOLink? {
        guard let regex = urlRegex else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let url = ns.substring(with: match.range)
        let lower = url.lowercased()
        func capture(_ pattern: String) -> String? {
            guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let m = r.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)),
                  m.numberOfRanges > 1 else { return nil }
            return (url as NSString).substring(with: m.range(at: 1))
        }
        if lower.contains("themoviedb.org") {
            let type = capture("themoviedb\\.org/(movie|tv)/") ?? nil
            let id = capture("themoviedb\\.org/(?:movie|tv)/([0-9]+)")
            return NFOLink(url: url, service: .tmdb, id: id, mediaType: type?.lowercased())
        }
        if lower.contains("imdb.com") {
            return NFOLink(url: url, service: .imdb, id: capture("(tt[0-9]{6,})"), mediaType: nil)
        }
        if lower.contains("thetvdb.com") {
            let id = capture("[?&]id=([0-9]+)") ?? capture("/series/([0-9]+)")
            return NFOLink(url: url, service: .tvdb, id: id, mediaType: "tv")
        }
        return NFOLink(url: url, service: .other, id: nil, mediaType: nil)
    }

    // MARK: element mapping

    private static func int(_ text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(digits) { return v }
        // "120 min", "2h"-style values: take the leading integer.
        let lead = digits.prefix { $0.isNumber || $0 == "-" }
        return Int(lead)
    }

    private static func double(_ text: String?) -> Double? {
        guard let text else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
    }

    private static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = NFOXML.plainText(text)
        return value.isEmpty ? nil : value
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func bool(_ text: String?) -> Bool {
        guard let t = text?.lowercased() else { return false }
        return t == "true" || t == "1" || t == "yes"
    }

    static func makeMetadata(_ node: NFOElement, kind: NFOKind) -> NFOMetadata {
        var m = NFOMetadata(kind: kind)
        m.title = clean(node.string("title"))
        m.originalTitle = clean(node.string("originaltitle"))
        m.sortTitle = clean(node.string("sorttitle"))
        m.showTitle = clean(node.string("showtitle"))
        m.plot = clean(node.string("plot"))
        m.outline = clean(node.string("outline"))
        m.tagline = clean(node.string("tagline"))

        let dateText = kind == .episode
            ? (node.string("aired") ?? node.string("premiered") ?? node.string("releasedate"))
            : (node.string("premiered") ?? node.string("releasedate") ?? node.string("aired"))
        m.premiered = dateText.flatMap { CalendarDay(parsing: $0) }
        m.year = int(node.string("year")).flatMap { (1000...9999).contains($0) ? $0 : nil } ?? m.premiered?.year

        m.runtimeMinutes = int(node.string("runtime"))
        if m.runtimeMinutes == nil || m.runtimeMinutes == 0 {
            if let seconds = double(node.first("fileinfo")?.first("streamdetails")?.first("video")?.string("durationinseconds")), seconds > 0 {
                m.runtimeMinutes = Int((seconds / 60).rounded())
            } else {
                m.runtimeMinutes = nil
            }
        }

        m.genres = unique(node.strings("genre"))
        m.studios = unique(node.strings("studio"))
        m.countries = unique(node.strings("country"))
        m.tags = unique(node.strings("tag"))
        m.certification = node.string("mpaa") ?? node.string("certification")
        m.directors = unique(node.strings("director"))
        m.writers = unique(node.strings("credits") + node.strings("writer"))
        m.trailer = node.string("trailer")

        // Ratings: the newer `<ratings>` block, then the legacy `<rating>` / `<votes>` pair.
        var ratings: [NFORating] = []
        for r in node.first("ratings")?.all("rating") ?? [] {
            guard let value = double(r.string("value")) else { continue }
            ratings.append(NFORating(
                name: r.attributes["name"]?.lowercased(), value: value,
                votes: int(r.string("votes")?.replacingOccurrences(of: ",", with: "")),
                max: double(r.attributes["max"]), isDefault: bool(r.attributes["default"])))
        }
        if ratings.isEmpty {
            for r in node.all("rating") where r.children.isEmpty {
                if let value = double(r.trimmed) {
                    ratings.append(NFORating(name: nil, value: value,
                                             votes: int(node.string("votes")?.replacingOccurrences(of: ",", with: "")),
                                             max: nil, isDefault: true))
                    break
                }
            }
        }
        if let critic = double(node.string("criticrating")) {
            ratings.append(NFORating(name: "critic", value: critic, votes: nil, max: 100, isDefault: false))
        }
        if let user = double(node.string("userrating")), user > 0 {
            ratings.append(NFORating(name: "user", value: user, votes: nil, max: 10, isDefault: false))
        }
        m.ratings = ratings

        // Identifiers.
        var ids: [NFOUniqueID] = []
        for u in node.all("uniqueid") {
            let value = u.trimmed
            guard !value.isEmpty else { continue }
            let type = (u.attributes["type"] ?? "").lowercased()
            ids.append(NFOUniqueID(type: type.isEmpty ? "unknown" : type, value: value, isDefault: bool(u.attributes["default"])))
        }
        if let legacy = node.string("tmdbid"), !ids.contains(where: { $0.type == "tmdb" }) { ids.append(NFOUniqueID(type: "tmdb", value: legacy)) }
        if let legacy = node.string("imdbid") ?? node.string("imdb_id"), !ids.contains(where: { $0.type == "imdb" }) { ids.append(NFOUniqueID(type: "imdb", value: legacy)) }
        if let legacy = node.string("tvdbid") ?? node.string("tvdb_id"), !ids.contains(where: { $0.type == "tvdb" }) { ids.append(NFOUniqueID(type: "tvdb", value: legacy)) }
        // Some NFO files have a bare `<id>`: tt-prefixed means IMDb, digits mean the show's TVDB id.
        if let bare = node.string("id") {
            if bare.lowercased().hasPrefix("tt"), !ids.contains(where: { $0.type == "imdb" }) {
                ids.append(NFOUniqueID(type: "imdb", value: bare))
            } else if kind == .tvshow, Int(bare) != nil, !ids.contains(where: { $0.type == "tvdb" }) {
                ids.append(NFOUniqueID(type: "tvdb", value: bare))
            }
        }
        m.uniqueIDs = ids
        m.tmdbID = int(m.uniqueID("tmdb"))
        m.imdbID = m.uniqueID("imdb").flatMap { $0.lowercased().hasPrefix("tt") ? $0 : nil }
        m.tvdbID = int(m.uniqueID("tvdb"))

        // Collection.
        if let set = node.first("set") {
            if set.children.isEmpty {
                m.collectionName = set.trimmed.isEmpty ? nil : set.trimmed
            } else {
                m.collectionName = set.string("name")
                m.collectionTMDBID = int(set.string("tmdbcolid") ?? set.string("tmdbid"))
            }
        }
        if m.collectionTMDBID == nil { m.collectionTMDBID = int(node.string("tmdbcolid")) }

        // People.
        m.actors = node.all("actor").compactMap { a in
            guard let name = a.string("name") else { return nil }
            return NFOPerson(name: name, role: a.string("role"), order: int(a.string("order")), thumb: a.string("thumb"))
        }

        // Artwork.
        var art: [NFOArtwork] = []
        for t in node.all("thumb") {
            let location = t.trimmed
            guard !location.isEmpty else { continue }
            let aspect = (t.attributes["aspect"] ?? "").lowercased()
            let type = (t.attributes["type"] ?? "").lowercased()
            let kindValue: NFOArtworkKind
            switch aspect {
            case "poster": kindValue = .poster
            case "banner": kindValue = .banner
            case "landscape": kindValue = .landscape
            case "clearlogo": kindValue = .clearlogo
            case "clearart": kindValue = .clearart
            case "discart": kindValue = .discart
            default: kindValue = (type == "season") ? .poster : .thumb
            }
            art.append(NFOArtwork(kind: kindValue, location: location, season: int(t.attributes["season"])))
        }
        for t in node.first("fanart")?.all("thumb") ?? [] where !t.trimmed.isEmpty {
            art.append(NFOArtwork(kind: .fanart, location: t.trimmed))
        }
        if let block = node.first("art") {
            for (name, kindValue) in [("poster", NFOArtworkKind.poster), ("fanart", .fanart), ("banner", .banner),
                                      ("landscape", .landscape), ("clearlogo", .clearlogo), ("clearart", .clearart), ("discart", .discart)] {
                if let location = block.string(name) { art.append(NFOArtwork(kind: kindValue, location: location)) }
            }
        }
        m.artwork = art

        // Episode and watch state.
        m.season = int(node.string("season"))
        m.episode = int(node.string("episode"))
        m.displaySeason = int(node.string("displayseason"))
        m.displayEpisode = int(node.string("displayepisode"))
        m.playCount = int(node.string("playcount"))
        if let resume = node.first("resume") {
            m.resumePositionSeconds = double(resume.string("position"))
            m.resumeTotalSeconds = double(resume.string("total"))
        }
        return m
    }
}
