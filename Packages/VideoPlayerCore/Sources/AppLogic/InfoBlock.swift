import Foundation

/// R453 (owner's recording IMG_1427.mov, 23 Nov 2026; PROVISIONAL): a date as far as it is known. A release or air date
/// whose month or day is unknown shows only what is known ("Mar 2021", "2021"), never an invented "1 Jan".
public struct PartialDate: Equatable, Hashable, Sendable {
    public var year: Int
    public var month: Int?
    public var day: Int?

    public init(year: Int, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "2021-03-05", "2021-03" or "2021"; nil for anything else.
    public init?(iso text: String?) {
        guard let text, !text.isEmpty else { return nil }
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(parts.count), let y = Int(parts[0]), (1800...2200).contains(y) else { return nil }
        let m: Int? = parts.count > 1 ? Int(parts[1]) : nil
        let d: Int? = parts.count > 2 ? Int(parts[2]) : nil
        if parts.count > 1 { guard let m, (1...12).contains(m) else { return nil } }
        if parts.count > 2 { guard let d, (1...31).contains(d) else { return nil } }
        self.init(year: y, month: m, day: d)
    }
}

/// The date as the system's date formatter writes it (medium date style, the user's region), on one line.
public enum InfoDateText {
    public static func text(_ date: PartialDate, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if let month = date.month, let day = date.day {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            guard let value = calendar.date(from: DateComponents(year: date.year, month: month, day: day)) else { return String(date.year) }
            return formatter.string(from: value)
        }
        if let month = date.month {
            formatter.setLocalizedDateFormatFromTemplate("yMMM")
            guard let value = calendar.date(from: DateComponents(year: date.year, month: month, day: 1)) else { return String(date.year) }
            return formatter.string(from: value)
        }
        return String(date.year)
    }
}

/// R453: ONE typed metadata line: runtime, release (or air) date, a content-rating box, resolution, audio format. A part
/// with no data is left out. Plain text except the rating, which is the line's only box.
public struct InfoLine: Equatable, Hashable, Sendable {
    public enum Segment: Equatable, Hashable, Sendable {
        case text(String)
        case ratingBox(String)
    }

    public var segments: [Segment]

    public init(runtime: String?, date: PartialDate?, contentRating: String?, resolution: String?, audio: String?, locale: Locale = .current) {
        var out: [Segment] = []
        func add(_ text: String?) { if let text, !text.isEmpty { out.append(.text(text)) } }
        add(runtime)
        add(date.map { InfoDateText.text($0, locale: locale) })
        if let contentRating, !contentRating.isEmpty { out.append(.ratingBox(contentRating)) }
        add(resolution)
        add(audio)
        segments = out
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// The line as one string (for VoiceOver and the tests): the parts joined by " · ".
    public var plain: String {
        segments.map { segment -> String in
            switch segment {
            case .text(let t): return t
            case .ratingBox(let r): return r
            }
        }.joined(separator: " · ")
    }
}

/// A score from one source: a system symbol and a number, no third-party name or logo.
public struct InfoRating: Equatable, Hashable, Sendable, Identifiable {
    public var id: String { symbol + value }
    public var symbol: String
    public var value: String

    public init(symbol: String, value: String) {
        self.symbol = symbol
        self.value = value
    }
}

/// What the info block of a show, season, episode or movie page says: the facts of one title.
public struct InfoFacts: Equatable, Sendable {
    public var runtime: String?
    public var date: PartialDate?
    public var contentRating: String?
    public var resolution: String?
    public var audio: String?
    public var genres: [String]
    public var ratings: [InfoRating]
    public var synopsis: String?

    public init(runtime: String? = nil, date: PartialDate? = nil, contentRating: String? = nil, resolution: String? = nil,
                audio: String? = nil, genres: [String] = [], ratings: [InfoRating] = [], synopsis: String? = nil) {
        self.runtime = runtime
        self.date = date
        self.contentRating = contentRating
        self.resolution = resolution
        self.audio = audio
        self.genres = genres
        self.ratings = ratings
        self.synopsis = synopsis
    }
}

/// The block under a show's buttons: it shows the FOCUSED episode, and the show's own data when focus is elsewhere
/// (R453, PROVISIONAL). Pure logic; the page only draws it.
public struct InfoBlock: Equatable, Hashable, Sendable {
    /// "S1 - E3 - Title" for an episode; nil for the show's own data (the page's large title says it).
    public var titleLine: String?
    public var line: InfoLine
    /// The genres on their own line, nil when none.
    public var genreLine: String?
    public var ratings: [InfoRating]
    public var synopsis: String?

