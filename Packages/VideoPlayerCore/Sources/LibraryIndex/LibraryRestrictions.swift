import Foundation

/// R458 (Hide a source; PROVISIONAL) and R459 (Parental Controls): the ONE rule that decides which titles the library shows.
/// The store applies it inside every query that returns titles (grids, counts, letter index, Continue Watching, Next Up,
/// Recently Added, a show's episodes, one title by id), so no screen can read a title the rule hides. Nothing here is stored
/// in the library database: the app sets it at launch and whenever a setting changes.
public struct LibraryRestrictions: Equatable, Sendable {
    /// A title is hidden when every one of its files is in a hidden source.
    public var hiddenSourceIDs: Set<String> = []
    /// R459 (Parental Controls): the ratings that may show. Nil: no rating rule.
    public var ratings: RatingRule?

    public init(hiddenSourceIDs: Set<String> = [], ratings: RatingRule? = nil) {
        self.hiddenSourceIDs = hiddenSourceIDs
        self.ratings = ratings
    }

    public var isEmpty: Bool { hiddenSourceIDs.isEmpty && ratings == nil }

    /// R459: which ratings may show. The labels are written the way `normalize` writes them (capitals, no spaces or hyphens,
    /// no country prefix: "PG-13" is "PG13"). A title whose rating is in no list is hidden, and so is a title with none unless
    /// `allowUnrated`. A film follows `movieLabels`, an episode follows `episodeLabels`; an episode with no rating of its own
    /// takes the rating of another episode of its show that has one (a show's NFO file names its rating once).
    public struct RatingRule: Equatable, Sendable {
        public var movieLabels: Set<String>
        public var episodeLabels: Set<String>
        public var allowUnrated: Bool

        public init(movieLabels: Set<String>, episodeLabels: Set<String>, allowUnrated: Bool) {
            self.movieLabels = movieLabels
            self.episodeLabels = episodeLabels
            self.allowUnrated = allowUnrated
        }

        /// "Rated PG-13", "US:PG-13" and "pg 13" all read PG13.
        public static func normalize(_ text: String?) -> String {
            var t = (text ?? "").uppercased().filter { !$0.isWhitespace && $0 != "-" }.replacingOccurrences(of: "RATED", with: "")
            if let colon = t.firstIndex(of: ":") { t = String(t[t.index(after: colon)...]) }
            return t
        }

        /// Ratings that say a title has none, as `normalize` writes them ("Unrated" is "UN", "Not Rated" is "NOT").
        public static let noRating: Set<String> = ["", "NR", "UN", "NOT", "NA", "NONE", "UNKNOWN"]
    }

    /// SQL twin of `RatingRule.normalize`: capitals, no spaces or hyphens, no "RATED", then the text after a colon (with no
    /// colon, `instr` is 0 and `substr(x, 1)` is the whole text).
    static func normalizedSQL(_ raw: String) -> String {
        let inner = "REPLACE(UPPER(REPLACE(REPLACE(TRIM(\(raw)),' ',''),'-','')),'RATED','')"
        return "substr(\(inner), instr(\(inner),':') + 1)"
    }

    /// The normalised rating of a film (its own) and of an episode (its own, else another episode's of the same show) for items
    /// aliased `i`. The rule and the count of unrated titles both read these two, so they cannot disagree.
    static func ratingSQL(alias i: String = "i") -> (movie: String, episode: String) {
        let own = "COALESCE(\(i).content_rating,'')"
        let inherited = "COALESCE(NULLIF(TRIM(\(i).content_rating),''), (SELECT s.content_rating FROM items s WHERE s.series_id = \(i).series_id AND TRIM(COALESCE(s.content_rating,'')) <> '' LIMIT 1), '')"
        return (normalizedSQL(own), normalizedSQL(inherited))
    }

    /// The SQL terms (joined with AND by the caller) and their arguments for items aliased `alias`.
    func terms(alias i: String = "i") -> (sql: [String], args: [SQLValue]) {
        var sql: [String] = []
        var args: [SQLValue] = []
        if !hiddenSourceIDs.isEmpty {
            let marks = Array(repeating: "?", count: hiddenSourceIDs.count).joined(separator: ",")
            sql.append("\(i).id IN (SELECT item_id FROM files WHERE removed_at IS NULL AND item_id IS NOT NULL AND source_id NOT IN (\(marks)))")
            args += hiddenSourceIDs.sorted().map { .text($0) }
        }
        if let rule = ratings {
            func clause(_ x: String, labels: Set<String>) -> (String, [SQLValue]) {
                let list = (rule.allowUnrated ? labels.union(RatingRule.noRating) : labels).sorted()
                let marks = list.isEmpty ? "NULL" : Array(repeating: "?", count: list.count).joined(separator: ",")
                return ("\(x) IN (\(marks))", list.map { .text($0) })
            }
            let expressions = Self.ratingSQL(alias: i)
            let (movieSQL, movieArgs) = clause(expressions.movie, labels: rule.movieLabels)
            let (episodeSQL, episodeArgs) = clause(expressions.episode, labels: rule.episodeLabels)
            sql.append("((\(i).kind = \(SQLiteLibraryStore.code(.movie)) AND \(movieSQL)) OR (\(i).kind <> \(SQLiteLibraryStore.code(.movie)) AND \(episodeSQL)))")
            args += movieArgs + episodeArgs
        }
        return (sql, args)
    }
}
