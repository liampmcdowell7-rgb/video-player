import Foundation
import LibraryIndex

/// R471 (40), PROVISIONAL (frame show t16s): a Related card's caption is one line, the kind of title and the genre it
/// shares with the page ("Show · Comedy", "Movie · Drama"), shown only while the card has focus (`FocusOnlyCaption`);
/// the poster carries the title the rest of the time. Wording ours.
public enum RelatedCaption {
    public enum Kind: Sendable { case movie, show }

    public static func text(kind: Kind, genre: String?) -> String {
        let name = kind == .movie ? "Movie" : "Show"
        guard let genre = genre?.trimmingCharacters(in: .whitespaces), !genre.isEmpty else { return name }
        return name + " · " + genre
    }

    /// For each title the library finds by the page's genres, the first of those genres (in the page's order) it shares.
    /// Keyed by the movie's id, or by the show's id for `.show` (found through its episodes).
    public static func sharedGenres(kind: Kind, genres: [String], store: any LibraryStore) async throws -> [Int64: String] {
        var out: [Int64: String] = [:]
        for genre in genres {
            guard let query = RelatedTitles.query(kind: kind == .movie ? .movie : .episode, genres: [genre]) else { continue }
            let found = try await store.page(query, limit: RelatedTitles.candidateLimit, offset: 0)
            for item in found {
                guard let key = kind == .movie ? item.id : item.seriesID, out[key] == nil else { continue }
                out[key] = genre.trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }
}