    /// The title line of an episode: "S1 - E3 - Title".
    public static func episodeTitle(season: Int, episode: Int, title: String) -> String {
        "S\(season) - E\(episode) - \(title)"
    }

    /// The show's own block.
    public static func show(_ facts: InfoFacts) -> InfoBlock {
        make(titleLine: nil, facts)
    }

    /// The focused episode's block. A part the episode has no data for takes the show's where an episode inherits it
    /// (genres, content rating); the synopsis, the date, the runtime and the ratings are never borrowed from the show.
    public static func episode(season: Int, number: Int, title: String, facts: InfoFacts, show: InfoFacts) -> InfoBlock {
        var own = facts
        if own.genres.isEmpty { own.genres = show.genres }
        if own.contentRating == nil { own.contentRating = show.contentRating }
        return make(titleLine: episodeTitle(season: season, episode: number, title: title), own)
    }

    private static func make(titleLine: String?, _ f: InfoFacts) -> InfoBlock {
        InfoBlock(titleLine: titleLine,
                  line: InfoLine(runtime: f.runtime, date: f.date, contentRating: f.contentRating, resolution: f.resolution, audio: f.audio),
                  genreLine: f.genres.isEmpty ? nil : f.genres.joined(separator: ", "),
                  ratings: f.ratings,
                  synopsis: f.synopsis.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
    }

    /// What the block says for VoiceOver when it changes.
    public var spoken: String {
        [titleLine, line.isEmpty ? nil : line.plain, genreLine, synopsis].compactMap { $0 }.joined(separator: ". ")
    }
}

/// R453 (item 6): the numbers of the density target, all in ONE place: the first screen of the show page shows the info
/// block, the buttons, the season strip, the full episode shelf with its captions and the "Cast and Crew" heading.
public enum InfoBlockLayout {
    /// The synopsis lines reserved, so the block never changes height when focus moves.
    public static let synopsisLines: Int = 3
    /// The focus must rest this long before the block changes (seconds).
    public static let focusRestSeconds: Double = 0.15
    /// The share of the screen height the first screen's content should fill (about 88%).
    public static let firstScreenFill: Double = 0.88
    public static let crossFadeSeconds: Double = 0.2
    /// The show page's hero area is as high as its content (title, info block, buttons) and at least this share of the page, so
    /// the first screen also holds the season strip, the episode shelf with its captions and the "Cast and Crew" heading
    /// (the old hero took 0.8 of the page). Estimate, not measured: PROVISIONAL, the picture of the show page decides.
    public static let showHeroFraction: Double = 0.30
}

/// The round icon buttons of the page's button row (R453 item 3), by SF Symbol name; the same on show, season, episode and movie pages.
public enum PageButtonSymbols {
    public static let watched = "checkmark.circle"
    /// R471 (103), PROVISIONAL (frames show t08s, t10s; owner R471 Part 2: no eye on the hero): a plain check while
    /// something is left to watch, as the reference show page's round button. Was "eye" (R453).
    public static let unwatched = "checkmark"
    public static let favourite = "heart"
    public static let favouriteOn = "heart.fill"
    public static let more = "ellipsis"

    public static func watched(_ isWatched: Bool) -> String { isWatched ? watched : unwatched }
    public static func favourite(_ isOn: Bool) -> String { isOn ? favouriteOn : favourite }
}

public extension InfoFacts {
    /// A movie's or an episode's facts from its page content and details (R453). The date: the details' (an edit, else TMDB's
    /// full date), else the library's year alone ("Year only when only a year is known"). Resolution and audio are the
    /// preferred file's headline badges as plain text.
    init(content: ItemDetailContent, details: TitleDetails?, contentRating: String?) {
        let year: PartialDate? = content.year.map { PartialDate(year: $0) }
        self.init(runtime: content.runtimeText, date: details?.releaseDate ?? year, contentRating: contentRating,
                  resolution: content.badges.first { $0.group == .resolution }?.text,
                  audio: content.badges.first { $0.group == .audio }?.text,
                  genres: details?.genres ?? [], ratings: [], synopsis: details?.overview)
    }
}
