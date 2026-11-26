import XCTest
@testable import AppLogic

/// R471 item 6: the show page's age guidance card, episode card text and hero description, from held data only.
final class ShowPageTextTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    func testAgeGuidanceSaysTheRatingAndWhereItCameFrom() {
        let card = AgeGuidance.make(rating: " TV-MA ", layer: .tmdb, descriptors: ["Language", "language", "Violence"])
        XCTAssertEqual(card, AgeGuidance(rating: "TV-MA", source: "Rating from TMDB", descriptors: ["Language", "Violence"]))
        XCTAssertEqual(AgeGuidance.make(rating: "15", layer: .source, descriptors: [])?.source, "Rating from your media server")
        XCTAssertNil(AgeGuidance.make(rating: "15", layer: nil, descriptors: [])?.source)
        XCTAssertNil(AgeGuidance.make(rating: nil, layer: .wikidata, descriptors: ["Violence"]), "no rating, no card: nothing invented")
        XCTAssertNil(AgeGuidance.make(rating: "  ", layer: .tmdb, descriptors: []))
    }

    func testAnEpisodeCardsTextComesFromItsDetails() {
        var details = TitleDetails(overview: "A storm reaches the harbour.", cast: [])
        details.releaseDate = PartialDate(year: 2024, month: 3, day: 5)
        details.contentRating = "TV-14"
        let text = EpisodeCardText.make(number: 4, title: "Low Tide", details: details, watched: true, hideSpoilers: true, locale: en)
        XCTAssertEqual(text.overline, "Episode 4")
        XCTAssertEqual(text.title, "Low Tide")
        XCTAssertEqual(text.description, "A storm reaches the harbour.")
        XCTAssertNotNil(text.date)
        XCTAssertEqual(text.rating, "TV-14")
        let hidden = EpisodeCardText.make(number: 4, title: "Low Tide", details: details, watched: false, hideSpoilers: true, locale: en)
        XCTAssertNotEqual(hidden.description, "A storm reaches the harbour.", "Hide Spoilers hides an unwatched episode's text")
        let bare = EpisodeCardText.make(number: 0, title: "Special", details: nil, watched: false, hideSpoilers: false)
        XCTAssertNil(bare.overline)
        XCTAssertNil(bare.description)
        XCTAssertNil(bare.date)
    }

    /// R471 (96): an episode card with no rating of its own shows the show's (frames show t12s, t14s); its own rating wins.
    func testAnEpisodeCardBorrowsTheShowsRating() {
        let bare = EpisodeCardText.make(number: 1, title: "Pilot", details: nil, watched: false, hideSpoilers: false,
                                        seriesRating: "TV-MA", locale: en)
        XCTAssertEqual(bare.rating, "TV-MA")
        var own = TitleDetails(overview: nil, cast: [])
        own.contentRating = "TV-14"
        XCTAssertEqual(EpisodeCardText.make(number: 1, title: "Pilot", details: own, watched: false, hideSpoilers: false,
                                            seriesRating: "TV-MA", locale: en).rating, "TV-14")
        own.contentRating = " "
        XCTAssertEqual(EpisodeCardText.make(number: 1, title: "Pilot", details: own, watched: false, hideSpoilers: false,
                                            seriesRating: "TV-MA", locale: en).rating, "TV-MA", "a blank rating is none")
        XCTAssertNil(EpisodeCardText.make(number: 1, title: "Pilot", details: nil, watched: false, hideSpoilers: false).rating)
    }

    func testTheShowHeroDescribesTheNextEpisodeElseTheShow() {
        let next = ShowHeroText.description(showOverview: "The show.", nextCode: "S4, E4", nextTitle: "Low Tide", nextOverview: "The episode.")
        XCTAssertEqual(next?.prefix, "S4, E4 · Low Tide:")
        XCTAssertEqual(next?.text, "The episode.")
        let show = ShowHeroText.description(showOverview: "The show.", nextCode: "S4, E4", nextTitle: "Low Tide", nextOverview: " ")
        XCTAssertNil(show?.prefix)
        XCTAssertEqual(show?.text, "The show.")
        XCTAssertNil(ShowHeroText.description(showOverview: nil, nextCode: nil, nextTitle: nil, nextOverview: nil))
    }
}
