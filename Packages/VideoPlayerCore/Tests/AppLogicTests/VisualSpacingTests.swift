import XCTest
@testable import AppLogic

/// R391 to R395 (owner's review of the screenshot run on fd9731f): the numbers and small rules the views take.
final class VisualSpacingTests: XCTestCase {
    func testTheTimeLeftIsTheLastFactOfTheMetadataLine() {
        XCTAssertEqual(ProductPage.factsLine("2021 · 1 h 52 min", timeLeft: "29 min left"), "2021 · 1 h 52 min · 29 min left")
        XCTAssertEqual(ProductPage.factsLine("2021 · 1 h 52 min", timeLeft: nil), "2021 · 1 h 52 min")
        XCTAssertEqual(ProductPage.factsLine("2021", timeLeft: "  "), "2021")
        XCTAssertEqual(ProductPage.factsLine("", timeLeft: "29 min left"), "29 min left")
        XCTAssertEqual(ProductPage.factsLine("", timeLeft: nil), "")
    }

    func testTheBadgeGapsAreInTheOwnersRange() {
        XCTAssertTrue((8.0...12.0).contains(BadgeSpacing.inGroup), "the gap inside a group is outside the owner's 8 to 12 pt")
        XCTAssertTrue((8.0...12.0).contains(BadgeSpacing.betweenGroups), "the gap between groups is outside the owner's 8 to 12 pt")
        XCTAssertGreaterThan(BadgeSpacing.betweenGroups, BadgeSpacing.inGroup, "a new group is not set apart (R373)")
        XCTAssertEqual(BadgeSpacing.groupExtra, BadgeSpacing.betweenGroups - BadgeSpacing.inGroup)
    }

    func testThePageNumbersAreApplesWhereApplePublishesOne() {
        // HIG Layout, tvOS: 1920 pt less two 80 pt margins is 1760 pt; two columns at 40 pt spacing are 860 pt each, and
        // eight are 185 pt (the page's table says 184 pt).
        let width: Double = 1920 - 2 * 80
        let half: Double = (width - Double(ProductPageSpacing.synopsisColumns - 1) * ProductPageSpacing.columnSpacing) / Double(ProductPageSpacing.synopsisColumns)
        XCTAssertEqual(half, 860)
        let circle: Double = (width - Double(ProductPageSpacing.castColumns - 1) * 40) / Double(ProductPageSpacing.castColumns)
        XCTAssertEqual(circle, 185)
        // The sample's `Text(loremIpsum).frame(maxWidth: 600)`.
        XCTAssertEqual(ProductPageSpacing.coverTextWidth, 600)
        // Half of HIG Layout's 100 pt between two grid rows.
        XCTAssertEqual(ProductPageSpacing.aboveFirstGridRow, 50)
    }

    func testTheLogosVisibleBoxLeavesItsEmptyMarginsOut() throws {
        // FIXTURE: 8 x 4 pixels, visible only in columns 3 to 5 of rows 1 and 2.
        let w = 8, h = 4
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for y in 1...2 { for x in 3...5 { rgba[(y * w + x) * 4 + 3] = 255 } }
        let box = try XCTUnwrap(TitleLogoRules.inkBounds(rgba: rgba, width: w, height: h))
        XCTAssertEqual(box.x, 3); XCTAssertEqual(box.y, 1); XCTAssertEqual(box.width, 3); XCTAssertEqual(box.height, 2)
        // A faint pixel under the threshold is not visible; one above it is.
        rgba[3] = 8
        XCTAssertEqual(try XCTUnwrap(TitleLogoRules.inkBounds(rgba: rgba, width: w, height: h)).x, 3)
        rgba[3] = 9
        let wider = try XCTUnwrap(TitleLogoRules.inkBounds(rgba: rgba, width: w, height: h))
        XCTAssertEqual(wider.x, 0); XCTAssertEqual(wider.y, 0); XCTAssertEqual(wider.width, 6); XCTAssertEqual(wider.height, 3)
        // Nothing visible, or a buffer of the wrong size: no box.
        XCTAssertNil(TitleLogoRules.inkBounds(rgba: [UInt8](repeating: 0, count: w * h * 4), width: w, height: h))
        XCTAssertNil(TitleLogoRules.inkBounds(rgba: [0, 0, 0, 255], width: 2, height: 2))
    }

    func testTheFailureAlertShowsTheResultAndTheStepOnly() {
        let tracker = PlaybackStartTracker()
        tracker.setPath(.direct)
        tracker.reach(.fileOpened, detail: "a link")
        tracker.reach(.itemCreated)
        tracker.note("a note")
        tracker.enter(.playerReady)
        let problem = tracker.problem(PlaybackFailures.startTimedOut(.playerReady, seconds: 30))
        XCTAssertEqual(problem.alertLines(), ["Result: " + PlaybackStartVerdict.neverReady.text, "Step: " + PlaybackStep.playerReady.title])
        // The full set stays where it was (Settings > Playback > Full Problem Report).
        XCTAssertGreaterThan(problem.screenLines().count, problem.alertLines().count)
        XCTAssertTrue(problem.fullText().contains("Notes:"))
    }

    func testAProblemWithNoCheckpointsShowsTheStepAlone() throws {
        let old = #"{"step":"playerReady","sourceKind":"Plex","container":"MKV","error":"x","at":0}"#
        let problem = try XCTUnwrap(PlaybackProblem.decoded(Data(old.utf8)))
        XCTAssertEqual(problem.alertLines(), ["Step: " + PlaybackStep.playerReady.title])
    }

    func testThePlayersLineUsesTheSystemsSeparatorAndTheAppsOwnTextsKeepTheirs() {
        let lines = PlayerEpisodeText.episodeLines(name: "A quiet beginning", show: "Sample Show 1", season: 1, episode: 3)
        XCTAssertEqual(lines.subtitle, "Sample Show 1 • S1, E3")
        XCTAssertFalse(lines.subtitle?.contains("·") ?? true)
        XCTAssertEqual(PlayerEpisodeText.upNextLine(show: "Sample Show 1", season: 1, episode: 4, name: nil), "Sample Show 1 · S1, E4")
    }
}
