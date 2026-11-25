import Foundation
import LibraryIndex

/// R471 (25) (owner's request R471, Part 3 item 12: "Related on the show page, from our own library: shared genres ...
/// excluding itself, portrait posters"): the library's other shows whose episodes share a genre with this show, ranked as
/// the movie page's Related (`RelatedTitles.rank`: most shared genres, then the higher rating, then the title). No online
/// lookup. PROVISIONAL (OPEN_QUESTIONS R471 (25)).
public enum RelatedShows {
    /// How many matching episodes the page reads before grouping them by show.
    public static let episodeCandidateLimit = 600

    /// The related shows of `seriesID`, best first, at most `RelatedTitles.limit`; empty with no genres.
    public static func find(seriesID: Int64, genres: [String], store: any LibraryStore) async throws -> [SeriesSummary] {
        guard let query = RelatedTitles.query(kind: .episode, genres: genres) else { return [] }
        let found = try await store.page(query, limit: episodeCandidateLimit, offset: 0)
        var shows: [SeriesSummary] = []
        for id in rank(found, excluding: seriesID, genres: genres) {
            if let show = summary(id: id, episodes: try await store.episodes(ofSeries: id)) { shows.append(show) }
        }
        return shows
    }

    /// One candidate per show (its title, its best episode rating), ranked; the show itself is left out.
    static func rank(_ episodes: [LibraryItem], excluding seriesID: Int64, genres: [String]) -> [Int64] {
        var best: [Int64: RelatedTitles.Candidate] = [:]
        for episode in episodes {
            guard let sid = episode.seriesID, sid != seriesID else { continue }
            var candidate = best[sid] ?? RelatedTitles.Candidate(id: sid, title: episode.seriesTitle ?? episode.title, rating: nil)
            if let r = episode.rating { candidate.rating = max(candidate.rating ?? r, r) }
            best[sid] = candidate
        }
        return RelatedTitles.rank(Array(best.values), excluding: seriesID, genres: genres)
    }

    /// A show's card, from all its episodes (the same counts as the Shows grid, `EpisodeGroupingCatalog`); nil with none.
    static func summary(id: Int64, episodes: [LibraryItem]) -> SeriesSummary? {
        guard let first = episodes.first else { return nil }
        var s = SeriesSummary(id: id, title: first.seriesTitle ?? first.title, episodeCount: episodes.count,
                              unwatchedCount: episodes.filter { !$0.watch.watched }.count,
                              seasonCount: Set(episodes.compactMap(\.season).filter { $0 > 0 }).count, artworkKey: "series-\(id)")
        s.inProgressCount = episodes.filter { !$0.watch.watched && $0.watch.position > 0 }.count
        s.year = episodes.compactMap(\.year).min()
        s.latestAdded = episodes.map(\.addedAt).max()
        s.lastPlayed = episodes.compactMap(\.watch.lastPlayed).max()
        return s
    }
}

/// R471 (25): the library keeps a title's genres once its page has read them (online details, with the user's edits), so
/// Related on the movie and show pages has genres to match. Nothing in the app wrote genres to the library before: the
/// movie page's Related (R471 (7)) could not fill. Each title is written once per run unless its genres change.
public actor GenreRecorder {
    private var written: [Int64: [String]] = [:]

    public init() {}

    /// Writes `genres` to each item (an episode list for a show) whose genres this run has not written yet; returns how
    /// many items were written. Empty genres write nothing (what the library holds stays).
    @discardableResult
    public func record(_ genres: [String], itemIDs: [Int64], store: any LibraryStore) async -> Int {
        let clean = Array(Set(genres.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        guard !clean.isEmpty else { return 0 }
        var count = 0
        for id in itemIDs where written[id] != clean {
            do {
                try await store.setMetadata(itemID: id, ItemMetadata(genres: clean))
                written[id] = clean
                count += 1
            } catch {
                continue
            }
        }
        return count
    }
}
