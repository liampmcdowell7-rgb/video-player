import Foundation
import VideoPlayerCore

// Matching a library file to a TMDB title.
//
// Everything about how scores are combined (weights, caps, the 0.8 threshold, the tie margin) is an
// "Interpretation (PROVISIONAL)": the spec says only "score candidates by title similarity, year, and
// runtime ... then auto-accept only above a confidence threshold". See docs/METADATA.md.

public struct MatchInput: Sendable {
    /// Result of `FilenameParser.parse(fileName:folders:)` for the file.
    public var parsed: ParsedMedia
    /// Parent folder names, nearest first. Used when the file name carries no title.
    public var folderNames: [String]
    /// Ids from a sidecar (.nfo). A tmdb or imdb id here is a hard match, no search.
    public var sidecarIDs: ProviderIDs?
    /// Length of the file, if known (from the container or a probe).
    public var fileDurationSeconds: Double?

    public init(parsed: ParsedMedia, folderNames: [String] = [], sidecarIDs: ProviderIDs? = nil, fileDurationSeconds: Double? = nil) {
        self.parsed = parsed
        self.folderNames = folderNames
        self.sidecarIDs = sidecarIDs
        self.fileDurationSeconds = fileDurationSeconds
    }

    public var kind: TitleKind { parsed.kind == .movie ? .movie : .series }
}

public struct MatchConfiguration: Sendable, Equatable {
    /// Confidence at or above which a match is accepted automatically. PROVISIONAL default.
    public var acceptThreshold: Double
    /// If the second best candidate is closer than this to the best one, the item needs review.
    public var tieMargin: Double
    /// How many candidates a "Needs review" outcome carries.
    public var maxCandidates: Int
    /// How many of the best candidates get the extra lookups (runtime, episodes, alternative titles).
    public var enrichCount: Int
    public var titleWeight: Double
    public var yearWeight: Double
    public var runtimeWeight: Double
    public var episodeWeight: Double
    public var runtimeToleranceMinutes: Double
    public var runtimeTolerancePercent: Double

    public init(acceptThreshold: Double = 0.8, tieMargin: Double = 0.05, maxCandidates: Int = 5, enrichCount: Int = 3, titleWeight: Double = 0.55, yearWeight: Double = 0.2, runtimeWeight: Double = 0.15, episodeWeight: Double = 0.1, runtimeToleranceMinutes: Double = 5, runtimeTolerancePercent: Double = 0.08) {
        self.acceptThreshold = acceptThreshold
        self.tieMargin = tieMargin
        self.maxCandidates = maxCandidates
        self.enrichCount = enrichCount
        self.titleWeight = titleWeight
        self.yearWeight = yearWeight
        self.runtimeWeight = runtimeWeight
        self.episodeWeight = episodeWeight
        self.runtimeToleranceMinutes = runtimeToleranceMinutes
        self.runtimeTolerancePercent = runtimeTolerancePercent
    }

    public static let standard = MatchConfiguration()
}

public enum MatchSource: String, Codable, Sendable {
    case sidecarID, filenameID, stored, automatic, userChosen
}

/// The episode(s) of a series that a file holds, checked against the provider's data.
public struct ResolvedEpisodes: Hashable, Sendable {
    public enum Method: String, Sendable { case seasonEpisode, absoluteNumber, airDate, special }
    public var seasonNumber: Int
    public var episodeNumbers: [Int]
    public var titles: [String]
    /// Sum of the episodes' runtimes when every one has a runtime.
    public var runtimeMinutes: Int?
    public var method: Method
}

public struct ScoredCandidate: Hashable, Sendable {
    public var hit: SearchHit
    /// 0...1.
    public var confidence: Double
    public var titleScore: Double
    /// nil when the year gives no evidence (missing on either side).
    public var yearScore: Double?
    public var runtimeScore: Double?
    /// 1 when the file's episode(s) exist in this series, 0 when not, nil when not applicable.
    public var episodeScore: Double?
    public var episodes: ResolvedEpisodes?
}

