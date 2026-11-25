import XCTest
@testable import ScreenChecks

/// R470: the cover is anchored at the WHOLE text column of each page, not at the title (the owner's photo of build
/// 202611250008: the episode's series line sat above the cover). Structure only, from the source: nothing is compiled or
/// run on tvOS here. The contrast along each block is proven in AppLogicTests/ArtReadabilityTests.
extension ScreenChecksTests {
    func testTheCoverIsAnchoredAtEachPagesTextColumn() throws {
        guard let title = try appSource("App/Shared/TitleHeader.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift"),
              let featured = try appSource("App/Features/Home/HomeFeaturedView.swift"),
              let home = try appSource("App/Features/Home/HomeRows.swift"),
              let reader = try appSource("App/Shared/ArtTextTop.swift") else { return }
        XCTAssertFalse(title.contains(".reportsArtTextTop()"), "the title alone reports the text's top again")
        // The episode and movie column: the series line is inside the stack that reports.
        XCTAssertTrue(detail.contains("                actions\n            }\n            // R470: the whole text column, from the series line of an episode down, reports its top for the cover behind it.\n            .reportsArtTextTop()"),
                      "the movie and episode text column does not report its top")
        let overline = try XCTUnwrap(detail.range(of: "ProductPage.episodeOverline"))
        let report = try XCTUnwrap(detail.range(of: ".reportsArtTextTop()"))
        XCTAssertLessThan(overline.lowerBound, report.lowerBound, "the series line is not inside the reporting column")
        XCTAssertTrue(seasons.contains(".reportsArtTextTop()\n                .productHero("), "the show and season column does not report its top")
        XCTAssertTrue(featured.contains(".reportsArtTextTop()\n        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)"),
                      "Home's featured column does not report its top")
        for (name, source) in [("detail", detail), ("seasons", seasons), ("home", home)] {
            XCTAssertTrue(source.contains(".artTextContent()"), "\(name): the scroll content names no coordinate space")
            XCTAssertTrue(source.contains(".artTextTop($textTop)"), "\(name): nothing reads the column's top")
        }
        // The reader keeps the LATEST value (the column grows upward as details load), not the largest.
        XCTAssertFalse(reader.contains("max(top"), "the reader keeps the largest value again")
        XCTAssertTrue(reader.contains("pageTop + insetTop + contentTop"), "the reader no longer adds the content inset")
    }
}
