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
}
