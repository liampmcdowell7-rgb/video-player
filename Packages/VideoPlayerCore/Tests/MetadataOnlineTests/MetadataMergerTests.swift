import XCTest
@testable import MetadataOnline

final class MetadataMergerTests: XCTestCase {
    private let sidecar = MetadataFields(
        title: "Sidecar Title", originalTitle: nil, tagline: nil, overview: "Sidecar overview",
        releaseDate: CalendarDate(year: 2001, month: 1, day: 1), runtimeMinutes: nil, genres: ["Drama"],
        certification: nil, poster: .local("poster.jpg"), backdrop: nil, logo: nil, cast: [Person(id: 0, name: "Local Actor")]
    )
    private let tmdb = MetadataFields(
        title: "TMDB Title", originalTitle: "TMDB Original", tagline: "TMDB tagline", overview: "TMDB overview",
        releaseDate: CalendarDate(year: 2002, month: 2, day: 2), runtimeMinutes: 120, genres: ["Action", "Comedy"],
        certification: "PG", poster: .tmdb("/p.jpg"), backdrop: .tmdb("/b.jpg"), logo: .tmdb("/l.png"), cast: [Person(id: 1, name: "TMDB Actor")]
    )
    private let embedded = MetadataFields(
        title: "Embedded Title", originalTitle: "Embedded Original", tagline: "Embedded tagline", overview: "Embedded overview",
        releaseDate: CalendarDate(year: 2003, month: 3, day: 3), runtimeMinutes: 99, genres: ["Documentary"],
        certification: "R", poster: .local("embedded-cover.jpg"), backdrop: .local("embedded-back.jpg"), logo: nil, cast: [Person(id: 2, name: "Embedded Actor")]
    )

    func testSidecarBeatsTMDBBeatsEmbeddedPerField() {
        let m = MetadataMerger.merge(sidecar: sidecar, tmdb: tmdb, embedded: embedded)
        XCTAssertEqual(m.fields.title, "Sidecar Title")
        XCTAssertEqual(m.source(of: .title), .sidecar)
        XCTAssertEqual(m.fields.overview, "Sidecar overview")
        XCTAssertEqual(m.fields.releaseDate?.year, 2001)
        XCTAssertEqual(m.source(of: .releaseDate), .sidecar)
        XCTAssertEqual(m.fields.genres, ["Drama"])
        XCTAssertEqual(m.fields.poster, .local("poster.jpg"))
        XCTAssertEqual(m.fields.cast.map(\.name), ["Local Actor"])
        XCTAssertEqual(m.source(of: .cast), .sidecar)
    }

    func testMissingSidecarFieldsFallToTMDB() {
        let m = MetadataMerger.merge(sidecar: sidecar, tmdb: tmdb, embedded: embedded)
        XCTAssertEqual(m.fields.originalTitle, "TMDB Original")
        XCTAssertEqual(m.source(of: .originalTitle), .tmdb)
        XCTAssertEqual(m.fields.tagline, "TMDB tagline")
        XCTAssertEqual(m.fields.runtimeMinutes, 120)
        XCTAssertEqual(m.source(of: .runtime), .tmdb)
        XCTAssertEqual(m.fields.certification, "PG")
        XCTAssertEqual(m.fields.backdrop, .tmdb("/b.jpg"))
        XCTAssertEqual(m.fields.logo, .tmdb("/l.png"))
        XCTAssertEqual(m.source(of: .backdrop), .tmdb)
    }

    func testEmbeddedOnlyFillsWhatNoOtherLayerHas() {
        let thin = MetadataFields(title: "T")
        let m = MetadataMerger.merge(sidecar: nil, tmdb: thin, embedded: embedded)
        XCTAssertEqual(m.fields.title, "T")
        XCTAssertEqual(m.source(of: .title), .tmdb)
        XCTAssertEqual(m.fields.overview, "Embedded overview")
        XCTAssertEqual(m.source(of: .overview), .embedded)
        XCTAssertEqual(m.fields.genres, ["Documentary"])
        XCTAssertEqual(m.source(of: .genres), .embedded)
        XCTAssertEqual(m.fields.poster, .local("embedded-cover.jpg"))
    }

