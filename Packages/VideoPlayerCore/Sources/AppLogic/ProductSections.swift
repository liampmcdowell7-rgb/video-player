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

    public static func make(number: Int, title: String, details: TitleDetails?, watched: Bool, hideSpoilers: Bool,
                            locale: Locale = .current) -> EpisodeCardText {
        EpisodeCardText(overline: number > 0 ? "Episode \(number)" : nil, title: title,
                        description: SpoilerRules.synopsis(details?.overview, watched: watched, hideSpoilers: hideSpoilers),
                        date: details?.releaseDate.map { InfoDateText.text($0, locale: locale) },
                        rating: details?.contentRating)
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

    public init(label: String, value: String, full: [String]? = nil) {
        self.label = label; self.value = value; self.full = full
    }
}

public enum ProductInfo {
    public static let informationHeading = "Information"
    public static let languagesHeading = "Languages"
    public static let accessibilityHeading = "Accessibility"
    /// How many languages a value lists before More.
    public static let visibleLimit = 3

    /// Information: Released, Run Time, Rated, Content Advisories, Region of Origin; each only when we hold it.
    public static func information(released: PartialDate?, year: Int?, durationSeconds: Double?, rating: String?,
                                   advisories: [String], regions: [String], locale: Locale = .current) -> [InfoEntry] {
        var out: [InfoEntry] = []
        if let released { out.append(InfoEntry(label: "Released", value: InfoDateText.text(released, locale: locale))) }
        else if let year, year > 0 { out.append(InfoEntry(label: "Released", value: String(year))) }
        if let d = durationSeconds, d > 0 { out.append(InfoEntry(label: "Run Time", value: DisplayText.runtime(d))) }
        if let r = rating?.trimmingCharacters(in: .whitespaces), !r.isEmpty { out.append(InfoEntry(label: "Rated", value: r)) }
        let advice = unique(advisories)
        if !advice.isEmpty { out.append(listed("Content Advisories", advice)) }
        let places = unique(regions)
        if !places.isEmpty { out.append(listed("Region of Origin", places)) }
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
        let audio = unique(speech.compactMap { $0.language.flatMap(name) })
        if !audio.isEmpty { out.append(listed("Audio", audio)) }
        let subtitles = unique(tracks.subtitles.compactMap { $0.language.flatMap(name) })
        if !subtitles.isEmpty { out.append(listed("Subtitles", subtitles)) }
        return out
    }

    /// Accessibility: each feature the file carries, with our own one-line explanation.
    public static func accessibility(_ features: [AccessFeature]) -> [InfoEntry] {
        features.map { InfoEntry(label: $0.spoken, value: $0.explanation) }
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

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
