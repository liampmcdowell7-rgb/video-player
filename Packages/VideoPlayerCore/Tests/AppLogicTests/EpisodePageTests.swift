import XCTest
import LibraryIndex
@testable import AppLogic

/// R387: the episode page's choices (`EpisodePage`): the row of the season's other episodes and the rating on the
/// metadata line. Every empty part is left out.
final class EpisodePageTests: XCTestCase {
    private func row(_ id: Int64, watched: Bool = false) -> EpisodeRow {
        EpisodeRow(id: id, title: "Episode \(id)", code: "S1, E\(id)", runtimeText: "42 min", progress: nil, isWatched: watched,
                   artworkKey: "item-\(id)")
    }

    private var seasons: [SeasonSection] {
        [SeasonSection(season: 1, title: "Season 1", episodes: [row(1, watched: true), row(2), row(3, watched: true)], watchedCount: 2),
         SeasonSection(season: 2, title: "Season 2", episodes: [row(4)], watchedCount: 0)]
    }

    func testTheRowIsTheEpisodesSeasonWithoutTheEpisodeInOrder() throws {
        let other = try XCTUnwrap(EpisodePage.otherEpisodes(in: seasons, season: 1, currentID: 2))
        XCTAssertEqual(other.season, 1)
        XCTAssertEqual(other.title, "Season 1")
        XCTAssertEqual(other.episodes.map(\.id), [1, 3])
        XCTAssertEqual(other.watchedCount, 2)
    }

    func testTheEpisodesIDWinsOverAWrongSeasonNumber() throws {
        let other = try XCTUnwrap(EpisodePage.otherEpisodes(in: seasons, season: 2, currentID: 3))
        XCTAssertEqual(other.season, 1)
        XCTAssertEqual(other.episodes.map(\.id), [1, 2])
    }

    func testTheSeasonNumberFindsTheSeasonWhenTheEpisodeIsNotListed() throws {
        let other = try XCTUnwrap(EpisodePage.otherEpisodes(in: seasons, season: 2, currentID: 99))
        XCTAssertEqual(other.episodes.map(\.id), [4])
    }

    func testNoRowForTheOnlyEpisodeOfASeasonOrAnUnknownSeason() {
        XCTAssertNil(EpisodePage.otherEpisodes(in: seasons, season: 2, currentID: 4))
        XCTAssertNil(EpisodePage.otherEpisodes(in: seasons, season: 7, currentID: 99))
        XCTAssertNil(EpisodePage.otherEpisodes(in: seasons, season: nil, currentID: 99))
        XCTAssertNil(EpisodePage.otherEpisodes(in: [], season: 1, currentID: 1))
    }

    func testTheEpisodesOwnRatingFirstThenTheShowsThenNone() {
        XCTAssertEqual(EpisodePage.rating(episode: "TV-14", series: "TV-MA"), "TV-14")
        XCTAssertEqual(EpisodePage.rating(episode: nil, series: "TV-MA"), "TV-MA")
        XCTAssertEqual(EpisodePage.rating(episode: " ", series: "TV-MA"), "TV-MA")
        XCTAssertNil(EpisodePage.rating(episode: nil, series: ""))
        XCTAssertNil(EpisodePage.rating(episode: nil, series: nil))
    }

    func testOnlyAnEpisodeWithAShowAndNoRatingOfItsOwnBorrowsTheShows() {
        XCTAssertTrue(EpisodePage.needsSeriesRating(kind: .episode, seriesID: 5, ownRating: nil))
        XCTAssertTrue(EpisodePage.needsSeriesRating(kind: .episode, seriesID: 5, ownRating: ""))
        XCTAssertFalse(EpisodePage.needsSeriesRating(kind: .episode, seriesID: 5, ownRating: "TV-14"))
        XCTAssertFalse(EpisodePage.needsSeriesRating(kind: .episode, seriesID: nil, ownRating: nil))
        XCTAssertFalse(EpisodePage.needsSeriesRating(kind: .movie, seriesID: nil, ownRating: nil))
    }

    /// R471 (85): genres, content advice and regions the episode lacks are the show's; its own win.
    func testAnEpisodeBorrowsTheShowsListsWhenItHasNone() {
        XCTAssertEqual(EpisodePage.borrowed([], series: ["Comedy", "Sports"]), ["Comedy", "Sports"])
        XCTAssertEqual(EpisodePage.borrowed(nil, series: ["Comedy"]), ["Comedy"])
        XCTAssertEqual(EpisodePage.borrowed(["Drama"], series: ["Comedy"]), ["Drama"])
        XCTAssertEqual(EpisodePage.borrowed([String](), series: nil), [])
    }

    func testAnEpisodeAsksForTheShowsDetailsWhenAnyListOrTheRatingIsMissing() {
        let full = (rating: "TV-14", genres: ["Drama"], advice: ["Violence"], regions: 1)
        XCTAssertFalse(EpisodePage.needsSeriesDetails(kind: .episode, seriesID: 5, ownRating: full.rating, ownGenres: full.genres,
                                                      ownAdvisories: full.advice, ownRegionCount: full.regions))
        XCTAssertTrue(EpisodePage.needsSeriesDetails(kind: .episode, seriesID: 5, ownRating: full.rating, ownGenres: [],
                                                     ownAdvisories: full.advice, ownRegionCount: full.regions))
        XCTAssertTrue(EpisodePage.needsSeriesDetails(kind: .episode, seriesID: 5, ownRating: full.rating, ownGenres: full.genres,
                                                     ownAdvisories: nil, ownRegionCount: full.regions))
        XCTAssertTrue(EpisodePage.needsSeriesDetails(kind: .episode, seriesID: 5, ownRating: full.rating, ownGenres: full.genres,
                                                     ownAdvisories: full.advice, ownRegionCount: 0))
        XCTAssertTrue(EpisodePage.needsSeriesDetails(kind: .episode, seriesID: 5, ownRating: nil, ownGenres: full.genres,
                                                     ownAdvisories: full.advice, ownRegionCount: full.regions))
        XCTAssertFalse(EpisodePage.needsSeriesDetails(kind: .episode, seriesID: nil, ownRating: nil, ownGenres: nil,
                                                      ownAdvisories: nil, ownRegionCount: 0))
        XCTAssertFalse(EpisodePage.needsSeriesDetails(kind: .movie, seriesID: nil, ownRating: nil, ownGenres: nil,
                                                      ownAdvisories: nil, ownRegionCount: 0))
    }
}