    func testBlankValuesCountAsMissing() {
        let blankSidecar = MetadataFields(title: "   ", originalTitle: "", tagline: "\n", overview: "", runtimeMinutes: 0, genres: [], certification: " ")
        let m = MetadataMerger.merge(sidecar: blankSidecar, tmdb: tmdb, embedded: embedded)
        XCTAssertEqual(m.fields.title, "TMDB Title")
        XCTAssertEqual(m.source(of: .title), .tmdb)
        XCTAssertEqual(m.fields.runtimeMinutes, 120, "0 minutes is not a runtime")
        XCTAssertEqual(m.fields.genres, ["Action", "Comedy"])
        XCTAssertEqual(m.fields.certification, "PG")
    }

    func testTextIsTrimmed() {
        let m = MetadataMerger.merge(sidecar: MetadataFields(title: "  Padded  "))
        XCTAssertEqual(m.fields.title, "Padded")
    }

    func testFieldNoLayerHasIsAbsentFromProvenance() {
        let m = MetadataMerger.merge(sidecar: MetadataFields(title: "Only"), tmdb: nil, embedded: nil)
        XCTAssertEqual(m.provenance, [.title: .sidecar])
        XCTAssertNil(m.source(of: .overview))
        XCTAssertNil(m.fields.overview)
        XCTAssertTrue(m.fields.genres.isEmpty)
    }

    func testNoLayersAtAll() {
        let m = MetadataMerger.merge()
        XCTAssertTrue(m.provenance.isEmpty)
        XCTAssertEqual(m.fields, MetadataFields())
    }

    func testEveryFieldHasProvenanceWhenAllLayersAreFull() {
        let m = MetadataMerger.merge(sidecar: nil, tmdb: tmdb, embedded: embedded)
        for field in MetadataField.allCases {
            XCTAssertEqual(m.source(of: field), .tmdb, "\(field)")
        }
    }

    func testArraysAreNotMixedAcrossLayers() {
        let m = MetadataMerger.merge(sidecar: MetadataFields(genres: ["A"]), tmdb: MetadataFields(genres: ["B", "C"]))
        XCTAssertEqual(m.fields.genres, ["A"])
    }

    // MARK: From the TMDB models

    func testMovieFieldsUseTheBestImagesForTheLanguage() async throws {
        let client = TMDBClient(credentials: .apiKey("k"), transport: MockTransport.routes(["/movie/603": Fixtures.movie603]), queueConfiguration: plainQueue(), clock: FakeClock())
        let movie = try await client.movie(id: 603)
        let f = MetadataMerger.fields(from: movie)
        XCTAssertEqual(f.title, "The Matrix")
        XCTAssertEqual(f.poster, .tmdb("/p_en.jpg"))
        XCTAssertEqual(f.backdrop, .tmdb("/b1.jpg"))
        XCTAssertEqual(f.logo, .tmdb("/logo_en.png"))
        XCTAssertEqual(f.runtimeMinutes, 136)
        XCTAssertEqual(f.certification, "R")
        XCTAssertEqual(f.cast.first?.name, "Keanu Reeves")
        let de = MetadataMerger.fields(from: movie, language: "de")
        XCTAssertEqual(de.poster, .tmdb("/p_de.jpg"))
    }

    func testPosterFallsBackToThePathOnTheTitleWhenThereAreNoImages() {
        let movie = MovieMetadata(ids: ProviderIDs(tmdb: 1), title: "X", posterPath: "/fallback.jpg", backdropPath: "/fb.jpg")
        let f = MetadataMerger.fields(from: movie)
        XCTAssertEqual(f.poster, .tmdb("/fallback.jpg"))
        XCTAssertEqual(f.backdrop, .tmdb("/fb.jpg"))
        XCTAssertNil(f.logo)
    }

    func testSeriesAndEpisodeFields() {
        let series = SeriesMetadata(ids: ProviderIDs(tmdb: 1), name: "Show", firstAirDate: CalendarDate(year: 2008, month: 1, day: 20), genres: ["Drama"], certification: "TV-MA", posterPath: "/s.jpg")
        let sf = MetadataMerger.fields(from: series)
        XCTAssertEqual(sf.title, "Show")
        XCTAssertEqual(sf.releaseDate?.year, 2008)
        XCTAssertNil(sf.runtimeMinutes)
        XCTAssertEqual(sf.poster, .tmdb("/s.jpg"))
        let episode = EpisodeMetadata(seriesID: 1, seasonNumber: 1, episodeNumber: 2, name: "Ep", overview: "O", airDate: CalendarDate(year: 2008, month: 1, day: 27), runtimeMinutes: 48, stillPath: "/still.jpg")
        let ef = MetadataMerger.fields(from: episode)
        XCTAssertEqual(ef.title, "Ep")
        XCTAssertEqual(ef.poster, .tmdb("/still.jpg"))
        XCTAssertEqual(ef.runtimeMinutes, 48)
    }

