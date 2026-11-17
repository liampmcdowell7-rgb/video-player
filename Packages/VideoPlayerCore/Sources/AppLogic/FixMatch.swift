import Foundation
import LibraryIndex

// Fix Match: when the automatic match is wrong, search again and pick the right title. The search itself is behind a
// protocol (the online lookup lives in MetadataOnline and is wired by the app), so this logic is tested without any network.

public struct MatchCandidate: Equatable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var year: Int?
    public var overview: String?
    public var subtitle: String { [year.map(String.init), overview.map { String($0.prefix(90)) }].compactMap { $0 }.joined(separator: " · ") }
    public init(id: Int, title: String, year: Int? = nil, overview: String? = nil) { self.id = id; self.title = title; self.year = year; self.overview = overview }
}

public protocol MatchSearching: Sendable {
    func search(title: String, year: Int?, kind: ItemKind) async throws -> [MatchCandidate]
}

/// How far one Fix Match choice reaches (docs/METADATA.md section 6, R37): season and show scopes are for episodes only; a
/// movie is always just itself (a folder of movies shares no single title).
public enum FixMatchScope: String, CaseIterable, Sendable {
    case thisFile, thisSeason, wholeShow

    public var title: String {
        switch self {
        case .thisFile: return "This File Only"
        case .thisSeason: return "This Season"
        case .wholeShow: return "The Whole Show"
        }
    }

    public static func choices(for kind: ItemKind) -> [FixMatchScope] { kind == .episode ? allCases : [.thisFile] }
}

/// Saves a choice permanently (the app keeps it in the match store, keyed by file path). nil in tests that do not need it.
public protocol MatchChoiceRecording: Sendable {
    func record(itemID: Int64, candidate: MatchCandidate, scope: FixMatchScope) async throws
}

public struct FixMatchViewModel: Sendable {
    public let store: any LibraryStore
    public let searcher: any MatchSearching
    public let recorder: (any MatchChoiceRecording)?
    public let itemID: Int64
    public let kind: ItemKind
    public private(set) var query: String
    public private(set) var scope: FixMatchScope = .thisFile
    public private(set) var state: ViewState<[MatchCandidate]> = .idle
    public private(set) var applied = false
    /// How many items the last choice changed (the screen can say "Applied to 8 episodes").
    public private(set) var appliedCount = 0

    public init(store: any LibraryStore, searcher: any MatchSearching, itemID: Int64, kind: ItemKind, currentTitle: String, recorder: (any MatchChoiceRecording)? = nil) {
        self.store = store; self.searcher = searcher; self.itemID = itemID; self.kind = kind; self.query = currentTitle; self.recorder = recorder
    }

    public var scopeChoices: [FixMatchScope] { FixMatchScope.choices(for: kind) }

    public mutating func setScope(_ new: FixMatchScope) { if scopeChoices.contains(new) { scope = new } }

    public mutating func search(_ text: String, year: Int? = nil) async {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { state = .idle; return }
        state = .loading
        do {
            let found = try await searcher.search(title: query, year: year, kind: kind)
            state = found.isEmpty
                ? .empty(EmptyState(reason: .noMatches, title: "No Matches", message: "Try the title without the year, or fewer words."))
                : .loaded(found)
        } catch {
            state = .failed(ErrorState.from(error, doing: "search for matches"))
        }
    }

    /// Saves the chosen match on the item. The title, year and id replace the guessed ones.
    /// A movie takes the title, year and id. PROVISIONAL: an episode takes only the series id (its own title is the episode's
    /// name, not the show's), for this file, its season or every episode of its show, according to `scope`.
    public mutating func choose(_ candidate: MatchCandidate) async {
        do {
            var changed = 0
            if kind == .movie {
                try await store.setMetadata(itemID: itemID, ItemMetadata(title: candidate.title, year: candidate.year, tmdbID: candidate.id))
                changed = 1
            } else {
                for id in try await targetEpisodeIDs() {
                    try await store.setMetadata(itemID: id, ItemMetadata(tmdbID: candidate.id))
                    changed += 1
                }
            }
            try await recorder?.record(itemID: itemID, candidate: candidate, scope: kind == .movie ? .thisFile : scope)
            appliedCount = changed
            applied = true
        } catch {
            state = .failed(ErrorState.from(error, doing: "save this match"))
        }
    }
}

extension FixMatchViewModel {
    /// The episodes one choice applies to. A season or show scope falls back to just this item when it has no series.
    func targetEpisodeIDs() async throws -> [Int64] {
        guard scope != .thisFile, let this = try await store.item(id: itemID), let seriesID = this.seriesID else { return [itemID] }
        let all = try await store.episodes(ofSeries: seriesID)
        let ids = scope == .wholeShow ? all.map(\.id) : all.filter { $0.season == this.season }.map(\.id)
        return ids.contains(itemID) ? ids : ids + [itemID]
    }
}

/// Discover is built on online lookups that are not wired yet; until they are, the tab says so plainly.
public enum DiscoverState {
    public static let notAvailable = EmptyState(
        reason: .nothingIndexed, title: "Discover Is Not Available Yet",
        message: "Suggestions need an online lookup that is not turned on in this version. Your library works without it.")
}
