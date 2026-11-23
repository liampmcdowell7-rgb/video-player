import XCTest
@testable import ScreenChecks

/// R413 to R421 (owner's reading of run #27 on 66cebd0): each fix checked from the source (structure only: nothing is
/// compiled or run on tvOS here), and the new B 2 rule on the run's own cases. Whether the next run agrees waits for it.
extension ScreenChecksTests {
    /// The body of the first `declaration` in `source`.
    private func run27Body(of declaration: String, in source: String) throws -> String {
        let start: String.Index = try XCTUnwrap(source.range(of: declaration)?.lowerBound, "no \(declaration)")
        return String(try XCTUnwrap(Self.braceBody(of: source, after: start), "the body of \(declaration)"))
    }

    /// R414: a task cover's material has the background's second level under it, over the opaque background, and both the
    /// cover's root and its pages draw those same layers.
    func testTaskCoverMaterialHasAGreyUnderIt() throws {
        guard let pane = try appSource("App/Shared/SettingsPane.swift") else { return }
        let fill: String = try run27Body(of: "struct TaskCoverFill: ViewModifier {", in: pane)
        let material: Range<String.Index> = try XCTUnwrap(fill.range(of: ".background(.regularMaterial, ignoresSafeAreaEdges: .all)"), "no material")
        let grey: Range<String.Index> = try XCTUnwrap(fill.range(of: ".background(BackgroundStyle().secondary, ignoresSafeAreaEdges: .all)"), "no second level under the material")
        let opaque: Range<String.Index> = try XCTUnwrap(fill.range(of: ".background(BackgroundStyle(), ignoresSafeAreaEdges: .all)"), "not opaque")
        XCTAssertLessThan(material.lowerBound, grey.lowerBound, "the grey is drawn above the material")
        XCTAssertLessThan(grey.lowerBound, opaque.lowerBound, "the opaque background is drawn above the grey")
        let chrome: String = try run27Body(of: "struct TaskCoverChrome: ViewModifier {", in: pane)
        XCTAssertTrue(chrome.contains(".modifier(TaskCoverFill())"), "the cover's root does not draw the layers")
        XCTAssertFalse(chrome.contains(".regularMaterial"), "the cover's root still draws a material of its own")
        let page: String = try run27Body(of: "struct TaskCoverPageBackground: ViewModifier {", in: pane)
        XCTAssertTrue(page.contains(".modifier(TaskCoverFill())"), "the cover's pages do not draw the layers")
    }

    /// R413: Movies and Shows keep no empty navigation bar now that their controls are a row on the page.
    func testLibraryTabsHaveNoEmptyNavigationBar() throws {
        guard let root = try appSource("App/Shell/RootView.swift") else { return }
        XCTAssertTrue(root.contains("MoviesView().tabRootScreen(\"Movies\", identifier: \"screen.movies\")"), "Movies is not a plain tab root")
        XCTAssertTrue(root.contains("ShowsView().tabRootScreen(\"Shows\", identifier: \"screen.shows\")"), "Shows is not a plain tab root")
        XCTAssertFalse(root.contains("toolbar: true)"), "a tab still keeps the navigation bar for controls that are no longer in it")
    }

    /// R415: B 2 fails on what the app controls (told hidden, not hittable), not on XCTest listing the page.
    func testPageBehindACoverFailsOnlyWhenNotHiddenOrHittable() {
        XCTAssertTrue(ScreenRules.pageReachableBehindCover(listed: []).passed)
        // Run #27, 10-add-source-types-COVER: told hidden, not hittable.
        let run27: CheckResult = ScreenRules.pageReachableBehindCover(listed: [(identifier: "screen.home", value: "cover probe: told hidden true", hittable: false)])
        XCTAssertTrue(run27.passed, run27.text)
        XCTAssertTrue(run27.text.contains("screen.home: told hidden true, isHittable false"), run27.text)
        let notTold: CheckResult = ScreenRules.pageReachableBehindCover(listed: [(identifier: "screen.item", value: "cover probe: told hidden false", hittable: false)])
        XCTAssertFalse(notTold.passed)
        XCTAssertTrue(notTold.text.contains("screen.item was not told to hide"), notTold.text)
        let noValue: CheckResult = ScreenRules.pageReachableBehindCover(listed: [(identifier: "screen.item", value: "", hittable: false)])
        XCTAssertFalse(noValue.passed, "a page with no probe value was not shown to be told hidden")
        let hittable: CheckResult = ScreenRules.pageReachableBehindCover(listed: [(identifier: "screen.needsReview", value: "cover probe: told hidden true", hittable: true)])
        XCTAssertFalse(hittable.passed)
        XCTAssertTrue(hittable.text.contains("PAGE BEHIND THE COVER IS REACHABLE"), hittable.text)
    }

