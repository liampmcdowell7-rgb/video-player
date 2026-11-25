import Foundation
import UserData

/// Reads "Move to Movies / Move to Shows" overrides from the user-data ledger, so they sync through iCloud with the rest of
/// the user data and survive a rescan and a rebuilt index (docs/SORTING.md).
public struct LedgerSortOverrides: SortOverrideProviding, @unchecked Sendable {
    public let ledger: UserDataLedger

    public init(ledger: UserDataLedger) { self.ledger = ledger }

    public func overrides(sourceID: String) -> [String: SortOverride] {
        var out: [String: SortOverride] = [:]
        for v in ledger.sortOverrides() where v.sourceID == sourceID {
            out[v.path] = SortOverride(v)
        }
        return out
    }

    /// R471 (15): the files the user deleted from the library (the scan leaves them out).
    public func excludedPaths(sourceID: String) -> Set<String> {
        Set(ledger.libraryRemovals().filter { $0.sourceID == sourceID }.map(\.path))
    }
}

public extension SortOverride {
    init(_ v: UDSortOverrideValue) {
        self.init(kind: v.kind == .movie ? .movie : .episode, title: v.title, year: v.year, season: v.season,
                  episode: v.episode, episodeEnd: v.episodeEnd, signal: v.signal)
    }
}
