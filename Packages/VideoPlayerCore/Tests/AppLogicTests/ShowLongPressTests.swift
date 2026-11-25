import XCTest
@testable import AppLogic

/// R471 (23): a long press on a show's poster and on a season offers the page's own actions (Edit Details and Manage
/// opened out), kept to what a card can run. FIXTURE: invented shows and episodes.
final class ShowLongPressTests: XCTestCase {
    private func row(_ id: Int64, watched: Bool) -> EpisodeRow {
        EpisodeRow(id: id, title: "Episode " + String(id), code: "E" + String(id), runtimeText: nil, progress: nil, isWatched: watched,
                   artworkKey: "item-" + String(id))
    }

    func testAShowsPosterOffersEditManageAndMarkAll() {
        let partly = SeriesSummary(id: 4, title: "Show One", episodeCount: 5, unwatchedCount: 2, seasonCount: 2, artworkKey: "series-4")
        XCTAssertEqual(ProductActions.cardList(partly.actionContext),
                       [.addToList, .addToPlaylistOrCollection, .rate, .markAllWatched, .markAllUnwatched, .changeArtwork, .editMetadata, .delete])
        let unseen = SeriesSummary(id: 4, title: "Show One", episodeCount: 5, unwatchedCount: 5, seasonCount: 2, artworkKey: "series-4")
        XCTAssertEqual(ProductActions.cardList(unseen.actionContext),
                       [.addToList, .addToPlaylistOrCollection, .rate, .markAllWatched, .changeArtwork, .editMetadata, .delete])
        let seen = SeriesSummary(id: 4, title: "Show One", episodeCount: 5, unwatchedCount: 0, seasonCount: 2, artworkKey: "series-4")
        XCTAssertFalse(ProductActions.cardList(seen.actionContext).contains(.markAllWatched))
        XCTAssertTrue(ProductActions.cardList(seen.actionContext).contains(.markAllUnwatched))
    }

    func testAShowsPosterHasNoUnmatchOrFixMatchAndNoDeleteUnderRestrictions() {
        var c = SeriesSummary(id: 4, title: "Show One", episodeCount: 1, unwatchedCount: 1, seasonCount: 1, artworkKey: "series-4").actionContext
        let card = ProductActions.cardList(c)
        XCTAssertFalse(card.contains(.unmatch), "whether the show is matched is not known on the poster")
        XCTAssertFalse(card.contains(.fixMatch))
        XCTAssertFalse(card.contains(.refreshMetadata), "Refresh Details stays on the page (it reports its result there)")
        c.deleteAllowed = false
        XCTAssertFalse(ProductActions.cardList(c).contains(.delete))
    }

    func testASeasonOffersRateMarkAllEditAndDeleteButNoLists() {
        let season = SeasonSection(season: 2, title: "Season 2", episodes: [row(1, watched: true), row(2, watched: false)], watchedCount: 1)
        XCTAssertEqual(ProductActions.cardList(season.actionContext), [.rate, .markAllWatched, .markAllUnwatched, .changeArtwork, .editMetadata, .delete])
        let done = SeasonSection(season: 2, title: "Season 2", episodes: [row(1, watched: true)], watchedCount: 1)
        XCTAssertEqual(ProductActions.cardList(done.actionContext), [.rate, .markAllUnwatched, .changeArtwork, .editMetadata, .delete])
    }

    func testAMoviesAndAnEpisodesCardListIsUnchanged() {
        var movie = ProductActionContext(kind: .movie)
        movie.hasFile = true; movie.matched = true; movie.someUnwatched = true; movie.someWatched = true
        XCTAssertEqual(ProductActions.cardList(movie), [.addToList, .addToPlaylistOrCollection, .rate, .markWatched, .changeArtwork, .editMetadata, .unmatch, .delete],
                       "Mark All belongs to shows and seasons only")
    }
}