public enum ReviewReason: String, Sendable {
    case lowConfidence, closeScores, episodeNotFound
}

public struct MatchResult: Hashable, Sendable {
    public var tmdbID: Int
    public var kind: TitleKind
    public var title: String
    public var year: Int?
    public var confidence: Double
    public var source: MatchSource
    public var episodes: ResolvedEpisodes?

    public init(tmdbID: Int, kind: TitleKind, title: String, year: Int?, confidence: Double, source: MatchSource, episodes: ResolvedEpisodes? = nil) {
        self.tmdbID = tmdbID
        self.kind = kind
        self.title = title
        self.year = year
        self.confidence = confidence
        self.source = source
        self.episodes = episodes
    }
}

public enum MatchOutcome: Sendable, Equatable {
    case matched(MatchResult)
    /// Best candidates, best first. Shown only on the Fix Match screen for this file.
    case needsReview(ReviewReason, [ScoredCandidate])
    case unmatched
}

enum EpisodeResolution {
    case notApplicable
    case found(ResolvedEpisodes)
    case missing
}

public struct MatchEngine: Sendable {
    public let provider: any CatalogProvider
    public let configuration: MatchConfiguration

    public init(provider: any CatalogProvider, configuration: MatchConfiguration = .standard) {
        self.provider = provider
        self.configuration = configuration
    }

    // MARK: Matching

    public func match(_ input: MatchInput) async throws -> MatchOutcome {
        let kind = input.kind
        let parsed = input.parsed

        // 1. Hard matches: an id given by a sidecar, then one in the file name. No search.
        let idSources: [(MatchSource, ProviderIDs)] = [
            (.sidecarID, input.sidecarIDs ?? ProviderIDs()),
            (.filenameID, ProviderIDs(tmdb: parsed.tmdbID, imdb: parsed.imdbID))
        ]
        for (source, ids) in idSources {
            if let result = try await hardMatch(ids: ids, kind: kind, source: source, parsed: parsed) { return .matched(result) }
        }

        // 2. Search.
        let titles = queryTitles(for: input)
        guard let primary = titles.first else { return .unmatched }
        var hits = try await search(query: primary, year: parsed.year, kind: kind)
        var ranked = try await rank(hits, input: input)
        if parsed.year != nil, !decide(ranked).isAutomaticMatch {
            // The year filter can hide the right title when the file's year is off; widen once.
            let wider = try await search(query: primary, year: nil, kind: kind)
            hits = merge(hits, wider)
            ranked = try await rank(hits, input: input)
        }
        if hits.isEmpty {
            let fallbacks: [String] = Array(titles.dropFirst()) + [TitleText.normalize(primary)]
            for alternative in fallbacks where !alternative.isEmpty && alternative.lowercased() != primary.lowercased() {
                let found = try await search(query: alternative, year: parsed.year, kind: kind)
                if !found.isEmpty {
                    hits = found
                    ranked = try await rank(hits, input: input)
                    break
                }
            }
        }
        return decide(ranked)
    }

    /// Ranked candidates for a query typed on the Fix Match screen (title and year as the user wrote them).
    /// The file's own duration and episode numbers still count when `input` has them.
    public func candidates(query: String, year: Int?, kind: TitleKind, input: MatchInput?, limit: Int = 10) async throws -> [ScoredCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var context = input ?? MatchInput(parsed: ParsedMedia())
        context.parsed.title = trimmed
        context.parsed.year = year
        context.parsed.kind = kind == .movie ? .movie : .episode
        var hits = try await search(query: trimmed, year: year, kind: kind)
        if year != nil { hits = merge(hits, try await search(query: trimmed, year: nil, kind: kind)) }
        return Array(try await rank(hits, input: context).prefix(limit))
    }

    // MARK: Decision

