import Foundation
import LibraryIndex
import AppLogic

/// Fix Match without a key: it says exactly what is needed and sends nothing.
struct LookupUnavailable: LocalizedError {
    var errorDescription: String? { OnlineLookupText.fixMatchNeedsKey }
}

struct UnavailableMatchSearcher: MatchSearching {
    func search(title: String, year: Int?, kind: ItemKind) async throws -> [MatchCandidate] {
        throw LookupUnavailable()
    }
}
