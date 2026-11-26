import Foundation
import VideoPlayerCore
import LibraryIndex
import MetadataLocal

/// R471 item 4 (PROVISIONAL): the sections under the hero of the product pages, built only from data we hold.
/// Layout from the reference frames (episode t02s, movie t04s and t06s); wording our own.

/// R471 item 6 (owner's Part 1 correction): the age guidance card of About: the rating we hold (R371), where it came
/// from, and the rating's descriptors only when that source gives them. No sentence of our own about the content.
public struct AgeGuidance: Equatable, Sendable {
    public var rating: String
    public var source: String?
    public var descriptors: [String]

    public static let heading = "Age Guidance"

    public static func make(rating: String?, layer: DetailsLayer?, descriptors: [String]) -> AgeGuidance? {
        guard let r = rating?.trimmingCharacters(in: .whitespaces), !r.isEmpty else { return nil }
        return AgeGuidance(rating: r, source: layer.map(sourceText), descriptors: ProductInfo.unique(descriptors))
    }

    /// Where the rating came from, in our words.
    static func sourceText(_ layer: DetailsLayer) -> String {
        switch layer {
        case .source: return "Rating from your media server"
        case .tmdb: return "Rating from TMDB"
        case .wikidata: return "Rating from Wikidata"
        }
    }
}

/// R471 item 6 (frames: show t12s and t14s): the text of a show page's episode card under the still: "Episode 4" (the
/// frames set it in capitals; ours stays in title case, rule L4), the title, three lines of description (hidden by Hide
/// Spoilers for an unwatched episode), and the air date with the rating.
public struct EpisodeCardText: Equatable, Sendable {
    public var overline: String?
    public var title: String
    public var description: String?
    public var date: String?
    public var rating: String?

    /// R471 (96): `seriesRating`, the show's own rating, stands in when the episode has none (frames show t12s, t14s: a
    /// rating box on every card), as the episode page borrows it (`EpisodePage.rating`, R471 (85)).
    public static func make(number: Int, title: String, details: TitleDetails?, watched: Bool, hideSpoilers: Bool,
                            seriesRating: String? = nil, locale: Locale = .current) -> EpisodeCardText {
        EpisodeCardText(overline: number > 0 ? "Episode \(number)" : nil, title: title,
                        description: SpoilerRules.synopsis(details?.overview, watched: watched, hideSpoilers: hideSpoilers),
                        date: details?.releaseDate.map { InfoDateText.text($0, locale: locale) },
                        rating: EpisodePage.rating(episode: details?.contentRating, series: seriesRating))
    }
}

/// R471 (28), PROVISIONAL (frames show t06s, t12s): the short line at the foot of an episode's still: the running time
/// ("47m"), or the time left ("18m") while the episode is part watched. Nil when the duration is unknown, and nil for a
/// watched episode (its check mark stands there).
public enum EpisodeStillLabel {
    public static func text(durationSeconds: Double?, progress: Double?, isWatched: Bool) -> String? {
        guard !isWatched, let duration = durationSeconds, duration.isFinite, duration > 0 else { return nil }
        if let progress, progress > 0, progress < 1 {
            return ShortDuration.left(duration * (1 - progress))
        }
        return ShortDuration.text(duration)
    }
}

/// R471 (30), PROVISIONAL (frames show t18s, t20s, movie t06s): the About card's genre line under the title, "Comedy,
/// Sports". Blank and repeated names are dropped and at most three are kept (rule S1: the line is never cut, so the
/// later genres go first). Nil when none is left.
public enum AboutGenres {
    public static let limit = 3

    public static func line(_ genres: [String]) -> String? {
        var seen = Set<String>()
        var kept: [String] = []
        for raw in genres {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            kept.append(name)
            if kept.count == limit { break }
        }
        return kept.isEmpty ? nil : kept.joined(separator: ", ")
    }
}

