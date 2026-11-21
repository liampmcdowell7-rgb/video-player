import XCTest
@testable import AppLogic
import LibraryIndex

// R349 (item C): the featured title of Home and the shape of each shelf.
final class HomeLayoutTests: XCTestCase {
    private func card(_ id: Int64, _ title: String, kind: ItemKind = .movie, progress: Double? = nil, series: Int64? = nil,
                      badges: [String] = [], second: [String] = []) -> ItemCard {
        ItemCard(id: id, kind: kind, title: title, subtitle: second.joined(separator: ShortLine.separator), progress: progress,
                 isWatched: false, isFavorite: false, badges: badges, artworkKey: "item-\(id)",
                 subtitleLine: ShortLine(ordered: second), badgeLine: ShortLine(ordered: badges), seriesID: series)
    }

    private func rows(_ pairs: [(HomeRowID, [ItemCard])]) -> [HomeRow] {
        pairs.map { HomeRow(id: $0.0, title: HomeViewModel.title(of: $0.0), cards: $0.1) }
    }

    func testContinueWatchingLeadsThenRecentlyAddedThenNextUp() {
        let all = rows([(.nextUp, [card(3, "Next")]), (.recentlyAdded, [card(2, "New")]),
                        (.continueWatching, [card(1, "Started", progress: 0.3)])])
        XCTAssertEqual(HomeFeatured.pick(from: all)?.card.id, 1)
        XCTAssertEqual(HomeFeatured.pick(from: all)?.shelf, .continueWatching)
        XCTAssertEqual(HomeFeatured.pick(from: Array(all.prefix(2)))?.card.id, 2, "without Continue Watching: Recently Added")
        XCTAssertEqual(HomeFeatured.pick(from: Array(all.prefix(1)))?.card.id, 3, "Next Up last")
    }

    func testTheHomeScreenSettingsDecide_aHiddenShelfGivesNoFeaturedTitle() {
        // The view passes only the shelves that show; with none, nothing is featured.
        XCTAssertNil(HomeFeatured.pick(from: []))
        XCTAssertNil(HomeFeatured.pick(from: rows([(.continueWatching, [])])), "an empty shelf gives nothing")
    }

    func testResumeForAStartedTitleAndPlayOtherwise() {
        XCTAssertEqual(HomeFeatured(card: card(1, "A", progress: 0.4), shelf: .continueWatching).playTitle, "Resume")
        XCTAssertEqual(HomeFeatured(card: card(1, "A"), shelf: .recentlyAdded).playTitle, "Play")
    }

    func testAnEpisodeShowsItsShowsArtworkAndLogo() {
        XCTAssertEqual(HomeFeatured(card: card(7, "Show", kind: .episode, series: 4), shelf: .nextUp).titleArtworkKey, "series-4")
        XCTAssertEqual(HomeFeatured(card: card(7, "Movie"), shelf: .recentlyAdded).titleArtworkKey, "item-7")
    }

    func testTheMetadataLineIsTheSecondLineThenTheBadgesWhichGoFirst() {
        let featured = HomeFeatured(card: card(1, "A", badges: ["4K", "Dolby Vision"], second: ["2021"]), shelf: .recentlyAdded)
        XCTAssertEqual(featured.metadata.full, "2021 · 4K · Dolby Vision")
        let year: Int = featured.metadata.segments.first { $0.text == "2021" }!.priority
        XCTAssertTrue(featured.metadata.segments.filter { $0.text != "2021" }.allSatisfy { $0.priority < year })
    }

    func testLandscapeShelvesAreContinueWatchingAndNextUp() {
        XCTAssertTrue(HomeRowID.continueWatching.usesLandscapeCards)
        XCTAssertTrue(HomeRowID.nextUp.usesLandscapeCards)
        XCTAssertFalse(HomeRowID.recentlyAdded.usesLandscapeCards)
    }
}
