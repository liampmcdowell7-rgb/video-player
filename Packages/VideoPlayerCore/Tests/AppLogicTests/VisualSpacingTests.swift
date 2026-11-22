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

    /// R396 (docs/AUDIT_VISUAL_TVAPP.md SF1): the values measured on Apple's pictures.
    func testTheSharedRowValuesAreInsideWhatApplesPicturesMeasure() {
        XCTAssertTrue((10.0...15.0).contains(BadgeSpacing.inGroup), "badges are 10 to 15 pt apart on Apple's pages")
        XCTAssertTrue((10.0...15.0).contains(BadgeSpacing.betweenGroups), "badges are 10 to 15 pt apart on Apple's pages")
        XCTAssertGreaterThan(BadgeSpacing.betweenGroups, BadgeSpacing.inGroup, "a new group is not set apart (R373)")
        XCTAssertEqual(BadgeSpacing.groupExtra, BadgeSpacing.betweenGroups - BadgeSpacing.inGroup)
        XCTAssertEqual(BadgeSpacing.afterText, 10, "the rating is about 10 pt after the text (A1, B1)")
        XCTAssertTrue((25.0...29.0).contains(RowSpacing.iconToLabel), "a list icon is about 25 to 29 pt from its label (A3, A2)")
        XCTAssertTrue((22.0...27.0).contains(RowSpacing.betweenActions), "action buttons are about 22 to 27 pt apart (A1, B1, A4)")
        XCTAssertTrue((650.0...658.0).contains(RowSpacing.textColumn), "the synopsis is at most about 650 to 658 pt wide (B1, A4)")
        XCTAssertEqual(RowSpacing.featuredToShelf, 105)
        XCTAssertEqual(RowSpacing.landscapeShelfColumns, 5)
        // Five 16:9 cards at 40 pt spacing on a 1760 pt page: 320 pt each (Apple's picture: about 318 pt).
        XCTAssertEqual((1760.0 - 4 * 40) / Double(RowSpacing.landscapeShelfColumns), 320)
    }

    func testTheStarringLineListsTheFirstThreeNames() {
        XCTAssertEqual(ProductPage.starring(["Ana", "Ben", "Cy", "Di"]), "Ana, Ben, Cy")
        XCTAssertEqual(ProductPage.starring(["Ana", " ", "Ben"]), "Ana, Ben")
        XCTAssertNil(ProductPage.starring([]))
        XCTAssertNil(ProductPage.starring(["", "  "]))
    }

    func testTheLineAboveAnEpisodesTitleIsTheShowThenTheCode() {
        XCTAssertEqual(ProductPage.episodeOverline(show: "Sample Show 1", code: "S1, E3"), "Sample Show 1 · S1, E3")
        XCTAssertEqual(ProductPage.episodeOverline(show: nil, code: "S1, E3"), "S1, E3")
        XCTAssertEqual(ProductPage.episodeOverline(show: "Sample Show 1", code: nil), "Sample Show 1")
        XCTAssertNil(ProductPage.episodeOverline(show: " ", code: nil))
    }

    func testThePageNumbersAreApplesWhereApplePublishesOne() {
        // HIG Layout, tvOS: 1920 pt less two 80 pt margins is 1760 pt; eight columns at 40 pt spacing
        // are 185 pt each (the page's table says 184 pt).
        let width: Double = 1920 - 2 * 80
        let circle: Double = (width - Double(ProductPageSpacing.castColumns - 1) * 40) / Double(ProductPageSpacing.castColumns)
        XCTAssertEqual(circle, 185)
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
        XCTAssertEqual(lines.title, "Sample Show 1")
        XCTAssertEqual(lines.subtitle, "S1, E3 • A quiet beginning")
        XCTAssertFalse(lines.subtitle?.contains("·") ?? true)
        XCTAssertEqual(PlayerEpisodeText.upNextLine(show: "Sample Show 1", season: 1, episode: 4, name: nil), "Sample Show 1 · S1, E4")
    }
}
