import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

// FIXTURE: invented ratings and synopses; nothing is contacted.
// R371 (owner's request of 21 Nov 2026): the content rating's source order (source, TMDB, Wikidata) and no badge for an
// unknown or empty rating.
final class ContentRatingTests: XCTestCase {
    private func rated(_ rating: String?, overview: String? = nil) -> TitleDetails {
        var d = TitleDetails(overview: overview, cast: [])
        d.contentRating = rating
        return d
    }

    func testTheSourceComesFirstThenTMDBThenWikidata() {
        let all = LayeredDetails.merge([(.source, rated("R")), (.wikidata, rated("PG")), (.tmdb, rated("PG-13"))])
        XCTAssertEqual(all.details?.contentRating, "R")
        XCTAssertEqual(all.ratingLayer, .source)
        // Asked in the synopsis order (source, Wikidata, TMDB), TMDB's certification still beats Wikidata's.
        let noSource = LayeredDetails.merge([(.source, rated(nil, overview: "Text.")), (.wikidata, rated("PG")), (.tmdb, rated("PG-13"))])
        XCTAssertEqual(noSource.details?.contentRating, "PG-13")
        XCTAssertEqual(noSource.ratingLayer, .tmdb)
        let wikidataOnly = LayeredDetails.merge([(.wikidata, rated("PG")), (.tmdb, rated(nil, overview: "Text."))])
        XCTAssertEqual(wikidataOnly.details?.contentRating, "PG")
        XCTAssertEqual(wikidataOnly.ratingLayer, .wikidata)
        XCTAssertEqual(wikidataOnly.used, [.wikidata, .tmdb])
    }

    func testUnknownOrEmptyRatingsGiveNoBadge() {
        for raw in [nil, "", "   ", "NR", "Not Rated", "Unrated", "N/A", "none"] as [String?] {
            XCTAssertNil(ContentRating.clean(raw), "\(raw ?? "nil")")
        }
        let none = LayeredDetails.merge([(.source, rated("")), (.tmdb, rated("NR", overview: "Text."))])
        XCTAssertNil(none.details?.contentRating)
        XCTAssertNil(none.ratingLayer)
        XCTAssertNil(LayeredDetails.merge([(.tmdb, rated(nil))]).details, "nothing at all: no details")
        XCTAssertEqual(MediaInfo.withRating([], details: none.details), [], "no Rating row without a rating")
    }

    func testTheRatingIsShownAsTheSourcesWriteItWithoutPrefixes() {
        XCTAssertEqual(ContentRating.clean("PG-13"), "PG-13")
        XCTAssertEqual(ContentRating.clean("Rated R"), "R")
        XCTAssertEqual(ContentRating.clean("US:TV-MA"), "TV-MA")
        XCTAssertEqual(ContentRating.clean("gb/15"), "15")
        XCTAssertEqual(ContentRating.clean(" TV-14 "), "TV-14")
        XCTAssertEqual(ContentRating.clean("FSK 16"), "FSK 16")
        XCTAssertEqual(ContentRating.clean("12"), "12")
    }

    func testInformationStartsWithTheRating() {
        let rows = [MediaInfoRow(label: "Resolution", value: "4K")]
        XCTAssertEqual(MediaInfo.withRating(rows, details: rated("TV-14")).map(\.label), ["Rating", "Resolution"])
        XCTAssertEqual(MediaInfo.withRating(rows, details: rated("TV-14")).first?.value, "TV-14")
    }

    /// The service keeps asking until a rating no later layer can beat: a source without a rating does not stop it.
    func testTheServiceAsksTMDBWhenTheSourceHasNoRating() async {
        let full = TitleDetails(overview: "Text.", cast: [TitleDetails.CastMember(id: 1, name: "Ann Example", role: "Lead")])
        let service = LayeredDetailsService(source: { _ in full }, wikidata: nil, tmdb: { _ in
            var d = TitleDetails(overview: nil, cast: [])
            d.contentRating = "PG-13"
            return d
        })
        let merged = await service.details(key: "item-1")
        XCTAssertEqual(merged.details?.contentRating, "PG-13")
        var ratedFull = full
        ratedFull.contentRating = "R"
        let stops = LayeredDetailsService(source: { _ in ratedFull }, wikidata: nil, tmdb: { _ in
            XCTFail("TMDB is not asked when the source gave everything")
            return nil
        })
        let first = await stops.details(key: "item-1")
        XCTAssertEqual(first.details?.contentRating, "R")
    }

    func testTheSampleTitlesCarryTheirInventedRatings() {
        XCTAssertEqual(UITestFixtureDetails.details(forTitle: "Sample Movie 1")?.contentRating, "PG-13")
        XCTAssertEqual(UITestFixtureDetails.details(forTitle: "Sample Show 1")?.contentRating, "TV-14")
        XCTAssertNil(UITestFixtureDetails.details(forTitle: "Sample Movie 2")?.contentRating)
    }
}
