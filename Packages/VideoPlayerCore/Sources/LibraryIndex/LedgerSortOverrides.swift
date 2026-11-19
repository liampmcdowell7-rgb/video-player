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
}

public extension SortOverride {
    init(_ v: UDSortOverrideValue) {
        self.init(kind: v.kind == .movie ? .movie : .episode, title: v.title, year: v.year, season: v.season,
                  episode: v.episode, episodeEnd: v.episodeEnd, signal: v.signal)
    }
}