    func testSidecarEpisodeTitleBeatsTMDBEpisodeTitle() {
        let episode = EpisodeMetadata(seriesID: 1, seasonNumber: 1, episodeNumber: 2, name: "TMDB Name", overview: "TMDB text")
        let local = MetadataFields(title: "My Own Name")
        let m = MetadataMerger.merge(sidecar: local, tmdb: MetadataMerger.fields(from: episode))
        XCTAssertEqual(m.fields.title, "My Own Name")
        XCTAssertEqual(m.fields.overview, "TMDB text")
        XCTAssertEqual(m.source(of: .overview), .tmdb)
    }

    // MARK: Models

    func testCalendarDateParsing() {
        XCTAssertEqual(CalendarDate("1999-03-31"), CalendarDate(year: 1999, month: 3, day: 31))
        XCTAssertEqual(CalendarDate("1999-03"), CalendarDate(year: 1999, month: 3, day: 1))
        XCTAssertEqual(CalendarDate("1999"), CalendarDate(year: 1999, month: 1, day: 1))
        for bad in [nil, "", "abc", "1999-13-01", "1999-00-10", "1999-02-32", "12", "99999-01-01", "1999-01-01-01"] as [String?] {
            XCTAssertNil(CalendarDate(bad), "\(bad ?? "nil")")
        }
        XCTAssertEqual(CalendarDate(year: 1999, month: 3, day: 1).description, "1999-03-01")
        XCTAssertLessThan(CalendarDate(year: 1999, month: 3, day: 31), CalendarDate(year: 1999, month: 4, day: 1))
    }

    func testImageChoicePrefersLanguageThenTextlessThenEnglish() {
        let images = [
            ImageRef(path: "/fr", language: "fr", voteAverage: 9),
            ImageRef(path: "/en", language: "en", voteAverage: 7),
            ImageRef(path: "/none", language: nil, voteAverage: 5),
            ImageRef(path: "/de1", language: "de", voteAverage: 4),
            ImageRef(path: "/de2", language: "de", voteAverage: 6)
        ]
        XCTAssertEqual(ImageSet.best(images, language: "de-DE")?.path, "/de2", "the user's language, best rated")
        XCTAssertEqual(ImageSet.best(images, language: "ja")?.path, "/none", "textless beats English for other languages")
        XCTAssertEqual(ImageSet.best(images.filter { $0.path != "/none" }, language: "ja")?.path, "/en")
        XCTAssertEqual(ImageSet.best(images.filter { $0.language == "fr" }, language: "ja")?.path, "/fr")
        XCTAssertNil(ImageSet.best([], language: "en"))
        XCTAssertEqual(ImageSet.best([ImageRef(path: "/a", language: "en"), ImageRef(path: "/b", language: "en")], language: "en")?.path, "/a", "equal rating keeps the provider's order")
    }

    func testModelsRoundTripThroughJSON() throws {
        let movie = MovieMetadata(ids: ProviderIDs(tmdb: 1, imdb: "tt1"), title: "T", releaseDate: CalendarDate(year: 2000, month: 1, day: 2), genres: ["A"], ratings: RatingSet(tmdb: Rating(source: .tmdb, percent: 80, display: "8.0/10", votes: 3)))
        let data = try JSONEncoder().encode(movie)
        XCTAssertEqual(try JSONDecoder().decode(MovieMetadata.self, from: data), movie)
        let fields = MetadataFields(title: "x", poster: .local("p.jpg"), backdrop: .tmdb("/b"))
        XCTAssertEqual(try JSONDecoder().decode(MetadataFields.self, from: JSONEncoder().encode(fields)), fields)
    }

    func testAttributionTextsAreTheRequiredNotices() {
        // The provider's API terms, section 3 (read 2026-11-17), with "application" chosen from its bracketed list.
        XCTAssertEqual(MetadataAttribution.tmdbNotice, "This application uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.")
        XCTAssertEqual(MetadataAttribution.justWatchNotice, "Where-to-watch data is provided by JustWatch.")
    }
}
