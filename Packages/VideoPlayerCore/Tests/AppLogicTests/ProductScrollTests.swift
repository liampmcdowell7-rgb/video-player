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

/// R471 (120): the motion between the hero and the part below it (`HeroMotion`), against the owner's timing table.
final class HeroMotionTests: XCTestCase {
    private let page: Double = 1080

    func testTheChosenValues() {
        XCTAssertEqual(HeroMotion.headerLogoWidthRatio, 1.3)
        XCTAssertEqual(HeroMotion.headerTextWidthRatio, 1.5)
        XCTAssertEqual(HeroMotion.headerStart(.logo), 0.60)
        XCTAssertEqual(HeroMotion.headerRest(.logo), 0.14)
        XCTAssertEqual(HeroMotion.headerStart(.text), 0.50)
        XCTAssertEqual(HeroMotion.headerRest(.text), 0.12)
        XCTAssertEqual(HeroMotion.heroEntry, 0.5)
        XCTAssertEqual(HeroMotion.sectionRise, 40)
        XCTAssertEqual(HeroMotion.topFadeHeight, 90)
    }

    /// The hero group leaves much faster than the header lands (owner: about 0.15 s against 0.55 s).
    func testTheHeroLeavesFastAndTheHeaderLandsSlowly() {
        for title in [HeroMotion.Title.logo, .text] {
            let hero = HeroMotion.timing(.heroGroup, title: title, belowHero: true)
            let header = HeroMotion.timing(.headerOffset, title: title, belowHero: true)
            XCTAssertLessThanOrEqual(hero.delay + hero.duration, 0.21)
            XCTAssertGreaterThanOrEqual(header.duration, 0.5)
            XCTAssertGreaterThan(header.delay, hero.delay, "the header appears after the hero starts leaving")
            XCTAssertEqual(HeroMotion.timing(.headerFade, title: title, belowHero: true), header)
        }
    }

    /// A3: the show logo's measured height (share of the screen from the top) after the press, within the table's 5 %.
    func testTheShowHeaderLandsAsMeasured() {
        let timing = HeroMotion.timing(.headerOffset, title: .logo, belowHero: true)
        let measured: [(t: Double, y: Double)] = [(0.20, 0.50), (0.23, 0.44), (0.26, 0.38), (0.34, 0.28), (0.40, 0.20),
                                                  (0.55, 0.15), (0.70, 0.14)]
        for point in measured {
            let y = HeroMotion.headerStart(.logo) - HeroMotion.headerTravel(.logo) * timing.progress(at: point.t)
            XCTAssertEqual(y, point.y, accuracy: 0.05, "t+\(point.t)")
        }
        XCTAssertEqual(timing.progress(at: 0.16), 0, accuracy: 0.001, "faint at t+0.16")
    }

    /// C3: the episode title's measured height after the press.
    func testTheEpisodeHeaderLandsAsMeasured() {
        let timing = HeroMotion.timing(.headerOffset, title: .text, belowHero: true)
        let measured: [(t: Double, y: Double)] = [(0.28, 0.38), (0.35, 0.31), (0.42, 0.26), (0.48, 0.24), (0.85, 0.12)]
        for point in measured {
            let y = HeroMotion.headerStart(.text) - HeroMotion.headerTravel(.text) * timing.progress(at: point.t)
            XCTAssertEqual(y, point.y, accuracy: 0.05, "t+\(point.t)")
        }
    }

    /// B: on Up the header is gone by t+0.22, at about 45 % of the screen; the hero enters from t+0.20 to t+0.60; the rows
    /// leave from t+0.15 to t+0.30.
    func testUpTimings() {
        let fade = HeroMotion.timing(.headerFade, title: .logo, belowHero: false)
        XCTAssertEqual(fade.delay + fade.duration, 0.22, accuracy: 0.001)
        let drop = HeroMotion.timing(.headerOffset, title: .logo, belowHero: false)
        let y = HeroMotion.headerRest(.logo) + HeroMotion.headerTravel(.logo) * drop.progress(at: 0.22)
        XCTAssertEqual(y, 0.45, accuracy: 0.05)
        let hero = HeroMotion.timing(.heroGroup, title: .logo, belowHero: false)
        XCTAssertEqual(hero.delay, 0.20, accuracy: 0.001)
        XCTAssertEqual(hero.delay + hero.duration, 0.60, accuracy: 0.001)
        let rows = HeroMotion.timing(.section, title: .logo, belowHero: false)
        XCTAssertEqual(rows.delay, 0.15, accuracy: 0.001)
        XCTAssertEqual(rows.delay + rows.duration, 0.30, accuracy: 0.001)
    }

    func testTheCurvesRunFromZeroToOne() {
        for curve in [HeroMotion.easeOut, HeroMotion.easeIn, HeroMotion.landing] {
            XCTAssertEqual(curve.value(at: 0), 0, accuracy: 0.001)
            XCTAssertEqual(curve.value(at: 1), 1, accuracy: 0.001)
            XCTAssertLessThanOrEqual(curve.value(at: 0.3), curve.value(at: 0.6))
        }
        XCTAssertGreaterThan(HeroMotion.landing.value(at: 0.2), HeroMotion.easeOut.value(at: 0.2), "a strong ease-out")
    }