/// R471 item 6: the show hero's description: the next-up episode's own synopsis after "S4, E4 · Title:" when we hold one
/// (frames show t08s), else the show's synopsis with no prefix.
public enum ShowHeroText {
    public static func description(showOverview: String?, nextCode: String?, nextTitle: String?, nextOverview: String?)
        -> (prefix: String?, text: String)? {
        if let text = nextOverview?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return (HeroLines.nextUpPrefix(code: nextCode, title: nextTitle), text)
        }
        if let text = showOverview?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return (nil, text) }
        return nil
    }
}

/// R471 item 7 (owner's Part 1 correction: "from the extras we hold. Move them to shelves and keep the menu items
/// reachable"): the video files next to a title split into Trailers and Bonus Content by their names (the common naming of
/// media servers: "-trailer", "teaser", and the rest of the extras). Information files (NFO and the like) stay in the menu only.
public enum ExtraShelves {
    public static let trailersHeading = "Trailers"
    public static let bonusHeading = "Bonus Content"

    public static func split(_ extras: [ExtraRow]) -> (trailers: [ExtraRow], bonus: [ExtraRow]) {
        let videos = extras.filter(\.isVideo)
        let trailers = videos.filter { $0.isTrailer || isTrailer($0.name) }
        return (trailers, videos.filter { !($0.isTrailer || isTrailer($0.name)) })
    }

    static func isTrailer(_ name: String) -> Bool {
        let base = ((name as NSString).deletingPathExtension).lowercased()
        return base.contains("trailer") || base.contains("teaser")
    }

    /// The card's title: the file name without its extension and without the trailing "-trailer" style tag.
    public static func displayName(_ name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        for tag in ["-trailer", "-teaser", "-behindthescenes", "-featurette", "-deletedscene", "-deleted", "-interview", "-scene", "-short", "-clip", "-extra", "-other"]
        where base.lowercased().hasSuffix(tag) {
            base = String(base.dropLast(tag.count))
        }
        let clean = base.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? name : clean
    }
}

/// R471 item 7 (owner's Part 1 correction: "from our own library. Titles sharing genres ... excluding itself; portrait
/// posters"): the library's titles of the same kind that share a genre with this one, most shared genres first, then the
/// higher rating, then the title. No online lookup.
public enum RelatedTitles {
    public static let heading = "Related"
    public static let limit = 18
    /// How many candidates the page asks the library for before ranking.
    public static let candidateLimit = 60

    /// The library query: same kind, any of the genres; nil with no genres (no shelf).
    public static func query(kind: ItemKind, genres: [String]) -> ItemQuery? {
        let set = Set(genres.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        guard !set.isEmpty else { return nil }
        var filter = ItemFilter()
        filter.kinds = [kind]
        filter.genres = set
        return ItemQuery(filter: filter, sort: ItemSort(key: .rating, ascending: false))
    }

    public struct Candidate: Equatable, Sendable {
        public var id: Int64
        public var title: String
        public var rating: Double?
        public init(id: Int64, title: String, rating: Double?) { self.id = id; self.title = title; self.rating = rating }
    }

    /// Ranks the candidates and returns their ids; `genresOf` gives a candidate's genres when known (else each counts as
    /// sharing one, since the library query already matched a genre).
    public static func rank(_ items: [Candidate], excluding id: Int64, genres: [String],
                            genresOf: (Int64) -> [String]? = { _ in nil }) -> [Int64] {
        let wanted = Set(genres.map { $0.lowercased() })
        func shared(_ item: Candidate) -> Int {
            guard let theirs = genresOf(item.id) else { return 1 }
            return Set(theirs.map { $0.lowercased() }).intersection(wanted).count
        }
        var seen = Set<Int64>()
        let ranked = items.filter { $0.id != id && seen.insert($0.id).inserted }.sorted { a, b in
            let sa = shared(a), sb = shared(b)
            if sa != sb { return sa > sb }
            if (a.rating ?? 0) != (b.rating ?? 0) { return (a.rating ?? 0) > (b.rating ?? 0) }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        return ranked.prefix(limit).map(\.id)
    }
}

/// One line of a column under the hero: a label, the value as shown, and the whole list when the value is shortened
/// ("More" opens it). Never cut mid-word: a long list shows its first `visibleLimit` entries, then More.
public struct InfoEntry: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
    public var full: [String]?
    /// R471 (33), PROVISIONAL (frames show t20s, movie t06s): an Accessibility entry is shown as its outlined badge
    /// ("SDH") over the explanation; the label stays its spoken name. Nil for every other entry.
    public var badge: String?

    public init(label: String, value: String, full: [String]? = nil, badge: String? = nil) {
        self.label = label; self.value = value; self.full = full; self.badge = badge
    }
}

public enum ProductInfo {
    public static let informationHeading = "Information"
    public static let languagesHeading = "Languages"
    public static let accessibilityHeading = "Accessibility"
    /// How many languages a value lists before More.
    public static let visibleLimit = 3
    /// R471 (44): how many characters of the Audio and Subtitles lists show before More (about five column lines).
    public static let languageBudget = 200

