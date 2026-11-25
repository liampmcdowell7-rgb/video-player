import XCTest
@testable import ScreenChecks

/// R471 (67), PROVISIONAL (owner 25 Nov 2026 round 7: "keep 0.30 (R453) for now, record 0.8 (R377) as the alternative; do
/// not change either value"): the three hero heights stay as the owner left them until the owner decides. Structure only,
/// from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testTheHeroHeightsStayAsTheOwnerLeftThem() throws {
        guard let block = try appSource("Packages/VideoPlayerCore/Sources/AppLogic/InfoBlock.swift"),
              let product = try appSource("App/Shared/ProductPageParts.swift"),
              let home = try appSource("App/Features/Home/HomeFeaturedView.swift") else { return }
        XCTAssertTrue(block.contains("public static let showHeroFraction: Double = 0.30"), "the show page: R453, for now")
        XCTAssertTrue(product.contains("static let heroFraction: CGFloat = 0.8"), "movie and episode pages: R377")
        XCTAssertTrue(home.contains("static let heightFraction: CGFloat = 0.8"), "Home: R377")
        guard let questions = try appSource("OPEN_QUESTIONS.md") else { return }
        XCTAssertTrue(questions.contains("(e) The show page's hero at 0.8, the height R377"), "0.8 kept as R453's open alternative")
    }
}
