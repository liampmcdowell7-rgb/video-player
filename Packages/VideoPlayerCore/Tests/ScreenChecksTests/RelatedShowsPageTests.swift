import XCTest
@testable import ScreenChecks

/// R471 (25), PROVISIONAL: the show page has Related between the cast and About, from the library only; both product
/// pages keep their genres in the library. Structure only, from the source: nothing is compiled or run on tvOS here.
extension ScreenChecksTests {
    /// R471 (26), PROVISIONAL (frame show t16s): Related comes before the cast.
    func testTheShowPageHasRelatedBetweenTheEpisodesAndTheCast() throws {
        guard let page = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        let names = ["EpisodeShelfRow(episodes:", "RelatedShowsShelf(shows: relatedShows", "CastShelf(cast: cast)",
                     "AboutSection(title: content.seriesTitle", "ProductInfoColumns("]
        let offsets: [Int] = try names.map { (name: String) -> Int in
            let range: Range<String.Index> = try XCTUnwrap(page.range(of: name), "no \(name)")
            return page.distance(from: page.startIndex, to: range.lowerBound)
        }
        XCTAssertEqual(offsets, offsets.sorted(), "episodes, Related, cast, About, then the columns")
        XCTAssertTrue(page.contains("RelatedShows.find(seriesID: seriesID, genres: genres, store: services.store)"), "from the library only")
        XCTAssertTrue(page.contains("services.genreRecorder.record(genres"), "the show's genres are kept for other pages")
    }

    func testTheMoviePageKeepsItsGenresAndTheShelfUsesSeriesCards() throws {
        guard let movie = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let shelf = try appSource("App/Features/Shows/RelatedShowsShelf.swift") else { return }
        XCTAssertTrue(movie.contains("services.genreRecorder.record(details?.genres ?? [], itemIDs: [content.itemID]"))
        XCTAssertTrue(shelf.contains("SeriesCard(series: show,"), "portrait posters with the show's long-press menu")
        XCTAssertTrue(shelf.contains("ShelfHeader(RelatedTitles.heading)"), "the same heading as the movie page")
        XCTAssertFalse(shelf.contains("online"), "no online lookup")
    }
}
