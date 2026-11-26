import XCTest
@testable import AppLogic
import LibraryIndex
import VideoPlayerCore

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

    /// R471 (46): the featured title's kind line is its page's: the kind word (a show for an episode), genres, rating box.
    func testTheFeaturedKindLineIsThePagesLine() {
        let movie = HomeFeatured(card: card(1, "A"), shelf: .recentlyAdded)
        XCTAssertEqual(movie.kindLine(genres: ["Drama", "Mystery"], rating: "PG"),
                       [.text("Movie"), .text("Drama"), .text("Mystery"), .ratingBox("PG")])
        let episode = HomeFeatured(card: card(2, "B", kind: .episode, series: 4), shelf: .nextUp)
        XCTAssertEqual(episode.kindLine(genres: [], rating: nil), [.text("TV Show")], "an episode is shown as its show")
        XCTAssertEqual(HomeFeatured.synopsisLines, 3)
    }

    /// R471 (86): the featured kind line starts with the source's glyph, as the pages' line does.
    func testTheFeaturedKindLineStartsWithTheSourceGlyph() {
        let movie = HomeFeatured(card: card(1, "A"), shelf: .recentlyAdded)
        XCTAssertEqual(movie.kindLine(source: .plex, genres: ["Drama"], rating: "PG"),
                       HeroLines.kindLine(kind: .movie, source: .plex, genres: ["Drama"], rating: "PG"))
        XCTAssertEqual(movie.kindLine(source: .plex, genres: [], rating: nil).first,
                       .glyph(symbol: SourceGlyph.symbol(.plex), spoken: SourceGlyph.spoken(.plex)))
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

    /// R471 (102): Home's Play gets the featured title's length, the played file's first, so a started title shows the
    /// time left inside the capsule as its page does; nothing invented when no length is known.
    func testTheFeaturedPlayKnowsTheTitlesLength() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        var item = try XCTUnwrap(episodes.first)
        item.runtime = 2_700
        item.watch.duration = 3_000
        XCTAssertEqual(HomeFeatured.playSeconds(of: item), 3_000, "the played file's own length first")
        item.watch.duration = nil
        XCTAssertEqual(HomeFeatured.playSeconds(of: item), 2_700, "else the catalogue runtime")
        item.runtime = 0
        XCTAssertNil(HomeFeatured.playSeconds(of: item))
        item.runtime = 3_000
        let capsule = PlayCapsule.make(progress: 0.4, durationSeconds: HomeFeatured.playSeconds(of: item))
        XCTAssertEqual(capsule.timeLeft, "30m", "40% of 50 minutes watched: 30m left in Play")
    }
}
