import Foundation
import LibraryIndex

/// R460 (follow-up to R459; PROVISIONAL): reads the rating of every title that has none kept yet, by the same path the Read Ratings
/// button and the title page use (`SourceRatings.storedRating`: the server's answer, else the title's information file; each answer
/// is kept in the library, "" when both say none, so a title is read once). The scan runs it while Restrictions are on, so a new
/// title has its rating before the lists are read again, and turning Restrictions on starts it for the titles already there.
public enum RatingPass {
    /// Walks the titles without a kept rating by id, so a title nothing can answer now does not hold the rest back. Returns how
    /// many titles got a rating (an answer of "" counts: it is recorded and not asked again).
    public static func read(store: SQLiteLibraryStore, server: (any ServerMetadataProviding)?, reader: (any SidecarReading)?,
                            batch: Int = 200) async -> Int {
        var read = 0
        var after: Int64 = 0
        while let items = try? await store.itemsWithoutRating(after: after, limit: batch), let last = items.last {
            for item in items where await SourceRatings.storedRating(item: item, store: store, server: server, reader: reader) != nil { read += 1 }
            after = last.id
        }
        return read
    }
}
