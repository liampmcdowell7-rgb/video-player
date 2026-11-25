import XCTest
@testable import AppLogic

/// R471 item 1: when the page counts as scrolled below its hero, and how strong the cover of the blurred copy is.
final class ProductScrollTests: XCTestCase {
    func testAtRestAndJustScrolledTheHeroIsStillClear() {
        XCTAssertFalse(ProductScroll.isBelowHero(offset: 0, heroHeight: 864))
        XCTAssertFalse(ProductScroll.isBelowHero(offset: -40, heroHeight: 864), "the overscroll at the top is no scroll")
        XCTAssertFalse(ProductScroll.isBelowHero(offset: 864 * ProductScroll.belowHeroShare - 1, heroHeight: 864))
    }

    func testPastTheShareThePageIsBelowTheHero() {
        XCTAssertTrue(ProductScroll.isBelowHero(offset: 864 * ProductScroll.belowHeroShare, heroHeight: 864))
        XCTAssertTrue(ProductScroll.isBelowHero(offset: 2_000, heroHeight: 864))
    }

    func testAPageNotMeasuredYetIsNeverBelowItsHero() {
        XCTAssertFalse(ProductScroll.isBelowHero(offset: 500, heroHeight: 0))
        XCTAssertFalse(ProductScroll.isBelowHero(offset: .nan, heroHeight: 864))
        XCTAssertFalse(ProductScroll.isBelowHero(offset: .infinity, heroHeight: 864))
    }

    /// The blurred copy's cover is the hero cover's full strength, so text below the hero is at least as readable.
    func testTheCoverBelowTheHeroIsTheStrengthProvedAtTheText() {
        XCTAssertEqual(ProductScroll.belowHeroCoverOpacity, ArtReadability.scrimMaxOpacity)
        let start = ArtReadability.coverStart(textTop: 700, height: 1080)
        let strongestHero = ArtReadability.coverStops(start: start).map(\.alpha).max() ?? 0
        XCTAssertGreaterThanOrEqual(ProductScroll.belowHeroCoverOpacity, strongestHero)
    }
}
