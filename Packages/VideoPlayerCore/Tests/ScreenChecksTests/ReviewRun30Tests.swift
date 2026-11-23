import XCTest
@testable import ScreenChecks

/// R435 (run #30, item 1): badge gaps are measured inside one group only. Frames from 55-show-page-BADGES.txt.
extension ScreenChecksTests {
    private func run30Card(x: Double, y: Double = 1290, gap: Double = 14) -> [(String, AXRect)] {
        [("badge.resolution-badge.hdr", AXRect(x: x, y: y, width: 91 + gap + 96, height: 58)),
         ("badge.resolution", AXRect(x: x, y: y, width: 91, height: 58)),
         ("badge.hdr", AXRect(x: x + 91 + gap, y: y, width: 96, height: 58))]
    }

    func testThreeEpisodeCardsOnOneLineAreNotMeasuredAgainstEachOther() {
        let frames: [(String, AXRect)] = run30Card(x: 177) + run30Card(x: 627) + run30Card(x: 1077)
        let result: CheckResult = ScreenRules.badgeGaps(badges: frames)
        XCTAssertTrue(result.passed, result.text)
    }

    func testARealGapInsideOneGroupStillFails() {
        let frames: [(String, AXRect)] = run30Card(x: 177) + run30Card(x: 627, gap: 60) + run30Card(x: 1077)
        let result: CheckResult = ScreenRules.badgeGaps(badges: frames)
        XCTAssertFalse(result.passed, result.text)
    }

    /// R440 (run #31; replaces R438's loop): the Audio and Subtitles steps are fresh player sessions of their own with no
    /// Menu press, each ends with `app.terminate()`, and the plan, the workflow and the first player session agree.
    /// From the source (structure only).
    func testBlindPressLoopDoesNotLeaveThePlayer() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift"),
              let workflow = try appSource(".github/workflows/compile-check.yml"),
              let plan = try appSource("scripts/screenshot-plan.tsv") else { return }
        let start: String.Index = try XCTUnwrap(tests.range(of: "private func blindMenuSession(")?.lowerBound)
        let session: String = String(try XCTUnwrap(Self.braceBody(of: tests, after: start))).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(session.contains("press(.menu)"), "a Menu press in the Audio and Subtitles sessions")
        XCTAssertFalse(session.contains("ScreenRules.changed("), "the pixel comparison is back")
        XCTAssertTrue(session.hasSuffix("app.terminate()"), "the session does not end with app.terminate()")
        XCTAssertTrue(session.contains("launch(\"-UITestFixtures\", open: \"Sample Show 1\""), "no fresh launch")
        XCTAssertTrue(session.contains("press(.playPause)") && session.contains("(\"Up\", .up)") && session.contains("press(.select)"))
        XCTAssertTrue(session.contains("shot(number + \"-try\\(index + 1)\")") && session.contains("-try\\(index + 1)\", \"PICTURE-ONLY, NOT VERIFIED BY THE TREE"))
        // Audio is the third icon (Right twice), Subtitles the second (Right once).
        XCTAssertTrue(tests.contains("func test12b_PlayerAudioMenu() { blindMenuSession(\"25-player-audio-menu\", rights: 2) }"))
        XCTAssertTrue(tests.contains("func test12c_PlayerSubtitlesMenu() { blindMenuSession(\"26-player-subtitles-menu\", rights: 1) }"))
        // The first player session (22 to 24 and 27) has no 25 or 26 step and presses no Menu.
        let first: Range<String.Index> = try XCTUnwrap(tests.range(of: "func test12_PlayerWithSampleClip() {"))
        let firstBody: String = String(try XCTUnwrap(Self.braceBody(of: tests, after: first.lowerBound)))
        XCTAssertFalse(firstBody.contains("press(.menu)"), "test12 presses Menu")
        XCTAssertFalse(firstBody.contains("shot(\"25-"), "test12 still takes 25")
        XCTAssertTrue(firstBody.contains("27-player-next-episode"))
        // The plan has 25 and 26 under their own tests, and the workflow runs those in the job that has room (part 3), once.
        XCTAssertTrue(plan.contains("test12b_PlayerAudioMenu\t25-player-audio-menu") && plan.contains("test12c_PlayerSubtitlesMenu\t26-player-subtitles-menu"))
        XCTAssertFalse(plan.contains("test12_PlayerWithSampleClip\t25-") || plan.contains("test12_PlayerWithSampleClip\t26-"))
        for name in ["test12b_PlayerAudioMenu", "test12c_PlayerSubtitlesMenu"] {
            XCTAssertEqual(workflow.components(separatedBy: "            \(name)").count - 1, 2, "\(name) must be in the run step and the collect step of one job")
        }
    }

    /// R439 (run #31, item 1): the time budget. test10's Larger Text half is test10b, in part 3 with test05 and test14; part 1
    /// keeps test01, 02, 03 and test10; every planned test is named in exactly one job (run step and collect step).
    func testPartOneHasHeadroomAndNoTestIsInTwoJobs() throws {
        guard let workflow = try appSource(".github/workflows/compile-check.yml"),
              let plan = try appSource("scripts/screenshot-plan.tsv"),
              let tests = try appSource("UITests/ScreenshotTests.swift") else { return }
        let jobs: [(String, [String])] = [
            ("  screenshots:\n", ["test01_FirstLaunchAndEmptyScreens", "test02_AddASource", "test03_Settings", "test10_SortingScreens"]),
            ("  screenshots-library:\n", ["test12_PlayerWithSampleClip", "test13_MovieSynopsisAndCast", "test15_ShowPageResponsive", "test04_LibraryScreens", "test16_LibraryToolbars"]),
            ("  screenshots-more:\n", ["test05_FilesSearchDiscover", "test14_ShowsToolbarAndCardMenu", "test10b_SortingScreensLargerText", "test12b_PlayerAudioMenu", "test12c_PlayerSubtitlesMenu"])]
        var seen: [String] = []
        for (header, expected) in jobs {
            let from: String.Index = try XCTUnwrap(workflow.range(of: header)?.upperBound, header)
            let rest: Substring = workflow[from...]
            let end: String.Index = rest.range(of: "\n  # JOB ")?.lowerBound ?? rest.endIndex
            let job: String = String(rest[..<end])
            for test in expected {
                XCTAssertEqual(job.components(separatedBy: "            \(test)").count - 1, 2, "\(test) must be in the run step and the collect step of \(header)")
                XCTAssertTrue(tests.contains("func \(test)()"), "no test method \(test)")
                seen.append(test)
            }
        }
        XCTAssertEqual(Set(seen).count, seen.count, "a test is named in two jobs")
        // Every test the plan names is in a job (or in the accessibility job), so no picture is "missing" because it moved.
        let planned: Set<String> = Set(plan.split(separator: "\n").filter { !$0.hasPrefix("#") }.compactMap { $0.split(separator: "\t").first.map(String.init) })
        let accessibility: Set<String> = ["test06_LargerTextAndBoldText", "test11_AccessibilityDefaults"]
        XCTAssertEqual(planned.subtracting(Set(seen)).subtracting(accessibility), [], "planned tests that no job runs")
        XCTAssertEqual(plan.components(separatedBy: "test10b_SortingScreensLargerText\t").count - 1, 10)
        XCTAssertEqual(plan.components(separatedBy: "test10_SortingScreens\t").count - 1, 11)
    }
}
