import XCTest
@testable import ScreenChecks

/// R429 to R433 (owner's reading of run #29): the rules in `ScreenRules` are run on frames; the app and UI-test fixes are
/// checked from the source (structure only: nothing is compiled or run on tvOS here).
extension ScreenChecksTests {
    private func run29Body(of declaration: String, in source: String) throws -> String {
        let start: String.Index = try XCTUnwrap(source.range(of: declaration)?.lowerBound, "no \(declaration)")
        return String(try XCTUnwrap(Self.braceBody(of: source, after: start), "the body of \(declaration)"))
    }

    /// R431: the episode card's group "badge.resolution-badge.hdr" holds the single badges. The frames are the shape of
    /// 55-show-page-BADGES (that note is not in this checkout): the group spans both badges, the badges are 10 pt apart.
    private var cardBadges: [(String, AXRect)] {
        [("1080p, resolution, HDR10, high dynamic range", AXRect(x: 80, y: 700, width: 249, height: 40)),
         ("1080p, resolution", AXRect(x: 80, y: 700, width: 109, height: 40)),
         ("HDR10, high dynamic range", AXRect(x: 199, y: 700, width: 130, height: 40))]
    }

    func testAGroupOfBadgesIsNotAnOverlap() {
        XCTAssertEqual(ScreenRules.badgeOverlaps(badges: cardBadges), [], "a parent group and its badges are reported as an overlap")
        // Real overlaps between siblings still count.
        let crossing: [(String, AXRect)] = [("A", AXRect(x: 0, y: 0, width: 100, height: 40)), ("B", AXRect(x: 60, y: 0, width: 100, height: 40))]
        XCTAssertEqual(ScreenRules.badgeOverlaps(badges: crossing).count, 1)
    }

    func testBadgeGapsAreMeasuredBetweenSiblingsOnly() {
        let result: CheckResult = ScreenRules.badgeGaps(badges: cardBadges)
        XCTAssertTrue(result.passed, result.text)
        // A real gap between two siblings still fails.
        let apart: [(String, AXRect)] = [("A", AXRect(x: 0, y: 0, width: 100, height: 40)), ("B", AXRect(x: 349, y: 0, width: 100, height: 40))]
        XCTAssertFalse(ScreenRules.badgeGaps(badges: apart).passed)
    }

    /// R433: only the system's Sort and Filter menus are recorded; our own pictures are not.
    func testOnlySystemMenuPicturesAreRecordedNotFailed() {
        for name in ["07-movies-toolbar-sort-submenu", "07-shows-toolbar-filter-submenu-larger-text", "07-movies-toolbar-sort-filter-menu"] {
            XCTAssertTrue(ScreenRules.isSystemMenuPicture(name), name)
        }
        for name in ["31-settings-playback", "56-show-page", "07-movies-toolbar-saved-views-menu"] {
            XCTAssertFalse(ScreenRules.isSystemMenuPicture(name), name)
        }
    }

    /// R429 and R430 and R432, from the source.
    func testRun29SourceFixes() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift"),
              let proposal = try appSource("App/Features/Player/UpNextProposalController.swift") else { return }
        // R429: no layout guide; pinned to the view; the order of the container calls.
        XCTAssertFalse(proposal.contains("playerLayoutGuide."), "the card still uses playerLayoutGuide")
        XCTAssertTrue(proposal.contains("host.view.topAnchor.constraint(equalTo: view.topAnchor"), "the card is not pinned to the view's top")
        XCTAssertTrue(proposal.contains("host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor)"), "the card is not centred")
        let load: String = try run29Body(of: "override func viewDidLoad() {", in: proposal)
        let add: Range<String.Index> = try XCTUnwrap(load.range(of: "addChild(host)"))
        let sub: Range<String.Index> = try XCTUnwrap(load.range(of: "view.addSubview(host.view)"))
        let activate: Range<String.Index> = try XCTUnwrap(load.range(of: "NSLayoutConstraint.activate"))
        let moved: Range<String.Index> = try XCTUnwrap(load.range(of: "host.didMove(toParent: self)"))
        XCTAssertTrue(add.lowerBound < sub.lowerBound && sub.lowerBound < activate.lowerBound && activate.lowerBound < moved.lowerBound)
        // R430: the finders look at any element type, and the tree is written.
        let test12: String = try run29Body(of: "func test12_PlayerWithSampleClip() {", in: tests)
        XCTAssertFalse(test12.contains("waitForAny(introButtons"), "Skip Intro is still looked up by exact label")
        XCTAssertTrue(tests.contains("hierarchy(number + \"-before\", of: app)"), "no tree at the audio and subtitle steps")
        XCTAssertTrue(test12.contains("hierarchy(\"22-player-skip-intro\", of: app)"), "no tree at the skip-intro step")
        let any: String = try run29Body(of: "func anyElement(containing", in: tests)
        XCTAssertTrue(any.contains("label CONTAINS[c]") && any.contains("identifier CONTAINS[c]") && any.contains("title CONTAINS[c]"))
        // R432: the end of the climb is the synopsis when the page has one.
        let up: String = try run29Body(of: "func scrollUpCheck(", in: tests)
        XCTAssertTrue(up.contains("topIdentifier"), "no topmost row")
        XCTAssertTrue(tests.contains("scrollUpCheck(\"58-movie-detail\", top: movieTop, topIdentifier: \"product.synopsis\", in: app)"))
        XCTAssertTrue(tests.contains("scrollUpCheck(\"56-show-page\", top: showTop, topIdentifier: \"product.synopsis\", in: app)"))
    }
}
