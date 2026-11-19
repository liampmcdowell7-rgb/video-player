import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// Matching rules, run against a fake catalogue. Titles, years and runtimes are invented for the tests.
final class MatchEngineTests: XCTestCase {

    // MARK: Catalogue

    static func catalog() -> FakeCatalog {
        let c = FakeCatalog()
        c.movies = [
            .movie(603, "The Marrowgate", year: 1999, popularity: 80),
            .movie(604, "The Marrowgate Reloaded", year: 2003, popularity: 60),
            .movie(438631, "Dunerra", year: 2021, popularity: 90),
            .movie(841, "Dunerra", year: 1984, popularity: 30),
            .movie(194, "Amélise", year: 2001, original: "Le Petit Monde d'Amélise Vernon"),
            .movie(129, "Drifting Lanterns", year: 2001, original: "漂う灯籠の夜"),
            .movie(787, "Mr. & Mrs. Pemberton", year: 2005),
            .movie(315635, "Kite-Man: Homeward", year: 2017),
            .movie(155, "The Dusk Warden", year: 2008),
            .movie(2001, "Aftlander", year: 1979),
            .movie(2002, "Aftlanders", year: 1986)
        ]
        c.series = [
            .show(1396, "Crossing Brine", year: 2008),
            .show(71446, "Paper Vault", year: 2017, original: "La bóveda de papel"),
            .show(1403, "Corwin's Agents of S.P.A.R.R.O.W.", year: 2013),
            .show(30984, "The Saga of the Starward Wardens: Die Neue Reihe", year: 2018, original: "星海守護伝 Die Neue Reihe"),
            .show(121, "Professor Where", year: 1963, popularity: 40),
            .show(57243, "Professor Where", year: 2005, popularity: 70),
            .show(5000, "Absolute Show", year: 2010),
            .show(2224, "The Daily Late Show", year: 2015)
        ]
        c.runtimes = [603: 136, 604: 138, 438631: 155, 841: 137, 787: 120, 155: 152]
        c.alternatives = [603: ["Marrowgate", "マロウゲート"]]

        let d = { (y: Int, m: Int, day: Int) in CalendarDate(year: y, month: m, day: day) }
        c.addSeason(series: 1396, number: 0, episodes: [(1, "Good Day Bad Day", 5, nil), (2, "Behind the Scenes", 12, nil)], startDate: d(2009, 2, 17))
        c.addSeason(series: 1396, number: 1, episodes: [(1, "Pilot", 58, d(2008, 1, 20)), (2, "Cat's in the Box...", 48, d(2008, 1, 27)), (3, "...And the Box's in the Lake", nil, d(2008, 2, 10))], startDate: d(2008, 1, 20))
        c.addSeason(series: 1396, number: 2, episodes: (1...13).map { ($0, "S2 E\($0)", 47, d(2009, 3, 8)) }, startDate: d(2009, 3, 8))
        c.addSeason(series: 5000, number: 1, episodes: (1...12).map { ($0, "A\($0)", 24, nil) }, startDate: d(2010, 1, 1))
        c.addSeason(series: 5000, number: 2, episodes: (1...12).map { ($0, "B\($0)", 24, nil) }, startDate: d(2011, 1, 1))
        c.addSeason(series: 2224, number: 1, episodes: [(1, "Opening Night", 42, d(2015, 9, 1)), (2, "Second Night", 42, d(2015, 9, 2))], startDate: d(2015, 9, 1))
        c.addSeason(series: 2224, number: 2, episodes: [(1, "Return", 42, d(2016, 9, 1)), (4, "Guest Night", 41, d(2016, 10, 12))], startDate: d(2016, 9, 1))
        return c
    }

    private func engine(_ c: FakeCatalog, _ config: MatchConfiguration = .standard) -> MatchEngine { MatchEngine(provider: c, configuration: config) }

    private func matched(_ outcome: MatchOutcome, file: StaticString = #filePath, line: UInt = #line) -> MatchResult? {
        guard case .matched(let r) = outcome else {
            XCTFail("expected matched, got \(outcome)", file: file, line: line)
            return nil
        }
        return r
    }

    // MARK: Movies

