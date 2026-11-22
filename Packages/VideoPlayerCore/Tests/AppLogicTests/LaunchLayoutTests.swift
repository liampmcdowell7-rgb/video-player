import XCTest
@testable import AppLogic

/// R388 (item B): the launch focus is claimed once, right after Home first appears; the scanning line never sits above a
/// page that has content.
final class LaunchLayoutTests: XCTestCase {
    func testTheFeaturedTitleClaimsTheFocusOnceRightAfterLaunch() {
        var focus = LaunchFocus()
        focus.homeShown(at: 100)
        XCTAssertTrue(focus.claim(at: 101.5))
        XCTAssertFalse(focus.claim(at: 102), "only once per app run")
        XCTAssertTrue(focus.settled)
    }

    func testNoClaimBeforeHomeWasShown() {
        var focus = LaunchFocus()
        XCTAssertFalse(focus.claim(at: 5))
        XCTAssertFalse(focus.settled, "the chance is kept for when Home appears")
        focus.homeShown(at: 6)
        XCTAssertTrue(focus.claim(at: 7))
    }

    func testALateFeaturedTitleLeavesTheFocusWhereThePersonPutIt() {
        var focus = LaunchFocus()
        focus.homeShown(at: 100)
        XCTAssertFalse(focus.claim(at: 100 + LaunchFocus.window + 0.1))
        XCTAssertFalse(focus.claim(at: 100 + LaunchFocus.window + 0.2), "and not later either")
        var edge = LaunchFocus()
        edge.homeShown(at: 100)
        XCTAssertTrue(edge.claim(at: 100 + LaunchFocus.window))
    }

    func testOnlyTheFirstAppearanceOfHomeCounts() {
        var focus = LaunchFocus()
        focus.homeShown(at: 100)
        focus.homeShown(at: 500)
        XCTAssertEqual(focus.firstShown, 100)
        XCTAssertFalse(focus.claim(at: 505), "re-showing Home much later does not reopen the window")
    }

    func testTheScanLineShowsOnlyWhileHomeHasNothingToShow() {
        XCTAssertTrue(HomeScanNotice.shows(isScanning: true, hasContent: false))
        XCTAssertFalse(HomeScanNotice.shows(isScanning: true, hasContent: true), "a launch scan must not push the page down")
        XCTAssertFalse(HomeScanNotice.shows(isScanning: false, hasContent: false))
        XCTAssertFalse(HomeScanNotice.shows(isScanning: false, hasContent: true))
    }
}
