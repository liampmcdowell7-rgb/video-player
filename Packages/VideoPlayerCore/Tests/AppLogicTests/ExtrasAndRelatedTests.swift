import XCTest
import LibraryIndex
@testable import AppLogic

/// R471 item 7: Trailers and Bonus Content from the extras we hold; Related from the library only.
final class ExtrasAndRelatedTests: XCTestCase {
    private func extra(_ id: Int64, _ name: String, video: Bool = true) -> ExtraRow {
        ExtraRow(id: id, name: name, kindText: video ? "Video" : "Information", sizeText: nil, isVideo: video)
    }

    func testExtrasSplitIntoTrailersAndBonusByName() {
        let split = ExtraShelves.split([extra(1, "Harbour-trailer.mkv"), extra(2, "Teaser 2.mp4"), extra(3, "Making of-featurette.mkv"),
                                        extra(4, "movie.nfo", video: false), extra(5, "Deleted scenes.mkv")])
        XCTAssertEqual(split.trailers.map(\.id), [1, 2])
        XCTAssertEqual(split.bonus.map(\.id), [3, 5], "information files stay in the menu only")
    }

    func testAnExtrasNameDropsItsExtensionAndTag() {
        XCTAssertEqual(ExtraShelves.displayName("Harbour-trailer.mkv"), "Harbour")
        XCTAssertEqual(ExtraShelves.displayName("Making.of-featurette.mkv"), "Making of")
        XCTAssertEqual(ExtraShelves.displayName("-trailer.mkv"), "-trailer.mkv", "never an empty name")
    }

    func testRelatedAsksTheLibraryForTheSameKindAndGenres() throws {
        let query = try XCTUnwrap(RelatedTitles.query(kind: .movie, genres: ["Drama", " ", "Crime"]))
        XCTAssertEqual(query.filter.kinds, [.movie])
        XCTAssertEqual(query.filter.genres, ["Drama", "Crime"])
        XCTAssertEqual(query.sort.key, .rating)
        XCTAssertNil(RelatedTitles.query(kind: .movie, genres: []), "no genres, no shelf")
    }

    func testRelatedLeavesItselfOutAndRanksBySharedGenresThenRating() {
        let items = [RelatedTitles.Candidate(id: 1, title: "Self", rating: 9),
                     RelatedTitles.Candidate(id: 2, title: "Bravo", rating: 6),
                     RelatedTitles.Candidate(id: 3, title: "Alpha", rating: 8),
                     RelatedTitles.Candidate(id: 4, title: "Charlie", rating: 5),
                     RelatedTitles.Candidate(id: 3, title: "Alpha", rating: 8)]
        let genres: [Int64: [String]] = [2: ["Drama", "Crime"], 3: ["Drama"], 4: ["drama", "CRIME"]]
        let ids = RelatedTitles.rank(items, excluding: 1, genres: ["Drama", "Crime"], genresOf: { genres[$0] })
        XCTAssertEqual(ids, [2, 4, 3], "two shared genres first (higher rating first), then one")
        XCTAssertEqual(RelatedTitles.rank(items, excluding: 1, genres: ["Drama"]), [3, 2, 4], "unknown genres: by rating")
        let many = (10..<40).map { RelatedTitles.Candidate(id: Int64($0), title: "T\($0)", rating: nil) }
        XCTAssertEqual(RelatedTitles.rank(many, excluding: 0, genres: ["Drama"]).count, RelatedTitles.limit)
    }
}