    func testMovieWithYear() async throws {
        let c = Self.catalog()
        let outcome = try await engine(c).match(MatchInput(parsed: P.movie("The Marrowgate", year: 1999)))
        let r = try XCTUnwrap(matched(outcome))
        XCTAssertEqual(r.tmdbID, 603)
        XCTAssertEqual(r.kind, .movie)
        XCTAssertEqual(r.title, "The Marrowgate")
        XCTAssertEqual(r.year, 1999)
        XCTAssertEqual(r.source, .automatic)
        XCTAssertGreaterThan(r.confidence, 0.9)
        XCTAssertNil(r.episodes)
        XCTAssertEqual(c.calls(withPrefix: "searchMovies"), ["searchMovies:The Marrowgate|1999"], "accepted at once, so no wider search")
    }

    func testMovieWithoutYear() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("The Marrowgate")))
        let r = try XCTUnwrap(matched(outcome))
        XCTAssertEqual(r.tmdbID, 603, "the sequel contains the title but is a weaker match")
        XCTAssertGreaterThan(r.confidence, 0.9)
    }

    func testYearOffByOneIsAcceptedAfterWideningTheSearch() async throws {
        let c = Self.catalog()
        let outcome = try await engine(c).match(MatchInput(parsed: P.movie("The Marrowgate", year: 2000)))
        let r = try XCTUnwrap(matched(outcome))
        XCTAssertEqual(r.tmdbID, 603)
        XCTAssertEqual(c.calls(withPrefix: "searchMovies"), ["searchMovies:The Marrowgate|2000", "searchMovies:The Marrowgate|-"])
        XCTAssertGreaterThanOrEqual(r.confidence, 0.8)
        XCTAssertLessThan(r.confidence, 0.9)
    }

    func testYearFarOffNeedsReview() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("The Marrowgate", year: 2010)))
        guard case .needsReview(let reason, let candidates) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .lowConfidence)
        XCTAssertEqual(candidates.first?.hit.tmdbID, 603)
        XCTAssertEqual(candidates.first?.yearScore, 0)
        XCTAssertLessThanOrEqual(candidates.first?.confidence ?? 1, 0.6)
    }

    func testFilenameThroughTheRealParser() async throws {
        let parsed = FilenameParser.parse(fileName: "The.Marrowgate.1999.1080p.BluRay.x264-GRP.mkv")
        XCTAssertEqual(parsed.title, "The Marrowgate")
        XCTAssertEqual(parsed.year, 1999)
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: parsed))
        XCTAssertEqual(matched(outcome)?.tmdbID, 603)
    }

    func testTitleFromParentFolderWhenFileNameHasNone() async throws {
        let parsed = FilenameParser.parse(fileName: "movie.mkv", folders: ["The Marrowgate (1999)"])
        let input = MatchInput(parsed: parsed, folderNames: ["The Marrowgate (1999)"])
        let outcome = try await engine(Self.catalog()).match(input)
        XCTAssertEqual(matched(outcome)?.tmdbID, 603)
    }

    func testFolderNameIsUsedWhenTheFileNameTitleIsEmpty() async throws {
        var p = P.movie("")
        p.year = 1999
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: p, folderNames: ["The Marrowgate (1999)", "Movies"]))
        XCTAssertEqual(matched(outcome)?.tmdbID, 603)
    }

    func testNoTitleAnywhereIsUnmatched() async throws {
        let c = Self.catalog()
        let outcome = try await engine(c).match(MatchInput(parsed: P.movie("")))
        XCTAssertEqual(outcome, .unmatched)
        XCTAssertTrue(c.calls.isEmpty)
    }

    func testNothingFoundIsUnmatched() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Zzzyxx Qqwwpp", year: 1999)))
        XCTAssertEqual(outcome, .unmatched)
    }

    func testProviderFailuresAreReportedNotHidden() async {
        let c = Self.catalog()
        c.failingSearch = .network("offline")
        do {
            _ = try await engine(c).match(MatchInput(parsed: P.movie("The Marrowgate", year: 1999)))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? MetadataError, .network("offline"))
        }
    }

    // MARK: Episodes

    func testTVEpisode() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", season: 1, episodes: [2])))
        let r = try XCTUnwrap(matched(outcome))
        XCTAssertEqual(r.tmdbID, 1396)
        XCTAssertEqual(r.kind, .series)
        let e = try XCTUnwrap(r.episodes)
        XCTAssertEqual(e.seasonNumber, 1)
        XCTAssertEqual(e.episodeNumbers, [2])
        XCTAssertEqual(e.titles, ["Cat's in the Box..."])
        XCTAssertEqual(e.runtimeMinutes, 48)
        XCTAssertEqual(e.method, .seasonEpisode)
    }

    func testMultiEpisodeFileSumsRuntimes() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", season: 1, episodes: [1, 2])))
        let e = try XCTUnwrap(matched(outcome)?.episodes)
        XCTAssertEqual(e.episodeNumbers, [1, 2])
        XCTAssertEqual(e.titles, ["Pilot", "Cat's in the Box..."])
        XCTAssertEqual(e.runtimeMinutes, 106)
    }

    func testMultiEpisodeWithAnUnknownRuntimeHasNoTotal() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", season: 1, episodes: [2, 3])))
        let e = try XCTUnwrap(matched(outcome)?.episodes)
        XCTAssertEqual(e.episodeNumbers, [2, 3])
        XCTAssertNil(e.runtimeMinutes)
    }

    func testMultiEpisodeNeedsEveryEpisodeToExist() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", season: 1, episodes: [3, 4])))
        guard case .needsReview(let reason, let candidates) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .episodeNotFound)
        XCTAssertEqual(candidates.first?.episodeScore, 0)
    }

    func testEpisodeThatDoesNotExistNeedsReview() async throws {
        for parsed in [P.episode("Crossing Brine", season: 1, episodes: [99]), P.episode("Crossing Brine", season: 9, episodes: [1])] {
            let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: parsed))
            guard case .needsReview(let reason, _) = outcome else { return XCTFail("got \(outcome)") }
            XCTAssertEqual(reason, .episodeNotFound)
        }
    }

    func testEpisodeWithoutSeasonDefaultsToSeasonOne() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", episodes: [1])))
        XCTAssertEqual(matched(outcome)?.episodes?.seasonNumber, 1)
    }

    func testSeriesWithoutEpisodeNumbersMatchesOnTitle() async throws {
        let c = Self.catalog()
        let outcome = try await engine(c).match(MatchInput(parsed: P.episode("Crossing Brine", year: 2008)))
        let r = try XCTUnwrap(matched(outcome))
        XCTAssertEqual(r.tmdbID, 1396)
        XCTAssertNil(r.episodes)
        XCTAssertTrue(c.calls(withPrefix: "season").isEmpty)
    }

    func testSpecialsAreCheckedAgainstSeasonZero() async throws {
        let ok = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", episodes: [2], special: true)))
        let e = try XCTUnwrap(matched(ok)?.episodes)
        XCTAssertEqual(e.seasonNumber, 0)
        XCTAssertEqual(e.titles, ["Behind the Scenes"])
        XCTAssertEqual(e.method, .special)

        let viaSeasonZero = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", season: 0, episodes: [1])))
        XCTAssertEqual(matched(viaSeasonZero)?.episodes?.titles, ["Good Day Bad Day"])

        let missing = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Crossing Brine", episodes: [9], special: true)))
        guard case .needsReview(let reason, _) = missing else { return XCTFail("got \(missing)") }
        XCTAssertEqual(reason, .episodeNotFound)
    }

    func testSpecialInASeriesWithoutASpecialsSeason() async throws {
        let c = Self.catalog()
        c.addSeason(series: 5000, number: 1, episodes: [(1, "A", 24, nil)])
        let outcome = try await engine(c).match(MatchInput(parsed: P.episode("Absolute Show", episodes: [1], special: true)))
        guard case .needsReview(let reason, _) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .episodeNotFound)
    }

    func testAbsoluteEpisodeNumbersWalkTheSeasons() async throws {
        let first = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Absolute Show", absolute: 5)))
        let e1 = try XCTUnwrap(matched(first)?.episodes)
        XCTAssertEqual([e1.seasonNumber, e1.episodeNumbers[0]], [1, 5])
        XCTAssertEqual(e1.method, .absoluteNumber)

        let second = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Absolute Show", absolute: 15)))
        let e2 = try XCTUnwrap(matched(second)?.episodes)
        XCTAssertEqual([e2.seasonNumber, e2.episodeNumbers[0]], [2, 3])
        XCTAssertEqual(e2.titles, ["B3"])

        let edge = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Absolute Show", absolute: 12)))
        XCTAssertEqual(matched(edge)?.episodes?.seasonNumber, 1, "12 is the last episode of season 1")
        let edge2 = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Absolute Show", absolute: 13)))
        XCTAssertEqual(matched(edge2)?.episodes?.seasonNumber, 2)
    }

    func testAbsoluteNumberBeyondTheLastEpisodeNeedsReview() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Absolute Show", absolute: 99)))
        guard case .needsReview(let reason, _) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .episodeNotFound)
    }

    func testDateBasedEpisodeFromAFileName() async throws {
        let parsed = FilenameParser.parse(fileName: "The.Daily.Late.Show.2016.10.12.720p.mkv")
        XCTAssertNotNil(parsed.airDate, "the parser reads the date")
        XCTAssertEqual(parsed.kind, .episode)
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: parsed))
        let r = try XCTUnwrap(matched(outcome))
        XCTAssertEqual(r.tmdbID, 2224)
        let e = try XCTUnwrap(r.episodes)
        XCTAssertEqual(e.method, .airDate)
        XCTAssertEqual([e.seasonNumber, e.episodeNumbers[0]], [2, 4])
        XCTAssertEqual(e.titles, ["Guest Night"])
    }

    func testDateWithNoEpisodeThatDayNeedsReview() async throws {
        let parsed = FilenameParser.parse(fileName: "The.Daily.Late.Show.2016.10.13.720p.mkv")
        XCTAssertNotNil(parsed.airDate)
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: parsed))
        guard case .needsReview(let reason, _) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .episodeNotFound)
    }

    func testEpisodeRuntimeFromFileDurationRaisesConfidence() async throws {
        let base = P.episode("Crossing Brine", season: 1, episodes: [2])
        let plain = try await engine(Self.catalog()).match(MatchInput(parsed: base))
        let withDuration = try await engine(Self.catalog()).match(MatchInput(parsed: base, fileDurationSeconds: 48 * 60))
        XCTAssertGreaterThan(try XCTUnwrap(matched(withDuration)).confidence, try XCTUnwrap(matched(plain)).confidence)
    }

    // MARK: The spec's named cases

    func testRemakeWithTheSameTitleIsToldApartByYear() async throws {
        let new = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Dunerra", year: 2021)))
        XCTAssertEqual(matched(new)?.tmdbID, 438631)
        let old = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Dunerra", year: 1984)))
        XCTAssertEqual(matched(old)?.tmdbID, 841)
    }

    func testRemakeWithNoYearIsATieNeedingReview() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Dunerra")))
        guard case .needsReview(let reason, let candidates) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .closeScores)
        XCTAssertEqual(Set(candidates.prefix(2).map(\.hit.tmdbID)), [438631, 841])
        XCTAssertEqual(candidates[0].hit.tmdbID, 438631, "ties are listed most popular first")
    }

    func testRemakeWithNoYearIsSettledByFileLength() async throws {
        let long = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Dunerra"), fileDurationSeconds: 155 * 60))
        XCTAssertEqual(matched(long)?.tmdbID, 438631)
        let short = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Dunerra"), fileDurationSeconds: 137 * 60))
        XCTAssertEqual(matched(short)?.tmdbID, 841)
    }

    func testForeignTitleMatchesThroughTheOriginalTitle() async throws {
        let series = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("La Bóveda de Papel")))
        XCTAssertEqual(matched(series)?.tmdbID, 71446)
        XCTAssertEqual(matched(series)?.title, "Paper Vault")

        let film = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Le Petit Monde d'Amélise Vernon", year: 2001)))
        XCTAssertEqual(matched(film)?.tmdbID, 194)

        let anime = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("漂う灯籠の夜", year: 2001)))
        XCTAssertEqual(matched(anime)?.tmdbID, 129)
    }

    func testAccentsDoNotMatter() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Amelise", year: 2001)))
        XCTAssertEqual(matched(outcome)?.tmdbID, 194)
    }

    func testThePrefixIsIgnoredBothWays() async throws {
        let a = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Marrowgate", year: 1999)))
        XCTAssertEqual(matched(a)?.tmdbID, 603, "file without The, catalogue with")
        let b = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Dusk Warden, The", year: 2008)))
        XCTAssertEqual(matched(b)?.tmdbID, 155)
        let c = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("The Dusk Warden", year: 2008)))
        XCTAssertEqual(matched(c)?.tmdbID, 155)
        XCTAssertGreaterThan(try XCTUnwrap(matched(c)).confidence, 0.95)
    }

    func testPunctuationDoesNotMatter() async throws {
        let smiths = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Mr and Mrs Pemberton", year: 2005)))
        XCTAssertEqual(matched(smiths)?.tmdbID, 787)
        let spider = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Kite Man Homeward", year: 2017)))
        XCTAssertEqual(matched(spider)?.tmdbID, 315635)
        let sparrow = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Corwin's Agents of SPARROW")))
        XCTAssertEqual(matched(sparrow)?.tmdbID, 1403)
    }

    func testSimilarTitlesAlienAndAliensAreNotConfused() async throws {
        let a = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Aftlander", year: 1979)))
        XCTAssertEqual(matched(a)?.tmdbID, 2001)
        let b = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Aftlanders", year: 1986)))
        XCTAssertEqual(matched(b)?.tmdbID, 2002)
    }

    func testLongSeriesTitles() async throws {
        let full = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("The Saga of the Starward Wardens: Die Neue Reihe", year: 2018)))
        XCTAssertEqual(matched(full)?.tmdbID, 30984)
        XCTAssertEqual(matched(full)?.confidence ?? 0, 0.9625, accuracy: 0.001)

        let dropped = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Saga of the Starward Wardens Die Neue Reihe")))
        XCTAssertEqual(matched(dropped)?.tmdbID, 30984, "article and punctuation differences only")

        let truncated = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Saga of the Starward Wardens", year: 2018)))
        XCTAssertEqual(matched(truncated)?.tmdbID, 30984, "a long title cut short, with a matching year")

        let truncatedNoYear = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Saga of the Starward Wardens")))
        guard case .needsReview(let reason, let candidates) = truncatedNoYear else { return XCTFail("got \(truncatedNoYear)") }
        XCTAssertEqual(reason, .lowConfidence, "a cut-short title with no year is not accepted on its own")
        XCTAssertEqual(candidates.first?.hit.tmdbID, 30984)
    }

    func testTwoCandidatesWithCloseScoresNeedReview() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.episode("Professor Where")))
        guard case .needsReview(let reason, let candidates) = outcome else { return XCTFail("got \(outcome)") }
        XCTAssertEqual(reason, .closeScores)
        XCTAssertEqual(candidates.prefix(2).map(\.hit.tmdbID), [57243, 121])
        XCTAssertEqual(candidates[0].confidence, candidates[1].confidence, accuracy: 0.0001)
    }

    func testTheTieMarginIsConfigurable() async throws {
        let c = Self.catalog()
        let strict = try await engine(c, MatchConfiguration(tieMargin: 0)).match(MatchInput(parsed: P.episode("Professor Where")))
        XCTAssertEqual(matched(strict)?.tmdbID, 57243, "with no margin the more popular one wins")
        let year = try await engine(c).match(MatchInput(parsed: P.episode("Professor Where", year: 1963)))
        XCTAssertEqual(matched(year)?.tmdbID, 121)
    }

    func testMismatchedTitleNeedsReviewAndOffersCandidates() async throws {
        let outcome = try await engine(Self.catalog()).match(MatchInput(parsed: P.movie("Bttl Rygl", year: 1999)))
        switch outcome {
        case .needsReview(let reason, let candidates):
            XCTAssertEqual(reason, .lowConfidence)
            XCTAssertLessThanOrEqual(candidates.count, 5)
        case .unmatched:
            break // nothing close enough to list is also "not accepted"
        case .matched:
            XCTFail("a garbled title must not be accepted")
        }
    }

    // MARK: Hard matches

    func testSidecarTMDBIDIsAHardMatchWithoutSearching() async throws {
        let c = Self.catalog()
        let input = MatchInput(parsed: P.movie("Totally Wrong Name"), sidecarIDs: ProviderIDs(tmdb: 603))
        let rOutcome = try await engine(c).match(input)
        let r = try XCTUnwrap(matched(rOutcome))
        XCTAssertEqual(r.tmdbID, 603)
        XCTAssertEqual(r.source, .sidecarID)
        XCTAssertEqual(r.confidence, 1)
        XCTAssertTrue(c.calls(withPrefix: "search").isEmpty)
    }

    func testSidecarIMDbIDUsesFindNotSearch() async throws {
        let c = Self.catalog()
        c.imdbToHits["tt0133093"] = [.movie(603, "The Marrowgate", year: 1999)]
        let input = MatchInput(parsed: P.movie("Anything"), sidecarIDs: ProviderIDs(imdb: "tt0133093"))
        let rOutcome = try await engine(c).match(input)
        let r = try XCTUnwrap(matched(rOutcome))
        XCTAssertEqual(r.tmdbID, 603)
        XCTAssertEqual(r.source, .sidecarID)
        XCTAssertEqual(c.calls, ["find:tt0133093"])
    }

    func testIMDbHitOfTheWrongKindIsIgnored() async throws {
        let c = Self.catalog()
        c.imdbToHits["tt0903747"] = [.show(1396, "Crossing Brine", year: 2008)]
        let outcome = try await engine(c).match(MatchInput(parsed: P.movie("The Marrowgate", year: 1999), sidecarIDs: ProviderIDs(imdb: "tt0903747")))
        XCTAssertEqual(matched(outcome)?.source, .automatic)
        XCTAssertEqual(matched(outcome)?.tmdbID, 603)
    }

    func testIDInTheFileNameIsAlsoAHardMatchButSidecarWins() async throws {
        var p = P.movie("Whatever")
        p.tmdbID = 604
        let c = Self.catalog()
        let fromNameOutcome = try await engine(c).match(MatchInput(parsed: p))
        let fromName = try XCTUnwrap(matched(fromNameOutcome))
        XCTAssertEqual(fromName.tmdbID, 604)
        XCTAssertEqual(fromName.source, .filenameID)
        let bothOutcome = try await engine(c).match(MatchInput(parsed: p, sidecarIDs: ProviderIDs(tmdb: 603)))
        let both = try XCTUnwrap(matched(bothOutcome))
        XCTAssertEqual(both.tmdbID, 603)
        XCTAssertEqual(both.source, .sidecarID)
    }

    func testUnknownHardIDFallsBackToSearching() async throws {
        let c = Self.catalog()
        let input = MatchInput(parsed: P.movie("The Marrowgate", year: 1999), sidecarIDs: ProviderIDs(tmdb: 999_999))
        let rOutcome = try await engine(c).match(input)
        let r = try XCTUnwrap(matched(rOutcome))
        XCTAssertEqual(r.tmdbID, 603)
        XCTAssertEqual(r.source, .automatic)
        XCTAssertFalse(c.calls(withPrefix: "search").isEmpty)
    }

    func testHardMatchOnASeriesStillResolvesTheEpisode() async throws {
        let c = Self.catalog()
        let input = MatchInput(parsed: P.episode("Wrong", season: 1, episodes: [2]), sidecarIDs: ProviderIDs(tmdb: 1396))
        let rOutcome = try await engine(c).match(input)
        let r = try XCTUnwrap(matched(rOutcome))
        XCTAssertEqual(r.tmdbID, 1396)
        XCTAssertEqual(r.episodes?.titles, ["Cat's in the Box..."])
        XCTAssertEqual(r.confidence, 1)
    }

    func testHardMatchKeepsTheUsersIDEvenIfTheEpisodeIsUnknown() async throws {
        let c = Self.catalog()
        let input = MatchInput(parsed: P.episode("Wrong", season: 1, episodes: [99]), sidecarIDs: ProviderIDs(tmdb: 1396))
        let rOutcome = try await engine(c).match(input)
        let r = try XCTUnwrap(matched(rOutcome))
        XCTAssertEqual(r.tmdbID, 1396)
        XCTAssertNil(r.episodes)
    }

    // MARK: Configuration and scoring parts

    func testTheThresholdIsConfigurable() async throws {
        let strict = try await engine(Self.catalog(), MatchConfiguration(acceptThreshold: 0.99)).match(MatchInput(parsed: P.movie("The Marrowgate", year: 1999)))
        guard case .needsReview(.lowConfidence, _) = strict else { return XCTFail("got \(strict)") }
        let farYear = MatchInput(parsed: P.movie("Drifting Lanterns", year: 2010))
        let normal = try await engine(Self.catalog()).match(farYear)
        guard case .needsReview(.lowConfidence, _) = normal else { return XCTFail("got \(normal)") }
        let loose = try await engine(Self.catalog(), MatchConfiguration(acceptThreshold: 0.5)).match(farYear)
        XCTAssertEqual(matched(loose)?.tmdbID, 129, "a far-off year is capped at 0.6, so a threshold of 0.5 accepts it")
    }

    func testTheDefaultThresholdIsPointEight() {
        XCTAssertEqual(MatchConfiguration.standard.acceptThreshold, 0.8)
        XCTAssertEqual(MatchConfiguration.standard.tieMargin, 0.05)
    }

    func testYearScoreTable() {
        let e = engine(FakeCatalog())
        XCTAssertEqual(e.yearScore(1999, 1999), 1)
        XCTAssertEqual(e.yearScore(1999, 2000), 0.6)
        XCTAssertEqual(e.yearScore(2000, 1999), 0.6)
        XCTAssertEqual(e.yearScore(1999, 2001), 0)
        XCTAssertNil(e.yearScore(nil, 1999))
        XCTAssertNil(e.yearScore(1999, nil))
    }

    func testRuntimeScoreTable() {
        let e = engine(FakeCatalog())
        XCTAssertEqual(e.runtimeScore(fileMinutes: 136, titleMinutes: 136, hasEdition: false), 1)
        XCTAssertEqual(e.runtimeScore(fileMinutes: 141, titleMinutes: 136, hasEdition: false), 1, "within 5 minutes")
        XCTAssertEqual(e.runtimeScore(fileMinutes: 150, titleMinutes: 136, hasEdition: false), 0.5, "within twice the tolerance (10.9 min)")
        XCTAssertEqual(e.runtimeScore(fileMinutes: 180, titleMinutes: 136, hasEdition: false), 0)
        XCTAssertEqual(e.runtimeScore(fileMinutes: 100, titleMinutes: 50, hasEdition: false), 0)
        XCTAssertEqual(e.runtimeScore(fileMinutes: 52, titleMinutes: 48, hasEdition: false), 1, "5 minute floor applies to short runtimes")
        XCTAssertEqual(e.runtimeScore(fileMinutes: 190, titleMinutes: 136, hasEdition: true), 0.5, "a named edition is expected to differ in length")
        XCTAssertEqual(e.runtimeScore(fileMinutes: 140, titleMinutes: 136, hasEdition: true), 1)
    }

    func testCombineRulesAndCaps() {
        let e = engine(FakeCatalog())
        let hit = SearchHit.movie(1, "x", year: 2000)
        func score(_ title: Double, year: Double? = nil, runtime: Double? = nil, episode: Double? = nil) -> Double {
            e.combine(ScoredCandidate(hit: hit, confidence: 0, titleScore: title, yearScore: year, runtimeScore: runtime, episodeScore: episode, episodes: nil))
        }
        XCTAssertEqual(score(1, year: 1, runtime: 1, episode: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(score(1), 0.9325, accuracy: 1e-9, "title alone: less evidence, so below 1")
        XCTAssertEqual(score(1, year: 1), 0.9625, accuracy: 1e-9)
        XCTAssertLessThan(score(1, year: 1), score(1, year: 1, runtime: 1))
        XCTAssertLessThanOrEqual(score(0.55, year: 1, runtime: 1, episode: 1), 0.5, "a weak title caps the result")
        XCTAssertLessThanOrEqual(score(1, year: 0, runtime: 1, episode: 1), 0.6, "a wrong year caps the result")
        XCTAssertLessThanOrEqual(score(1, year: 1, episode: 0), 0.5, "a missing episode caps the result")
        XCTAssertEqual(score(0), 0)
        XCTAssertGreaterThanOrEqual(score(0.6, year: 0.6), 0)
        XCTAssertLessThanOrEqual(score(1, year: 1, runtime: 1, episode: 1), 1)
    }

    func testAlternativeTitlesLiftTheTitleScore() async throws {
        let c = Self.catalog()
        let hit = SearchHit.movie(603, "The Marrowgate", year: 1999)
        var p = P.movie("マロウゲート", year: 1999)
        p.title = "マロウゲート"
        let ranked = try await engine(c).rank([hit], input: MatchInput(parsed: p))
        XCTAssertEqual(ranked[0].titleScore, 1)
        XCTAssertGreaterThan(ranked[0].confidence, 0.9)
        XCTAssertEqual(c.calls(withPrefix: "alt"), ["alt:603"])
    }

    func testAlternativeTitlesAreNotFetchedWhenTheTitleAlreadyMatches() async throws {
        let c = Self.catalog()
        _ = try await engine(c).match(MatchInput(parsed: P.movie("The Marrowgate", year: 1999)))
        XCTAssertTrue(c.calls(withPrefix: "alt").isEmpty)
    }

    func testOnlyTheBestCandidatesAreEnriched() async throws {
        let c = Self.catalog()
        c.movies += [.movie(9001, "Dunerra Messiah", year: 2024), .movie(9002, "Dunerra Drifter", year: 2020), .movie(9003, "Dunerra Planet", year: 2019)]
        let config = MatchConfiguration(enrichCount: 2)
        _ = try await engine(c, config).match(MatchInput(parsed: P.movie("Dunerra"), fileDurationSeconds: 155 * 60))
        XCTAssertEqual(c.calls(withPrefix: "runtime").count, 2)
    }

    func testMatchingIsDeterministic() async throws {
        let input = MatchInput(parsed: P.movie("Dunerra"))
        let a = try await engine(Self.catalog()).match(input)
        let b = try await engine(Self.catalog()).match(input)
        XCTAssertEqual(a, b)
    }

    // MARK: Fix Match search

    func testCandidateSearchRanksAndLimits() async throws {
        let list = try await engine(Self.catalog()).candidates(query: "marrowgate", year: nil, kind: .movie, input: nil)
        XCTAssertEqual(list.first?.hit.tmdbID, 603)
        XCTAssertTrue(list.contains { $0.hit.tmdbID == 604 })
        let one = try await engine(Self.catalog()).candidates(query: "marrowgate", year: nil, kind: .movie, input: nil, limit: 1)
        XCTAssertEqual(one.count, 1)
        let none = try await engine(Self.catalog()).candidates(query: "   ", year: nil, kind: .movie, input: nil)
        XCTAssertTrue(none.isEmpty)
    }

    func testCandidateSearchWithAYearAlsoLooksAtOtherYears() async throws {
        let c = Self.catalog()
        let list = try await engine(c).candidates(query: "Dunerra", year: 1984, kind: .movie, input: nil)
        XCTAssertEqual(list.first?.hit.tmdbID, 841, "the requested year ranks first")
        XCTAssertTrue(list.contains { $0.hit.tmdbID == 438631 }, "the other year is still offered")
    }

    func testCandidateSearchForSeriesUsesTheFilesEpisodeNumbers() async throws {
        let input = MatchInput(parsed: P.episode("ignored", season: 1, episodes: [2]))
        let list = try await engine(Self.catalog()).candidates(query: "Crossing Brine", year: nil, kind: .series, input: input)
        XCTAssertEqual(list.first?.hit.tmdbID, 1396)
        XCTAssertEqual(list.first?.episodeScore, 1)
        XCTAssertEqual(list.first?.episodes?.titles, ["Cat's in the Box..."])
    }
}
