import XCTest
@testable import ScreenChecks

/// R471 (21), PROVISIONAL (owner): the product pages have no How to Watch card and no show-page seasons line, and the
/// sections below the hero keep their order without it. Structure only, from the source: nothing is compiled or run on
/// tvOS here.
extension ScreenChecksTests {
    /// The offsets of `names` in `source`, in the order given; fails for a missing one.
    private func offsets(of names: [String], in source: String) throws -> [Int] {
        try names.map { (name: String) -> Int in
            let range: Range<String.Index> = try XCTUnwrap(source.range(of: name), "no \(name)")
            return source.distance(from: source.startIndex, to: range.lowerBound)
        }
    }

    func testProductPagesHaveNoHowToWatch() throws {
        let paths: [String] = ["App/Features/Detail/ItemDetailContentView.swift", "App/Features/Shows/SeasonsList.swift",
                               "App/Shared/ProductSectionsView.swift", "Packages/VideoPlayerCore/Sources/AppLogic/ProductSections.swift"]
        for path in paths {
            guard let source = try appSource(path) else { return }
            for gone in ["HowToWatch", "howToWatch", "seasonsLine", "product.howToWatch"] {
                XCTAssertFalse(source.contains(gone), "\(path) still has \(gone)")
            }
        }
    }

    /// The movie and episode page: trailers, bonus content, related, cast, About, then the columns (R471 (26)).
    func testMovieAndEpisodePageOrderWithoutHowToWatch() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        let order: [Int] = try offsets(of: ["ExtrasShelf(heading: ExtraShelves.trailersHeading", "ExtrasShelf(heading: ExtraShelves.bonusHeading",
                                            "RelatedShelf(cards: related)", "CastShelf(cast: cast)", "AboutSection(title: content.title",
                                            "ProductInfoColumns(information:"], in: detail)
        XCTAssertEqual(order, order.sorted(), "the movie and episode page sections are out of order")
    }

    /// The show page: the episodes, the cast, About, then the columns.
    func testShowPageOrderWithoutHowToWatch() throws {
        guard let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        let order: [Int] = try offsets(of: ["EpisodeShelfRow(episodes:", "CastShelf(cast: cast)", "AboutSection(title: content.seriesTitle",
                                            "ProductInfoColumns(information:"], in: seasons)
        XCTAssertEqual(order, order.sorted(), "the show page sections are out of order")
    }
}