    func decide(_ ranked: [ScoredCandidate]) -> MatchOutcome {
        guard let top = ranked.first else { return .unmatched }
        let shown = Array(ranked.prefix(configuration.maxCandidates))
        if top.episodeScore == 0 { return .needsReview(.episodeNotFound, shown) }
        if top.confidence < configuration.acceptThreshold { return .needsReview(.lowConfidence, shown) }
        if ranked.count > 1, top.confidence - ranked[1].confidence < configuration.tieMargin { return .needsReview(.closeScores, shown) }
        return .matched(MatchResult(tmdbID: top.hit.tmdbID, kind: top.hit.kind, title: top.hit.title, year: top.hit.year, confidence: top.confidence, source: .automatic, episodes: top.episodes))
    }

    // MARK: Hard matches

    private func hardMatch(ids: ProviderIDs, kind: TitleKind, source: MatchSource, parsed: ParsedMedia) async throws -> MatchResult? {
        var found: SearchHit?
        if let tmdb = ids.tmdb {
            do { found = try await provider.hit(tmdbID: tmdb, kind: kind) } catch MetadataError.notFound { found = nil }
        }
        if found == nil, let imdb = ids.imdb, !imdb.isEmpty {
            do { found = try await provider.find(imdbID: imdb).first { $0.kind == kind } } catch MetadataError.notFound { found = nil }
        }
        guard let hit = found else { return nil }
        var episodes: ResolvedEpisodes?
        if kind == .series, case .found(let resolved) = try await resolveEpisodes(seriesID: hit.tmdbID, parsed: parsed) { episodes = resolved }
        return MatchResult(tmdbID: hit.tmdbID, kind: kind, title: hit.title, year: hit.year, confidence: 1.0, source: source, episodes: episodes)
    }

    // MARK: Search and ranking

