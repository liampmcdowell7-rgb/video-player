import XCTest
import LibraryIndex
@testable import AppLogic

/// R319: the content rating in the player's Info tab (`iTunesMetadataContentRating`): which title's rating, and its text.
final class PlayerRatingTests: XCTestCase {
    func testAnEpisodeUsesItsShowsRatingAndAFilmItsOwn() {
        XCTAssertEqual(PlayerRating.detailsKey(itemID: 7, isEpisode: true, seriesID: 3), "series-3")
        XCTAssertEqual(PlayerRating.detailsKey(itemID: 7, isEpisode: false, seriesID: nil), "item-7")
        XCTAssertEqual(PlayerRating.detailsKey(itemID: 7, isEpisode: true, seriesID: nil), "item-7", "an episode without a show")
        XCTAssertEqual(PlayerRating.detailsKey(itemID: 7, isEpisode: false, seriesID: 3), "item-7")
        // The keys are the ones the details service reads.
        XCTAssertEqual(ArtworkKey(PlayerRating.detailsKey(itemID: 7, isEpisode: true, seriesID: 3)), .series(3))
        XCTAssertEqual(ArtworkKey(PlayerRating.detailsKey(itemID: 7, isEpisode: false, seriesID: nil)), .item(7))
    }

    func testTheLibraryItemOverloadFollowsTheSameRule() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        let episode = try XCTUnwrap(episodes.first)
        let series = try XCTUnwrap(episode.seriesID)
        XCTAssertEqual(PlayerRating.detailsKey(for: episode), "series-\(series)")
    }

    func testTheValueIsTheBadgeTextAndNothingWithoutARating() {
        XCTAssertEqual(PlayerRating.metadataValue("PG-13"), "PG-13")
        XCTAssertEqual(PlayerRating.metadataValue("Rated R"), "R")
        XCTAssertEqual(PlayerRating.metadataValue("US:TV-MA"), "TV-MA")
        XCTAssertEqual(PlayerRating.metadataValue(" 15 "), "15")
        for none in [nil, "", "  ", "NR", "Not Rated", "Unrated"] {
            XCTAssertNil(PlayerRating.metadataValue(none), String(describing: none))
        }
    }

    // MARK: R380: the rating before playback starts, and what the lookup after the start may replace

    func testAtStartTheSourceRatingWins() {
        XCTAssertEqual(PlayerRating.atStart(sourceRating: "TV-14", storedRating: "15"), .init(value: "TV-14", layer: .source))
        XCTAssertEqual(PlayerRating.atStart(sourceRating: "Rated R", storedRating: nil), .init(value: "R", layer: .source))
    }

    func testAtStartOnlyAStoredRating() {
        XCTAssertEqual(PlayerRating.atStart(sourceRating: nil, storedRating: "PG-13"), .init(value: "PG-13", layer: .source))
    }

    func testAtStartNeitherGivesNothing() {
        XCTAssertNil(PlayerRating.atStart(sourceRating: nil, storedRating: nil))
        // "" is the library's record that the source and the NFO file have none (R374).
        XCTAssertNil(PlayerRating.atStart(sourceRating: nil, storedRating: ""))
    }

    func testAtStartNotRatedValuesAreIgnored() {
        XCTAssertNil(PlayerRating.atStart(sourceRating: "NR", storedRating: "Not Rated"))
        XCTAssertEqual(PlayerRating.atStart(sourceRating: "Not Rated", storedRating: "12"), .init(value: "12", layer: .source))
        XCTAssertEqual(PlayerRating.atStart(sourceRating: "Unrated", storedRating: nil), nil)
    }

    func testTheLookupFillsAnItemWithoutARating() {
        XCTAssertEqual(PlayerRating.afterLookup(current: nil, answer: "PG", answerLayer: .tmdb), .init(value: "PG", layer: .tmdb))
        XCTAssertEqual(PlayerRating.afterLookup(current: nil, answer: "15", answerLayer: .wikidata), .init(value: "15", layer: .wikidata))
        XCTAssertEqual(PlayerRating.afterLookup(current: nil, answer: "15", answerLayer: nil), .init(value: "15", layer: nil))
    }

    func testTheLookupReplacesAWeakerRatingOnly() {
        // A source rating set at start is the strongest (R371: source, then TMDB, then Wikidata).
        let source = PlayerRating.Choice(value: "TV-14", layer: .source)
        XCTAssertNil(PlayerRating.afterLookup(current: source, answer: "TV-MA", answerLayer: .tmdb))
        XCTAssertNil(PlayerRating.afterLookup(current: source, answer: "15", answerLayer: .wikidata))
        XCTAssertNil(PlayerRating.afterLookup(current: source, answer: "15", answerLayer: nil), "an unknown layer ranks lowest")
        // The source's own answer may update it.
        XCTAssertEqual(PlayerRating.afterLookup(current: source, answer: "TV-MA", answerLayer: .source), .init(value: "TV-MA", layer: .source))
        // A weaker rating is replaced by a stronger one, and by one of the same layer.
        let wikidata = PlayerRating.Choice(value: "12", layer: .wikidata)
        XCTAssertEqual(PlayerRating.afterLookup(current: wikidata, answer: "PG-13", answerLayer: .tmdb), .init(value: "PG-13", layer: .tmdb))
        XCTAssertEqual(PlayerRating.afterLookup(current: wikidata, answer: "15", answerLayer: .wikidata), .init(value: "15", layer: .wikidata))
        let tmdb = PlayerRating.Choice(value: "PG-13", layer: .tmdb)
        XCTAssertNil(PlayerRating.afterLookup(current: tmdb, answer: "12", answerLayer: .wikidata))
    }

    func testTheLookupWithoutARatingOrTheSameValueChangesNothing() {
        let source = PlayerRating.Choice(value: "R", layer: .source)
        XCTAssertNil(PlayerRating.afterLookup(current: source, answer: nil, answerLayer: nil))
        XCTAssertNil(PlayerRating.afterLookup(current: source, answer: "NR", answerLayer: .source))
        XCTAssertNil(PlayerRating.afterLookup(current: source, answer: "Rated R", answerLayer: .source), "same value after cleaning")
        XCTAssertNil(PlayerRating.afterLookup(current: nil, answer: "Not Rated", answerLayer: .tmdb))
    }
}
