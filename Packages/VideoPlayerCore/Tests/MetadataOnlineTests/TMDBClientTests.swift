import XCTest
import VideoPlayerCore
@testable import MetadataOnline

/// TMDB client against a mock transport with hand-written fixtures (see Fixtures.swift: not recorded from the real service).
final class TMDBClientTests: XCTestCase {
    private let key = "test-key-not-real"

    private func client(_ transport: MockTransport, cache: (any MetadataCache)? = nil, language: String = "en-US", region: String = "US", clock: FakeClock = FakeClock(), credentials: TMDBCredentials? = nil, queue: QueueConfiguration? = nil) -> TMDBClient {
        TMDBClient(credentials: credentials ?? .apiKey(key), transport: transport, cache: cache ?? InMemoryMetadataCache(), language: language, region: region, queueConfiguration: queue ?? plainQueue(), clock: clock)
    }

    private func items(_ r: HTTPRequest) -> [String: String] {
        let comps = URLComponents(url: r.url, resolvingAgainstBaseURL: false)
        return Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Requests

    func testSearchMovieRequestShape() async throws {
        let transport = MockTransport.routes(["/search/movie": Fixtures.searchMovieMarrowgate])
        let hits = try await client(transport).searchMovies(query: "The Marrowgate", year: 1999)
        let r = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.url.path, "/3/search/movie")
        XCTAssertEqual(r.url.host, "api.themoviedb.org")
        let q = items(r)
        XCTAssertEqual(q["query"], "The Marrowgate")
        XCTAssertEqual(q["year"], "1999")
        XCTAssertEqual(q["language"], "en-US")
        XCTAssertEqual(q["api_key"], key)
        XCTAssertEqual(q["include_adult"], "false")
        XCTAssertEqual(hits.map(\.tmdbID), [603, 604])
        XCTAssertEqual(hits[0].title, "The Marrowgate")
        XCTAssertEqual(hits[0].year, 1999)
        XCTAssertEqual(hits[0].kind, .movie)
        XCTAssertNil(hits[1].posterPath)
    }

    func testSearchSeriesUsesFirstAirDateYear() async throws {
        let transport = MockTransport.routes(["/search/tv": Fixtures.searchTV])
        let hits = try await client(transport).searchSeries(query: "Crossing Brine", firstAirYear: 2008)
        XCTAssertEqual(items(transport.requests[0])["first_air_date_year"], "2008")
        XCTAssertEqual(hits.first?.kind, .series)
        XCTAssertEqual(hits.first?.year, 2008)
        XCTAssertEqual(hits.first?.originalTitle, "Crossing Brine")
    }

    func testQueryValuesArePercentEncodedIncludingPlusAndAmpersand() async throws {
        let transport = MockTransport.routes(["/search/movie": Fixtures.searchEmpty])
        _ = try await client(transport).searchMovies(query: "C++ & Co", year: nil)
        let url = transport.requests[0].url.absoluteString
        XCTAssertTrue(url.contains("query=C%2B%2B%20%26%20Co"), url)
        XCTAssertNil(items(transport.requests[0])["year"])
    }

    func testReadAccessTokenIsSentAsBearerHeaderNotInTheURL() async throws {
        let transport = MockTransport.routes(["/search/movie": Fixtures.searchEmpty])
        _ = try await client(transport, credentials: .readAccessToken("tok-not-real")).searchMovies(query: "x", year: nil)
        let r = transport.requests[0]
        XCTAssertEqual(r.headers["Authorization"], "Bearer tok-not-real")
        XCTAssertNil(items(r)["api_key"])
        XCTAssertFalse(r.url.absoluteString.contains("tok-not-real"))
    }

    func testEmptyCredentialsFailBeforeAnyRequest() async {
        let transport = MockTransport.routes([:])
        for creds in [TMDBCredentials.apiKey(""), .readAccessToken("")] {
            do {
                _ = try await client(transport, credentials: creds).searchMovies(query: "x", year: nil)
                XCTFail("expected missingCredentials")
            } catch {
                XCTAssertEqual(error as? MetadataError, .missingCredentials)
            }
        }
        XCTAssertEqual(transport.count, 0)
    }