    /// Down: scrolling past the hero's share turns the hero state into the below-hero state.
    func testDownHidesTheHeroAndLandsTheHeader() {
        for title in [HeroMotion.Title.logo, .text] {
            let before = HeroMotion.frame(belowHero: ProductScroll.isBelowHero(offset: 0, heroHeight: 864), title: title,
                                          reduceMotion: false, pageHeight: page)
            let after = HeroMotion.frame(belowHero: ProductScroll.isBelowHero(offset: 700, heroHeight: 864), title: title,
                                         reduceMotion: false, pageHeight: page)
            XCTAssertEqual(before.heroOpacity, 1)
            XCTAssertEqual(before.heroOffset, 0)
            XCTAssertEqual(before.headerOpacity, 0)
            XCTAssertEqual(HeroMotion.headerTotalOffset(before), HeroMotion.headerTravel(title) * page, accuracy: 0.001,
                           "the header starts at the measured height")
            XCTAssertEqual(before.sectionOffset, HeroMotion.sectionRise)
            XCTAssertEqual(before.topFadeOff, 1)
            XCTAssertTrue(before.heroTitleIsAccessible)

            XCTAssertEqual(after.heroOpacity, HeroMotion.heroHiddenOpacity, "faded out, still focusable (R471 (121))")
            XCTAssertEqual(after.heroOffset, -HeroMotion.heroEntry * page, accuracy: 0.001, "the hero waits above")
            XCTAssertEqual(after.headerOpacity, 1)
            XCTAssertEqual(HeroMotion.headerTotalOffset(after), 0, "the header at its place")
            XCTAssertEqual(after.sectionOffset, 0)
            XCTAssertEqual(after.topFadeOff, 0, "the top edge fades below the hero")
            XCTAssertFalse(after.heroTitleIsAccessible, "the header's title carries the label")
        }
    }

    /// Up: the reverse state, so the hero comes down from above and the header drops and fades.
    func testUpReturnsToTheHeroState() {
        for title in [HeroMotion.Title.logo, .text] {
            let below = HeroMotion.frame(belowHero: true, title: title, reduceMotion: false, pageHeight: page)
            let back = HeroMotion.frame(belowHero: ProductScroll.isBelowHero(offset: 0, heroHeight: 864), title: title,
                                        reduceMotion: false, pageHeight: page)
            XCTAssertEqual(back, HeroMotion.frame(belowHero: false, title: title, reduceMotion: false, pageHeight: page))
            XCTAssertLessThan(below.heroOffset, back.heroOffset)
            XCTAssertGreaterThan(HeroMotion.headerTotalOffset(back), HeroMotion.headerTotalOffset(below))
        }
    }

    func testReduceMotionIsACrossfadeWithNoOffsets() {
        for below in [false, true] {
            for title in [HeroMotion.Title.logo, .text] {
                let still = HeroMotion.frame(belowHero: below, title: title, reduceMotion: true, pageHeight: page)
                let moving = HeroMotion.frame(belowHero: below, title: title, reduceMotion: false, pageHeight: page)
                XCTAssertEqual(still.heroOffset, 0)
                XCTAssertEqual(still.headerOffset, 0)
                XCTAssertEqual(still.sectionOffset, 0)
                XCTAssertEqual(still.heroOpacity, moving.heroOpacity)
                XCTAssertEqual(still.headerOpacity, moving.headerOpacity)
                XCTAssertEqual(still.topFadeOff, moving.topFadeOff)
                XCTAssertEqual(still.heroTitleIsAccessible, moving.heroTitleIsAccessible)
            }
        }
    }

    func testAPageNotMeasuredYetHasNoShareOffsets() {
        let below = HeroMotion.frame(belowHero: true, title: .logo, reduceMotion: false, pageHeight: 0)
        XCTAssertEqual(below.heroOffset, 0)
        let hero = HeroMotion.frame(belowHero: false, title: .logo, reduceMotion: false, pageHeight: .nan)
        XCTAssertEqual(hero.headerOffset, 0)
    }

    /// R471 (121): below the hero the hero group (Play and the first screen's controls) never reaches opacity 0, the
    /// value at which a view stops being focusable (Apple's `canBecomeFocused`), nor UIKit's 0.01 hit-test limit, so Up
    /// from the rows can land on Play; it is still faded far below any readable strength.
    func testTheHeroStaysFocusableBelowTheHero() {
        XCTAssertGreaterThan(HeroMotion.heroHiddenOpacity, 0.01)
        XCTAssertLessThanOrEqual(HeroMotion.heroHiddenOpacity, 0.05)
        for title in [HeroMotion.Title.logo, .text] {
            for reduceMotion in [false, true] {
                for height in [0.0, 1080] {
                    let below = HeroMotion.frame(belowHero: true, title: title, reduceMotion: reduceMotion, pageHeight: height)
                    XCTAssertGreaterThan(below.heroOpacity, 0, "the hero would leave the focus chain")
                    XCTAssertEqual(below.heroOpacity, HeroMotion.heroHiddenOpacity)
                }
            }
        }
    }

    /// Exactly one title instance carries the label; a page with no header keeps the hero's.
    func testOneAccessibleTitle() {
        XCTAssertTrue(HeroMotion.frame(belowHero: false, title: .logo, reduceMotion: false, pageHeight: page).heroTitleIsAccessible)
        XCTAssertFalse(HeroMotion.frame(belowHero: true, title: .logo, reduceMotion: false, pageHeight: page).heroTitleIsAccessible)
        XCTAssertTrue(HeroMotion.frame(belowHero: true, title: .text, reduceMotion: false, pageHeight: page,
                                       hasHeader: false).heroTitleIsAccessible)
    }
}