    /// Information: Released, Run Time, Rated, Content Advisories, Region of Origin; each only when we hold it.
    /// R471 (92): `yearOnly` for a movie or a show (frames movie t06s "1973", show t20s "2020"); an episode keeps its full
    /// date (episode t02s).
    public static func information(released: PartialDate?, year: Int?, durationSeconds: Double?, rating: String?,
                                   advisories: [String], regions: [String], yearOnly: Bool = false,
                                   locale: Locale = .current) -> [InfoEntry] {
        var out: [InfoEntry] = []
        if yearOnly {
            if let y = released?.year ?? year, y > 0 { out.append(InfoEntry(label: "Released", value: String(y))) }
        } else if let released { out.append(InfoEntry(label: "Released", value: InfoDateText.text(released, locale: locale))) }
        else if let year, year > 0 { out.append(InfoEntry(label: "Released", value: String(year))) }
        // R471 (94): the short form, "25m" or "1h 30m" (frame movie t06s), as on the hero facts line.
        if let d = durationSeconds, d > 0 { out.append(InfoEntry(label: "Run Time", value: ShortDuration.text(d))) }
        if let r = rating?.trimmingCharacters(in: .whitespaces), !r.isEmpty { out.append(InfoEntry(label: "Rated", value: r)) }
        let advice = unique(advisories)
        if !advice.isEmpty { out.append(listed("Content Advisories", advice)) }
        let places = unique(regions)
        // R471 (95): "Regions of Origin" for more than one (frame show t20s), "Region of Origin" for one (movie t06s).
        if !places.isEmpty { out.append(listed(places.count > 1 ? "Regions of Origin" : "Region of Origin", places)) }
        return out
    }

    /// Languages: Original Audio (the catalogue's original language when known, else the file's default audio track),
    /// Audio and Subtitles (each language once, in the file's order). Tracks of no stated language are left out.
    public static func languages(tracks: FileTrackDetails?, originalLanguage: String? = nil) -> [InfoEntry] {
        guard let tracks else { return [] }
        var out: [InfoEntry] = []
        let speech = tracks.audio.filter { !$0.isCommentary }
        let original = originalLanguage.flatMap(name) ?? (speech.first(where: \.isDefault) ?? speech.first)?.language.flatMap(name)
        if let original { out.append(InfoEntry(label: "Original Audio", value: original)) }
        // R471 (41), PROVISIONAL (frame show t20s): each language once, with what its tracks are in brackets: the audio
        // formats ("English (Dolby Digital Plus 5.1, AAC 2.0)"), and SDH or Forced for subtitles ("English (SDH)").
        // R471 (43), PROVISIONAL (frame show t20s): a described-picture track adds "AD" after the formats, and a
        // closed-caption track "CC" before "SDH", the same short names as the Accessibility badges.
        let plain = speech.filter { !AccessFeature.isDescription($0.name) }
        let describedTracks = speech.filter { AccessFeature.isDescription($0.name) }
        let audio = described(plain.compactMap { track in
            track.language.flatMap(name).map { ($0, FormatNames.audio(codec: track.codec, channels: track.channels, atmos: false)) }
        } + describedTracks.compactMap { track in
            track.language.flatMap(name).map { ($0, AccessFeature.ad.badgeText) }
        })
        if !audio.isEmpty { out.append(listed("Audio", audio, budget: languageBudget)) }
        let subtitles = described(tracks.subtitles.flatMap { track -> [(language: String, detail: String?)] in
            guard let language = track.language.flatMap(name) else { return [] }
            let codec = track.codec.lowercased()
            var kinds: [String] = []
            if codec.contains("608") || codec.contains("708") { kinds.append(AccessFeature.cc.badgeText) }
            if track.isHearingImpaired { kinds.append(AccessFeature.sdh.badgeText) }
            if track.isForced { kinds.append("Forced") }
            return kinds.isEmpty ? [(language, nil)] : kinds.map { (language, $0) }
        }, ranked: [AccessFeature.cc.badgeText, AccessFeature.sdh.badgeText, "Forced"])
        if !subtitles.isEmpty { out.append(listed("Subtitles", subtitles, budget: languageBudget)) }
        return out
    }