    private func queryTitles(for input: MatchInput) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ t: String) {
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TitleText.normalize(trimmed)
            if !trimmed.isEmpty, !key.isEmpty, seen.insert(key).inserted { out.append(trimmed) }
        }
        add(input.parsed.title)
        for folder in input.folderNames { add(FilenameParser.parse(fileName: folder).title) }
        return out
    }

    private func search(query: String, year: Int?, kind: TitleKind) async throws -> [SearchHit] {
        do {
            switch kind {
            case .movie: return try await provider.searchMovies(query: query, year: year)
            case .series: return try await provider.searchSeries(query: query, firstAirYear: year)
            }
        } catch MetadataError.notFound {
            return []
        }
    }

    private func merge(_ a: [SearchHit], _ b: [SearchHit]) -> [SearchHit] {
        var seen = Set(a.map(\.tmdbID))
        return a + b.filter { seen.insert($0.tmdbID).inserted }
    }

    func rank(_ hits: [SearchHit], input: MatchInput) async throws -> [ScoredCandidate] {
        let parsed = input.parsed
        let query = parsed.title.isEmpty ? (queryTitles(for: input).first ?? "") : parsed.title
        guard !query.isEmpty else { return [] }

        var scored: [ScoredCandidate] = hits.map { hit in
            let names = [hit.title] + (hit.originalTitle.map { [$0] } ?? [])
            let title = TitleText.bestSimilarity(query: query, names: names)
            var c = ScoredCandidate(hit: hit, confidence: 0, titleScore: title, yearScore: yearScore(parsed.year, hit.year), runtimeScore: nil, episodeScore: nil, episodes: nil)
            c.confidence = combine(c)
            return c
        }
        // Stable order: confidence, then popularity, then id.
        func order(_ a: ScoredCandidate, _ b: ScoredCandidate) -> Bool {
            if a.confidence != b.confidence { return a.confidence > b.confidence }
            let (pa, pb) = (a.hit.popularity ?? 0, b.hit.popularity ?? 0)
            if pa != pb { return pa > pb }
            return a.hit.tmdbID < b.hit.tmdbID
        }
        scored.sort(by: order)

        // When the title and year already settle the match, alternative titles are not looked up (fewer requests).
        let settled: Bool = {
            guard let top = scored.first, top.confidence >= configuration.acceptThreshold else { return false }
            return scored.count < 2 || top.confidence - scored[1].confidence >= configuration.tieMargin
        }()

        // The best `enrichCount` candidates get the extra lookups. If checking them pushes an unchecked candidate to the
        // top (a checked one lost points for a missing episode, say), the next batch is checked too, up to three rounds,
        // so the winner is never one whose evidence was not looked at.
        var checked = Set<Int>()
        var rounds = 0
        while rounds < 3, let first = scored.first, !checked.contains(first.hit.tmdbID) || rounds == 0 {
            let batch = scored.indices.filter { !checked.contains(scored[$0].hit.tmdbID) }.prefix(configuration.enrichCount)
            if batch.isEmpty { break }
            for index in batch {
                scored[index] = try await enrich(scored[index], query: query, input: input, skipAlternatives: settled)
                checked.insert(scored[index].hit.tmdbID)
            }
            scored.sort(by: order)
            rounds += 1
        }
        return scored
    }

    private func enrich(_ candidate: ScoredCandidate, query: String, input: MatchInput, skipAlternatives: Bool) async throws -> ScoredCandidate {
        var c = candidate
        let parsed = input.parsed
        if !skipAlternatives, c.titleScore < 0.9, let extra = try? await provider.alternativeTitles(kind: c.hit.kind, id: c.hit.tmdbID) {
            c.titleScore = max(c.titleScore, TitleText.bestSimilarity(query: query, names: extra))
        }
        switch c.hit.kind {
        case .movie:
            if let seconds = input.fileDurationSeconds, seconds > 0 {
                do {
                    if let runtime = try await provider.movieRuntime(id: c.hit.tmdbID), runtime > 0 {
                        c.runtimeScore = runtimeScore(fileMinutes: seconds / 60, titleMinutes: Double(runtime), hasEdition: parsed.edition != nil)
                    }
                } catch MetadataError.notFound {}
            }
        case .series:
            switch try await resolveEpisodes(seriesID: c.hit.tmdbID, parsed: parsed) {
            case .notApplicable: break
            case .missing: c.episodeScore = 0
            case .found(let resolved):
                c.episodeScore = 1
                c.episodes = resolved
                if let seconds = input.fileDurationSeconds, seconds > 0, let runtime = resolved.runtimeMinutes, runtime > 0 {
                    c.runtimeScore = runtimeScore(fileMinutes: seconds / 60, titleMinutes: Double(runtime), hasEdition: false)
                }
            }
        }
        c.confidence = combine(c)
        return c
    }

    // MARK: Scoring

    /// Exact year 1, off by one 0.6 (release dates differ by region), otherwise 0. nil when either side is unknown.
    func yearScore(_ wanted: Int?, _ actual: Int?) -> Double? {
        guard let wanted, let actual else { return nil }
        switch abs(wanted - actual) {
        case 0: return 1
        case 1: return 0.6
        default: return 0
        }
    }

    func runtimeScore(fileMinutes: Double, titleMinutes: Double, hasEdition: Bool) -> Double {
        let tolerance = max(configuration.runtimeToleranceMinutes, titleMinutes * configuration.runtimeTolerancePercent)
        let diff = abs(fileMinutes - titleMinutes)
        var score: Double = diff <= tolerance ? 1 : (diff <= 2 * tolerance ? 0.5 : 0)
        // A named edition ("Extended", "Director's Cut") is expected to differ in length.
        if hasEdition, score < 0.5 { score = 0.5 }
        return score
    }

    func combine(_ c: ScoredCandidate) -> Double {
        let k = configuration
        var total = k.titleWeight * c.titleScore
        var used = k.titleWeight
        if let y = c.yearScore { total += k.yearWeight * y; used += k.yearWeight }
        if let r = c.runtimeScore { total += k.runtimeWeight * r; used += k.runtimeWeight }
        if let e = c.episodeScore { total += k.episodeWeight * e; used += k.episodeWeight }
        let everything = k.titleWeight + k.yearWeight + k.runtimeWeight + k.episodeWeight
        guard used > 0, everything > 0 else { return 0 }
        // Less evidence means less certainty: scale between 0.85 (title only) and 1.0 (all four components).
        var confidence = total / used * (0.85 + 0.15 * used / everything)
        if c.titleScore < 0.6 { confidence = min(confidence, 0.5) }
        if let y = c.yearScore, y == 0 { confidence = min(confidence, 0.6) }
        if let e = c.episodeScore, e == 0 { confidence = min(confidence, 0.5) }
        return max(0, min(1, confidence))
    }

    // MARK: Episodes

    func resolveEpisodes(seriesID: Int, parsed: ParsedMedia) async throws -> EpisodeResolution {
        // Date-based ("Show 2024-03-05"): look in the season that started most recently before that date.
        if let date = parsed.airDate, parsed.episodes.isEmpty {
            let target = CalendarDate(year: date.year, month: date.month, day: date.day)
            let summaries: [SeasonSummary]
            do { summaries = try await provider.seriesSeasons(id: seriesID) } catch MetadataError.notFound { return .missing }
            let seasons = summaries.filter { $0.seasonNumber > 0 }.sorted { $0.seasonNumber > $1.seasonNumber }
            let plausible = seasons.filter { ($0.airDate ?? target) <= target }.prefix(3)
            for s in plausible {
                let data: SeasonMetadata
                do { data = try await provider.season(seriesID: seriesID, number: s.seasonNumber) } catch MetadataError.notFound { continue }
                if let ep = data.episodes.first(where: { $0.airDate == target }) {
                    return .found(ResolvedEpisodes(seasonNumber: s.seasonNumber, episodeNumbers: [ep.episodeNumber], titles: [ep.name], runtimeMinutes: ep.runtimeMinutes, method: .airDate))
                }
            }
            return .missing
        }

        // Absolute numbering ("Show - 123"): walk the seasons in order.
        if let absolute = parsed.absoluteEpisode, parsed.season == nil, parsed.episodes.isEmpty, !parsed.isSpecial {
            var remaining = absolute
            let summaries: [SeasonSummary]
            do { summaries = try await provider.seriesSeasons(id: seriesID) } catch MetadataError.notFound { return .missing }
            for s in summaries.filter({ $0.seasonNumber > 0 }).sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
                if remaining <= s.episodeCount {
                    let data = try? await provider.season(seriesID: seriesID, number: s.seasonNumber)
                    let ep = data?.episodes.first { $0.episodeNumber == remaining }
                    return .found(ResolvedEpisodes(seasonNumber: s.seasonNumber, episodeNumbers: [remaining], titles: ep.map { [$0.name] } ?? [], runtimeMinutes: ep?.runtimeMinutes, method: .absoluteNumber))
                }
                remaining -= s.episodeCount
            }
            return .missing
        }

        guard !parsed.episodes.isEmpty else { return .notApplicable }
        let isSpecial = parsed.isSpecial || parsed.season == 0
        let seasonNumber = isSpecial ? 0 : (parsed.season ?? 1)
        let data: SeasonMetadata
        do { data = try await provider.season(seriesID: seriesID, number: seasonNumber) } catch MetadataError.notFound { return .missing }
        var chosen: [EpisodeMetadata] = []
        for number in parsed.episodes {
            guard let ep = data.episodes.first(where: { $0.episodeNumber == number }) else { return .missing }
            chosen.append(ep)
        }
        let runtimes = chosen.compactMap(\.runtimeMinutes)
        return .found(ResolvedEpisodes(seasonNumber: seasonNumber, episodeNumbers: parsed.episodes, titles: chosen.map(\.name), runtimeMinutes: runtimes.count == chosen.count ? runtimes.reduce(0, +) : nil, method: isSpecial ? .special : .seasonEpisode))
    }
}

extension MatchOutcome {
    var isAutomaticMatch: Bool {
        if case .matched = self { return true }
        return false
    }
}
