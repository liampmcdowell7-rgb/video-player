import XCTest
@testable import AppLogic

/// R339: seasons as tabs above one episode list.
final class SeasonTabsTests: XCTestCase {
    private func season(_ n: Int, ids: [Int64]) -> SeasonSection {
        SeasonSection(season: n, title: "Season \(n)",
                      episodes: ids.map { EpisodeRow(id: $0, title: "E", code: "S\(n), E1", runtimeText: nil, progress: nil, isWatched: false, artworkKey: "k") },
                      watchedCount: 0)
    }

    func testStyleByCount() {
        XCTAssertEqual(SeasonTabs.style(seasonCount: 0), .heading)
        XCTAssertEqual(SeasonTabs.style(seasonCount: 1), .heading)
        XCTAssertEqual(SeasonTabs.style(seasonCount: 2), .segmented)
        XCTAssertEqual(SeasonTabs.style(seasonCount: 7), .segmented, "HIG: about five to seven segments")
        XCTAssertEqual(SeasonTabs.style(seasonCount: 8), .menu)
    }

    func testShownSeason() {
        let seasons = [season(1, ids: [1, 2]), season(2, ids: [3, 4])]
        XCTAssertEqual(SeasonTabs.shown(seasons, chosen: nil, resumeEpisodeID: nil)?.season, 1, "the first")
        XCTAssertEqual(SeasonTabs.shown(seasons, chosen: nil, resumeEpisodeID: 4)?.season, 2, "the season Play starts in")
        XCTAssertEqual(SeasonTabs.shown(seasons, chosen: 1, resumeEpisodeID: 4)?.season, 1, "the person's choice wins")
        XCTAssertEqual(SeasonTabs.shown(seasons, chosen: 9, resumeEpisodeID: 4)?.season, 2, "a season that went away")
        XCTAssertNil(SeasonTabs.shown([], chosen: nil, resumeEpisodeID: nil))
    }
}