    /// R417 to R421: the UI test fixes of run #27.
    func testRun27TestFaultsAreFixed() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift") else { return }
        // R417: the automatic skip's "Watch Intro" counts.
        XCTAssertTrue(tests.contains("let introButtons: [String] = [\"Skip Intro\", \"Watch Intro\"]"), "test12 still expects only Skip Intro")
        // R418: no frame read on the sidebar element without checking it exists.
        XCTAssertFalse(tests.contains("navigationChrome(in: app).frame"), "a frame is read on a sidebar that may not exist")
        let chrome: String = try run27Body(of: "func chromeFrameText(", in: tests)
        XCTAssertTrue(chrome.contains("chrome.exists ?"), "chromeFrameText reads the frame of a missing element")
        // R419: either seeded recent search counts.
        XCTAssertTrue(tests.contains("let seeded: [String] = [\"Sample Movie 2\", \"Sample Show\"]"), "76-search-recent looks for one term only")
        // R420: re-selection is a record, not a failure.
        let reselect: String = try run27Body(of: "func reselectTabCheck(", in: tests)
        XCTAssertFalse(reselect.contains("XCTAssert"), "the re-selection check still fails the test")
        XCTAssertTrue(reselect.contains("RESELECT NOT DONE (record only, R420)"), "the re-selection note does not say it is a record")
        // R421: the Movies folder row by its name and count, not the sidebar's Movies tab.
        XCTAssertTrue(tests.contains("NSPredicate(format: \"label BEGINSWITH %@\", \"Movies, \")"), "72-files-folder still looks for the label Movies alone")
    }

    /// R416: every simulator job copies the app's crash reports and uploads them with its logs.
    func testEverySimulatorJobUploadsTheAppsCrashReports() throws {
        guard let workflow = try appSource(".github/workflows/compile-check.yml") else { return }
        let steps: Int = workflow.components(separatedBy: "run: bash scripts/ci-crash-reports.sh \"$GITHUB_WORKSPACE/build/ci\"").count - 1
        XCTAssertEqual(steps, 5, "not every simulator job (package tests, screenshots, screenshots-library, screenshots-more, accessibility) copies the crash reports")
        XCTAssertEqual(workflow.components(separatedBy: "            build/ci/crash-reports/\n").count - 1, 5, "not every log artifact holds the crash reports")
    }

    /// R423: each simulator job also uploads its crash reports as a small artifact of their own, only when there is one.
    func testEverySimulatorJobUploadsItsCrashReportsAlone() throws {
        guard let workflow = try appSource(".github/workflows/compile-check.yml") else { return }
        for job in ["simulator-tests", "screenshots", "screenshots-library", "screenshots-more", "accessibility-screenshots"] {
            let step: String = "      - name: Upload the app's crash reports\n        if: always()\n        uses: actions/upload-artifact@v7\n        with:\n          name: crash-reports-\(job)\n          path: build/ci/crash-reports/\n          if-no-files-found: ignore\n"
            XCTAssertTrue(workflow.contains(step), "no crash-reports-\(job) artifact")
        }
        guard let copy = try appSource("scripts/ci-crash-reports.sh") else { return }
        XCTAssertTrue(copy.contains("ci-crash-summary.py"), "the copy step does not write the summary")
        XCTAssertTrue(copy.contains("cat \"$summary\" >> \"$GITHUB_STEP_SUMMARY\""), "the summary does not reach the job summary")
    }
}