    /// Accessibility: each feature the file carries, with our own one-line explanation.
    public static func accessibility(_ features: [AccessFeature]) -> [InfoEntry] {
        features.map { InfoEntry(label: $0.spoken, value: $0.explanation, badge: $0.badgeText) }
    }

    /// R471 item 5: country names for Region of Origin, in the person's language ("United States"); a code the system does
    /// not know stays as the code.
    public static func regionNames(_ codes: [String], locale: Locale = .current) -> [String] {
        codes.map { locale.localizedString(forRegionCode: $0) ?? $0 }
    }

    /// R471 item 5: "Director" or "Directors" and the names, for the hero's credits block; nil with none.
    public static func directorLine(_ names: [String]) -> (label: String, names: String)? {
        let clean = unique(names)
        guard !clean.isEmpty else { return nil }
        return (clean.count == 1 ? "Director" : "Directors", clean.joined(separator: ", "))
    }

    /// A language's English name, nil for "undetermined" and "no linguistic content".
    static func name(_ code: String) -> String? {
        let key = code.lowercased().split(separator: "-").first.map(String.init) ?? ""
        if key.isEmpty || ["und", "zxx", "mis"].contains(key) { return nil }
        return MatroskaTrack.languageName(for: code)
    }

    static func listed(_ label: String, _ values: [String]) -> InfoEntry {
        if values.count <= visibleLimit { return InfoEntry(label: label, value: values.joined(separator: ", ")) }
        return InfoEntry(label: label, value: values.prefix(visibleLimit).joined(separator: ", "), full: values)
    }

    /// R471 (44), PROVISIONAL (frames show t20s, movie t06s): a language list shows whole entries while they fit
    /// `languageBudget` characters (about five lines of the column), then More; always at least one entry.
    static func listed(_ label: String, _ values: [String], budget: Int) -> InfoEntry {
        var shown: [String] = []
        var length = 0
        for value in values {
            let added = (shown.isEmpty ? 0 : 2) + value.count
            if !shown.isEmpty && length + added > budget { break }
            shown.append(value)
            length += added
        }
        if shown.count == values.count { return InfoEntry(label: label, value: values.joined(separator: ", ")) }
        return InfoEntry(label: label, value: shown.joined(separator: ", "), full: values)
    }

    /// R471 (41): one entry per language, in the order of the file, with its tracks' kinds once each in brackets.
    /// `ranked` details come first, in that order (R471 (43): "CC" before "SDH"); the rest keep the order they were seen.
    static func described(_ pairs: [(language: String, detail: String?)], ranked: [String] = []) -> [String] {
        var order: [String] = []
        var details: [String: [String]] = [:]
        for (language, detail) in pairs {
            if details[language] == nil { order.append(language); details[language] = [] }
            if let detail, !detail.isEmpty, !(details[language] ?? []).contains(detail) { details[language, default: []].append(detail) }
        }
        func rank(_ detail: String) -> Int { ranked.firstIndex(of: detail) ?? ranked.count }
        return order.map { language in
            let seen = details[language] ?? []
            let kinds = seen.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
            return kinds.isEmpty ? language : "\(language) (\(kinds.joined(separator: ", ")))"
        }
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
