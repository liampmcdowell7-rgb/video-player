import Foundation

// The watchlist: titles the user chose to remember in Discover (Search tab, empty field) (titles they do NOT own yet). A user list, so it is
// user data (docs/STORAGE_MODEL.md section 2): one record per title, record type "watchlist", synced like every other record.
//
// Version safety: a plain field-by-field record with no special merge rule (`UDSchema.schema(for:)` falls back to "later
// stamp wins" for an unregistered type, so nothing in Schema.swift had to change). An older app that does not know the type
// keeps the record untouched (unknown types merge field by field and are kept, STORAGE_MODEL.md section 3). Removing a
// title writes a deletion stamp, like saved views and sources; adding it again later revives it.

public struct UDWatchlistEntry: Equatable, Hashable, Sendable {
    /// "movie" or "series" (the TMDB kind the title was found under).
    public var kind: String
    public var tmdbID: Int
    public var title: String
    public var year: Int?
    /// The data supplier's poster path (not an address), so the card can draw its picture later.
    public var posterPath: String?
    public var addedAt: Date

    public init(kind: String, tmdbID: Int, title: String, year: Int? = nil, posterPath: String? = nil, addedAt: Date) {
        self.kind = kind
        self.tmdbID = tmdbID
        self.title = title
        self.year = year
        self.posterPath = posterPath
        self.addedAt = addedAt
    }

    /// The record id: stable across devices.
    public var recordID: String { UDWatchlist.recordID(kind: kind, tmdbID: tmdbID) }
}

public enum UDWatchlist {
    public static let type = "watchlist"

    public static func recordID(kind: String, tmdbID: Int) -> String { "\(kind)-\(tmdbID)" }

    public static func patch(_ e: UDWatchlistEntry, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: type, id: e.recordID)
        r.set("kind", .string(e.kind), at: stamp)
        r.set("tmdbID", .int(Int64(e.tmdbID)), at: stamp)
        r.set("title", .string(e.title), at: stamp)
        r.set("year", e.year.map { .int(Int64($0)) } ?? .null, at: stamp)
        r.set("posterPath", e.posterPath.map { .string($0) } ?? .null, at: stamp)
        r.set("addedAt", .double(e.addedAt.timeIntervalSince1970), at: stamp)
        return r
    }

    public static func tombstone(kind: String, tmdbID: Int, at stamp: UDStamp) -> UDRecord {
        UDRecord(type: type, id: recordID(kind: kind, tmdbID: tmdbID), fields: [:], deleted: stamp)
    }

    public static func value(of r: UDRecord) -> UDWatchlistEntry? {
        guard r.type == type, !r.isDeleted, let kind = r["kind"]?.asString, let id = r["tmdbID"]?.asInt, let title = r["title"]?.asString else { return nil }
        return UDWatchlistEntry(kind: kind, tmdbID: Int(id), title: title, year: r["year"]?.asInt.map { Int($0) },
                                posterPath: r["posterPath"]?.asString, addedAt: Date(timeIntervalSince1970: r["addedAt"]?.asDouble ?? 0))
    }
}

public extension UserDataLedger {
    /// The watchlist, newest first.
    func watchlist() -> [UDWatchlistEntry] {
        records(ofType: UDWatchlist.type).compactMap { UDWatchlist.value(of: $0) }
            .sorted { $0.addedAt != $1.addedAt ? $0.addedAt > $1.addedAt : $0.recordID < $1.recordID }
    }

    func addToWatchlist(_ entry: UDWatchlistEntry, at date: Date? = nil) {
        apply(UDWatchlist.patch(entry, at: stamp(date)))
    }

    func removeFromWatchlist(kind: String, tmdbID: Int, at date: Date? = nil) {
        apply(UDWatchlist.tombstone(kind: kind, tmdbID: tmdbID, at: stamp(date)))
    }
}
