import Foundation

/// What one Fix Match choice changed, so it can be undone.
public struct FixMatchChange: Sendable, Equatable {
    public var added: StoredMatch
    /// The choice this one replaced (same scope and path), restored on undo.
    public var replaced: StoredMatch?
    public var result: MatchResult
}

/// Matching with saved choices and the Fix Match actions.
/// A saved choice always beats automatic matching, and is used without any network call.
public struct FixMatchService: Sendable {
    public let engine: MatchEngine
    public let store: any MatchStore
    private let now: @Sendable () -> Date

    public init(engine: MatchEngine, store: any MatchStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.store = store
        self.now = now
    }

    /// The saved choice for the file if there is one, otherwise automatic matching.
    public func resolve(file: FileIdentity, input: MatchInput) async throws -> MatchOutcome {
        let season = input.parsed.isSpecial ? 0 : input.parsed.season
        if let saved = await store.lookup(file: file, season: season) {
            return .matched(await result(for: saved, input: input, source: .stored))
        }
        return try await engine.match(input)
    }

    /// Fix Match search: ranked candidates for a title and year typed by the user.
    public func search(query: String, year: Int?, kind: TitleKind, input: MatchInput?) async throws -> [ScoredCandidate] {
        try await engine.candidates(query: query, year: year, kind: kind, input: input)
    }

    /// Saves the user's choice. Season and folder scopes are only for series.
    public func choose(_ hit: SearchHit, for file: FileIdentity, input: MatchInput, scope: MatchScope) async throws -> FixMatchChange {
        let path: String
        switch scope {
        case .file:
            path = file.path
        case .season, .folder:
            guard hit.kind == .series else { throw MetadataError.scopeNotAllowed("a season or folder choice needs a series, not a movie") }
            path = file.folderPath
        }
        let match = StoredMatch(scope: scope, path: path, fileSize: scope == .file ? file.size : nil, tmdbID: hit.tmdbID, kind: hit.kind, title: hit.title, year: hit.year, createdAt: now())
        let replaced = try await store.save(match)
        let result = await result(for: match, input: input, source: .userChosen)
        return FixMatchChange(added: match, replaced: replaced, result: result)
    }

    /// Takes a choice back, restoring the one it replaced.
    public func undo(_ change: FixMatchChange) async throws {
        try await store.remove(id: change.added.id)
        if let old = change.replaced { try await store.save(old) }
    }

    private func result(for saved: StoredMatch, input: MatchInput, source: MatchSource) async -> MatchResult {
        var episodes: ResolvedEpisodes?
        if saved.kind == .series, let resolution = try? await engine.resolveEpisodes(seriesID: saved.tmdbID, parsed: input.parsed), case .found(let found) = resolution {
            episodes = found
        }
        return MatchResult(tmdbID: saved.tmdbID, kind: saved.kind, title: saved.title, year: saved.year, confidence: 1.0, source: source, episodes: episodes)
    }
}