    func testCredentialsNeverAppearInDescriptions() {
        XCTAssertFalse(String(describing: TMDBCredentials.apiKey("secret-abc")).contains("secret-abc"))
        XCTAssertFalse(String(reflecting: TMDBCredentials.readAccessToken("secret-xyz")).contains("secret-xyz"))
        var dumped = ""
        dump(TMDBCredentials.apiKey("secret-dump"), to: &dumped)
        XCTAssertFalse(dumped.contains("secret-dump"))
    }

    func testKeyIsNotWrittenToTheOnDiskCache() async throws {
        let dir = tempDirectory("tmdb-secret")
        defer { try? FileManager.default.removeItem(at: dir) }
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        _ = try await client(transport, cache: JSONFileMetadataCache(directory: dir)).movie(id: 603)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files.isEmpty)
        for f in files {
            XCTAssertFalse(f.contains(key))
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            XCTAssertFalse(text.contains(key), "cache file \(f) contains the key")
        }
    }

    // MARK: Movie mapping

    func testMovieDetailsAreMappedAndRequestAppendsEverything() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let m = try await client(transport).movie(id: 603)
        let q = items(transport.requests[0])
        XCTAssertEqual(q["append_to_response"], "credits,images,videos,release_dates,external_ids")
        XCTAssertEqual(m.ids, ProviderIDs(tmdb: 603, imdb: "tt0133093", tvdb: nil))
        XCTAssertEqual(m.title, "The Marrowgate")
        XCTAssertEqual(m.originalTitle, "The Marrowgate")
        XCTAssertEqual(m.originalLanguage, "en")
        XCTAssertEqual(m.tagline, "Welcome to the Waking Hour.")
        XCTAssertEqual(m.releaseDate, CalendarDate(year: 1999, month: 3, day: 31))
        XCTAssertEqual(m.year, 1999)
        XCTAssertEqual(m.runtimeMinutes, 136)
        XCTAssertEqual(m.genres, ["Action", "Science Fiction"])
        XCTAssertEqual(m.certification, "R", "type 3 (theatrical) with a value wins over the blank one")
        XCTAssertEqual(m.posterPath, "/poster603.jpg")
        XCTAssertEqual(m.backdropPath, "/backdrop603.jpg")
        XCTAssertEqual(m.collection, CollectionRef(id: 2344, name: "The Marrowgate Collection", posterPath: "/coll_poster.jpg", backdropPath: nil))
        XCTAssertEqual(m.language, "en-US")
    }

    func testCastIsOrderedAndCrewKeepsDirectors() async throws {
        let m = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603])).movie(id: 603)
        XCTAssertEqual(m.credits.cast.map(\.name), ["Rowan Ashby", "Corin Hale"])
        XCTAssertEqual(m.credits.cast[0].character, "Wren")
        XCTAssertEqual(m.credits.cast[0].profilePath, "/ashby.jpg")
        XCTAssertNil(m.credits.cast[1].profilePath)
        XCTAssertEqual(m.credits.directors.map(\.name), ["Mira Castell"])
    }

    func testTrailersAreLinksOnly() async throws {
        let m = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603])).movie(id: 603)
        XCTAssertEqual(m.videos.count, 2)
        XCTAssertEqual(m.videos[0].url?.absoluteString, "https://www.youtube.com/watch?v=vKQi3bBA1y8")
        XCTAssertTrue(m.videos[0].official)
        XCTAssertEqual(m.videos[1].url?.absoluteString, "https://vimeo.com/x1")
    }

    func testImageChoiceFollowsTheLanguageSetting() async throws {
        let english = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603]), language: "en-US").movie(id: 603)
        XCTAssertEqual(english.images.bestPoster(language: "en-US")?.path, "/p_en.jpg")
        let german = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603]), language: "de-DE").movie(id: 603)
        XCTAssertEqual(german.images.bestPoster(language: german.language)?.path, "/p_de.jpg")
        XCTAssertEqual(english.images.bestPoster(language: "fr-FR")?.path, "/p_none.jpg", "no French poster: a textless one beats English")
        XCTAssertEqual(english.images.bestLogo(language: "en")?.path, "/logo_en.png")
        XCTAssertEqual(english.images.bestBackdrop(language: "en")?.path, "/b1.jpg")
    }

    func testImageLanguageRequestIncludesTheUsersLanguageEnglishAndTextless() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        _ = try await client(transport, language: "de-DE").movie(id: 603)
        XCTAssertEqual(items(transport.requests[0])["include_image_language"], "de,en,null")
        let t2 = MockTransport.routes(["/movie/603": Fixtures.movie603])
        _ = try await client(t2, language: "en-US").movie(id: 603)
        XCTAssertEqual(items(t2.requests[0])["include_image_language"], "en,null")
    }

    func testTMDBRatingIsLabelledAndHiddenWithoutVotes() async throws {
        let m = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603])).movie(id: 603)
        let r = try XCTUnwrap(m.ratings.tmdb)
        XCTAssertEqual(r.label, "TMDB")
        XCTAssertEqual(r.display, "8.2/10")
        XCTAssertEqual(r.percent, 82, accuracy: 0.001)
        XCTAssertEqual(r.votes, 25000)
        let sparse = try await client(MockTransport.routes(["/movie/42": Fixtures.movieSparse])).movie(id: 42)
        XCTAssertNil(sparse.ratings.tmdb)
        XCTAssertTrue(sparse.ratings.visible.isEmpty)
    }

    func testCertificationUsesTheConfiguredRegion() async throws {
        let m = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603]), region: "DE").movie(id: 603)
        XCTAssertEqual(m.certification, "16")
        let none = try await client(MockTransport.routes(["/movie/603": Fixtures.movie603]), region: "JP").movie(id: 603)
        XCTAssertNil(none.certification)
    }

    func testMissingAndNullFieldsDoNotBreakDecoding() async throws {
        let m = try await client(MockTransport.routes(["/movie/42": Fixtures.movieSparse])).movie(id: 42)
        XCTAssertEqual(m.title, "Sparse")
        XCTAssertNil(m.releaseDate)
        XCTAssertNil(m.year)
        XCTAssertNil(m.runtimeMinutes)
        XCTAssertEqual(m.genres, [])
        XCTAssertNil(m.overview, "blank text is nil")
        XCTAssertNil(m.tagline)
        XCTAssertNil(m.collection)
        XCTAssertNil(m.originalTitle)
        XCTAssertNil(m.posterPath)
        XCTAssertTrue(m.credits.cast.isEmpty)
        XCTAssertTrue(m.images.posters.isEmpty)
        XCTAssertTrue(m.videos.isEmpty)
        XCTAssertNil(m.certification)
    }

    func testResponseWithoutAnIdIsADecodingError() async {
        let transport = MockTransport.routes(["/movie/9": #"{"title":"No id"}"#])
        do {
            _ = try await client(transport).movie(id: 9)
            XCTFail("expected an error")
        } catch {
            guard case .decoding = error as? MetadataError else { return XCTFail("wrong error \(error)") }
        }
    }

    func testNonJSONBodyIsADecodingError() async {
        let transport = MockTransport.routes(["/movie/9": "<html>oops</html>"])
        do {
            _ = try await client(transport).movie(id: 9)
            XCTFail("expected an error")
        } catch {
            guard case .decoding = error as? MetadataError else { return XCTFail("wrong error \(error)") }
        }
    }

    func testMissingOverviewFallsBackToEnglishText() async throws {
        let transport = MockTransport { request in
            let lang = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "language" }?.value
            return response(200, lang == "en-US" ? Fixtures.movieEnglishOverview : Fixtures.movieGermanNoOverview)
        }
        let m = try await client(transport, language: "de-DE").movie(id: 777)
        XCTAssertEqual(m.title, "Das Beispiel", "the title stays in the user's language")
        XCTAssertEqual(m.overview, "English overview.")
        XCTAssertEqual(m.tagline, "English tagline.")
        XCTAssertEqual(transport.count, 2)
    }

    func testEnglishUsersDoNotGetAFallbackRequest() async throws {
        let transport = MockTransport.routes(["/movie/42": Fixtures.movieSparse])
        _ = try await client(transport, language: "en-US").movie(id: 42)
        XCTAssertEqual(transport.count, 1)
    }

    // MARK: Series, season, episode

    func testSeriesDetails() async throws {
        let transport = MockTransport.routes(["/tv/1396": Fixtures.tv1396])
        let s = try await client(transport).series(id: 1396)
        XCTAssertEqual(items(transport.requests[0])["append_to_response"], "credits,images,videos,content_ratings,external_ids")
        XCTAssertEqual(s.ids, ProviderIDs(tmdb: 1396, imdb: "tt0903747", tvdb: 81189))
        XCTAssertEqual(s.name, "Crossing Brine")
        XCTAssertEqual(s.firstAirDate, CalendarDate(year: 2008, month: 1, day: 20))
        XCTAssertEqual(s.year, 2008)
        XCTAssertEqual(s.status, "Ended")
        XCTAssertEqual(s.networks, ["North Channel"])
        XCTAssertEqual(s.certification, "TV-MA")
        XCTAssertEqual(s.seasons.map(\.seasonNumber), [0, 1, 2], "sorted, specials first")
        XCTAssertEqual(s.numberOfSeasons, 2, "the specials season does not count")
        XCTAssertEqual(s.seasons[2].episodeCount, 13)
        XCTAssertEqual(s.credits.cast.first?.name, "Dale Hollis")
    }

    func testSeasonWithEpisodes() async throws {
        let transport = MockTransport.routes(["/tv/1396/season/1": Fixtures.tv1396Season1])
        let s = try await client(transport).season(seriesID: 1396, number: 1)
        XCTAssertEqual(s.seasonNumber, 1)
        XCTAssertEqual(s.name, "Season 1")
        XCTAssertEqual(s.episodes.map(\.episodeNumber), [1, 2, 3])
        XCTAssertEqual(s.episodes[0].name, "Pilot")
        XCTAssertEqual(s.episodes[0].airDate, CalendarDate(year: 2008, month: 1, day: 20))
        XCTAssertEqual(s.episodes[0].runtimeMinutes, 58)
        XCTAssertEqual(s.episodes[0].stillPath, "/e1.jpg")
        XCTAssertEqual(s.episodes[0].guestStars.first?.name, "Guest One")
        XCTAssertEqual(s.episodes[0].seriesID, 1396)
        XCTAssertNil(s.episodes[1].stillPath)
        XCTAssertNil(s.episodes[2].runtimeMinutes, "null runtime")
        XCTAssertNil(s.episodes[2].overview, "null overview")
    }

    func testEpisodeDetails() async throws {
        let transport = MockTransport.routes(["/tv/1396/season/1/episode/1": Fixtures.tv1396Episode])
        let e = try await client(transport).episode(seriesID: 1396, season: 1, episode: 1)
        XCTAssertEqual(e.name, "Pilot")
        XCTAssertEqual(e.seasonNumber, 1)
        XCTAssertEqual(e.episodeNumber, 1)
        XCTAssertEqual(e.voteAverage ?? 0, 8.2, accuracy: 0.001)
        XCTAssertEqual(e.crew.first?.job, "Director")
    }

    // MARK: Other endpoints

    func testCollectionPartsAreOrderedByReleaseDate() async throws {
        let c = try await client(MockTransport.routes(["/collection/2344": Fixtures.collection2344])).collection(id: 2344)
        XCTAssertEqual(c.name, "The Marrowgate Collection")
        XCTAssertEqual(c.parts.map(\.tmdbID), [603, 604, 605])
        XCTAssertEqual(c.parts[0].releaseDate?.year, 1999)
    }

    func testImagesCreditsExternalIDsTranslationsAndAlternativeTitles() async throws {
        let transport = MockTransport.routes([
            "/movie/603/images": Fixtures.images603, "/movie/603/credits": Fixtures.credits603,
            "/tv/1396/external_ids": Fixtures.externalIDs1396, "/movie/603/translations": Fixtures.translations603,
            "/movie/603/alternative_titles": Fixtures.alternativeTitlesMovie, "/tv/1396/alternative_titles": Fixtures.alternativeTitlesTV
        ])
        let c = client(transport)
        let images = try await c.images(kind: .movie, id: 603)
        XCTAssertEqual(images.posters.map(\.path), ["/p_en.jpg"])
        XCTAssertEqual(images.posters[0].width, 1000)
        XCTAssertEqual(images.logos.count, 1)
        let credits = try await c.credits(kind: .movie, id: 603)
        XCTAssertEqual(credits.cast.map(\.name), ["Rowan Ashby"])
        let ids = try await c.externalIDs(kind: .series, id: 1396)
        XCTAssertEqual(ids, ProviderIDs(tmdb: 1396, imdb: "tt0903747", tvdb: 81189))
        let tr = try await c.translations(kind: .movie, id: 603)
        XCTAssertEqual(tr.map(\.language), ["de", "en"])
        XCTAssertEqual(tr[0].title, "Marrowgate")
        XCTAssertNil(tr[1].tagline, "blank tagline")
        let altMovie = try await c.alternativeTitles(kind: .movie, id: 603)
        XCTAssertEqual(altMovie, ["Marrowgate", "マロウゲート"])
        let altTV = try await c.alternativeTitles(kind: .series, id: 1396)
        XCTAssertEqual(altTV, ["BB"])
    }

    func testFindByIMDbID() async throws {
        let transport = MockTransport.routes(["/find/tt0133093": Fixtures.findByIMDb])
        let hits = try await client(transport).find(imdbID: "tt0133093")
        XCTAssertEqual(items(transport.requests[0])["external_source"], "imdb_id")
        XCTAssertEqual(hits.map(\.tmdbID), [603])
        XCTAssertEqual(hits.first?.kind, .movie)
    }

    func testConfigurationAndImageURLs() async throws {
        let c = client(MockTransport.routes(["/configuration": Fixtures.tmdbConfiguration]))
        let builder = await c.imageURLBuilder()
        // Quality principle (R98): sizes at or above what a 4K screen draws (docs/COVERAGE.md, "Defaults changed").
        XCTAssertEqual(builder.url(path: "/abc.jpg", kind: .poster)?.absoluteString, "https://image.tmdb.org/t/p/w780/abc.jpg")
        XCTAssertEqual(builder.url(path: "/abc.jpg", kind: .backdrop)?.absoluteString, "https://image.tmdb.org/t/p/original/abc.jpg")
        XCTAssertEqual(builder.url(path: "/abc.jpg", kind: .logo)?.absoluteString, "https://image.tmdb.org/t/p/original/abc.jpg")
        XCTAssertEqual(builder.url(path: "/abc.jpg", kind: .profile)?.absoluteString, "https://image.tmdb.org/t/p/h632/abc.jpg")
        XCTAssertEqual(builder.url(path: "/abc.jpg", kind: .still)?.absoluteString, "https://image.tmdb.org/t/p/original/abc.jpg")
        XCTAssertEqual(builder.url(path: "abc.jpg", kind: .poster, size: "w500")?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.jpg")
        XCTAssertEqual(builder.url(path: "/abc.jpg", kind: .poster, size: "w9999")?.absoluteString, "https://image.tmdb.org/t/p/original/abc.jpg")
        XCTAssertNil(builder.url(path: nil, kind: .poster))
        XCTAssertNil(builder.url(path: "", kind: .poster))
    }

    func testImageBuilderFallsBackWhenConfigurationIsUnavailable() async {
        let builder = await client(MockTransport.routes([:])).imageURLBuilder()
        XCTAssertEqual(builder.url(path: "/a.jpg", kind: .poster)?.absoluteString, "https://image.tmdb.org/t/p/w780/a.jpg")
    }

    // MARK: Errors

    func testStatusCodesMapToErrors() async {
        let cases: [(Int, MetadataError)] = [(401, .invalidAPIKey), (403, .invalidAPIKey), (404, .notFound), (418, .unexpectedStatus(418))]
        for (status, expected) in cases {
            let transport = MockTransport { _ in response(status, Fixtures.tmdbInvalidKey) }
            do {
                _ = try await client(transport).movie(id: 1)
                XCTFail("expected an error for \(status)")
            } catch {
                XCTAssertEqual(error as? MetadataError, expected, "status \(status)")
            }
        }
    }

    func testRateLimitingIsHandledByTheQueue() async throws {
        let clock = FakeClock()
        let box = RequestQueueTests.Box([response(429, headers: ["Retry-After": "5"]), response(200, Fixtures.searchMovieMarrowgate)])
        let transport = MockTransport { _ in box.next() }
        let hits = try await client(transport, clock: clock).searchMovies(query: "The Marrowgate", year: nil)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(clock.totalSlept, 5, accuracy: 0.001)
    }

    // MARK: Cache behaviour

    func testSecondCallIsServedFromTheCache() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let c = client(transport)
        let a = try await c.movie(id: 603)
        let b = try await c.movie(id: 603)
        XCTAssertEqual(a, b)
        XCTAssertEqual(transport.count, 1)
    }

    func testStaleEntriesAreRefetched() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let clock = FakeClock()
        let c = client(transport, clock: clock)
        _ = try await c.movie(id: 603)
        clock.advance(13 * 86_400)
        _ = try await c.movie(id: 603)
        XCTAssertEqual(transport.count, 1, "still inside the 14 day lifetime")
        clock.advance(2 * 86_400)
        _ = try await c.movie(id: 603)
        XCTAssertEqual(transport.count, 2)
    }

    func testOfflineUseAfterFirstMatchServesStaleData() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let clock = FakeClock()
        let c = client(transport, clock: clock, queue: plainQueue(retries: 1))
        let first = try await c.movie(id: 603)
        clock.advance(100 * 86_400)
        struct Offline: Error {}
        transport.setHandler { _ in throw Offline() }
        let again = try await c.movie(id: 603)
        XCTAssertEqual(first, again)
    }

    func testServerErrorsAlsoFallBackToStaleData() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let clock = FakeClock()
        let c = client(transport, clock: clock, queue: plainQueue(retries: 1))
        _ = try await c.movie(id: 603)
        clock.advance(100 * 86_400)
        transport.setHandler { _ in response(503) }
        let m = try await c.movie(id: 603)
        XCTAssertEqual(m.title, "The Marrowgate")
    }

    func testNoCacheMeansTheNetworkErrorIsReported() async {
        struct Offline: Error {}
        let transport = MockTransport { _ in throw Offline() }
        do {
            _ = try await client(transport, queue: plainQueue(retries: 0)).movie(id: 603)
            XCTFail("expected an error")
        } catch {
            guard case .network = error as? MetadataError else { return XCTFail("wrong error \(error)") }
        }
    }

    func testNotFoundIsNotMaskedByStaleData() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let clock = FakeClock()
        let c = client(transport, clock: clock)
        _ = try await c.movie(id: 603)
        clock.advance(100 * 86_400)
        transport.setHandler { _ in response(404, Fixtures.tmdbNotFound) }
        do {
            _ = try await c.movie(id: 603)
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? MetadataError, .notFound)
        }
    }

    func testDifferentLanguagesAreCachedSeparately() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let cache = InMemoryMetadataCache()
        _ = try await client(transport, cache: cache, language: "en-US").movie(id: 603)
        _ = try await client(transport, cache: cache, language: "de-DE").movie(id: 603)
        XCTAssertEqual(transport.count, 2)
        let keys = await cache.keys
        XCTAssertEqual(keys, ["tmdb/movie/603/de-DE", "tmdb/movie/603/en-US"])
    }

    func testCorruptCacheEntryIsIgnoredAndReplaced() async throws {
        let cache = InMemoryMetadataCache()
        await cache.store(Data("not json".utf8), for: CacheKey(provider: "tmdb", kind: "movie", id: "603", variant: "en-US"), ttl: 1e9, at: Date())
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let m = try await client(transport, cache: cache, clock: FakeClock(start: Date())).movie(id: 603)
        XCTAssertEqual(m.title, "The Marrowgate")
        XCTAssertEqual(transport.count, 1)
    }

    func testRequestsCounterReflectsNetworkUse() async throws {
        let transport = MockTransport.routes(["/movie/603": Fixtures.movie603])
        let c = client(transport)
        _ = try await c.movie(id: 603)
        _ = try await c.movie(id: 603)
        let sent = await c.requestsSent
        XCTAssertEqual(sent, 1)
    }
}
