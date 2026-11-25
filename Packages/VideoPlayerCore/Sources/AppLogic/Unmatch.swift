import Foundation
import LibraryIndex
import UserData
import MetadataOnline

/// R471 (14), PROVISIONAL: Unmatch for a movie or a whole show (a season and an episode follow their show). It removes the
/// online id, so the catalogue's description, pictures and credits stop showing, and holds the files unmatched so the
/// automatic matcher does not match them again (`UDUnmatchHold`). The files, the title, the watch state and the user's edits
/// stay: edits kept under the online id move to the keys the title is known by without one (the file for a movie or an
/// episode, the show's name for a show and its seasons). Fix Match afterwards matches it again.
public struct Unmatcher: Sendable {
    public enum Target: Equatable, Sendable {
        case movie(itemID: Int64)
        case show(seriesID: Int64, title: String)
    }

    public let store: any LibraryStore
    public let ledger: UserDataLedger
    /// Removes saved Fix Match choices for the files; nil when the app has no match store.
    public let forgetter: (any MatchChoiceForgetting)?

    public init(store: any LibraryStore, ledger: UserDataLedger, forgetter: (any MatchChoiceForgetting)? = nil) {
        self.store = store; self.ledger = ledger; self.forgetter = forgetter
    }

    /// The confirmation's title, message and button (our wording): it says exactly what changes and what stays.
    public static func confirmation(_ target: Target, title: String, episodeCount: Int = 0) -> (title: String, message: String, button: String) {
        switch target {
        case .movie:
            return ("Unmatch “\(title)”?",
                    "The online description, pictures and credits are removed from this movie, and it is not matched again "
                    + "automatically. The file, your progress and your edits stay. Fix Match can match it again.",
                    "Unmatch")
        case .show:
            let episodes = episodeCount == 1 ? "1 episode" : "\(episodeCount) episodes"
            return ("Unmatch “\(title)”?",
                    "The online description, pictures and credits are removed from this show and its \(episodes), and they are "
                    + "not matched again automatically. The files, your progress and your edits stay. Fix Match can match it again.",
                    "Unmatch")
        }
    }

    /// Unmatches the target. Returns how many library items changed.
    @discardableResult
    public func run(_ target: Target, at date: Date = Date()) async throws -> Int {
        switch target {
        case .movie(let itemID):
            guard let item = try await store.item(id: itemID) else { return 0 }
            let files = try await store.versions(of: itemID)
            let fileKeys = files.map { UDEditKey.file(sourceID: $0.sourceID, path: $0.path) }
            if let tmdb = item.tmdbID, let preferred = EditTarget.keys(for: item, files: files).last, preferred != .movie(tmdbID: tmdb) {
                ledger.rekeyEdits(from: .movie(tmdbID: tmdb), to: preferred, at: date)
            }
            try await forgetter?.forget(itemIDs: [itemID])
            for key in fileKeys { ledger.holdUnmatched(key, at: date) }
            try await store.clearMatch(itemIDs: [itemID])
            return 1
        case .show(let seriesID, let title):
            let episodes = try await store.episodes(ofSeries: seriesID)
            let tmdb = episodes.lazy.compactMap(\.tmdbID).first
            if let tmdb {
                let byName = EditTarget.showKeys(tmdbID: nil, title: title)[0]
                ledger.rekeyEdits(from: .show(tmdbID: tmdb), to: byName, at: date)
                for season in Set(episodes.compactMap(\.season)) {
                    ledger.rekeyEdits(from: UDEditKey.show(tmdbID: tmdb).season(season), to: byName.season(season), at: date)
                }
            }
            for episode in episodes {
                let files = try await store.versions(of: episode.id)
                if let tmdb = episode.tmdbID ?? tmdb, let s = episode.season, let e = episode.episode,
                   let fileKey = EditTarget.keys(for: episode, files: files).last, fileKey != UDEditKey.show(tmdbID: tmdb).episode(season: s, episode: e) {
                    ledger.rekeyEdits(from: UDEditKey.show(tmdbID: tmdb).episode(season: s, episode: e), to: fileKey, at: date)
                }
                for f in files { ledger.holdUnmatched(.file(sourceID: f.sourceID, path: f.path), at: date) }
            }
            let ids = episodes.map(\.id)
            try await forgetter?.forget(itemIDs: ids)
            try await store.clearMatch(itemIDs: ids)
            return ids.count
        }
    }
}

/// Removes the saved Fix Match choices that apply to these items' files, so a stored choice does not match them again.
public protocol MatchChoiceForgetting: Sendable {
    func forget(itemIDs: [Int64]) async throws
}

/// The app's match store (matches.json and its iCloud records, R381) as a `MatchChoiceForgetting`.
public struct StoredMatchForgetter: MatchChoiceForgetting {
    public let matches: any MatchStore
    public let store: any LibraryStore

    public init(matches: any MatchStore, store: any LibraryStore) { self.matches = matches; self.store = store }

    public func forget(itemIDs: [Int64]) async throws {
        for id in itemIDs {
            guard let item = try await store.item(id: id) else { continue }
            for file in try await store.versions(of: id) {
                let identity = TMDBArtworkProvider.identity(of: file)
                // A file can be covered by its own choice, its season's and a folder's: remove each that applies.
                for _ in 0..<8 {
                    guard let saved = await matches.lookup(file: identity, season: item.season) else { break }
                    try await matches.remove(id: saved.id)
                }
            }
        }
    }
}
