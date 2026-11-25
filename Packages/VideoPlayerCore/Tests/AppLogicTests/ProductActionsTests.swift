import XCTest
@testable import AppLogic

/// R471 Part 3 and 4: the actions list per type, Manage per type, and that an unbuilt action is never offered.
final class ProductActionsTests: XCTestCase {
    func testAMoviesFullListIsTheOwnersOrder() {
        var c = ProductActionContext(kind: .movie)
        c.started = true; c.matched = true; c.hasFile = true; c.versionCount = 2
        XCTAssertEqual(ProductActions.all(c), [.resume, .restart, .addToWatchlist, .addToList, .addToPlaylistOrCollection, .rate,
                                              .markWatched, .manage, .fileInfo, .moreWaysToWatch])
        c.onWatchlist = true; c.watched = true; c.started = false
        XCTAssertEqual(Array(ProductActions.all(c).prefix(2)), [.removeFromWatchlist, .addToList])
        XCTAssertTrue(ProductActions.all(c).contains(.markUnwatched))
    }

    func testAnEpisodesFullListStartsWithAudioAndSubtitlesAndGoesToItsShow() {
        var c = ProductActionContext(kind: .episode)
        c.hasFile = true
        XCTAssertEqual(ProductActions.all(c), [.audio, .subtitles, .addToList, .addToPlaylistOrCollection, .markWatched,
                                              .goToShow, .goToSeason, .manage, .fileInfo])
    }

    func testShowsAndSeasonsMarkEverythingAndHaveNoAudioOrSubtitles() {
        var show = ProductActionContext(kind: .show)
        show.someUnwatched = true; show.someWatched = true; show.matched = true
        let list = ProductActions.all(show)
        XCTAssertFalse(list.contains(.audio) || list.contains(.subtitles))
        XCTAssertTrue(list.contains(.markAllWatched) && list.contains(.markAllUnwatched))
        var season = ProductActionContext(kind: .season)
        season.someUnwatched = true
        XCTAssertEqual(ProductActions.all(season), [.addToList, .addToPlaylistOrCollection, .markAllWatched, .goToShow, .manage])
    }

    func testManageIsShorterForEpisodesAndSeasons() {
        var movie = ProductActionContext(kind: .movie)
        movie.matched = true; movie.hasFile = true
        XCTAssertEqual(ProductActions.manage(movie), [.changeArtwork, .editMetadata, .refreshMetadata, .analyze, .fixMatch, .unmatch,
                                                     .playHistory, .fileInfo, .delete])
        var episode = ProductActionContext(kind: .episode)
        episode.hasFile = true
        XCTAssertEqual(ProductActions.manage(episode), [.changeArtwork, .editMetadata, .analyze, .playHistory, .fileInfo, .delete])
        movie.fixMatchAllowed = false; movie.matched = false; movie.hasFile = false
        let limited = ProductActions.manage(movie)
        XCTAssertFalse(limited.contains(.fixMatch), "Restrictions turn Fix Match off (R460)")
        XCTAssertFalse(limited.contains(.unmatch), "nothing to unmatch")
        XCTAssertFalse(limited.contains(.fileInfo) || limited.contains(.analyze), "no file")
    }

    func testOnlyBuiltActionsAreOffered() {
        for kind in [ProductActionContext.Kind.movie, .episode, .show, .season] {
            var c = ProductActionContext(kind: kind)
            c.started = true; c.matched = true; c.hasFile = true; c.someWatched = true; c.someUnwatched = true; c.versionCount = 3
            XCTAssertTrue(ProductActions.list(c).allSatisfy { $0 == .manage || $0.isBuilt }, "\(kind)")
            XCTAssertTrue(ProductActions.manageList(c).allSatisfy(\.isBuilt), "\(kind)")
        }
        for kind in [ProductActionContext.Kind.movie, .episode, .show, .season] {
            let c = ProductActionContext(kind: kind)
            XCTAssertEqual(ProductActions.list(c).contains(.manage), !ProductActions.manageList(c).isEmpty,
                           "Manage is listed exactly when something inside it works (\(kind))")
        }
        XCTAssertFalse(ProductActions.list(ProductActionContext(kind: .movie)).contains(.rate), "Rate is not built yet")
    }

    func testTheDestructiveActionsAsk() {
        XCTAssertTrue(ProductAction.delete.needsConfirmation)
        XCTAssertTrue(ProductAction.unmatch.needsConfirmation)
        XCTAssertFalse(ProductAction.markWatched.needsConfirmation)
        XCTAssertTrue(ProductAction.allCases.filter(\.isManage).allSatisfy { ProductActions.manage({ var c = ProductActionContext(kind: .movie); c.matched = true; c.hasFile = true; return c }()).contains($0) })
    }
}
