import XCTest
@testable import LibraryIndex
@testable import AppLogic

/// R471 (40): a Related card's focus caption, the kind of title and the genre it shares with the page.
/// FIXTURE: invented titles and genres.
final class RelatedCaptionTests: XCTestCase {
    func testTheCaptionIsTheKindAndTheSharedGenre() {
        XCTAssertEqual(RelatedCaption.text(kind: .show, genre: "Comedy"), "Show · Comedy")
        XCTAssertEqual(RelatedCaption.text(kind: .movie, genre: " Drama "), "Movie · Drama")
        XCTAssertEqual(RelatedCaption.text(kind: .movie, genre: nil), "Movie", "the kind alone when no genre is known")
        XCTAssertEqual(RelatedCaption.text(kind: .show, genre: ""), "Show")
    }

    func testEachTitleGetsThePagesFirstGenreItShares() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let aftlander = try await rig.movieID("Aftlander")
        let zornwick = try await rig.movieID("Zornwick")
        try await rig.store.setMetadata(itemID: aftlander, ItemMetadata(genres: ["Drama", "Mystery"]))
        try await rig.store.setMetadata(itemID: zornwick, ItemMetadata(genres: ["Mystery"]))
        let movies = try await RelatedCaption.sharedGenres(kind: .movie, genres: ["Drama", "Mystery"], store: rig.store)
        XCTAssertEqual(movies[aftlander], "Drama", "the page's first genre wins")
        XCTAssertEqual(movies[zornwick], "Mystery")
        let hexfall = try await rig.movieID("Hexfall")
        XCTAssertNil(movies[hexfall], "no shared genre, no entry")

        let episodes = try await rig.episodes(ofSeriesTitle: "Show Two")
        let showTwo = try XCTUnwrap(episodes.first?.seriesID)
        for episode in episodes { try await rig.store.setMetadata(itemID: episode.id, ItemMetadata(genres: ["Comedy"])) }
        let shows = try await RelatedCaption.sharedGenres(kind: .show, genres: ["Comedy"], store: rig.store)
        XCTAssertEqual(shows[showTwo], "Comedy", "a show is keyed by its own id, found through its episodes")
    }
}
