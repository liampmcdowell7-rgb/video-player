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
        XCTAssertEqual(ProductActions.all(c), [.audio, .subtitles, .addToList, .addToPlaylistOrCollection, .rate, .markWatched,
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
        XCTAssertEqual(ProductActions.all(season), [.addToList, .addToPlaylistOrCollection, .rate, .markAllWatched, .goToShow, .manage])
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
        XCTAssertTrue(ProductActions.list(ProductActionContext(kind: .movie)).contains(.rate), "Rate is built (R471 (16))")
    }

    func testALongPressOffersThePagesOwnActionsInThePagesOrder() {
        var movie = ProductActionContext(kind: .movie)
        movie.started = true; movie.hasFile = true; movie.matched = true
        XCTAssertEqual(ProductActions.cardList(movie), [.rate, .markWatched, .changeArtwork, .editMetadata, .unmatch, .delete])
        movie.watched = true
        XCTAssertEqual(ProductActions.cardList(movie), [.rate, .markUnwatched, .changeArtwork, .editMetadata, .unmatch, .delete])
        for kind in [ProductActionContext.Kind.movie, .episode, .show, .season] {
            var c = ProductActionContext(kind: kind)
            c.started = true; c.matched = true; c.hasFile = true; c.someWatched = true; c.someUnwatched = true
            let page = ProductActions.list(c) + ProductActions.manageList(c)
            let card = ProductActions.cardList(c)
            XCTAssertTrue(card.allSatisfy(page.contains), "a card never offers what the page does not (\(kind))")
            XCTAssertEqual(card, page.filter(card.contains), "same order as the page (\(kind))")
        }
    }

    func testACardsContextFollowsTheCard() {
        let card = ItemCard(id: 7, kind: .episode, title: "Pilot", subtitle: nil, progress: 0.4, isWatched: false, isFavorite: false,
                            badges: [], artworkKey: "item-7")
        let c = card.actionContext
        XCTAssertEqual(c.kind, .episode)
        XCTAssertTrue(c.started)
        XCTAssertFalse(c.watched)
        XCTAssertEqual(ProductActions.cardList(c), [.rate, .markWatched, .changeArtwork, .editMetadata, .delete])
    }

    func testTheDestructiveActionsAsk() {
        XCTAssertTrue(ProductAction.delete.needsConfirmation)
        XCTAssertTrue(ProductAction.unmatch.needsConfirmation)
        XCTAssertFalse(ProductAction.markWatched.needsConfirmation)
        XCTAssertTrue(ProductAction.allCases.filter(\.isManage).allSatisfy { ProductActions.manage({ var c = ProductActionContext(kind: .movie); c.matched = true; c.hasFile = true; return c }()).contains($0) })
    }
}
