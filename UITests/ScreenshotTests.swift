import XCTest

/// Screenshots of every screen the Siri Remote can reach, for review without a device (docs/GITHUB_ACTIONS_RUNBOOK.md, job 4).
///
/// Each test launches the app in a debug-only UI-test mode (`-UITestEmpty` or `-UITestFixtures`, App/Support/UITestMode.swift):
/// a clean start, no network, and in fixtures mode a synthetic sample library. Every screenshot is an attachment kept
/// always, named "NN-name"; the workflow exports them as NN-name.png in that order.
///
/// A screen that cannot be reached does not stop the run: a text attachment "NN-name-NOT-REACHED" says why (with a screenshot
/// of what is shown instead), and the test goes on. No screenshot is ever taken while the app is not in front (the fourth CI
/// run saved the system Home Screen under the app's screen names after a crash at launch); that is a test failure instead. Remote API: XCUIRemote (https://developer.apple.com/documentation/xcuiautomation/xcuiremote).
final class ScreenshotTests: XCTestCase {
    /// The app launched last; every screenshot is of it, and only while it is in front.
    private var current: XCUIApplication?

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: Helpers

    @discardableResult
    func launch(_ mode: String, tab: String? = nil, open: String? = nil, extra: [String] = [],
                launchTimeout: TimeInterval = 20) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [mode] + extra
        if let tab { args += ["-UITestTab", tab] }
        if let open { args += ["-UITestOpen", open] }
        app.launchArguments = args
        app.launch()
        current = app
        // Fourth CI run: the app died at launch and every "screenshot" showed the system Home Screen. Say so at once.
        if !appIsInFront(app, timeout: launchTimeout) {
            XCTFail("The app is not in the foreground after launch \(args) (state \(app.state.rawValue)); it probably crashed.")
        }
        return app
    }

    /// True when this app, not the system Home Screen, is in front: running in the foreground with one of its own screens
    /// (accessibility identifier "screen.<name>", App/Shell/RootView.swift) or its tab bar or sidebar present.
    func appIsInFront(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        guard app.wait(for: .runningForeground, timeout: timeout) else { return false }
        let screen = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "screen.")).firstMatch
        return screen.waitForExistence(timeout: timeout) || navigationChrome(in: app).exists
    }

    /// R359 (scan finding 3): the app's top-level navigation: the tab bar before R359, the system sidebar since
    /// (`.tabViewStyle(.sidebarAdaptable)`). How tvOS 27 exposes the sidebar to XCUITest is not on Apple's pages
    /// (UNVERIFIED): the tab bar when there is one, else the first table, collection view, outline or group that holds an
    /// item labelled "Home" and one labelled "Settings" and is narrower than half the window (so never the whole page).
    /// When the sidebar is collapsed and not in the tree, the element returned does not exist.
    func navigationChrome(in app: XCUIApplication) -> XCUIElement {
        let bar: XCUIElement = app.tabBars.firstMatch
        if bar.exists { return bar }
        let window: CGRect = app.windows.firstMatch.frame
        let home: NSPredicate = NSPredicate(format: "label == %@", "Home")
        let settings: NSPredicate = NSPredicate(format: "label == %@", "Settings")
        for query in [app.tables, app.collectionViews, app.outlines, app.otherElements] {
            for candidate in query.containing(home).containing(settings).allElementsBoundByIndex.prefix(6)
            where candidate.exists && candidate.frame.width > 0 && (window.width <= 0 || candidate.frame.width < window.width / 2) {
                return candidate
            }
        }
        return bar
    }

    /// R359: true while the app shows a sidebar rather than a tab bar (no tab bar in the tree). Moves towards the navigation
    /// are then Left, and into the content Right; with a tab bar, Up and Down.
    func usesSidebar(_ app: XCUIApplication) -> Bool {
        !app.tabBars.firstMatch.exists
    }

    /// Waits for the screen with the accessibility identifier `id` ("screen.home", "screen.item", ...).
    /// #36 group 5a: when the screen does not come (test12 of the third run of 20 Nov: "Timed out while evaluating UI query"
    /// on screen.series), a picture of the screen is kept BEFORE the test goes on to fail: "<test>-WAIT-<id>", taken with
    /// XCUIScreen (the display, no query on the app).
    func waitForScreen(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let found: Bool = app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: timeout)
        if !found { pictureOfTheScreen("WAIT-" + id) }
        return found
    }

    /// The display as it is, saved as "<test>-<what>.png" (no app query, so it works while the app is hung).
    func pictureOfTheScreen(_ what: String) {
        let screenshot: XCUIScreenshot = XCUIScreen.main.screenshot()
        let test: String = name.components(separatedBy: " ").last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "]")) } ?? "test"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = test + "-" + what
        attachment.lifetime = .keepAlways
        add(attachment)
        writeFile(test + "-" + what + ".png", screenshot.pngRepresentation)
    }

    /// A screenshot named `name`, taken only while the app is in front. Otherwise a failure and a text note, never a picture
    /// of the system Home Screen saved under the name of one of the app's screens.
    /// #36 group 1 c: `endOfScroll` names a scroll step that may find the page already at the end of its content; an
    /// identical picture after it is reported as "end of scroll" (an -END-OF-SCROLL note), not as a warning. `expectStill`:
    /// the picture is MEANT to equal the one before (the "-later" pictures, group 1 d), so no warning either; the caller
    /// checks it. Every other identical pair keeps the WARNING and the -UNCHANGED note.
    func shot(_ name: String, mustChangeAfter step: String? = nil, endOfScroll: String? = nil, expectStill: Bool = false) {
        guard let app = current, appIsInFront(app, timeout: 2) else {
            let state = current.map { "\($0.state.rawValue)" } ?? "not launched"
            XCTFail("\(name): the app is not in the foreground (state \(state)); no screenshot taken.")
            note(name + "-APP-NOT-IN-FRONT", "The app was not in the foreground (state \(state)), so no screenshot was taken.")
            return
        }
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // #24 A: the same picture as a file at once, so it survives a test run that is stopped before the result bundle is
        // complete (the run on fa00af8 lost every picture that way).
        let png = screenshot.pngRepresentation
        writeFile(name + ".png", png)
        // #15 item 1.6: every capture must show something new. The CI run for 8bb0f0c saved 58 and 61 "scrolled" three
        // times each, pixel for pixel the same as the page before: Down moved nothing. #24 C: same pixels is a WARNING
        // (the -UNCHANGED note, listed in index.md), not a test failure; the picture is kept either way.
        // #33 L: a step that was MEANT to change the screen (`mustChangeAfter`) fails the test when it did not
        // (ScreenRules.changed, proven on the run's 56 / 56-later pair in ScreenChecksTests).
        if let step, let previous = lastShot {
            let result: CheckResult = ScreenRules.changed([UInt8](previous.png), [UInt8](png), step: step)
            if !result.passed {
                note(name + "-UNCHANGED", "Identical, pixel for pixel, to \(previous.name).\n" + result.text)
                XCTFail("\(name): \(step) did not change the screen (identical to \(previous.name))")
            }
        } else if let previous = lastShot, previous.png == png, expectStill {
            // Checked by the caller (laterPictures: identical AND the caption whole).
        } else if let previous = lastShot, previous.png == png, let endOfScroll {
            note(name + "-END-OF-SCROLL", "end of scroll: identical, pixel for pixel, to \(previous.name) after \(endOfScroll); the page is at the end of its content, so the scroll had nothing more to show.")
        } else if let previous = lastShot, previous.png == png {
            print("WARNING: \(name): the screen did not change since \(previous.name) (identical pixels).")
            note(name + "-UNCHANGED", "Identical, pixel for pixel, to \(previous.name): the step before it did not change the screen.")
        }
        lastShot = (name, png)
        lastScreenshot = screenshot
        focusRoomCheck(name, screenshot)
    }

    /// R345: on every picture with a focused row (the white platter of the system focus effect), the row must be whole: its
    /// rounded corners intact on both sides (no straight cut) and its frame inside the picture (`FocusRoom`, proven in
    /// FocusRoomTests on the run of 21 Nov, where 31-settings-playback was cut flat at x 990). A failure writes a
    /// -FOCUS-CLIPPED note and fails the test; a picture without a focused row is not measured.
    func focusRoomCheck(_ name: String, _ screenshot: XCUIScreenshot) {
        guard let image = RGBImage(screenshot: screenshot) else { return }
        let result: CheckResult = FocusRoom.check(image)
        guard !result.passed else { return }
        note(name + "-FOCUS-CLIPPED", result.text)
        XCTFail("\(name): \(result.verdict)")
    }

    /// The last capture as a screenshot, for the pixel checks of the "-later" pictures.
    private var lastScreenshot: XCUIScreenshot?

    /// The last capture, for the changed-screen check in `shot`.
    private var lastShot: (name: String, png: Data)?

    func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        writeFile(name + ".txt", Data(text.utf8))
    }

    /// #24 A: the folder every picture and note of this test is also written to, as files: $SCREENSHOT_DIR/<test name>/
    /// when the CI passes SCREENSHOT_DIR (xcodebuild hands TEST_RUNNER_SCREENSHOT_DIR to the runner as SCREENSHOT_DIR:
    /// the TEST_RUNNER_ prefix rule of `man xcodebuild`, from memory, unverified) and that host folder can be written from the
    /// simulator; otherwise the runner's own temporary folder, vp-screenshots/<test name>/, which the CI finds inside the
    /// simulator's data folder (scripts/ci-ui-tests.sh). The folder used is printed ("SCREENSHOT FILES: ...").
    private lazy var fileFolder: URL? = {
        // XCTestCase.name is "-[ScreenshotTests test01_FirstLaunchAndEmptyScreens]".
        let method = self.name.split(separator: " ").last.map { String($0.filter { $0 != "]" }) } ?? "unknown-test"
        var bases: [URL] = []
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty {
            bases.append(URL(fileURLWithPath: dir, isDirectory: true))
        }
        bases.append(FileManager.default.temporaryDirectory.appendingPathComponent("vp-screenshots", isDirectory: true))
        for base in bases {
            let folder = base.appendingPathComponent(method, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let probe = folder.appendingPathComponent("write-check.tmp")
                try Data("ok".utf8).write(to: probe)
                try? FileManager.default.removeItem(at: probe)
                print("SCREENSHOT FILES: \(folder.path)")
                return folder
            } catch {
                print("SCREENSHOT FILES: cannot write to \(folder.path): \(error)")
            }
        }
        return nil
    }()

    /// Writes one picture or note into `fileFolder`. A failed write is printed, never a test failure.
    private func writeFile(_ fileName: String, _ data: Data) {
        guard let folder = fileFolder else { return }
        do { try data.write(to: folder.appendingPathComponent(fileName)) } catch {
            print("SCREENSHOT FILE NOT WRITTEN: \(fileName): \(error)")
        }
    }

    /// R313: the player names the sample episode with its season and episode number in the TV app's form ("S1, E1"), in the
    /// transport bar's subtitle and the Info tab. A missing code is recorded as not reached, with what the screen shows.
    func episodeCodeCheck(_ picture: String, in app: XCUIApplication) {
        let code: String = "S1, E1"
        if waitFor(code, in: app, timeout: 3) { note(picture + "-EPISODE-CODE", "\u{201C}\(code)\u{201D}: found") }
        else {
            notReached(picture + "-EPISODE-CODE", "No text containing \u{201C}\(code)\u{201D} on screen.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
    }

    /// A screen that was not reached: a note with the reason, and a screenshot of what IS on screen instead (when the app
    /// is in front), named "NN-name-NOT-REACHED", so the reason can be seen.
    func notReached(_ name: String, _ reason: String) {
        note(name + "-NOT-REACHED", reason)
        if let app = current, appIsInFront(app, timeout: 2) {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name + "-NOT-REACHED"
            attachment.lifetime = .keepAlways
            add(attachment)
            writeFile(name + "-NOT-REACHED.png", screenshot.pngRepresentation)
        }
    }

    /// R311 (CI run on a0ae4a6: after Play, the page with a spinner and no player for 30 s; build 5 on the device: a black
    /// player, then the page again with no message): how a player start that did not reach the picture ended, for the
    /// not-reached note. "SILENT FAILURE" is the regression this guards against: no player, no spinner and no alert.
    func playerStartOutcome(in app: XCUIApplication) -> String {
        let alert: XCUIElement = app.alerts.firstMatch
        if alert.exists {
            let texts: [String] = alert.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
            return "The player showed an alert: “\(alert.label)”: " + texts.joined(separator: " | ")
        }
        let spinner: XCUIElement = app.descendants(matching: .any).matching(identifier: "player.loading").firstMatch
        if spinner.exists {
            return "The player is still starting; its spinner says the step is: \(spinner.value as? String ?? "(no value)")."
        }
        if !app.descendants(matching: .any).matching(identifier: "player.screen").firstMatch.exists {
            return "SILENT FAILURE: no player, no spinner and no alert (the page underneath may be showing). Settings > Playback > Last Playback Problem holds the step."
        }
        return "The player is up but no “Skip Intro” came (focus on \(focusedLabel(in: app)))."
    }

    /// #24 C: the first `lines` lines of the accessibility tree, printed to the test log and returned for a note.
    func trimmedHierarchy(_ app: XCUIApplication, lines: Int = 60) -> String {
        let text = app.debugDescription.split(separator: "\n", omittingEmptySubsequences: false).prefix(lines).joined(separator: "\n")
        print("HIERARCHY (first \(lines) lines):\n\(text)")
        return text
    }

    /// Waits for text containing `text` anywhere on screen.
    func waitFor(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    /// The focusable element (button or cell) labelled `text`, never a tab-bar button (#15 item 1.3).
    /// Order: a label exactly `text`, then a label starting with `text` and a separator (", " or " "), then any label
    /// containing it. Before this, "Movies" matched the Movies TAB before the Movies folder row (so 72 showed the Movies tab
    /// and 73 was not reached), and "FTP" matched the SFTP row first (14 and 15 identical).
    ///
    /// #25 A1: also menu buttons, and any button, cell or menu button that has a descendant StaticText with that label. The
    /// run on 1fe5d50 (library notes/57-movie-detail-HIERARCHY.txt) showed Extras and More as Button elements with NO label
    /// of their own; the label was on a child StaticText, so no label query found them.
    func control(_ text: String, in app: XCUIApplication) -> XCUIElement {
        control(id: nil, label: text, in: app)
    }

    /// #25 A1 and A2: the control with the accessibility identifier `id` (ControlID, App/Shared/ControlID.swift) when one is
    /// given and present, otherwise the control labelled `label` as in `control(_:in:)`. Never a tab-bar button. Nothing is
    /// tapped: `open` and `focus` move the focus with the remote.
    func control(id: String?, label: String, in app: XCUIApplication) -> XCUIElement {
        let tabBar = navigationChrome(in: app)
        let tabFrame = tabBar.exists ? tabBar.frame : .null
        func outsideTabBar(_ element: XCUIElement) -> Bool {
            tabFrame.isNull || !tabFrame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
        }
        if let id {
            for element in app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.prefix(6)
            where element.exists && outsideTabBar(element) {
                return element
            }
        }
        let predicates = [NSPredicate(format: "label == %@", label),
                          NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", label + ",", label + " "),
                          NSPredicate(format: "label CONTAINS %@", label)]
        for predicate in predicates {
            // #24 C: switches too (the Sort by Filename toggle on a source page). #25 A1: menu buttons, then the
            // containers whose own label is empty but whose child StaticText carries it.
            let queries = [app.buttons.matching(predicate), app.cells.matching(predicate), app.menuButtons.matching(predicate),
                           app.switches.matching(predicate),
                           app.buttons.containing(predicate), app.menuButtons.containing(predicate), app.cells.containing(predicate)]
            for query in queries {
                for element in query.allElementsBoundByIndex.prefix(12) where element.exists && outsideTabBar(element) {
                    return element
                }
            }
        }
        // Nothing yet (a lazy list may not have built the row): a query that `focus` can wait on while moving down.
        if let id { return app.descendants(matching: .any).matching(identifier: id).firstMatch }
        return app.cells.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// #25 A2: an identifier must be exposed once. More than one element with it (a Menu and its label both carrying it, or
    /// the same control twice on screen) is written as "NN-name-ID-COUNT", with the tree; never a test failure.
    func checkExposedOnce(_ id: String, name: String, in app: XCUIApplication) {
        let count = app.descendants(matching: .any).matching(identifier: id).count
        if count != 1 {
            note(name + "-ID-COUNT", "The identifier “\(id)” is exposed \(count) times (expected once).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
    }

    /// #25 A3: waits until the element stops moving (two reads 0.5 s apart with the same frame), e.g. the last row of a sheet
    /// after its presentation animation, instead of a fixed time. True when it exists and stood still within `timeout`.
    func waitUntilStill(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let end = Date().addingTimeInterval(timeout)
        var last = element.frame
        while Date() < end {
            usleep(500_000)
            let now = element.frame
            if now == last, !now.isEmpty { return true }
            last = now
        }
        return false
    }

    /// #25 B10: where the focus is when a page opens. Written as "NN-name-FOCUS" with the focused element's identifier, label
    /// and frame and "FOCUS OK" (the element with identifier `expected`, or the element around it, has the focus) or
    /// "FOCUS PROBLEM"; the run on 1fe5d50 showed the tab bar focused on the movie page (78). Never a test failure.
    func focusCheck(_ name: String, expected: String, in app: XCUIApplication) {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let target = app.descendants(matching: .any).matching(identifier: expected).firstMatch
        var lines = ["expected: \(expected) (present: \(target.exists))"]
        guard focused.exists else {
            note(name + "-FOCUS", (lines + ["focused: none", "FOCUS PROBLEM: nothing has the focus"]).joined(separator: "\n"))
            return
        }
        lines.append("focused: identifier “\(focused.identifier)”, label “\(focused.label)”, frame \(String(describing: focused.frame))")
        let f = focused.frame, t = target.exists ? target.frame : .null
        let ok = focused.identifier == expected
            || (!t.isNull && (f.contains(CGPoint(x: t.midX, y: t.midY)) || t.contains(CGPoint(x: f.midX, y: f.midY))))
        lines.append(ok ? "FOCUS OK" : "FOCUS PROBLEM: the focus is not on \(expected)")
        note(name + "-FOCUS", lines.joined(separator: "\n"))
    }

    /// #25 A3: waits for any of `labels` (items of a menu that has just opened), so a menu picture shows the menu open.
    func waitForAny(_ labels: [String], in app: XCUIApplication, timeout: TimeInterval = 5) -> String? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels where app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.exists {
                return label
            }
            usleep(300_000)
        } while Date() < end
        return nil
    }

    /// #25 A3: moves the focus from the tab bar (where it starts on a tab's root) into the content: Down until the focused
    /// element is outside the tab bar. True when it is.
    func focusContent(in app: XCUIApplication, maxPresses: Int = 4) -> Bool {
        for _ in 0..<maxPresses {
            // R359: the tab bar or the sidebar; into the content is Down from a tab bar, Right from a sidebar.
            let tabBar = navigationChrome(in: app)
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists, !(tabBar.exists && tabBar.frame.contains(CGPoint(x: focused.frame.midX, y: focused.frame.midY))) { return true }
            XCUIRemote.shared.press(usesSidebar(app) ? .right : .down); usleep(500_000)
        }
        return false
    }

    /// R388 follow-up (item 13 of the owner's review of the run on fd9731f): moves the focus to a CARD of Home's first
    /// shelf. Since R388 Home opens with the focus on the featured title's Play, so a Select or a long press sent "from
    /// launch" plays the title instead of opening a card's menu (08-card-long-press-go-to showed the failure alert).
    /// First into the content (`focusContent`, for a run that still starts in the sidebar), then Down while the focus is
    /// on the featured Play or More or anywhere inside the featured area. True when the focus is on something below it.
    /// Nothing is selected here.
    func focusFirstHomeCard(in app: XCUIApplication, maxPresses: Int = 4) -> Bool {
        guard focusContent(in: app) else { return false }
        let featured: XCUIElement = app.descendants(matching: .any).matching(identifier: "home.featured").firstMatch
        for _ in 0...maxPresses {
            let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard focused.exists else { return false }
            let onFeaturedControl: Bool = focused.identifier == "control.featuredPlay" || focused.identifier == "control.featuredMore"
            let inFeatured: Bool = featured.exists && featured.frame.contains(CGPoint(x: focused.frame.midX, y: focused.frame.midY))
            if !onFeaturedControl && !inFeatured { return true }
            XCUIRemote.shared.press(.down); usleep(600_000)
        }
        return false
    }

    /// The label of the element that has the focus now ("none" when nothing has it), for NOT-REACHED reasons.
    func focusedLabel(in app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? "“\(focused.label)”" : "none"
    }

    /// #36 8 T4: what has the focus right now (label, identifier, frame) and whether its label contains `expected`. The
    /// "-later" pictures of 50 and 56 in the run of 20 Nov were identical to the first ones, and nothing said whether the
    /// card still had the focus while the test waited.
    func focusLine(expected: String, in app: XCUIApplication) -> (ok: Bool, line: String) {
        let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        guard focused.exists else { return (false, "focused: none (expected “\(expected)”)") }
        let ok: Bool = focused.label.contains(expected)
        var verdict: String = "yes"
        if !ok { verdict = "NO" }
        return (ok, "focused “\(focused.label)” id “\(focused.identifier)” frame \(focused.frame); expected “\(expected)”: \(verdict)")
    }

    /// #36 8 T4: the first picture, then 3 s of focus and the "-later" picture, with the focus asserted before each wait and
    /// written to "<name>-FOCUS" (before the first picture, before the wait, after the wait). No "-later" picture is taken
    /// when the focus has left `expected`: the comparison would say nothing.
    /// #36 group 1 d: the system does NOT scroll a long caption on a focused card (third run of 20 Nov: 50 and 56 identical
    /// to their "-later" pictures, both captions cut mid-word), so the pair now passes only when the two pictures are
    /// identical (nothing moves on its own) AND the caption `caption` is whole (ScreenRules.captionFits, R264).
    func laterPictures(_ name: String, expected: String, caption: String, step: String, in app: XCUIApplication, firstLine: String) {
        var lines: [String] = [firstLine]
        let before: (ok: Bool, line: String) = focusLine(expected: expected, in: app)
        lines.append("before the first picture: " + before.line)
        sleep(1); shot(name)
        let waiting: (ok: Bool, line: String) = focusLine(expected: expected, in: app)
        lines.append("before the 3 s wait: " + waiting.line)
        guard before.ok, waiting.ok else {
            lines.append("FOCUS PROBLEM: the focus is not on “\(expected)”; no -later picture")
            note(name + "-FOCUS", lines.joined(separator: "\n"))
            XCTFail("\(name): the focus is not on “\(expected)” before the wait (\(waiting.line))")
            notReached(name + "-later", "The focus was not on “\(expected)” before the 3 s wait: \(waiting.line)")
            return
        }
        sleep(3)
        let after: (ok: Bool, line: String) = focusLine(expected: expected, in: app)
        lines.append("after the 3 s wait: " + after.line)
        lines.append(after.ok ? "FOCUS OK" : "FOCUS PROBLEM: the focus left “\(expected)” during the wait")
        note(name + "-FOCUS", lines.joined(separator: "\n"))
        let first: Data? = lastShot?.png
        shot(name + "-later", expectStill: true)
        guard let first, let later = lastShot?.png, let screenshot = lastScreenshot else { return }
        let result: CheckResult = ScreenRules.stillAndWhole([UInt8](first), [UInt8](later), caption: captionCheck(caption, in: app, screenshot: screenshot))
        note(name + "-later-CAPTION", "after \(step)\n" + result.text)
        XCTAssertTrue(result.passed, "\(name)-later: " + result.verdict)
        captionOverlapCheck(name, caption: caption, in: app)
    }

    /// R355 (item 6): a long name in a Files row is whole: its text is on screen, inside the screen's width, and it does not
    /// run over its second line (`detail`). Picture 72 of the run of 21 Nov cut it at rest ("… Card Is W"). "-NAME" note;
    /// a failure fails the test. The row's combined text ("name, 3 items") is skipped; the frames cannot show a clip inside
    /// the text's own frame: the picture shows that.
    func longNameCheck(_ name: String, name text: String, detail: String, in app: XCUIApplication) {
        let label: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", text, detail)).firstMatch
        let second: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label == %@", detail)).firstMatch
        guard label.waitForExistence(timeout: 5), second.exists else {
            note(name + "-NAME", "the long name or its \u{201C}\(detail)\u{201D} line was not found: NOT CHECKED")
            XCTFail("\(name): the long name \u{201C}\(text)\u{201D} or \u{201C}\(detail)\u{201D} was not found")
            return
        }
        let box: CGRect = label.frame
        let screen: CGRect = app.windows.firstMatch.frame
        var failures: [String] = []
        if box.maxX > screen.maxX { failures.append("the name runs past the screen's right edge") }
        if box.intersects(second.frame) { failures.append("the name runs over \u{201C}\(detail)\u{201D}") }
        var lines: [String] = ["name \u{201C}\(label.label)\u{201D} \(box)", "\u{201C}\(detail)\u{201D} \(second.frame)"]
        lines.append(failures.isEmpty ? "LONG NAME OK" : "FAILED: " + failures.joined(separator: "; "))
        note(name + "-NAME", lines.joined(separator: "\n"))
        for failure in failures { XCTFail("\(name): \(failure) (R355)") }
    }

    /// R354 (item 5): the long caption does not run over the lines under it. The run of 21 Nov drew S2 E3's three-line
    /// caption (88 pt) over its "43 min" line. Every other text of the card that holds `caption` must start below the
    /// caption's frame or end above it. "-OVERLAP" note; an overlap fails the test.
    func captionOverlapCheck(_ name: String, caption: String, in app: XCUIApplication) {
        let text: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", caption)).firstMatch
        let card: XCUIElement = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", caption)).firstMatch
        guard text.exists, card.exists else {
            note(name + "-OVERLAP", "the caption or its card was not found: NOT CHECKED")
            XCTFail("\(name): the caption \u{201C}\(caption)\u{201D} or its card was not found for the overlap check")
            return
        }
        let box: CGRect = text.frame
        var lines: [String] = ["caption \(box)"]
        var overlaps: [String] = []
        for other in card.staticTexts.allElementsBoundByIndex where other.label != text.label {
            let frame: CGRect = other.frame
            lines.append("\u{201C}\(other.label)\u{201D} \(frame)")
            if frame.intersects(box) { overlaps.append(other.label) }
        }
        lines.append(overlaps.isEmpty ? "CAPTION OVERLAP OK" : "OVERLAP: the caption runs over " + overlaps.joined(separator: ", "))
        note(name + "-OVERLAP", lines.joined(separator: "\n"))
        XCTAssertTrue(overlaps.isEmpty, "\(name): the caption runs over \(overlaps.joined(separator: ", ")) (R354)")
    }

    /// R339 (docs/HIG_AUDIT.md T10): the show page has its season tabs and lists ONE season's episodes. The note -SEASONS
    /// lists the seasons whose cards are on screen; it fails when there is not exactly one.
    func seasonTabsCheck(_ name: String, in app: XCUIApplication) {
        let tabs: Bool = app.segmentedControls[ControlID.seasonTabs].exists || app.buttons[ControlID.seasonTabs].exists
        let labels: [String] = app.buttons.allElementsBoundByIndex.map(\.label)
        let result: CheckResult = ScreenRules.oneSeasonListed(cardLabels: labels)
        note("\(name)-SEASONS", (tabs ? "season tabs found" : "SEASON TABS NOT FOUND") + "\n" + result.text)
        XCTAssertTrue(tabs, "\(name): the season tabs are missing")
        XCTAssertTrue(result.passed, "\(name): " + result.text)
    }

    /// R365 (item 13): "<name>-HEADING": the whole-synopsis page shows the title above the text.
    func synopsisHeadingCheck(_ name: String, title: String, in app: XCUIApplication) {
        let heading: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        let text: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample synopsis")).firstMatch
        let above: Bool = heading.exists && text.exists && heading.frame.minY < text.frame.minY
        note(name + "-HEADING", (above ? "HEADING OK" : "NO TITLE ABOVE THE TEXT")
             + "\ntitle \u{201C}\(title)\u{201D}: " + (heading.exists ? "\(heading.frame)" : "not found")
             + "\ntext: " + (text.exists ? "\(text.frame)" : "not found"))
        XCTAssertTrue(above, "\(name): the title \u{201C}\(title)\u{201D} is not the heading above the synopsis")
    }

    /// R341: "<name>-TITLES": the person page lists Sample Actor 1's six sample titles (five movies, one show) as cards.
    func personPageCheck(_ name: String, in app: XCUIApplication) {
        let wanted: [String] = (1...5).map { "Sample Movie \($0)" } + ["Sample Show 1"]
        let labels: [String] = app.buttons.allElementsBoundByIndex.map(\.label)
        let missing: [String] = wanted.filter { title in !labels.contains { $0.hasPrefix(title) } }
        let extra: Bool = labels.contains { $0.hasPrefix("Sample Movie 6") || $0.hasPrefix("Sample Show 2") }
        let ok: Bool = missing.isEmpty && !extra
        note("\(name)-TITLES", (ok ? "PERSON TITLES OK" : "PERSON TITLES WRONG") + "\nmissing: \(missing)\nother titles listed: \(extra)")
        XCTAssertTrue(ok, "\(name): missing \(missing), other titles \(extra)")
    }

    /// R335 (docs/HIG_AUDIT.md T1, T2): Down from the tab bar onto the first portrait card, its picture
    /// ("<name>", the system lift on a borderless lockup), and the "-LOCKUP" note: the caption (the StaticText with the
    /// focused card's title) must be inside the focused card (`ScreenRules.captionInLockup`). A caption that is not exposed
    /// in the tree is reported, not failed (whether tvOS 27 exposes the label's text inside the button: UNVERIFIED).
    /// R360 (item 7): the tree reports the button as the artwork only, so "inside" is now written for the record and the
    /// test fails on `ScreenRules.captionMovesOnFocus`: the focused title must sit lower than a resting card's title in
    /// the same row (Apple: the title moves "out of the way of the button's image as it scales up on focus").
    func lockupCheck(_ name: String, in app: XCUIApplication) {
        // Down past the library toolbar (Sort, Filter, ...) onto the first card of the grid.
        var focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<4 where !focused.label.hasPrefix("Sample") {
            XCUIRemote.shared.press(.down); sleep(1)
            focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        }
        guard focused.exists, focused.label.hasPrefix("Sample") else {
            // R361 (item 8): picture 54 stopped on "Jump to Letter", right of the only two show cards. The grid is now a
            // focus section, so Down from any control above it should land on a card.
            return notReached(name, "No sample card took the focus after Down (focus on \(focusedLabel(in: app))). R361: the grid is a focus section, so this is a failure of that fix.")
        }
        settle(); shot(name)
        let title: String = focused.label
        let text: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        let inside: CheckResult = ScreenRules.captionInLockup(focused: AXRect(focused.frame), caption: text.exists ? AXRect(text.frame) : nil, title: title)
        // R360: a resting card's title in the same row (another sample title within 60 pt of the focused one's height).
        var resting: XCUIElement?
        if text.exists {
            for other in app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label != %@", "Sample", title)).allElementsBoundByIndex.prefix(12)
            where other.exists && abs(other.frame.minY - text.frame.minY) < 60 {
                resting = other; break
            }
        }
        let moves: CheckResult = ScreenRules.captionMovesOnFocus(focusedCaption: text.exists ? AXRect(text.frame) : nil,
                                                                 restingCaption: resting.map { AXRect($0.frame) }, title: title)
        note(name + "-LOCKUP", "for the record (R335): " + inside.text + "\n" + moves.text)
        if text.exists { XCTAssertTrue(moves.passed, "\(name): " + moves.verdict) }
    }

    /// The caption check for a focused card: the caption is the StaticText containing `caption`, its column the focused
    /// card's width less the caption's left inset on both sides (the caption is leading-aligned with equal side paddings).
    func captionCheck(_ caption: String, in app: XCUIApplication, screenshot: XCUIScreenshot) -> CheckResult {
        let card: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let text: XCUIElement = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", caption)).firstMatch
        let window: CGRect = app.windows.firstMatch.frame
        guard card.exists, text.exists, window.width > 0, let image = RGBImage(screenshot: screenshot) else {
            return CheckResult(passed: false, lines: ["no focused card, no caption containing “\(caption)”, or the picture could not be read", "CAPTION NOT MEASURED"])
        }
        let cardFrame: CGRect = card.frame
        let textFrame: CGRect = text.frame
        let inset: CGFloat = max(0, textFrame.minX - cardFrame.minX)
        let column = AXRect(x: Double(cardFrame.minX + inset), y: Double(textFrame.minY), width: Double(cardFrame.width - 2 * inset), height: Double(textFrame.height))
        return ScreenRules.captionFits(image, scale: Double(image.width) / Double(window.width), column: column, text: AXRect(textFrame))
    }

    /// Presses Down until the focus stops moving (three presses in a row with the same focused frame) or `maxPresses`.
    /// True when the focus stopped, i.e. the end of the list was reached.
    func moveFocusToEnd(in app: XCUIApplication, maxPresses: Int = 40) -> Bool {
        // #36 group 5: the focus is "unmoved" only when BOTH its label and its frame stay the same (a scrolling list can put
        // the next row where the last one was), and every press is recorded in `focusPath` for the notes.
        focusPath = []
        var last: String?
        var unmoved = 0
        for press in 1...maxPresses {
            XCUIRemote.shared.press(.down); usleep(400_000)
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let here: String = focused.exists ? "“\(focused.label)” \(focused.frame)" : "none"
            focusPath.append("\(press) Down: \(here)")
            if here == last { unmoved += 1; if unmoved >= 3 { return true } } else { unmoved = 0 }
            last = here
        }
        return false
    }

    /// R346 (owner's device test of build 5, 21 Nov 2026, item A): on a long page, Up from a lower row must scroll the page
    /// back row by row until its FIRST row has the focus; only the next Up may reach the tab bar (tvOS Settings and the TV
    /// app behave so). On build 5 the focus jumped to the tab bar as soon as it reached the top of the visible area.
    /// Method: `top` is what had the focus when the page opened (its first row); Down until the focus stops, then Up, one
    /// press at a time, recording each focused element. PASS when the last element focused before the tab bar (or before
    /// the focus stops moving) is `top`. Writes "<name>-SCROLL-UP" and fails the test on a jump. Leaves the focus on the tab
    /// bar (or the first row), so call it at the END of a page's steps.
    func scrollUpCheck(_ name: String, top: String, in app: XCUIApplication, maxPresses: Int = 40) {
        let reachedEnd: Bool = moveFocusToEnd(in: app, maxPresses: maxPresses)
        let down: String = focusPathText()
        // R359: with the sidebar, Up at the first row stops there (the sidebar is to the left), so the check ends when the
        // focus stops moving.
        let tabBar: XCUIElement = navigationChrome(in: app)
        var path: [String] = []
        var lastContent: String = focusedLabel(in: app)
        var reachedTabBar: Bool = false
        var last: String?
        var unmoved: Int = 0
        for press in 1...maxPresses {
            XCUIRemote.shared.press(.up); usleep(400_000)
            let inTabBar: Bool = tabBar.exists
                && tabBar.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.exists
            let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let label: String = focused.exists ? "“\(focused.label)”" : "none"
            var frame: String = ""
            if focused.exists { frame = "\(focused.frame)" }
            var place: String = ""
            if inTabBar { place = "TAB BAR " }
            path.append("\(press) Up: \(place)\(label) \(frame)")
            if inTabBar { reachedTabBar = true; break }
            let here: String = label + frame
            if here == last { unmoved += 1; if unmoved >= 3 { break } } else { unmoved = 0 }
            last = here
            lastContent = label
        }
        // #29: typed steps, no ternary inside a `+` chain.
        let passed: Bool = lastContent == top
        var stop: String = "the focus stopped (the tab bar was not reached)"
        if reachedTabBar { stop = "the tab bar" }
        var verdict: String = "SCROLL UP OK: the first row \(top) had the focus before \(stop)"
        if !passed { verdict = "FOCUS JUMPED: the last row before \(stop) was \(lastContent), not the first row \(top)" }
        let upLines: String = path.joined(separator: "\n")
        let text: String = "first row (focused when the page opened): \(top)\nend reached going down: \(reachedEnd)\nDOWN \(down)\nUP \(path.count) presses:\n\(upLines)\n\(verdict)"
        note(name + "-SCROLL-UP", text)
        XCTAssertTrue(passed, "\(name): " + verdict)
        // Back into the page, so the next step (a Back press, an open) starts from the page and not from the tab bar.
        if reachedTabBar { XCUIRemote.shared.press(.down); usleep(400_000) }
    }

    /// R389 (owner's device test of 22 Nov 2026: Settings could not scroll down to Last Playback Problem): Down until the
    /// focus stops, then the page's last row (identifier "settings.lastRow", `SettingsRowID.last`) must have the focus.
    /// Before R389 the focus stopped at the last control and the read-only rows below it stayed out of reach. Writes
    /// "<name>-LAST-ROW"; fails the test when the last row was not reached; a page without a marked last row is noted only.
    func lastRowCheck(_ name: String, in app: XCUIApplication, maxPresses: Int = 40) {
        let lastRow: XCUIElement = app.descendants(matching: .any)["settings.lastRow"]
        guard lastRow.waitForExistence(timeout: 5) else {
            note(name + "-LAST-ROW", "NOT CHECKED: no row marked settings.lastRow on this page")
            return
        }
        let reachedEnd: Bool = moveFocusToEnd(in: app, maxPresses: maxPresses)
        let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        var reached: Bool = lastRow.hasFocus
        if !reached && focused.exists {
            reached = ScreenRules.focusReached(focused: AXRect(focused.frame), focusedLabel: focused.label,
                                               target: AXRect(lastRow.frame), targetLabel: lastRow.label)
        }
        var verdict: String = "LAST ROW REACHED: “\(lastRow.label)” had the focus"
        if !reached {
            var stoppedOn: String = "nothing"
            if focused.exists { stoppedOn = "“\(focused.label)”" }
            verdict = "LAST ROW NOT REACHED: the focus stopped on \(stoppedOn), not on “\(lastRow.label)”"
        }
        note(name + "-LAST-ROW", "end reached going down: \(reachedEnd)\nDOWN \(focusPathText())\n\(verdict)")
        XCTAssertTrue(reached, "\(name): " + verdict)
    }

    /// R348 (owner's device test of build 5, item B): pressing the tab that is already selected takes it back to its first
    /// page. From a pushed page (its header `pushedHeader`), Up until the tab bar has the focus (the selected tab takes it),
    /// then Select. PASS when `rootText` is on screen and no element is labelled `pushedHeader`. Writes "<name>-RESELECT" and
    /// the picture "<name>".
    func reselectTabCheck(_ name: String, rootText: String, pushedHeader: String, in app: XCUIApplication) {
        let focusedInBar: NSPredicate = NSPredicate(format: "hasFocus == true")
        // R359: the sidebar is reached with Left (it may be collapsed and out of the tree until then), the tab bar with Up.
        let sidebar: Bool = usesSidebar(app)
        var presses: Int = 0
        while presses < 40 {
            let chrome: XCUIElement = navigationChrome(in: app)
            if chrome.exists && chrome.descendants(matching: .any).matching(focusedInBar).firstMatch.exists { break }
            XCUIRemote.shared.press(sidebar ? .left : .up); usleep(400_000); presses += 1
        }
        let onTab: String = focusedLabel(in: app)
        XCUIRemote.shared.press(.select); sleep(2)
        let pushedLeft: Bool = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", pushedHeader)).firstMatch.exists
        let atRoot: Bool = waitFor(rootText, in: app, timeout: 5)
        let passed: Bool = atRoot && !pushedLeft
        var verdict: String = "RESELECT OK: back on the tab's first page"
        if !passed { verdict = "RESELECT FAILED: \(pushedHeader) still in the tree \(pushedLeft), first page text “\(rootText)” shown \(atRoot)" }
        var way: String = "Up presses to the tab bar"
        if sidebar { way = "Left presses to the sidebar" }
        note(name + "-RESELECT", "\(way): \(presses)\ntab focused: \(onTab)\n\(verdict)")
        shot(name)
        XCTAssertTrue(passed, "\(name): " + verdict)
    }

    /// R349 (owner's device test of build 5, item C): Home leads with the featured area (artwork, title, one metadata line,
    /// Play or Resume, More) and its Continue Watching and Next Up shelves have landscape cards. Writes "<name>-FEATURED";
    /// a missing featured area or Play fails the test (the sample library always has a title to feature).
    func homeFeaturedCheck(_ name: String, in app: XCUIApplication) {
        let area: XCUIElement = app.descendants(matching: .any).matching(identifier: "home.featured").firstMatch
        let play: XCUIElement = app.descendants(matching: .any).matching(identifier: "control.featuredPlay").firstMatch
        let more: XCUIElement = app.descendants(matching: .any).matching(identifier: "control.featuredMore").firstMatch
        var lines: [String] = ["featured area: \(area.exists) \(area.exists ? "\(area.frame)" : "")",
                               "Play: \(play.exists) “\(play.exists ? play.label : "")”, More: \(more.exists)"]
        let window: CGRect = app.windows.firstMatch.frame
        if area.exists, window.height > 0 {
            lines.append("featured height \(Int(area.frame.height)) of \(Int(window.height)) (planned two thirds, R349)")
        }
        for shelf in ["Continue Watching", "Next Up", "Recently Added"] {
            let header: XCUIElement = app.staticTexts[shelf]
            lines.append("shelf \(shelf): \(header.exists ? "shown" : "not on screen")")
        }
        let passed: Bool = area.exists && play.exists && more.exists
        lines.append(passed ? "FEATURED OK" : "FEATURED AREA MISSING")
        note(name + "-FEATURED", lines.joined(separator: "\n"))
        XCTAssertTrue(passed, "\(name): the featured area, its Play or its More is missing")
    }

    /// R350 (owner's device test of build 5, item D): the movie and show pages in the TV app's product-page order: Play in
    /// the hero area, then (when the page has them) "Cast & Crew", then "Information" at the bottom (movie and episode
    /// pages). Reads the frames from the tree (the page is not lazy, so sections below the screen are in it). Writes
    /// "<name>-PRODUCT"; a section out of order, a missing Play or a missing Information fails the test.
    func productPageCheck(_ name: String, information: Bool, in app: XCUIApplication) {
        let play: XCUIElement = app.descendants(matching: .any).matching(identifier: "control.play").firstMatch
        let cast: XCUIElement = app.staticTexts["Cast & Crew"]
        let info: XCUIElement = app.staticTexts["Information"]
        var lines: [String] = []
        var problems: [String] = []
        if play.exists { lines.append("Play at y \(Int(play.frame.minY))") } else { problems.append("no Play") }
        if cast.exists { lines.append("Cast & Crew at y \(Int(cast.frame.minY))") } else { lines.append("Cast & Crew: not on this page (no cast)") }
        if info.exists { lines.append("Information at y \(Int(info.frame.minY))") }
        else if information { problems.append("no Information section") }
        if play.exists, cast.exists, cast.frame.minY <= play.frame.minY { problems.append("Cast & Crew is not below Play") }
        if play.exists, info.exists, info.frame.minY <= play.frame.minY { problems.append("Information is not below Play") }
        if cast.exists, info.exists, info.frame.minY <= cast.frame.minY { problems.append("Information is not below Cast & Crew") }
        if app.staticTexts["Media Info"].exists { problems.append("the old “Media Info” heading is still shown") }
        // R370: the badges are drawn elements labelled "4K, resolution" and so on (identifier "badge.<group>").
        let badges: [String] = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "badge.")).allElementsBoundByIndex.map(\.label)
        lines.append("format badges shown: \(badges.isEmpty ? "none" : badges.joined(separator: ", "))")
        var verdict: String = "PRODUCT PAGE ORDER OK"
        if !problems.isEmpty { verdict = "PRODUCT PAGE PROBLEM: " + problems.joined(separator: "; ") }
        lines.append(verdict)
        note(name + "-PRODUCT", lines.joined(separator: "\n"))
        XCTAssertTrue(problems.isEmpty, "\(name): " + verdict)
    }

    /// R388 (item B): at launch the focus is in Home's content (the sidebar collapsed), and the sidebar expanding and
    /// collapsing again never moves the page: the featured area's top is the same at launch, with the sidebar open (Left),
    /// and after it closes (Right). Writes "<name>-SIDEBAR" with the frames; a focus outside the content at launch or a
    /// featured area that moved by more than 1 pt fails the test (soft). Whether the open sidebar draws over the page is in
    /// the frames (the chrome's width), not judged.
    func sidebarLaunchCheck(_ name: String, in app: XCUIApplication) {
        let featured: XCUIElement = app.descendants(matching: .any).matching(identifier: ControlID.featured).firstMatch
        guard featured.exists else { notReached(name + "-SIDEBAR", "Home has no featured area."); return }
        var lines: [String] = []
        var problems: [String] = []
        let chrome: XCUIElement = navigationChrome(in: app)
        let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let inChrome: Bool = focused.exists && chrome.exists && chrome.frame.contains(CGPoint(x: focused.frame.midX, y: focused.frame.midY))
        lines.append("at launch: focus \(focusedLabel(in: app)) \(inChrome ? "IN THE SIDEBAR" : "in the content"); sidebar frame \(chrome.exists ? String(describing: chrome.frame) : "not found")")
        if !focused.exists || inChrome { problems.append("the focus is not in the content at launch") }
        let atLaunch: CGFloat = featured.frame.minY
        lines.append("featured top at launch: \(Int(atLaunch))")
        XCUIRemote.shared.press(.left); sleep(1)
        let open: CGFloat = featured.frame.minY
        lines.append("sidebar opened (Left): focus \(focusedLabel(in: app)); sidebar frame \(navigationChrome(in: app).frame); featured top \(Int(open))")
        XCUIRemote.shared.press(.right); sleep(1)
        let closed: CGFloat = featured.frame.minY
        lines.append("sidebar closed (Right): focus \(focusedLabel(in: app)); sidebar frame \(navigationChrome(in: app).frame); featured top \(Int(closed))")
        if abs(open - atLaunch) > 1 { problems.append("the page moved when the sidebar opened (\(Int(atLaunch)) to \(Int(open)))") }
        if abs(closed - atLaunch) > 1 { problems.append("the page did not return to its launch position (\(Int(atLaunch)) to \(Int(closed)))") }
        let verdict: String = problems.isEmpty ? "SIDEBAR LAUNCH OK" : "SIDEBAR LAUNCH PROBLEM: " + problems.joined(separator: "; ")
        lines.append(verdict)
        note(name + "-SIDEBAR", lines.joined(separator: "\n"))
        XCTAssertTrue(problems.isEmpty, "\(name): " + verdict)
    }

    /// R387 (item A): the episode page is the product page with an episode's parts. From the tree only (no scrolling): the
    /// "S1, E1" line above the episode's title, Play, and the row of the season's other episodes (its heading) below Play.
    /// Writes "<name>-EPISODE"; a missing part or one out of order fails the test (soft, the player steps still run).
    /// The hero picture (the episode's still) cannot be read from the tree and stays on the device checklist.
    /// Item 7 of the owner's review of the run on fd9731f: the run reported "no title". The page's own container carries
    /// the title as its label (`pushedScreen`), and the title text is a header, which the tree may not list as a static
    /// text; so the title is any element with that label that is not the page itself (lower than half the window).
    /// Also checked now: the season row starts on the first screen (it peeks under the hero), and the Information
    /// heading, with the table of specs under it, does not.
    func episodePageCheck(_ name: String, code: String, title: String, season: String, in app: XCUIApplication) {
        let window: CGRect = app.windows.firstMatch.frame
        let codeLine: XCUIElement = app.staticTexts[code]
        var titleText: XCUIElement = app.staticTexts[title]
        if !titleText.exists {
            for candidate in app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex.prefix(8)
            where candidate.exists && candidate.frame.height > 0 && candidate.frame.height < window.height / 2 {
                titleText = candidate
                break
            }
        }
        let information: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Information")).firstMatch
        let play: XCUIElement = app.descendants(matching: .any).matching(identifier: "control.play").firstMatch
        let row: XCUIElement = app.staticTexts[season]
        var lines: [String] = []
        var problems: [String] = []
        if codeLine.exists { lines.append("“\(code)” at y \(Int(codeLine.frame.minY))") } else { problems.append("no “\(code)” line") }
        if titleText.exists { lines.append("“\(title)” at y \(Int(titleText.frame.minY))") } else { problems.append("no title") }
        if play.exists { lines.append("Play at y \(Int(play.frame.minY))") } else { problems.append("no Play") }
        if row.exists { lines.append("“\(season)” row at y \(Int(row.frame.minY))") } else { problems.append("no row of the season's other episodes") }
        if codeLine.exists, titleText.exists, codeLine.frame.minY >= titleText.frame.minY { problems.append("the code line is not above the title") }
        if play.exists, row.exists, row.frame.minY <= play.frame.minY { problems.append("the season row is not below Play") }
        if row.exists, window.height > 0, row.frame.minY >= window.maxY { problems.append("the season row does not show on the first screen") }
        if information.exists, window.height > 0, information.frame.height > 0 {
            lines.append("“Information” at y \(Int(information.frame.minY)) (window height \(Int(window.height)))")
            if information.frame.minY < window.maxY { problems.append("Information, the table of specs, is on the first screen") }
        } else {
            lines.append("“Information”: not in the tree yet (below the first screen)")
        }
        let verdict: String = problems.isEmpty ? "EPISODE PAGE OK" : "EPISODE PAGE PROBLEM: " + problems.joined(separator: "; ")
        lines.append(verdict)
        note(name + "-EPISODE", lines.joined(separator: "\n"))
        XCTAssertTrue(problems.isEmpty, "\(name): " + verdict)
    }

    /// R370 (owner's decision of 21 Nov 2026): the drawn format badges are never cut. Every element whose identifier starts
    /// with "badge." (the full set at the top of Information, each badge its own element) has a size, lies inside the window
    /// from side to side, and overlaps no other badge; the metadata line (one combined element) lies inside the window. The
    /// note "-BADGES" lists every badge with its frame. R371: with `rating`, the line must say "Rated <rating>" (the sample
    /// movie and show carry invented ratings, UITestFixtureDetails). Vertical position is not checked: Information is below the fold.
    func badgesNotCutCheck(_ name: String, expectBadges: Bool, rating: String? = nil, in app: XCUIApplication) {
        let window: CGRect = app.windows.firstMatch.frame
        let found: [XCUIElement] = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "badge.")).allElementsBoundByIndex
        var lines: [String] = ["window \(Int(window.width)) x \(Int(window.height))"]
        var problems: [String] = []
        var frames: [(String, CGRect)] = []
        for badge in found {
            let f: CGRect = badge.frame
            lines.append("\(badge.identifier) “\(badge.label)” x \(Int(f.minX)) y \(Int(f.minY)) w \(Int(f.width)) h \(Int(f.height))")
            if f.width <= 0 || f.height <= 0 { problems.append("“\(badge.label)” has no size") }
            if f.minX < window.minX || f.maxX > window.maxX { problems.append("“\(badge.label)” is cut at the side of the window") }
            for (other, g) in frames where f.intersection(g).width > 1 && f.intersection(g).height > 1 {
                problems.append("“\(badge.label)” overlaps “\(other)”")
            }
            frames.append((badge.label, f))
        }
        if found.isEmpty && expectBadges { problems.append("no badge element found") }
        let line: XCUIElement = app.descendants(matching: .any).matching(identifier: "product.metadataLine").firstMatch
        if line.exists {
            let f: CGRect = line.frame
            lines.append("metadata line “\(line.label)” x \(Int(f.minX)) w \(Int(f.width))")
            if f.minX < window.minX || f.maxX > window.maxX { problems.append("the metadata line is cut at the side of the window") }
            // R371: the rating badge is in the line (one combined element), said as "Rated <rating>"; it is never dropped.
            if let rating, !line.label.contains("Rated \(rating)") { problems.append("the rating “\(rating)” is not in the metadata line") }
        } else {
            lines.append("metadata line: not found by identifier")
            if rating != nil { problems.append("no metadata line to hold the rating") }
        }
        // R391 (shared fault 1): badges of one line stand close together (`ScreenRules.badgeGaps`; the run on fd9731f
        // measured 65 to 72 pt between them).
        let gaps: CheckResult = ScreenRules.badgeGaps(badges: frames.map { (pair: (String, CGRect)) -> (String, AXRect) in (pair.0, AXRect(pair.1)) })
        lines += gaps.lines
        if !gaps.passed { problems.append(gaps.verdict) }
        let verdict: String = problems.isEmpty ? "BADGES NOT CUT" : "BADGES PROBLEM: " + problems.joined(separator: "; ")
        lines.append(verdict)
        note(name + "-BADGES", lines.joined(separator: "\n"))
        XCTAssertTrue(problems.isEmpty, "\(name): " + verdict)
    }

    /// #36 group 5: what each press of the last `moveFocusToEnd` or `focus` did, one line per press ("3 Down: “Plex” {…}").
    private var focusPath: [String] = []

    /// The presses recorded by the last focus helper, for a NOT-REACHED note.
    func focusPathText() -> String {
        "\(focusPath.count) presses:\n" + focusPath.joined(separator: "\n")
    }

    /// Moves the focus with the remote's arrows until `target` has it. Direction comes from where the target is relative to
    /// the focused element. Run 44401030622 pressed Left 311 times on Settings: the focused element was the ROW (a cell)
    /// around the target button, so `target.hasFocus` stayed false and the frames overlapped. Now a focused element that
    /// contains the target's centre (or lies inside the target) counts as the target, and the loop stops when three
    /// presses in a row leave the focus where it was.
    func focus(_ target: XCUIElement, in app: XCUIApplication, maxPresses: Int = 30) -> Bool {
        let remote = XCUIRemote.shared
        var last: String?
        var unmoved = 0
        focusPath = []
        for press in 1...maxPresses {
            guard target.exists else { remote.press(.down); focusPath.append("\(press) Down: target not in the tree yet"); continue }
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard focused.exists else { remote.press(.down); focusPath.append("\(press) Down: nothing focused"); continue }
            let f = focused.frame, t = target.frame
            // #36 8 T5: the same element (same non-empty label), or each frame holds the other's centre. Before, ONE centre
            // inside the other frame was enough: a borderless episode lockup reports a 615 pt tall frame reaching far past
            // its visible card (55-show-page-HIERARCHY), so the More button's centre fell inside the S1 E1 card's frame,
            // the helper stopped on More, and test12 pressed Select on it (22-player-skip-intro-NOT-REACHED: the More menu
            // open on the show page).
            if ScreenRules.focusReached(focused: AXRect(f), focusedLabel: focused.label, target: AXRect(t), targetLabel: target.label) { return true }
            // #36 group 5: unmoved only when the label AND the frame stay the same (see `moveFocusToEnd`).
            let here: String = "“\(focused.label)” \(f)"
            if here == last { unmoved += 1; if unmoved >= 3 { return false } } else { unmoved = 0 }
            last = here
            let direction: XCUIRemote.Button = Self.direction(from: f, to: t)
            focusPath.append("\(press) \(Self.name(of: direction)) from \(here) toward \(t)")
            remote.press(direction)
        }
        return target.exists && target.hasFocus
    }

    /// #33 L: the arrow that moves the focus from `f` toward `t`. The run of 20 Nov missed three targets with the old rule
    /// (Down only when the target starts below the focused element's bottom edge):
    /// - a row a lazy list has not laid out yet reports an EMPTY frame at the origin, so the old rule pressed Up, toward the top
    ///   (10-add-source-learn-more: focus stayed on “Search Your Network”; 65-needs-review-choice-larger-text: on the tab bar);
    ///   an empty frame now means "further down the list";
    /// - episode cards of two seasons are 615 pt tall but only 427 pt apart, so the frames overlap vertically and the old rule
    ///   pressed Left on the first card for ever (56-show-season-2-episode-row); the centres decide now: vertical when they
    ///   are more than half a height apart, otherwise horizontal.
    /// The rule is `ScreenRules.focusDirection`, proven on the run's frames in ScreenChecksTests.
    static func name(of button: XCUIRemote.Button) -> String {
        switch button {
        case .down: return "Down"
        case .up: return "Up"
        case .left: return "Left"
        case .right: return "Right"
        default: return "other"
        }
    }

    static func direction(from f: CGRect, to t: CGRect) -> XCUIRemote.Button {
        switch ScreenRules.focusDirection(from: AXRect(f), to: AXRect(t)) {
        case .down: return .down
        case .up: return .up
        case .left: return .left
        case .right: return .right
        }
    }

    /// The accessibility hierarchy right after a screen opened (screenshot review item 7): are the rows buttons or cells,
    /// with labels? Kept as a text attachment "NN-name-HIERARCHY" in the screenshots-logs artifact.
    func hierarchy(_ name: String, of app: XCUIApplication) {
        note(name + "-HIERARCHY", app.debugDescription)
    }

    /// Types `text` on the tvOS on-screen keyboard by moving to each key and pressing Select (run 44401030622: `typeText`
    /// failed with "Neither element nor any descendant has keyboard focus" on the search keyboard). False when a key is not
    /// found or cannot be reached.
    /// #36 group 5b: 76-search-results of the third run of 20 Nov stopped on "t": no key of the linear keyboard carries the
    /// focus flag (76-search-results-HIERARCHY: "Keyboard …, Focused" and "SearchField …, Keyboard Focused", every Key
    /// without it), so the focus helper could not tell where it was. The focused key is the ENLARGED one ("t" 70 x 80 beside
    /// 54 x 64; ScreenRules.focusedKey), and the keys are one row in reading order: Left or Right until the wanted key is the
    /// enlarged one, then Select. Every step goes to the "-FOCUS-PATH" note of `name`.
    func typeOnKeyboard(_ text: String, in app: XCUIApplication, name: String) -> Bool {
        var path: [String] = []
        defer { note(name + "-FOCUS-PATH", path.joined(separator: "\n")) }
        for character in text {
            let label: String = String(character)
            var typed: Bool = false
            for press in 0..<40 {
                let dump: AccessibilityDump = AccessibilityDump(app.keyboards.firstMatch.debugDescription)
                let keys: [(label: String, frame: AXRect)] = dump.nodes.filter { $0.type == "Key" }.compactMap { (node: AXNode) in
                    node.frame.map { (label: node.label, frame: $0) }
                }
                guard let target = keys.firstIndex(where: { $0.label == label || $0.label == label.uppercased() }) else {
                    path.append("no key \u{201C}\(label)\u{201D} among \(keys.count) keys"); return false
                }
                guard let here = ScreenRules.focusedKey(keys) else {
                    // R296: fourth run of 20 Nov, 76-search-results-HIERARCHY: the focus was still on the tab bar's Search
                    // item (y 61, "Focused") above the keyboard row (y 262), so no key was enlarged. Down moves the focus
                    // into the keyboard; at most three presses, each one in the note.
                    if press < 3 {
                        path.append("no enlarged key among \(keys.count) keys (focus on \u{201C}\(focusedLabel(in: app))\u{201D}): Down")
                        XCUIRemote.shared.press(.down); usleep(400_000); continue
                    }
                    path.append("no enlarged key among \(keys.count) keys: the focused key is not known"); return false
                }
                path.append("\u{201C}\(label)\u{201D}: focus on \u{201C}\(keys[here].label)\u{201D} \(keys[here].frame) after \(press) presses")
                if here == target {
                    XCUIRemote.shared.press(.select); usleep(400_000); typed = true; break
                }
                XCUIRemote.shared.press(target < here ? .left : .right); usleep(300_000)
            }
            if !typed { path.append("\u{201C}\(label)\u{201D} NOT REACHED in 40 presses"); return false }
        }
        path.append("TYPED \u{201C}\(text)\u{201D}")
        return true
    }

    /// Focuses the control labelled `text` and presses Select. False (with a NOT-REACHED note for `name`) when it cannot.
    /// #25 A2: with `id`, the control is looked up by its identifier first (and checked to be exposed once), then by `text`.
    /// #25 A4: a NOT-REACHED note names the identifier and label searched and carries the element dump.
    func open(_ text: String, id: String? = nil, in app: XCUIApplication, name: String) -> Bool {
        let searched = id.map { "identifier “\($0)” or label “\(text)”" } ?? "label “\(text)”"
        let target = control(id: id, label: text, in: app)
        guard target.waitForExistence(timeout: 10) else {
            notReached(name, "No control with the \(searched) was found (buttons, cells, menu buttons, switches, and containers of a StaticText with that label).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
            return false
        }
        if let id, target.identifier == id { checkExposedOnce(id, name: name, in: app) }
        guard focus(target, in: app, maxPresses: 40) else {
            notReached(name, "The focus could not be moved to the \(searched) with the remote's arrows (focus stayed on \(focusedLabel(in: app))).\n" + focusPathText() + "\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
            return false
        }
        // #36 8 T5: Select only on the target (22-player-skip-intro pressed Select on More in the run of 20 Nov).
        let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let onTarget: Bool = focused.exists && ScreenRules.focusReached(focused: AXRect(focused.frame), focusedLabel: focused.label,
                                                                         target: AXRect(target.frame), targetLabel: target.label)
        guard target.hasFocus || onTarget else {
            notReached(name, "The focus is on \(focusedLabel(in: app)), not on the \(searched); Select not pressed.\n" + focusPathText())
            return false
        }
        XCUIRemote.shared.press(.select)
        return true
    }

    /// #25 B2: a toolbar control of Movies or Shows. R375: the toolbar is the system's (OPEN_QUESTIONS R375); Needs Review
    /// and Jump to Letter are items of its More menu (text-labelled actions apart from the symbols; tvOS has no
    /// `ToolbarSpacer`), so they are opened through More. Sort and Filter, Saved Views and More are on the bar.
    func openToolbarControl(_ text: String, id: String, in app: XCUIApplication, name: String) -> Bool {
        if Self.moreMenuIDs.contains(id) {
            guard open("More", id: ControlID.moreControls, in: app, name: name) else { return false }
            sleep(1)
            return open(text, in: app, name: name)
        }
        return open(text, id: id, in: app, name: name)
    }

    /// R375: the controls that live in the library toolbar's More menu.
    static let moreMenuIDs: Set<String> = [ControlID.needsReview, ControlID.jumpToLetter]

    /// The tab bar from the accessibility tree (OPEN_QUESTIONS R167 (c)): six tabs Home, Movies, Shows, Files, Search,
    /// Settings, each whole inside the window and not overlapping the next. Written as "NN-name-TABBAR" (in the
    /// screenshots-logs artifact) with every tab's label and frame and a final "TAB BAR OK" or "TAB BAR PROBLEM: ...".
    /// A fade at the bar's edge is drawn, not reported in the tree; the screenshot shows that.
    /// R359: the same six items in the sidebar, one under the other (`navigationChrome`); the note's first line says which
    /// the app showed. With the sidebar collapsed on Home, Left opens it first.
    func tabBarCheck(_ name: String, in app: XCUIApplication) {
        let expected = ["Home", "Movies", "Shows", "Files", "Search", "Settings"]
        let window = app.windows.firstMatch.frame
        let sidebar: Bool = usesSidebar(app)
        var opened: String = ""
        if sidebar, !navigationChrome(in: app).exists {
            XCUIRemote.shared.press(.left); sleep(1); opened = " (opened with Left)"
        }
        let chrome: XCUIElement = navigationChrome(in: app)
        var kind: String = "tab bar"
        if sidebar { kind = "sidebar \(chrome.exists ? "\(chrome.elementType.rawValue) \(chrome.frame)" : "NOT FOUND")" + opened }
        var items: [XCUIElement] = []
        for label in expected {
            let item: XCUIElement = chrome.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            if item.exists { items.append(item) }
        }
        var lines = ["navigation: " + kind] + items.map { "\($0.label)\t\(String(describing: $0.frame))" }
        var problems: [String] = []
        let labels = items.map(\.label)
        if labels != expected { problems.append("tabs are \(labels), expected \(expected)") }
        for b in items where b.frame.isEmpty || !window.contains(b.frame) {
            problems.append("“\(b.label)” is not whole inside the window \(String(describing: window))")
        }
        for (a, b) in zip(items, items.dropFirst()) where (sidebar ? a.frame.maxY > b.frame.minY + 1 : a.frame.maxX > b.frame.minX + 1) {
            problems.append("“\(a.label)” overlaps “\(b.label)”")
        }
        // R376: the "Library" section header (Movies, Shows, Files). How tvOS 27 exposes it is UNVERIFIED, so a missing header
        // is recorded, not judged; a header that is there must sit between Home and Movies.
        if sidebar {
            let header: XCUIElement = chrome.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Library")).firstMatch
            if header.exists {
                lines.append("section\tLibrary\t\(String(describing: header.frame))")
                if let home = items.first(where: { $0.label == "Home" }), let movies = items.first(where: { $0.label == "Movies" }),
                   !(header.frame.minY >= home.frame.maxY - 1 && header.frame.maxY <= movies.frame.minY + 1) {
                    problems.append("the Library header is not between Home and Movies")
                }
            } else {
                lines.append("section\tLibrary\tnot in the tree (recorded, not judged)")
            }
        }
        lines.append(problems.isEmpty ? "TAB BAR OK" : "TAB BAR PROBLEM: " + problems.joined(separator: "; "))
        note(name + "-TABBAR", lines.joined(separator: "\n"))
        if sidebar, !opened.isEmpty { XCUIRemote.shared.press(.right); sleep(1) }
    }

    func back() { XCUIRemote.shared.press(.menu); sleep(1) }

    func settle() { sleep(2) }

    // MARK: Empty library (clean start)

    func test01_FirstLaunchAndEmptyScreens() {
        let app = launch("-UITestEmpty")
        // #24 C: no "01-first-launch" shot any more. The app has no first-launch screen of its own (no onboarding): a clean
        // start opens Home, so 01 was pixel for pixel 02-home-empty (run on fa00af8). 02 is the first-launch picture.
        if waitForScreen("screen.home", in: app) {
            _ = waitFor("Add a Source", in: app, timeout: 10)
            settle(); shot("02-home-empty")
            tabBarCheck("02-home-empty", in: app)
        } else { notReached("02-home-empty", "The Home screen (screen.home) did not appear within 30 s.") }
        app.terminate()

        // 06: the Search tab with an empty field shows Discover (here its "needs a key" state); OPEN_QUESTIONS R167 (c).
        // There is no Discover tab any more, so the former 06 (discover) and 07 (search) are this one screen.
        for (n, tab, name) in [("03", "movies", "movies-empty"), ("04", "shows", "shows-empty"), ("05", "files", "files-empty"),
                               ("06", "search", "search-empty-discover")] {
            let a = launch("-UITestEmpty", tab: tab)
            if waitForScreen("screen.\(tab)", in: a) { settle(); shot("\(n)-\(name)") }
            else { notReached("\(n)-\(name)", "The \(tab) screen (screen.\(tab)) did not appear within 30 s.") }
            a.terminate()
        }
    }

    func test02_AddASource() {
        let app = launch("-UITestEmpty")
        guard waitForScreen("screen.home", in: app), waitFor("Add a Source", in: app) else { return }
        rememberPage(app)
        guard open("Add a Source", in: app, name: "10-add-source-types") else { return }
        // #25 A3: the list is ready when its first row (identifier control.searchYourNetwork) is there; "Type an Address" is a
        // section header further down that a lazy list may not have built yet.
        guard waitForScreen(ControlID.searchYourNetwork, in: app, timeout: 15) else {
            return notReached("10-add-source-types", "The source type list did not open (no element with the identifier “\(ControlID.searchYourNetwork)”).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
        checkExposedOnce(ControlID.searchYourNetwork, name: "10-add-source-types", in: app)
        settle()
        shot("10-add-source-types")
        hierarchy("10-add-source-types", of: app)
        // #30: full screen, no tab bar (R228).
        checkFullScreen(anchor: ControlID.searchYourNetwork, label: "Search Your Network", in: app, name: "10-add-source-types")
        // #25 A2: each type row by its identifier ("sourceKind." + SourceKind raw value), the label as the fallback.
        let kinds = [("11", "WebDAV", "webdav"), ("12", "SMB", "smb"), ("13", "NFS", "nfs"), ("14", "SFTP", "sftp"), ("15", "FTP", "ftp"),
                     ("16", "UPnP/DLNA", "upnp"), ("17", "Jellyfin", "jellyfin"), ("18", "Emby", "emby"), ("19", "Web Link", "directLink")]
        for (n, kind, raw) in kinds {
            let name = "\(n)-form-" + kind.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
            guard open(kind, id: ControlID.sourceKind(raw), in: app, name: name) else { continue }
            // The form is ready when its Connect button stands still (R324: the forms have no Cancel).
            _ = waitUntilStill(control(id: ControlID.sourceConnect, label: "Connect", in: app))
            shot(name)
            // R331 (docs/SOURCE_SETUP_DESIGN.md): an empty form shows no placeholder as a value (R322), and Connect is its one
            // action, with a shape at rest (R324). The R273 checks of drawn text fields (-FIELDS-AT-REST, -SAFE-AREA) are
            // gone: the form draws no text field since R320.
            checkNoPlaceholderValues(name, in: app)
            checkActions(name, in: app)
            checkNoKeyField(in: app, name: name)
            checkFullScreen(anchor: ControlID.sourceConnect, label: "Connect", in: app, name: name)
            if n == "11" { keyboardOfNameRow(in: app) }
            back()
            _ = waitForScreen(ControlID.searchYourNetwork, in: app, timeout: 5)
        }
        // #25 B1: the type notes moved to "About Source Types" (Learn More); its page, once.
        if open("About Source Types", id: ControlID.learnMore, in: app, name: "10-add-source-learn-more") {
            settle(); shot("10-add-source-learn-more")
            // R329: About Source Types is a list of the types; the WebDAV row opens WebDAV's own About page, whose heading is
            // "About WebDAV" with a "Tested" section ("10-add-source-about-webdav", "-ABOUT-PAGE" note).
            let about: String = "10-add-source-about-webdav"
            if open("WebDAV", id: ControlID.sourceAbout("webdav"), in: app, name: about) {
                settle(); shot(about)
                let heading: Bool = app.staticTexts.matching(NSPredicate(format: "label == %@", "About WebDAV")).firstMatch.exists
                let tested: Bool = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Tested")).firstMatch.exists
                note(about + "-ABOUT-PAGE", "heading \u{201C}About WebDAV\u{201D}: " + (heading ? "shown OK" : "NOT SHOWN")
                     + "\nsection \u{201C}Tested\u{201D}: " + (tested ? "shown OK" : "NOT SHOWN"))
                XCTAssertTrue(heading, "\(about): the type's About page has no \u{201C}About WebDAV\u{201D} heading")
                back()
            }
            back()
        }
        app.terminate()

        // 20: the types that cannot be set up yet, with their reasons, at the bottom of the list (#15 item 1.3). A fresh launch,
        // so nothing left open by the forms above can stop it; then Down until the focus stops (the Cancel row is last, the
        // "Not Available Yet" rows above it are focusable since #33 L).
        let end = launch("-UITestEmpty")
        if waitForScreen("screen.home", in: end), waitFor("Add a Source", in: end), open("Add a Source", in: end, name: "20-add-source-not-available"),
           waitForScreen(ControlID.searchYourNetwork, in: end, timeout: 15) {
            // #36 group 5: the run of 20 Nov stopped with “Dropbox, No sign-in for TVs” focused (Plex, About Source Types and
            // Cancel below it). The end is reached when Cancel has the focus; every press is written to the -FOCUS-PATH note.
            // The section header is drawn in upper case and its label in the tree is too (“NOT AVAILABLE YET” in the
            // run's notes), so it is looked for without case.
            let reachedEnd: Bool = moveFocusToEnd(in: end)
            let cancel: XCUIElement = control(id: ControlID.sourceCancel, label: "Cancel", in: end)
            let onCancel: Bool = cancel.exists && (cancel.hasFocus || focusedLabel(in: end) == "“Cancel”")
            // #29: typed steps, no ternary inside a `+` chain.
            var pathVerdict: String = "FOCUS PROBLEM: Cancel was not reached (focus on \(focusedLabel(in: end)))"
            if onCancel { pathVerdict = "FOCUS REACHED CANCEL OK" }
            let pathNote: String = focusPathText() + "\nend reached: \(reachedEnd); Cancel focused: \(onCancel)\n" + pathVerdict
            note("20-add-source-not-available-FOCUS-PATH", pathNote)
            let header: Bool = end.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Not Available Yet")).firstMatch
                .waitForExistence(timeout: 5)
            if onCancel || header {
                settle(); shot("20-add-source-not-available")
                checkCover("20-add-source-not-available", scrolled: "moving the focus down the list to Cancel", in: end)
            }
            if !onCancel {
                notReached("20-add-source-not-available", "Moving down did not reach Cancel (focus on \(focusedLabel(in: end))).\n" + focusPathText())
                XCTFail("20-add-source-not-available: the remote's Down did not reach Cancel below the Not Available Yet rows")
            }
            // Network search last: it may ask for local-network permission, which a test cannot answer reliably.
            end.terminate()
        }
        // R366 (compile run of 21 Nov 2026, item 14): with the real search, picture 21 listed the machine the run was on (a
        // real name in a public picture). The fake server makes the search list only the synthetic "Sample NAS" and
        // browse nothing.
        let network = launch("-UITestEmpty", extra: ["-UITestFakeServer"])
        if waitForScreen("screen.home", in: network), waitFor("Add a Source", in: network), open("Add a Source", in: network, name: "21-search-your-network"),
           waitForScreen(ControlID.searchYourNetwork, in: network, timeout: 15),
           open("Search Your Network", id: ControlID.searchYourNetwork, in: network, name: "21-search-your-network") {
            sleep(4); shot("21-search-your-network"); checkCover("21-search-your-network", in: network)
            // R366: the list shows the synthetic server (a record that the fake search, not the real one, ran).
            let sample: Bool = network.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample NAS")).firstMatch.exists
            note("21-search-your-network-NAMES", sample ? "FAKE SEARCH OK: Sample NAS listed" : "Sample NAS NOT LISTED: check the picture for a real name before publishing it")
        }
        network.terminate()
        // #30 items 2 and 3: the found row and the found server's form, with ONE synthetic server (-UITestFakeServer: the
        // search lists it without browsing; no network; Debug builds only, the Release-string check covers its texts).
        let rawName = "Sample NAS 802046173902541866"
        let fake = launch("-UITestEmpty", extra: ["-UITestFakeServer"])
        if waitForScreen("screen.home", in: fake), waitFor("Add a Source", in: fake), open("Add a Source", in: fake, name: "21-search-your-network-result"),
           waitForScreen(ControlID.searchYourNetwork, in: fake, timeout: 15),
           open("Search Your Network", id: ControlID.searchYourNetwork, in: fake, name: "21-search-your-network-result") {
            if waitFor("Sample NAS", in: fake, timeout: 10) {
                settle(); shot("21-search-your-network-result"); checkCover("21-search-your-network-result", in: fake)
                // The row shows the readable name and the type; the raw identifier is not on the list (item 3).
                let rawOnList: Bool = fake.staticTexts[rawName].exists
                note("21-search-your-network-result-ROW", rawOnList ? "RAW ID ON THE LIST ROW" : "RAW ID NOT ON THE LIST ROW OK")
                XCTAssertFalse(rawOnList, "21-search-your-network-result: the raw server ID is drawn on the list row")
                if open("Sample NAS", in: fake, name: "21-search-your-network-server-details"),
                   waitForScreen(ControlID.serverID, in: fake, timeout: 10) {
                    let row: XCUIElement = control(id: ControlID.serverID, label: "Server ID", in: fake)
                    if focus(row, in: fake) {
                        settle(); shot("21-search-your-network-server-details")
                        // R294: the focus was moved down to the Server ID row, so the form has scrolled and its first text
                        // is above the screen by design (fourth run of 20 Nov: "Name" at y -121); the title rule is skipped.
                        checkCover("21-search-your-network-server-details", scrolled: "the focus moved down to the Server ID row", in: fake)
                    }
                    else { notReached("21-search-your-network-server-details", "The Server ID row did not take the focus (focus on \(focusedLabel(in: fake))).") }
                    let value: String = (row.value as? String) ?? ""
                    note("21-search-your-network-server-details-ROW", "Server ID row value: \(value)\nframe: \(row.frame)\n" + (value == rawName ? "WHOLE ID OK" : "ID NOT WHOLE"))
                    XCTAssertEqual(value, rawName, "21-search-your-network-server-details: the Server ID row does not carry the whole identifier")
                    // #33 D: the Name row starts with the readable name only. R320: the form draws no text field; the Name
                    // ROW (identifier sourceField.name) reports the value. The tree carries the whole value, not what is drawn,
                    // so a "…" cut cannot be read here; the picture 21-search-your-network-server-details shows it.
                    let nameRow: XCUIElement = control(id: ControlID.sourceField("name"), label: "Name", in: fake)
                    let fieldValues: [String] = [(nameRow.value as? String) ?? ""]
                    // #34 1: typed steps, no ternary inside a `+` chain (the #29 pattern).
                    let hasReadable: Bool = fieldValues.contains("Sample NAS")
                    let hasRaw: Bool = fieldValues.contains { (value: String) -> Bool in value.contains(rawName) }
                    let nameOK: Bool = hasReadable && !hasRaw
                    var nameVerdict: String = "NAME FIELD IS NOT “Sample NAS” ALONE"
                    if nameOK { nameVerdict = "NAME IS THE READABLE NAME OK" }
                    let nameNote: String = "text field values: \(fieldValues)\n" + nameVerdict
                    note("21-search-your-network-server-details-NAME", nameNote)
                    XCTAssertTrue(nameOK, "21-search-your-network-server-details: the Name field is not “Sample NAS” alone: \(fieldValues)")
                }
                formSearchPicksServer(in: fake)
            } else {
                notReached("21-search-your-network-result", "The synthetic server “Sample NAS” was not listed within 10 s.")
            }
        }
    }

    // MARK: Settings (with the sample library, so Sources and Library show content)

    func test03_Settings() {
        let app = launch("-UITestFixtures", tab: "settings")
        guard waitForScreen("screen.settings", in: app), waitFor("Playback", in: app) else { return notReached("30-settings", "Settings did not open.") }
        settle()
        shot("30-settings")
        hierarchy("30-settings", of: app)
        let pages = [("31", "Playback"), ("32", "Home Screen"), ("33", "Sources"), ("35", "Library"), ("36", "Online Lookup"),
                     ("37", "Storage and iCloud"), ("38", "Accessibility")]
        for (n, page) in pages {
            let name = "\(n)-settings-" + page.lowercased().replacingOccurrences(of: " ", with: "-")
            guard open(page, in: app, name: name) else { continue }
            settle()
            let pageTop: String = focusedLabel(in: app)
            shot(name)
            // #36 T6: every Settings page from 31 to 38 gets a -CONTRAST note of all its texts.
            textContrast(name, in: app)
            if page == "Playback" {
                checkContrast(name, prefixes: ["How titles play", "Skip buttons appear", "Playback Stats adds"], in: app)
                // R389: Down must reach the last row (Last Playback Problem); then the R346 check goes back up.
                lastRowCheck(name, in: app)
                // R346 (item A): the longest Settings pane; Up from its last row must reach its first row first.
                scrollUpCheck(name, top: pageTop, in: app)
            }
            if page == "Library" {
                // R389: the counts below Needs Review hold no control; Down must reach the last one (Files).
                lastRowCheck(name, in: app)
            }
            if page == "Sources", open("Sample Library", in: app, name: "34-settings-source-detail") {
                settle(); shot("34-settings-source-detail"); textContrast("34-settings-source-detail", in: app); back()
            }
            back()
        }
        app.terminate()

        // 40: About, from a fresh launch on the Settings tab (#15 item 1.3): About is the LAST row, and after seven pages
        // and backs the focus could be anywhere. Down until the focus stops, then open the row labelled exactly "About".
        let about = launch("-UITestFixtures", tab: "settings")
        guard waitForScreen("screen.settings", in: about), waitFor("Playback", in: about) else { return notReached("40-about", "Settings did not open for About.") }
        _ = moveFocusToEnd(in: about)
        guard open("About", in: about, name: "40-about") else { return }
        settle()
        shot("40-about")
        let aboutTop: String = focusedLabel(in: about)
        // #24 C: the run on fa00af8 had 41-1/2/3 identical to 40: the page is longer than the screen, but its text rows were
        // not focusable, so Down had nothing to move to. The rows now take focus (App/Features/Settings/AboutView.swift);
        // four Down presses per picture move the focus, and the page with it, a screen further.
        for step in 1...3 {
            for _ in 0..<4 { XCUIRemote.shared.press(.down); usleep(400_000) }
            sleep(1)
            shot("41-about-scrolled-\(step)")
        }
        // R346 (item A): the owner's build 5 jumped to the tab bar on Up before the page was back at its first row.
        scrollUpCheck("41-about", top: aboutTop, in: about)
        // #25 A2: by its identifier; the long notices moved to Learn More pages (B9), so the link is nearer the top.
        if open("Full Licence Texts", id: ControlID.fullLicenceTexts, in: about, name: "42-licence-texts") {
            settle(); shot("42-licence-texts")
            let licenceTop: String = focusedLabel(in: about)
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("43-licence-texts-scrolled-\(step)") }
            scrollUpCheck("43-licence-texts", top: licenceTop, in: about)
            // R348 (item B): two pages deep in Settings (About, Full Licence Texts); pressing Settings again goes back to
            // the first Settings page.
            reselectTabCheck("44-settings-reselected", rootText: "Playback", pushedHeader: "Full Licence Texts", in: about)
        }
        about.terminate()

        // #26: Online Lookup with a key set (a synthetic key in the in-memory store, -UITestFakeTMDBKey; nothing is sent),
        // shown masked; then a second source is added and its form must have no key field (one key for the whole app).
        let keyed = launch("-UITestFixtures", tab: "settings", extra: ["-UITestFakeTMDBKey"])
        guard waitForScreen("screen.settings", in: keyed), waitFor("Playback", in: keyed) else {
            return notReached("36-settings-online-lookup-key-set", "Settings did not open with the synthetic key.")
        }
        if open("Online Lookup", in: keyed, name: "36-settings-online-lookup-key-set") {
            settle()
            let masked = keyed.descendants(matching: .any).matching(identifier: ControlID.keyValue("tmdb")).firstMatch
            if !masked.waitForExistence(timeout: 5) {
                notReached("36-settings-online-lookup-key-set", "No masked key row (identifier “\(ControlID.keyValue("tmdb"))”).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(keyed, lines: 80))")
            }
            shot("36-settings-online-lookup-key-set")
            keyEntryRow(in: keyed)
            regionPicker(in: keyed)
            for _ in 0..<6 { XCUIRemote.shared.press(.down); usleep(400_000) }
            sleep(1)
            shot("36-settings-online-lookup-key-set-scrolled")
            back()
        }
        if open("Sources", in: keyed, name: "39-second-source-no-key-field"), open("Add a Source", in: keyed, name: "39-second-source-no-key-field"),
           waitForScreen(ControlID.searchYourNetwork, in: keyed, timeout: 15),
           open("WebDAV", id: ControlID.sourceKind("webdav"), in: keyed, name: "39-second-source-no-key-field") {
            _ = waitUntilStill(control(id: ControlID.sourceConnect, label: "Connect", in: keyed))
            checkNoKeyField(in: keyed, name: "39-second-source-no-key-field")
        }
    }

    /// #30 C / #33 C: Add a Source and its forms are full screen. The run of 20 Nov measured the Cancel BUTTON's own label (90
    /// of 1920 wide, note 111-default-source-form-PRESENTATION) and called every form a small sheet; the ROW around the
    /// anchor is measured now (`ScreenRules.fullScreenRow`: the Cell, else the Table or CollectionView, else the nearest
    /// wider container; proven on note 10 in Packages/VideoPlayerCore/Tests/ScreenChecksTests). Part of `checkCover`.
    func checkFullScreen(anchor id: String, label: String, in app: XCUIApplication, name: String) {
        checkCover(name, anchor: id, in: app)
    }

    /// #33 B: the text frames of the page that is on screen now, kept so `checkCover` can look for them THROUGH the cover
    /// that opens next (once the cover is open, the page is hidden from accessibility and its frames cannot be read).
    private var pageTextsBeforeCover: [AXRect] = []

    func rememberPage(_ app: XCUIApplication) {
        let dump: AccessibilityDump = AccessibilityDump(app.debugDescription)
        var texts: [AXRect] = []
        if let page = dump.pageRoot { texts = dump.textFrames(under: page) }
        pageTextsBeforeCover = texts
        print("PAGE TEXTS REMEMBERED: \(pageTextsBeforeCover.count)")
    }

    /// #33 A and B: every task cover (`taskCover`, App/Shared/SettingsPane.swift) while it is open. Writes "<name>-COVER" with
    /// one section per check and fails the test, naming the check, when any fails:
    /// - row (C, with `anchor`): the row around the anchor is wider than half the window;
    /// - B (2): no "screen.*" element of the page behind is in the accessibility tree;
    /// - A: the cover's title starts at or below the 60 pt safe area, its rows and fields do not overlap;
    /// - B (3): the tab bar is not hittable;
    /// - B (1): the tab bar band (y 46 to 114, full width) and every text the page had (`rememberPage`) show the cover's
    ///   own background colour, within `CoverPixels.channelTolerance` (its doc comment explains the numbers).
    /// The same functions fail on pictures 11, 66 and 74 of the run of 20 Nov and pass on a plain opaque cover
    /// (Packages/VideoPlayerCore/Tests/ScreenChecksTests).
    /// `scrolled`: why the picture shows a scrolled list (#36 group-1 b); a name ending in "-scrolled" counts as scrolled.
    func checkCover(_ name: String, anchor: String? = nil, scrolled: String? = nil, in app: XCUIApplication) {
        let screenshot: XCUIScreenshot = XCUIScreen.main.screenshot()
        let dump: AccessibilityDump = AccessibilityDump(app.debugDescription)
        var lines: [String] = []
        var failures: [String] = []
        func take(_ title: String, _ result: CheckResult) {
            lines.append("## " + title)
            lines += result.lines
            if !result.passed { failures.append(title + ": " + result.verdict) }
        }
        if let anchor { take("row width (C)", ScreenRules.fullScreenRow(in: dump, anchor: anchor)) }
        take("cover exposed to accessibility (#34 2)", ScreenRules.coverExposed(in: dump))
        take("page hidden from accessibility (B 2)", ScreenRules.pageHiddenBehindCover(in: dump))
        // #36 group 2: for each page screen still in the tree, what XCTest says of it and of its controls (a record, not
        // part of the rule: the rule stays "not in the tree"). XCTest has no VoiceOver query, so whether VoiceOver can
        // reach them is NOT measured here; Apple's isModal page says non-modal siblings "are ignored".
        lines.append("## page behind the cover, as XCTest sees it (record only)")
        for screenID in Set(dump.nodes.map(\.identifier).filter { $0.hasPrefix("screen.") }).sorted() {
            let screen: XCUIElement = app.descendants(matching: .any).matching(identifier: screenID).firstMatch
            guard screen.exists else { continue }
            lines.append("\(screenID): exists true, isHittable \(screen.isHittable), isEnabled \(screen.isEnabled)")
            let controls: [XCUIElement] = screen.buttons.allElementsBoundByIndex.prefix(8).map { $0 }
            for control in controls where control.exists {
                lines.append("  button “\(control.label)”: isHittable \(control.isHittable), isEnabled \(control.isEnabled)")
            }
        }
        // R362 (item 10): which cause is left (record only). The cover's value is the app's cover counter; a page screen's
        // value says whether it was told to hide. Counter 0: the cover never counted itself. "told hidden true" on a page
        // still listed: the page was hidden and XCTest lists it anyway (then XCTest's tree is not VoiceOver's).
        lines.append("## cover counter (R362, record only)")
        let probes: [XCUIElement] = app.descendants(matching: .any).matching(NSPredicate(format: "value BEGINSWITH %@", "cover probe")).allElementsBoundByIndex.prefix(8).map { $0 }
        if probes.isEmpty { lines.append("no cover probe value in the tree") }
        for probe in probes where probe.exists {
            let value: String = (probe.value as? String) ?? ""
            lines.append("\(probe.identifier.isEmpty ? probe.label : probe.identifier): \(value)")
        }
        var scrolledReason: String? = scrolled
        if scrolledReason == nil, name.hasSuffix("-scrolled") || name.contains("-scrolled-") { scrolledReason = "scrolling (“-scrolled” in its name)" }
        take("cover layout (A)", ScreenRules.coverLayout(in: dump, scrolled: scrolledReason))
        // #36 S-C (R255): buttons side by side are the same size and at least 66 pt high.
        if let cover = dump.coverRoot { take("buttons side by side (#36 S-C)", ScreenRules.sideBySideButtons(in: dump, root: cover)) }
        let tabBar: XCUIElement = navigationChrome(in: app)
        let hittable: Bool = tabBar.exists && tabBar.isHittable
        var tabBarVerdict: String = "TAB BAR NOT HITTABLE OK"
        if hittable { tabBarVerdict = "TAB BAR HITTABLE" }
        take("tab bar (B 3)", CheckResult(passed: !hittable, lines: ["tab bar in the tree: \(tabBar.exists), hittable: \(hittable)",
                                                                  tabBarVerdict]))
        if let image = RGBImage(screenshot: screenshot), let windowIndex = dump.window,
           let window = dump.nodes[windowIndex].frame, window.width > 0 {
            let scale: Double = Double(image.width) / window.width
            var texts: [AXRect] = pageTextsBeforeCover
            if texts.isEmpty, let page = dump.pageRoot, page != dump.coverRoot { texts = dump.textFrames(under: page) }
            lines.append("picture \(image.width) x \(image.height) px, \(String(format: "%.2f", scale)) px per pt, \(texts.count) page texts sampled")
            take("pixels (B 1)", CoverPixels.check(image, scale: scale, regions: CoverPixels.regions(pageTexts: texts, window: window),
                                                   exclude: CoverPixels.coverElements(in: dump)))
        } else {
            take("pixels (B 1)", CheckResult(passed: false, lines: ["the screenshot could not be read or the window has no frame", "PIXELS NOT MEASURED"]))
        }
        // #36 S-A: every cover picture gets a -CONTRAST note of its own texts.
        textContrast(name, in: app, root: dump.coverRoot, screenshot: screenshot, dump: dump)
        var coverVerdict: String = "COVER OK"
        if !failures.isEmpty { coverVerdict = "COVER PROBLEM: " + failures.joined(separator: "; ") }
        lines.append(coverVerdict)
        note(name + "-COVER", lines.joined(separator: "\n"))
        // #36 8 T2/T3: the tree of every cover, so the next run's notes give the frames of any overlap and the page's
        // elements in the tree (the run of 20 Nov had no tree of 66, 94 or the Saved View cover).
        hierarchy(name, of: app)
        for failure in failures { XCTFail("\(name): \(failure)") }
    }

    /// R333: Settings > Online Lookup's Replace Key is ONE value row (no text or secure field drawn on the page), its value is
    /// empty or dots, never the key; Select opens the key's entry page, headed "Replace Key", with ONE secure field
    /// ("36-settings-online-lookup-key-entry"). "-KEY-ENTRY" note; a failure fails the test. Back returns to the page.
    func keyEntryRow(in app: XCUIApplication) {
        let name: String = "36-settings-online-lookup-key-entry"
        let row: XCUIElement = control(id: ControlID.keyEntry("tmdb"), label: "Replace Key", in: app)
        guard row.waitForExistence(timeout: 5) else {
            return notReached(name, "No Replace Key row (identifier \u{201C}\(ControlID.keyEntry("tmdb"))\u{201D}).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
        var failures: [String] = []
        // The Region field (an in-place system text field, not part of R333) is not counted: only a secure field or a field
        // labelled with "key".
        let keyFields: Int = app.textFields.matching(NSPredicate(format: "label CONTAINS[c] %@", "key")).count
        let drawnFields: Int = keyFields + app.secureTextFields.count
        if drawnFields > 0 { failures.append("\(drawnFields) key field(s) drawn on the page (a field inside a row, R333)") }
        // R364 (item 12): Done on the entry page saves the key, so the page has no Save Key button (Remove Key stays).
        if app.buttons.matching(NSPredicate(format: "label == %@", "Save Key")).firstMatch.exists {
            failures.append("a Save Key button is on the page (R364: Done on the entry page saves)")
        }
        let value: String = (row.value as? String) ?? ""
        if !value.allSatisfy({ $0 == "\u{2022}" }) && value != "Entered" { failures.append("the row value \u{201C}\(value)\u{201D} is not empty or dots") }
        var lines: [String] = ["row \u{201C}\(row.label)\u{201D} value \u{201C}\(value)\u{201D}", "key fields drawn on the page: \(drawnFields)"]
        if focus(row, in: app, maxPresses: 20) {
            XCUIRemote.shared.press(.select)
            let field: XCUIElement = app.descendants(matching: .any).matching(identifier: ControlID.entryField).firstMatch
            if field.waitForExistence(timeout: 10) {
                settle(); shot(name)
                let heading: Bool = app.staticTexts.matching(NSPredicate(format: "label == %@", "Replace Key")).firstMatch.exists
                lines.append("entry page heading \u{201C}Replace Key\u{201D}: " + (heading ? "shown" : "NOT SHOWN"))
                lines.append("secure fields: \(app.secureTextFields.count), text fields: \(app.textFields.count)")
                if !heading { failures.append("the entry page has no \u{201C}Replace Key\u{201D} heading") }
                if app.secureTextFields.count != 1 || app.textFields.count != 0 { failures.append("the entry page does not have exactly one secure field") }
                hierarchy(name, of: app)
                back()
            } else {
                notReached(name, "Select on Replace Key did not open its entry page.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
            }
        } else {
            notReached(name, "The Replace Key row could not be focused (focus on \(focusedLabel(in: app))).\n" + focusPathText())
        }
        note("36-settings-online-lookup-KEY-ENTRY", (lines + [failures.isEmpty ? "KEY ENTRY OK" : "FAILED: " + failures.joined(separator: "; ")]).joined(separator: "\n"))
        for failure in failures { XCTFail("\(name): \(failure)") }
    }

    /// R334: Online Lookup's Region is a system picker row, not a typed field: no text field labelled "Region" is drawn on the
    /// page, the row shows the country trailing (the fixtures keep the default, US), and Select opens the system's list of
    /// countries ("36-settings-online-lookup-region"). "-REGION" note; a failure fails the test. Back returns to the page.
    func regionPicker(in app: XCUIApplication) {
        let name: String = "36-settings-online-lookup-region"
        var failures: [String] = []
        let typed: Int = app.textFields.matching(NSPredicate(format: "label CONTAINS[c] %@", "region")).count
        if typed > 0 { failures.append("\(typed) text field(s) labelled Region drawn on the page (R334: a picker)") }
        let row: XCUIElement = control(id: ControlID.regionPicker, label: "Region", in: app)
        var lines: [String] = ["Region text fields drawn on the page: \(typed)"]
        if row.waitForExistence(timeout: 5), focus(row, in: app, maxPresses: 30) {
            let value: String = (row.value as? String) ?? ""
            lines.append("row \u{201C}\(row.label)\u{201D} value \u{201C}\(value)\u{201D}")
            // R353: the row shows the chosen country's name trailing (the fixtures keep the default, US).
            if !value.contains("United States") { failures.append("the Region row does not show \u{201C}United States\u{201D} (value \u{201C}\(value)\u{201D})") }
            XCUIRemote.shared.press(.select)
            if waitFor("Germany", in: app, timeout: 10) {
                settle(); shot(name)
                lines.append("the list of countries opened (\u{201C}Germany\u{201D} found)")
                hierarchy(name, of: app)
            } else {
                failures.append("Select on Region did not open a list of countries")
                notReached(name, "Select on Region did not open a list of countries.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
            }
            back()
        } else {
            notReached(name, "The Region row could not be focused (focus on \(focusedLabel(in: app))).\n" + focusPathText())
        }
        note("36-settings-online-lookup-REGION", (lines + [failures.isEmpty ? "REGION OK" : "FAILED: " + failures.joined(separator: "; ")]).joined(separator: "\n"))
        for failure in failures { XCTFail("\(name): \(failure)") }
    }

    /// R333: the Move to Shows cover has one value row per field (Show, Year, Season, Episode, Last Episode) and no text field
    /// drawn in a row; at the default size, Select on Show opens its entry page headed "Show" with ONE text field
    /// ("66-move-sheet-entry-show"). "-MOVE-ROWS" note; a failure fails the test. Back returns to the cover.
    func moveRows(in app: XCUIApplication, suffix: String) {
        let name: String = "66-move-sheet\(suffix)"
        var failures: [String] = []
        var lines: [String] = []
        for (raw, label) in [("title", "Show"), ("year", "Year"), ("season", "Season"), ("episode", "Episode"), ("episodeEnd", "Last Episode")] {
            let row: XCUIElement = control(id: ControlID.moveField(raw), label: label, in: app)
            let found: Bool = row.exists
            lines.append("row \u{201C}\(label)\u{201D}: " + (found ? "value \u{201C}\((row.value as? String) ?? "")\u{201D}" : "MISSING"))
            if !found { failures.append("no \u{201C}\(label)\u{201D} row") }
        }
        let drawnFields: Int = app.textFields.count + app.secureTextFields.count
        lines.append("fields drawn on the cover: \(drawnFields)")
        if drawnFields > 0 { failures.append("\(drawnFields) text field(s) drawn on the cover (a field inside a row, R333)") }
        if suffix.isEmpty {
            let row: XCUIElement = control(id: ControlID.moveField("title"), label: "Show", in: app)
            if row.exists, focus(row, in: app, maxPresses: 20) {
                XCUIRemote.shared.press(.select)
                let field: XCUIElement = app.descendants(matching: .any).matching(identifier: ControlID.entryField).firstMatch
                if field.waitForExistence(timeout: 10) {
                    settle(); shot("66-move-sheet-entry-show")
                    let heading: Bool = app.staticTexts.matching(NSPredicate(format: "label == %@", "Show")).firstMatch.exists
                    lines.append("entry page heading \u{201C}Show\u{201D}: " + (heading ? "shown" : "NOT SHOWN") + ", text fields: \(app.textFields.count)")
                    if !heading { failures.append("the Show entry page has no \u{201C}Show\u{201D} heading") }
                    if app.textFields.count != 1 { failures.append("the Show entry page does not have exactly one text field") }
                    hierarchy("66-move-sheet-entry-show", of: app)
                    back()
                } else {
                    notReached("66-move-sheet-entry-show", "Select on the Show row did not open its entry page.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
                }
            } else {
                notReached("66-move-sheet-entry-show", "The Show row could not be focused (focus on \(focusedLabel(in: app))).\n" + focusPathText())
            }
        }
        note(name + "-MOVE-ROWS", (lines + [failures.isEmpty ? "MOVE ROWS OK" : "FAILED: " + failures.joined(separator: "; ")]).joined(separator: "\n"))
        for failure in failures { XCTFail("\(name): \(failure)") }
    }

    /// #26 item 9: a source form never asks for an API key or token (the one app-wide key is in Settings > Online Lookup).
    /// Fails, with the fields found, when any text or secure field is labelled with "key" or "token".
    func checkNoKeyField(in app: XCUIApplication, name: String) {
        let fields = app.textFields.allElementsBoundByIndex + app.secureTextFields.allElementsBoundByIndex
        let labels = fields.map { [$0.label, $0.placeholderValue ?? "", $0.identifier].joined(separator: " | ") }
        let offending = labels.filter { $0.range(of: "key", options: .caseInsensitive) != nil || $0.range(of: "token", options: .caseInsensitive) != nil }
        // #29: typed steps instead of one expression with two ternaries and a `+` chain.
        var listed: [String] = labels
        if listed.isEmpty { listed = ["(no text fields)"] }
        var verdict = "NO KEY FIELD OK"
        if !offending.isEmpty { verdict = "KEY FIELD FOUND: \(offending.joined(separator: "; "))" }
        let text: String = listed.joined(separator: "\n") + "\n" + verdict
        note(name + "-FIELDS", text)
        XCTAssertTrue(offending.isEmpty, "\(name): a source form asks for a key: \(offending)")
    }

    // MARK: Library screens with the sample library

    func test04_LibraryScreens() {
        var app = launch("-UITestFixtures", tab: "home")
        if waitForScreen("screen.home", in: app), waitFor("Sample", in: app, timeout: 60) { settle(); shot("50-home-rows"); homeFeaturedCheck("50-home-rows", in: app); sidebarLaunchCheck("50-home-launch", in: app); XCUIRemote.shared.press(.down); sleep(1); shot("51-home-rows-lower") }
        else { notReached("50-home-rows", "No sample title appeared on Home within 60 s (the sample library did not load).") }
        // The card long-press menu on the focused Home card. #25 A3: the focus starts on the tab bar, so move it into the
        // content first, and wait for the menu's items before the picture.
        // R388 follow-up (item 13): onto a card whatever has the focus now (the featured Play at launch, a card after the
        // Down above); never a long press on Play.
        if focusFirstHomeCard(in: app) {
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            if waitForAny(["Mark as Watched", "Mark as Unwatched"], in: app) != nil { sleep(1); shot("52-card-long-press-menu") }
            else { notReached("52-card-long-press-menu", "The long-press menu did not open (no “Mark as Watched/Unwatched” item; focus on \(focusedLabel(in: app))).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))") }
        } else { notReached("52-card-long-press-menu", "The focus could not be moved to a card of the first shelf (focus on \(focusedLabel(in: app))).") }
        app.terminate()

        // #36 group 1 d (R264): Sample Movie 7 (the long title, 20 % watched) is in Continue Watching; its wide card is focused,
        // and two pictures 3 s apart must be identical with the caption whole (no moving text, nothing cut).
        app = launch("-UITestFixtures", tab: "home")
        if waitForScreen("screen.home", in: app), waitFor("Sample", in: app, timeout: 60), focusContent(in: app),
           focus(control("Sample Movie 7", in: app), in: app) {
            let focusedFrame: CGRect = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.frame
            let isWide: Bool = focusedFrame.width > focusedFrame.height
            let firstLine: String = "focused \(focusedLabel(in: app)) frame \(focusedFrame) wide \(isWide)"
            note("50-home-continue-watching-caption-FOCUS", firstLine)
            if isWide {
                // #36 8 T4: Sample Movie 7 is the long title; the focus is asserted before the wait and written to the
                // -FOCUS note.
                laterPictures("50-home-continue-watching-caption", expected: "Sample Movie 7", caption: "Sample Movie 7",
                              step: "3 s of focus on the Continue Watching card of Sample Movie 7",
                              in: app, firstLine: firstLine)
            } else {
                notReached("50-home-continue-watching-caption", "The focused Sample Movie 7 card is not the wide Continue Watching card (frame \(focusedFrame)).")
            }
        } else {
            notReached("50-home-continue-watching-caption", "Could not move the focus to the Continue Watching card of Sample Movie 7 (focus on \(focusedLabel(in: app))).")
        }
        app.terminate()

        for (n, tab) in [("53", "movies"), ("54", "shows")] {
            app = launch("-UITestFixtures", tab: tab)
            if waitForScreen("screen.\(tab)", in: app), waitFor("Sample", in: app, timeout: 60) {
                settle(); shot("\(n)-\(tab)")
                lockupCheck("\(n)-\(tab)-focused", in: app)
            } else { notReached("\(n)-\(tab)", "No sample title appeared.") }
            app.terminate()
        }

        app = launch("-UITestFixtures", open: "Sample Show 1")
        if waitForScreen("screen.series", in: app, timeout: 60), waitFor("Season 1", in: app, timeout: 20) {
            settle(); shot("55-show-page")
            let showTop: String = focusedLabel(in: app)
            productPageCheck("55-show-page", information: false, in: app)
            badgesNotCutCheck("55-show-page", expectBadges: false, rating: "TV-14", in: app)
            // R336: the show page's backdrop, as on the movie page ("55-show-page-CONTRAST", a note).
            textContrast("55-show-page", in: app)
            // #33 E: every episode card the same size (55 of the run of 20 Nov: S2 E3 378 x 566 beside 410 x 615).
            let pageTree: String = app.debugDescription
            note("55-show-page-HIERARCHY", pageTree)
            let cards: CheckResult = ScreenRules.equalEpisodeCards(in: AccessibilityDump(pageTree))
            note("55-show-page-CARDS", cards.text)
            XCTAssertTrue(cards.passed, "55-show-page: " + cards.verdict)
            checkGap("55-show-page", tree: pageTree, anchors: [ControlID.play, ControlID.more], kinds: ["StaticText"], minimum: 40, what: "buttons to the first season heading")
            // R339 (docs/HIG_AUDIT.md T10): the season tabs, and the episodes of ONE season under them.
            seasonTabsCheck("55-show-page", in: app)
            // #15 item 1.6: the scrolled states of the show page (each must differ from the one before).
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); let mustChange: String? = step == 1 ? "Down on the show page" : nil; shot("55-show-page-scrolled-\(step)", mustChangeAfter: mustChange, endOfScroll: step == 1 ? nil : "Down on the show page") }
            for _ in 0..<2 { XCUIRemote.shared.press(.up) }; sleep(1)
            // R339: seasons are tabs above one episode list. Focus on the Season 2 tab selects it (HIG Segmented controls, tvOS);
            // then the list holds season 2's episodes only.
            let seasonTwo: XCUIElement = app.segmentedControls[ControlID.seasonTabs].buttons["Season 2"]
            if focus(seasonTwo.exists ? seasonTwo : control("Season 2", in: app), in: app), waitFor("S2, E1", in: app, timeout: 10) {
                settle(); seasonTabsCheck("56-show-season-2-tab", in: app)
                if focus(control("S2, E1", in: app), in: app) { settle(); shot("56-show-season-2-episode-row", endOfScroll: "moving the focus to the season 2 row") }
                else { notReached("56-show-season-2-episode-row", "Could not move the focus to a season 2 episode (focus on \(focusedLabel(in: app))).") }
            } else { notReached("56-show-season-2-episode-row", "The Season 2 tab did not show season 2's episodes (focus on \(focusedLabel(in: app))).") }
            // #30 Part 2 / #36 group 4 (R264): S2 E3 has the longest caption. It wraps at the readable floor instead of being
            // cut; the two pictures 3 s apart must be identical with the caption whole (default text size).
            if focus(control("S2, E3", in: app), in: app) || focus(control("S2, E3, A very long episode title that is wider than any episode card on the show page", in: app), in: app) {
                // #36 8 T4: S2 E3 is the long title; the focus is asserted before the wait and written to the -FOCUS note.
                laterPictures("56-show-long-episode-caption", expected: "S2, E3", caption: "A very long episode title",
                              step: "3 s of focus on S2 E3", in: app,
                              firstLine: "focused \(focusedLabel(in: app)) after moving to S2 E3")
            } else {
                notReached("56-show-long-episode-caption", "Could not move the focus to S2 E3 (focus on \(focusedLabel(in: app))).")
            }
            // R346 (item A): Up from the bottom of the show page reaches its first control before the tab bar.
            scrollUpCheck("56-show-page", top: showTop, in: app)
        } else { hierarchy("55-show-page", of: app); notReached("55-show-page", "The show page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 1", in: app) {
            settle(); shot("57-movie-detail")
            let movieTop: String = focusedLabel(in: app)
            productPageCheck("57-movie-detail", information: true, in: app)
            badgesNotCutCheck("57-movie-detail", expectBadges: true, rating: "PG-13", in: app)
            let movieTree: String = app.debugDescription
            note("57-movie-detail-HIERARCHY", movieTree)
            checkGap("57-movie-detail", tree: movieTree, anchors: [ControlID.play, ControlID.more], kinds: ["StaticText"], minimum: 40, what: "buttons to the next heading")
            focusCheck("57-movie-detail", expected: ControlID.play, in: app)
            // R336 (docs/HIG_AUDIT.md T6): the backdrop is at full strength under the system material; every text's
            // contrast against it in "57-movie-detail-CONTRAST" (a note, not a failure; targets PROVISIONAL, R240).
            textContrast("57-movie-detail", in: app)
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); let mustChange: String? = step == 1 ? "Down on the movie page" : nil; shot("58-movie-detail-scrolled-\(step)", mustChangeAfter: mustChange, endOfScroll: step == 1 ? nil : "Down on the movie page") }
            // R346 (item A): Up from the bottom of the movie page reaches Play before the tab bar.
            scrollUpCheck("58-movie-detail", top: movieTop, in: app)
            // Fix Match is in the More menu (ItemDetailContentView.moreMenu), not a button on the page: the old test looked for
            // it on the page and never found it (#15 item 1.3). Up to the action row first: the focus is below it after 58.
            for _ in 0..<6 { XCUIRemote.shared.press(.up) }; sleep(1)
            rememberPage(app)
            if open("More", id: ControlID.more, in: app, name: "59-fix-match"), waitForAny(["Fix Match"], in: app) != nil,
               open("Fix Match", in: app, name: "59-fix-match") {
                settle(); shot("59-fix-match"); checkCover("59-fix-match", in: app); back()
            }
        } else { hierarchy("57-movie-detail", of: app); notReached("57-movie-detail", "The movie detail page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 2")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 2", in: app) {
            settle(); shot("60-movie-detail-two-versions")
            focusCheck("60-movie-detail-two-versions", expected: ControlID.play, in: app)
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("61-movie-detail-two-versions-scrolled-\(step)", endOfScroll: step == 1 ? nil : "Down on the movie page") }
        } else { notReached("60-movie-detail-two-versions", "The detail page did not open.") }
        app.terminate()

        detailActionShots()

        // Pressing Play on a sample file shows the playback error screen (sample files have no video).
        app = launch("-UITestFixtures", open: "Sample Movie 5")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 5", in: app), open("Play", id: ControlID.play, in: app, name: "62-playback-error") {
            sleep(5); shot("62-playback-error")
        }
        app.terminate()
    }

    /// The movie page's actions (#15 item 1.6), numbers 44 to 49 (free in the main set). Each from a fresh launch, so one
    /// action's result (watched, favourite) cannot change what the next one shows.
    /// Sample Movie 1: started 40 % (so Start Over shows), one subtitle file (so Extras shows), not watched, not a favourite.
    /// Sample Movie 2: two versions.
    func detailActionShots() {
        func openMovie(_ title: String, _ name: String) -> XCUIApplication? {
            let app = launch("-UITestFixtures", open: title)
            guard waitForScreen("screen.item", in: app, timeout: 60), waitFor(title, in: app) else {
                notReached(name, "The page of \(title) did not open."); app.terminate(); return nil
            }
            settle()
            return app
        }

        // 44: the More menu open; 45: after Mark as Watched, More again (it must now offer Mark as Unwatched);
        // 46: after Add to Favorites, More again (it must now offer Remove from Favorites).
        if let app = openMovie("Sample Movie 1", "44-movie-more-menu") {
            if open("More", id: ControlID.more, in: app, name: "44-movie-more-menu"), waitForAny(["Mark as Watched"], in: app) != nil {
                sleep(1); shot("44-movie-more-menu")
                if open("Mark as Watched", in: app, name: "45-movie-mark-watched-result") {
                    sleep(2)
                    if open("More", id: ControlID.more, in: app, name: "45-movie-mark-watched-result"), waitForAny(["Mark as Unwatched"], in: app) != nil {
                        sleep(1); shot("45-movie-mark-watched-result")
                    } else { notReached("45-movie-mark-watched-result", "After Mark as Watched, More did not offer “Mark as Unwatched”.") }
                    if open("Add to Favorites", in: app, name: "46-movie-add-favorite-result") {
                        sleep(2)
                        if open("More", id: ControlID.more, in: app, name: "46-movie-add-favorite-result"), waitForAny(["Remove from Favorites"], in: app) != nil {
                            sleep(1); shot("46-movie-add-favorite-result")
                        } else { notReached("46-movie-add-favorite-result", "After Add to Favorites, More did not offer “Remove from Favorites”.") }
                    }
                }
            }
            app.terminate()
        }

        // 47: the Versions menu open (two versions).
        if let app = openMovie("Sample Movie 2", "47-movie-versions-menu") {
            if open("Versions", id: ControlID.versions, in: app, name: "47-movie-versions-menu") {
                // The menu lists the two versions by their names (2160p and 1080p in the sample library).
                if waitForAny(["2160p", "1080p"], in: app) == nil { print("47: no version item seen before the picture") }
                sleep(1); shot("47-movie-versions-menu")
            }
            app.terminate()
        }

        // 48 (#33 J): Sample Movie 1 has only subtitle files and pictures beside it, which are not extras, so the page has no
        // Extras button. Before #33 this picture showed the menu listing the two subtitle files.
        if let app = openMovie("Sample Movie 1", "48-movie-extras") {
            sleep(1)
            XCTAssertFalse(app.buttons[ControlID.extras].exists, "48: an Extras button is shown for a movie with only subtitles and pictures")
            shot("48-movie-extras")
            app.terminate()
        }

        // 49: Start Over focused, then what selecting it shows (sample files have no video: the playback error).
        if let app = openMovie("Sample Movie 1", "49-movie-start-over") {
            if focus(control(id: ControlID.startOver, label: "Start Over", in: app), in: app) {
                sleep(1); shot("49-movie-start-over")
                XCUIRemote.shared.press(.select); sleep(5); shot("49-movie-start-over-result")
            } else { notReached("49-movie-start-over", "No “Start Over” button could be focused (focus on \(focusedLabel(in: app))).") }
            app.terminate()
        }
    }

    /// #21 E: the player, with the debug-only generated clip that stands in for Sample Show 1 S01E01 in fixture mode
    /// (App `UITestClip`: 40 s of coloured frames, two silent audio tracks and two subtitle tracks, English and French; an
    /// intro marker at 2 to 20 s from the sample's .segments.json). Numbers 22 to 27 (11 to 19 are the Add a Source forms). Job 4. HDR, Dolby Vision and Atmos
    /// cannot be shown this way and stay on the device checklist. Every step records "not reached" instead of failing.
    func test12_PlayerWithSampleClip() {
        let app = launch("-UITestFixtures", open: "Sample Show 1")
        guard waitForScreen("screen.series", in: app, timeout: 60), waitFor("Season 1", in: app, timeout: 20) else {
            notReached("22-player-skip-intro", "The show page did not open."); app.terminate(); return
        }
        checkResponsive("test12-show-page-responsive", text: "Season 1", in: app)
        // #36 8 T5: the S1 E1 card by its full spoken label (the button's label is "S1, E1, A quiet beginning" since R358), so no other
        // control can match; the focus is checked on that card before Select, and the path goes into the note.
        let episodeLabel: String = "S1, E1, A quiet beginning"
        // R339: one season's episodes under the season tabs; S1 E1 is under Season 1 (focus selects a tab).
        if !app.buttons[episodeLabel].exists {
            let seasonOne: XCUIElement = app.segmentedControls[ControlID.seasonTabs].buttons["Season 1"]
            _ = focus(seasonOne.exists ? seasonOne : control("Season 1", in: app), in: app); sleep(1)
        }
        guard open(episodeLabel, in: app, name: "22-player-skip-intro"), waitForScreen("screen.item", in: app, timeout: 20) else {
            notReached("22-player-skip-intro", "The S01E01 page did not open (focus on \(focusedLabel(in: app))).\n" + focusPathText())
            app.terminate(); return
        }
        settle()
        // Item 7 of the owner's review of the run on fd9731f: the run had no picture of the episode page. The first
        // screen, the check, then the page scrolled once (Down from Play), and back up to Play.
        shot("22-episode-page")
        episodePageCheck("22-episode-page", code: "S1, E1", title: "A quiet beginning", season: "Season 1", in: app)
        XCUIRemote.shared.press(.down); sleep(1); shot("22-episode-page-scrolled-1")
        XCUIRemote.shared.press(.up); sleep(1)
        // S01E01 is watched in the sample library, so its button says "Play Again" ("Play" matches it).
        guard open("Play", id: ControlID.play, in: app, name: "22-player-skip-intro") else { app.terminate(); return }
        // The clip is written on first use (a few seconds), then plays; Skip Intro shows from 2 s to 20 s.
        if waitFor("Skip Intro", in: app, timeout: 30) { sleep(1); shot("22-player-skip-intro") }
        else {
            shot("22-player-skip-intro-missing")
            notReached("22-player-skip-intro", "No “Skip Intro” within 30 s of Play. " + playerStartOutcome(in: app))
        }

        // The transport bar and controls: one press of Play/Pause pauses and shows them.
        XCUIRemote.shared.press(.playPause); sleep(2); shot("23-player-controls")
        episodeCodeCheck("23-player-controls", in: app)
        // The info panel: down from the transport bar.
        XCUIRemote.shared.press(.down); sleep(2); shot("24-player-info-panel")
        episodeCodeCheck("24-player-info-panel", in: app)
        // R340 (docs/HIG_AUDIT.md T15 to T17): the app's content tabs in the info panel, Episodes and Playback Stats
        // (`customInfoViewControllers`). Notes, not failures: how tvOS 27 exposes the tab titles is not on any Apple page read.
        // R368 (compile run of 21 Nov 2026, item 9(c)): run 8's picture 24-player-info-panel DRAWS the three tabs (Info,
        // Episodes, Playback Stats), but no element with those labels was in the tree ("NOT FOUND"), so the by-label focus
        // could not reach them and the focus stayed in the Info content ("Play, From Beginning"). The tabs are the system
        // player's own row: they are reached the way a person does, Up from the panel's content onto the tab row, then Right
        // once per tab. The note records the focused label after each press, and the panel's tree for the next fix.
        hierarchy("24-player-info-panel", of: app)
        let tabNames: [String] = ["Episodes", "Playback Stats"]
        var tabLines: [String] = tabNames.map { "\($0) in the tree: " + (waitFor($0, in: app, timeout: 3) ? "found" : "NOT FOUND") }
        XCUIRemote.shared.press(.up); sleep(1)
        tabLines.append("after Up: focus on \(focusedLabel(in: app))")
        for (picture, tab) in [("24-player-episodes-tab", "Episodes"), ("24-player-stats-tab", "Playback Stats")] {
            XCUIRemote.shared.press(.right); sleep(2)
            let now: String = focusedLabel(in: app)
            tabLines.append("after Right toward \u{201C}\(tab)\u{201D}: focus on \(now)")
            shot(picture)
        }
        note("24-player-info-panel-TABS", tabLines.joined(separator: "\n"))
        // R368, item 9(d): where test12 stops (run 8 took no 25, 26 or 27 picture and left no note saying why).
        note("test12-progress", "24 done; next 25-player-audio-menu")
        // Back up to the transport bar (the info panel closes).
        for _ in 0..<2 { XCUIRemote.shared.press(.up); sleep(1) }
        // The audio and subtitle menus of the system player (two tracks each, English and French).
        for (number, label) in [("25-player-audio-menu", "Audio"), ("26-player-subtitles-menu", "Subtitles")] {
            // #25 A3: the system player's own menus carry no identifier we can set; by label. The picture waits for the
            // menu's items (the two tracks), so it shows the menu open.
            if open(label, in: app, name: number) {
                if waitForAny(["English", "French", "Off"], in: app) == nil { print("\(number): no track item seen before the picture") }
                sleep(1); shot(number); XCUIRemote.shared.press(.menu); sleep(1)
            }
            else { shot(number + "-missing") }
        }

        note("test12-progress", "24, 25 and 26 done; next 27-player-next-episode")
        // Next Episode: play on to the end of the clip; the Up Next card names Sample Show 1 S01E02 ("The long way round").
        XCUIRemote.shared.press(.playPause)
        if waitFor("The long way round", in: app, timeout: 60) {
            sleep(1); shot("27-player-next-episode")
            // R340 (docs/HIG_AUDIT.md T19): the system Up Next card (`UpNextProposalController`); Play Now starts S01E02. Before
            // R340 the accept was dropped and nothing started. The note says what followed (the sample library has no clip for
            // S01E02, so a "cannot play" alert over the show page also shows that the advance ran).
            if open("Play Now", id: ControlID.upNextPlayNow, in: app, name: "27-player-after-play-now") {
                sleep(5); shot("27-player-after-play-now")
                let alert: XCUIElement = app.alerts.firstMatch
                note("27-player-after-play-now-ADVANCE", "alert: " + (alert.exists ? alert.label : "none")
                     + "\nUp Next still up: \(app.buttons[ControlID.upNextPlayNow].exists)\nfocus: \(focusedLabel(in: app))")
            }
        }
        else { shot("27-player-next-episode-missing"); notReached("27-player-next-episode", "No Up Next card for S01E02 by the end of the clip.") }
        app.terminate()
    }

    /// #21 D: the movie page with a synopsis and cast from the debug-only fake details (`UITestFixtureDetails`, no network).
    /// 57/58 (Sample Movie 1, short synopsis and cast) and 60/61 (Sample Movie 2, a full cast shelf) already show them; this
    /// adds the very long synopsis with its whole-text page (77) and the page with neither (78). Job 4b.
    /// #22 B: the same two cases on the show page (77-show-..., Sample Show 1; 78-show-..., Sample Show 2).
    func test13_MovieSynopsisAndCast() {
        var app = launch("-UITestFixtures", open: "Sample Movie 4")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 4", in: app), waitFor("Sample synopsis", in: app, timeout: 10) {
            settle(); shot("77-movie-long-synopsis")
            if open("Sample synopsis", in: app, name: "77-movie-long-synopsis-page") { settle(); shot("77-movie-long-synopsis-page"); synopsisHeadingCheck("77-movie-long-synopsis-page", title: "Sample Movie 4", in: app); back() }
            for _ in 0..<4 { XCUIRemote.shared.press(.down) }; sleep(1); shot("77-movie-long-synopsis-cast")
            // R341 (docs/HIG_AUDIT.md T8): Select on a cast entry opens that person's page, the library's titles with them in
            // the same poster grid. Sample Actor 1 is in Sample Movie 1 to 5 and Sample Show 1 (UITestFixtureDetails).
            let actor: XCUIElement = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample Actor 1,")).firstMatch
            if focus(actor.exists ? actor : control("Sample Actor 1", in: app), in: app) {
                XCUIRemote.shared.press(.select)
                if waitForScreen("screen.person", in: app, timeout: 20), waitFor("Sample Movie 5", in: app, timeout: 20) {
                    settle(); shot("79-person-page")
                    personPageCheck("79-person-page", in: app)
                } else { hierarchy("79-person-page", of: app); notReached("79-person-page", "Select on Sample Actor 1 did not open the person page.") }
            } else { notReached("79-person-page", "Could not move the focus to Sample Actor 1 (focus on \(focusedLabel(in: app))).") }
        } else { hierarchy("77-movie-long-synopsis", of: app); notReached("77-movie-long-synopsis", "The page or its fake synopsis did not appear.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 6")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 6", in: app) {
            settle(); shot("78-movie-no-synopsis-or-cast")
            checkContrast("78-movie-no-synopsis-or-cast", prefixes: ["Resolution", "Frame Rate", "Bitrate"], in: app)
            focusCheck("78-movie-no-synopsis-or-cast", expected: ControlID.play, in: app)
        } else { notReached("78-movie-no-synopsis-or-cast", "The page did not open.") }
        app.terminate()

        // #22 B: the show page gets the same synopsis and cast. Sample Show 1 has the very long synopsis and a cast; Sample
        // Show 2 has neither, so its page must show no empty band. The test keeps its name (the workflow selects it by name).
        app = launch("-UITestFixtures", open: "Sample Show 1")
        if waitForScreen("screen.series", in: app, timeout: 60), waitFor("Season 1", in: app, timeout: 20), waitFor("Sample synopsis", in: app, timeout: 10) {
            checkResponsive("test13-show-page-responsive", text: "Season 1", in: app)
            settle(); shot("77-show-long-synopsis")
            if open("Sample synopsis", in: app, name: "77-show-long-synopsis-page") { settle(); shot("77-show-long-synopsis-page"); synopsisHeadingCheck("77-show-long-synopsis-page", title: "Sample Show 1", in: app); back() }
            // #25 B7: the cast is after the episode shelves now; Down until the focus stops reaches it (the last shelf).
            _ = moveFocusToEnd(in: app, maxPresses: 12); sleep(1); shot("77-show-long-synopsis-cast")
        } else { hierarchy("77-show-long-synopsis", of: app); notReached("77-show-long-synopsis", "The show page or its fake synopsis did not appear.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Show 2")
        if waitForScreen("screen.series", in: app, timeout: 60), waitFor("Season 1", in: app, timeout: 20) {
            settle(); shot("78-show-no-synopsis-or-cast")
        } else { notReached("78-show-no-synopsis-or-cast", "The show page did not open.") }
        app.terminate()
    }

    /// #33 K (OPEN_QUESTIONS R240): the contrast of the texts whose labels start with `prefixes`, measured on a fresh
    /// screenshot by ScreenChecks `Contrast` (method and limits in its header). Writes "<name>-CONTRAST" with one line per
    /// text. It never fails the test: the 4.5:1 target is PROVISIONAL, and the HIG table gives 3:1 for text of 18 pt and up.
    func checkContrast(_ name: String, prefixes: [String], in app: XCUIApplication) {
        guard let image = RGBImage(screenshot: XCUIScreen.main.screenshot()) else { return note(name + "-CONTRAST", "The screenshot could not be read.") }
        let scale: Double = Double(image.width) / max(1, Double(app.windows.firstMatch.frame.width))
        var lines: [String] = ["scale \(scale); target 4.5:1 PROVISIONAL (R240); HIG table: 3:1 at 18 pt and up"]
        for prefix in prefixes {
            let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            guard text.exists, let m = Contrast.measure(image, frame: AXRect(text.frame), scale: scale) else {
                lines.append("“\(prefix)…”: not found"); continue
            }
            var line: String = "“\(prefix)…” \(AXRect(text.frame)): \(m)"
            if m.ratio < 4.5 { line += " BELOW 4.5" }
            lines.append(line)
        }
        note(name + "-CONTRAST", lines.joined(separator: "\n"))
    }

    /// #36 S-A and T6 (OPEN_QUESTIONS R253, PROVISIONAL): "<name>-CONTRAST" for a whole screen: every text under `root` (a
    /// cover's root; the page's when nil) by `ScreenRules.coverContrast`, the title against 7:1 and every other text against
    /// 4.5:1. A note and a printed warning, never a test failure (the targets are PROVISIONAL, as R240).
    func textContrast(_ name: String, in app: XCUIApplication, root: Int? = nil, screenshot: XCUIScreenshot? = nil,
                      dump: AccessibilityDump? = nil) {
        let picture: XCUIScreenshot = screenshot ?? XCUIScreen.main.screenshot()
        let tree: AccessibilityDump = dump ?? AccessibilityDump(app.debugDescription)
        guard let image = RGBImage(screenshot: picture), let windowIndex = tree.window,
              let window = tree.nodes[windowIndex].frame, window.width > 0,
              let start = root ?? tree.pageRoot else {
            return note(name + "-CONTRAST", "The screenshot or the accessibility tree could not be read.\nCONTRAST NOT MEASURED")
        }
        let scale: Double = Double(image.width) / window.width
        let result: CheckResult = ScreenRules.coverContrast(image, scale: scale, in: tree, root: start)
        note(name + "-CONTRAST", result.text)
        if !result.passed { print("WARNING: \(name): " + (result.lines.last ?? "")) }
    }

    /// #33 F (2): the same measure as test15 inside test12 and test13, the two tests that hung in part 1 of the run of 20 Nov
    /// (test12 "main thread busy" while waiting for screen.series, test13 "Timed out while evaluating UI query" on Sample Show
    /// 1) while test15 and test04 passed on the same page in part 2. Three cheap queries (a StaticText by label), Down and Up
    /// between them; each query over 5 s fails the test and the note "<name>" has the times. The cause is NOT known; this
    /// only says where and how long, and the hang sample of scripts/ci-ui-tests.sh says what the main thread was doing.
    func checkResponsive(_ name: String, text: String, in app: XCUIApplication) {
        var lines: [String] = []
        var worst: TimeInterval = 0
        for move in [nil, XCUIRemote.Button.down, XCUIRemote.Button.up] as [XCUIRemote.Button?] {
            if let move { XCUIRemote.shared.press(move) }
            let start: Date = Date()
            let found: Bool = app.staticTexts[text].exists
            let took: TimeInterval = Date().timeIntervalSince(start)
            worst = max(worst, took)
            var pressed: String = "no press"
            if let move { pressed = String(describing: move) }
            let seconds: String = String(format: "%.2f", took)
            lines.append("query after \(pressed): \(seconds) s, “\(text)” found: \(found)")
            sleep(1)
        }
        var busyVerdict: String = "RESPONSIVE OK"
        if worst > 5 { busyVerdict = "MAIN THREAD BUSY" }
        let worstText: String = String(format: "%.2f", worst)
        lines.append("worst \(worstText) s, limit 5 s: " + busyVerdict)
        note(name, lines.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(worst, 5, "\(name): a query waited \(String(format: "%.1f", worst)) s for the app's main thread (limit 5 s).")
    }

    /// #31 (OPEN_QUESTIONS R231): the show page of Sample Show 1 must leave the main thread free. In the run of 20 Nov test04
    /// stopped there: the page was drawn, then nothing changed for 30 s and XCTest reported "main thread busy for 30.0s".
    /// Every query below needs the app's main run loop; a query that takes longer than 5 s fails the test, and so does a
    /// page that does not open. The focus is moved down and up between the queries, as test04 does for 55. Writes the times
    /// to "show-page-responsive" (no pictures).
    func test15_ShowPageResponsive() {
        let app = launch("-UITestFixtures", open: "Sample Show 1")
        guard waitForScreen("screen.series", in: app, timeout: 60) else {
            note("show-page-responsive", "The show page did not open within 60 s (or the app was busy).")
            XCTFail("The show page of Sample Show 1 did not open within 60 s.")
            return
        }
        let limit: TimeInterval = 5
        var worst: TimeInterval = 0
        var lines: [String] = []
        let moves: [XCUIRemote.Button?] = [nil, nil, .down, .down, .up, .up, nil]
        for (round, move) in moves.enumerated() {
            if let move { XCUIRemote.shared.press(move) }
            let start: Date = Date()
            let found: Bool = app.staticTexts["Season 1"].exists
            let took: TimeInterval = Date().timeIntervalSince(start)
            if took > worst { worst = took }
            lines.append("query \(round + 1): \(String(format: "%.2f", took)) s, Season 1 found: \(found)")
            sleep(1)
        }
        var verdict: String = "RESPONSIVE OK"
        if worst > limit { verdict = "MAIN THREAD BUSY" }
        lines.append("worst \(String(format: "%.2f", worst)) s, limit \(Int(limit)) s: \(verdict)")
        note("show-page-responsive", lines.joined(separator: "\n"))
        XCTAssertLessThanOrEqual(worst, limit, "The show page kept the main thread busy for \(String(format: "%.1f", worst)) s (limit 5 s).")
        app.terminate()
    }

    // MARK: Library toolbars and menus (#32)

    /// #32 F: the Movies and Shows toolbars and each of their menus, at the default size and at Larger Text, with checks that
    /// FAIL the test when the toolbar is wrong or a menu is wrong (OPEN_QUESTIONS R233 to R236, R375):
    /// - `checkToolbarGroups` (R375; was #33 G's gap ratio of our own row): the system toolbar's controls (Sort and Filter,
    ///   Saved Views, More) are all there, on one line, whole inside the window, not overlapping, above the first card row;
    ///   their spacing is the system's and is only recorded (`ScreenRules.systemToolbar`);
    /// - `checkMenu`: an open menu with fewer than three items, or an item that ends below the window (a menu cut at the
    ///   bottom); for the Filter menu also each group submenu.
    /// Moved here from test14 (part 1, the job the time budget stopped) into part 2 (R232). Files has no toolbar (its folders
    /// list by name, no sort or filter), so it has no pictures here.
    func test16_LibraryToolbars() {
        for (tab, prefix) in [("shows", "07-shows-toolbar"), ("movies", "07-movies-toolbar")] {
            toolbarShots(tab: tab, prefix: prefix, suffix: "", extra: [])
            toolbarShots(tab: tab, prefix: prefix, suffix: "-larger-text", extra: ["-UITestTextSize", "accessibility3"])
        }
    }

    /// One toolbar and its menus: "<prefix><suffix>", then "<prefix>-sort-filter-menu<suffix>" (R344), "-sort-submenu",
    /// "-filter-submenu" (the Resolution group open) and "-saved-views-menu" (with no saved view: what the Save View button opens).
    func toolbarShots(tab: String, prefix: String, suffix: String, extra: [String]) {
        let app = launch("-UITestFixtures", tab: tab, extra: extra)
        guard waitForScreen("screen.\(tab)", in: app), waitFor("Sample", in: app, timeout: 60) else {
            notReached(prefix + suffix, "No sample title appeared on the \(tab) screen."); app.terminate(); return
        }
        settle(); shot(prefix + suffix)
        checkToolbarGroups(prefix + suffix, in: app)
        checkGap(prefix + suffix, tree: app.debugDescription, anchors: Array(Self.toolbarControlIDs), kinds: ["Button", "Cell"], minimum: 60, what: "toolbar to the first card row")
        // What is on screen with every menu closed: a menu's items are what appears on top of it.
        let closed: Set<String> = Set(controlLabels(in: app).map { $0.0 })
        // R344 (docs/HIG_AUDIT.md T5): one Sort and Filter menu: "Sort By (…)", the four filter groups and Clear All Filters
        // on its first level; the sort pickers and each group's toggles in submenus.
        if openToolbarControl("Sort and Filter", id: ControlID.sortAndFilter, in: app, name: prefix + "-sort-filter-menu" + suffix) {
            sleep(1); shot(prefix + "-sort-filter-menu" + suffix)
            checkMenu(prefix + "-sort-filter-menu" + suffix, expected: ["Sort By", "Watched", "Resolution", "Dynamic Range", "Sound", "Clear All Filters"], before: closed, in: app)
            let menuOpen: Set<String> = Set(controlLabels(in: app).map { $0.0 })
            if open("Sort By", in: app, name: prefix + "-sort-submenu" + suffix) {
                sleep(1); shot(prefix + "-sort-submenu" + suffix)
                checkMenu(prefix + "-sort-submenu" + suffix, expected: ["Title", "Year", "Date Added"], before: menuOpen, in: app)
                back()
            }
            if open("Resolution", in: app, name: prefix + "-filter-submenu" + suffix) {
                sleep(1); shot(prefix + "-filter-submenu" + suffix)
                checkMenu(prefix + "-filter-submenu" + suffix, expected: [], before: menuOpen, in: app)
                back()
            }
            back(); _ = focusContent(in: app)
        }
        // With no saved view this is the Save View button (R236): the picture shows the page it opens.
        rememberPage(app)
        if openToolbarControl("Save View", id: ControlID.savedViews, in: app, name: prefix + "-saved-views-menu" + suffix) {
            sleep(1); shot(prefix + "-saved-views-menu" + suffix); checkCover(prefix + "-saved-views-menu" + suffix, in: app)
            back()
        }
        app.terminate()
    }

    /// R375: the system toolbar (`ScreenRules.systemToolbar`). Writes "<name>-GROUPS" (the note's old name, so the run's
    /// notes stay comparable) with every control's frame, the system's gaps (recorded, not judged) and the verdict.
    /// History: #32 F / #33 G / #36 6 judged our own row's gaps (ratio 2) and equal sizes (`ScreenRules.toolbarGroups`).
    func checkToolbarGroups(_ name: String, in app: XCUIApplication) {
        let bar: [(String, String)] = [("Sort and Filter", ControlID.sortAndFilter), ("Saved Views", ControlID.savedViews), ("More", ControlID.moreControls)]
        let items: [(String, AXRect)] = bar.compactMap { (label: String, id: String) -> (String, AXRect)? in
            let element: XCUIElement = app.descendants(matching: .any).matching(identifier: id).firstMatch
            guard element.exists, !element.frame.isEmpty else { return nil }
            return (label, AXRect(element.frame))
        }.sorted { (a: (String, AXRect), b: (String, AXRect)) -> Bool in a.1.x < b.1.x }
        let card: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Sample")).firstMatch
        let window: CGRect = app.windows.firstMatch.frame
        let result: CheckResult = ScreenRules.systemToolbar(items: items, expected: bar.map { $0.0 },
                                                            window: AXRect(window), firstContentY: card.exists ? Double(card.frame.minY) : nil)
        // R391 (shared fault 3): the three controls are the same size (`ScreenRules.equalSizes`; the run on fd9731f
        // measured 108 x 66, 98 x 81 and 100 x 63). A focused control may be drawn larger, so the one with the focus is
        // left out of the comparison.
        let focusedElement: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        let focusedID: String = focusedElement.exists ? focusedElement.identifier : ""
        let focusedName: String? = bar.first { (pair: (String, String)) -> Bool in pair.1 == focusedID }?.0
        let sizes: CheckResult = ScreenRules.equalSizes(items: items.filter { (item: (String, AXRect)) -> Bool in item.0 != focusedName })
        note(name + "-GROUPS", result.text + "\n" + sizes.text + (focusedName.map { "\n(focused, not compared: \($0))" } ?? ""))
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
        XCTAssertTrue(sizes.passed, "\(name): " + sizes.verdict)
    }

    /// #33 I (R239): a vertical gap (`ScreenRules.gapBelow`), written as "<name>-GAP"; fails below `minimum`.
    func checkGap(_ name: String, tree: String, anchors: [String], kinds: Set<String>, minimum: Double, what: String) {
        let result: CheckResult = ScreenRules.gapBelow(in: AccessibilityDump(tree), anchors: anchors, kinds: kinds, minimum: minimum, what: what)
        note(name + "-GAP", result.text)
        XCTAssertTrue(result.passed, "\(name): " + result.lines.joined(separator: " "))
    }

    /// #33 C: the toolbar's own controls, which are never menu items.
    static let toolbarControlIDs: Set<String> = [ControlID.sortAndFilter, ControlID.savedViews, ControlID.moreControls,
                                                ControlID.needsReview, ControlID.jumpToLetter]

    /// #33 C: every labelled Cell, MenuItem, Button and Switch on screen, outside the tab bar and not a toolbar control, read
    /// from ONE accessibility dump. A tvOS menu item is a Cell with NO label of its own: the run of 20 Nov found "Mark as
    /// Watched" in the open More menu only as "Cell at {{769.0, 583.4}, {416.0, 67.3}}" through cells containing a
    /// StaticText with that label (screenshots-library-logs, test.log). The old rule read `element.label` and skipped empty
    /// labels, so it found 0 items in every open menu. The text of a Cell is now its first StaticText's label.
    func controlLabels(in app: XCUIApplication) -> [(String, AXRect)] {
        ScreenRules.menuItems(in: AccessibilityDump(app.debugDescription), before: [], ignoringIdentifiers: Self.toolbarControlIDs)
    }

    /// #32 F / #33 C: the open menu: the items that appeared since `before` (from `controlLabels` with the menu closed), so
    /// the grid behind the menu is not counted (`ScreenRules.menu`). Fails when fewer than three are found, when an item ends
    /// below the window (cut at the bottom), or when an `expected` label is missing. Writes "<name>-MENU".
    func checkMenu(_ name: String, expected: [String], before: Set<String>, in app: XCUIApplication) {
        let dump: AccessibilityDump = AccessibilityDump(app.debugDescription)
        var windowMaxY: Double = 1080
        if let window = dump.window, let frame = dump.nodes[window].frame { windowMaxY = frame.maxY }
        let items: [(String, AXRect)] = ScreenRules.menuItems(in: dump, before: before, ignoringIdentifiers: Self.toolbarControlIDs)
        let result: CheckResult = ScreenRules.menu(items: items, expected: expected, windowMaxY: windowMaxY)
        note(name + "-MENU", result.text)
        // The tree of the open menu, so the next run's notes can prove the element type (none was written in the run of 20 Nov).
        hierarchy(name, of: app)
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
    }

    /// The card long-press menu with Go to Movie / Go to Show (and Remove from Continue Watching when the focused card is in
    /// that row) and where it leads (08). Part 1. The Shows toolbar (07) moved to test16_LibraryToolbars (#32).
    func test14_ShowsToolbarAndCardMenu() {
        // #32: the Shows toolbar and its menus (07-shows-*) moved to test16_LibraryToolbars (part 2, R232).
        let app = launch("-UITestFixtures", tab: "home")
        if waitForScreen("screen.home", in: app), waitFor("Sample", in: app, timeout: 60) {
            settle()
            // #25 A3: onto a card first, then the long press; the picture waits for the menu's Go to item, so it shows
            // the menu open. R388 follow-up (item 13): the focus starts on the featured Play since R388, and the long
            // press there started playback (the run on fd9731f: this picture showed the playback failure alert).
            guard focusFirstHomeCard(in: app) else {
                notReached("08-card-long-press-go-to", "The focus could not be moved to a card of the first shelf (focus on \(focusedLabel(in: app)))."); app.terminate(); return
            }
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            guard let label = waitForAny(["Go to Show", "Go to Movie"], in: app) else {
                notReached("08-card-long-press-go-to", "The long-press menu showed no “Go to Movie/Show” item (identifier “\(ControlID.goToTitle)”).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))"); app.terminate(); return
            }
            sleep(1); shot("08-card-long-press-go-to")
            if open(label, id: ControlID.goToTitle, in: app, name: "08-card-go-to-result") {
                _ = waitForScreen(label == "Go to Show" ? "screen.series" : "screen.item", in: app, timeout: 10)
                settle(); shot("08-card-go-to-result")
            }
        } else { notReached("08-card-long-press-go-to", "No sample title appeared on Home within 60 s.") }
        app.terminate()
    }

    func test05_FilesSearchDiscover() {
        var app = launch("-UITestFixtures", tab: "files")
        if waitForScreen("screen.files", in: app), waitFor("Sample Library", in: app, timeout: 60) {
            settle(); shot("70-files-sources")
            hierarchy("70-files-sources", of: app)
            if open("Sample Library", in: app, name: "71-files-root") {
                settle(); shot("71-files-root"); hierarchy("71-files-root", of: app)
                if open("Movies", in: app, name: "72-files-folder") {
                    settle(); shot("72-files-folder")
                    let folderTop: String = focusedLabel(in: app)
                    // #15 7.2: opening a folder must keep the Files tab. If the Movies tab got selected instead, say so (the
                    // test pressed the tab, or the app switched tabs) rather than leave a Movies grid named "files-folder".
                    // #24 C: the run on fa00af8 failed here ("no match for TabBar > Button where isSelected == 1", line 562):
                    // reading `label` of a query with no match fails the test. Now the screens tell it: the folder screen
                    // (screen.folder, App/Shell/RootView.swift) is shown and the Movies tab's screen (screen.movies) is not.
                    // Only existence checks, so this can never fail the test; the trimmed tree goes into the note and log.
                    let onFolder = waitForScreen("screen.folder", in: app, timeout: 5)
                    let onMovies = app.descendants(matching: .any).matching(identifier: "screen.movies").firstMatch.exists
                    if !onFolder || onMovies {
                        notReached("72-files-folder", "After opening the Movies folder: folder screen shown \(onFolder), Movies tab screen shown \(onMovies). Accessibility tree (first 60 lines):\n\(trimmedHierarchy(app))")
                    }
                    // R346 (item A): Up from the last file of the folder reaches the first file before the tab bar.
                    // R355 (item 6): the long folder name is whole (it wraps at the floor) and clear of its "3 items" line.
                    if onFolder { longNameCheck("72-files-folder", name: "Sample Movie 7 With A Much Longer", detail: "3 items", in: app) }
                    if onFolder { scrollUpCheck("72-files-folder", top: folderTop, in: app) }
                    if open("Sample Movie 1 (2021)", in: app, name: "73-files-movie-folder") {
                        settle(); shot("73-files-movie-folder")
                        // #25 B9: the picture waits for the sheet's last element (Done) to stand still.
                        rememberPage(app)
                        if open("2160p.mkv", in: app, name: "74-file-details") {
                            _ = waitUntilStill(control(id: nil, label: "Done", in: app)); shot("74-file-details"); hierarchy("74-file-details", of: app)
                            checkCover("74-file-details", in: app)
                        }
                    }
                }
            }
        } else { notReached("70-files-sources", "The sample source did not appear in Files.") }
        app.terminate()

        app = launch("-UITestFixtures", tab: "search")
        // Empty field: Discover below the search field (no key in UI-test mode, so its "Discover Needs a Key" state).
        if waitForScreen("screen.search", in: app) { settle(); shot("75-search-discover-no-key") }
        else { notReached("75-search-discover-no-key", "The Search screen (screen.search) did not appear within 30 s.") }
        // The search field of `.searchable` on tvOS: a search field, a text field, or only the on-screen keyboard (which
        // takes typed text directly). Whichever exists is used; the keyboard must be up before typing.
        let field = [app.searchFields.firstMatch, app.textFields.firstMatch].first { $0.waitForExistence(timeout: 5) }
        if let field, !app.keyboards.firstMatch.exists {
            _ = focus(field, in: app)
            XCUIRemote.shared.press(.select)
        }
        if app.keyboards.firstMatch.waitForExistence(timeout: 10) {
            if typeOnKeyboard("sam", in: app, name: "76-search-results") {
                sleep(3)
                shot("76-search-results")
                // R337 (docs/HIG_AUDIT.md T11): every element that carries a sample title, so the run shows whether the
                // system search suggestions appear next to the results. A note, not a failure: their place on tvOS 27 is
                // not on any Apple page read.
                let titled = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Sample'")).allElementsBoundByIndex
                note("76-search-results-SUGGESTIONS", titled.prefix(40).map { "\($0.elementType.rawValue) \u{201C}\($0.label)\u{201D} \($0.frame)" }.joined(separator: "\n"))
            } else {
                hierarchy("76-search-results", of: app)
                notReached("76-search-results", "The keys of the on-screen keyboard could not be reached with the remote (every step in 76-search-results-FOCUS-PATH).")
            }
        } else {
            notReached("76-search-results", "No on-screen keyboard appeared (search field found: \(field != nil)).")
        }
        app.terminate()
        // R343 (docs/HIG_AUDIT.md T11): recent searches under the empty search field, with Clear Recent Searches. Two searches
        // are given through the launch arguments' UserDefaults domain (`-search.recentSearches`), so the picture does not depend
        // on an earlier run; the argument domain cannot be cleared by the app, so Clear itself is not exercised here.
        app = launch("-UITestFixtures", tab: "search", extra: ["-" + "search.recentSearches", "Sample Movie 2\nSample Show"])
        if waitForScreen("screen.search", in: app) {
            let field = [app.searchFields.firstMatch, app.textFields.firstMatch].first { $0.waitForExistence(timeout: 5) }
            if let field, !app.keyboards.firstMatch.exists { _ = focus(field, in: app); XCUIRemote.shared.press(.select) }
            if waitFor("Recent Searches", in: app, timeout: 10) || waitFor("Sample Movie 2", in: app, timeout: 2) {
                settle(); shot("76-search-recent")
                let listed: Bool = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Sample Show")).firstMatch.exists
                let clear: Bool = app.buttons[ControlID.clearRecentSearches].exists || app.buttons["Clear Recent Searches"].exists
                note("76-search-recent-RECENT", (listed && clear ? "RECENT SEARCHES OK" : "RECENT SEARCHES WRONG")
                     + "\nrecent search listed: \(listed)\nClear Recent Searches shown: \(clear)")
                XCTAssertTrue(listed && clear, "76-search-recent: listed \(listed), clear \(clear)")
            } else { hierarchy("76-search-recent", of: app); notReached("76-search-recent", "No recent searches under the empty field (keyboard up: \(app.keyboards.firstMatch.exists)).") }
        } else { notReached("76-search-recent", "The Search screen did not appear.") }
        app.terminate()
        // R342 (docs/HIG_AUDIT.md T12): the invented Discover (-UITestFakeDiscover, `UITestFixtureDiscover`; no key, no
        // network): the cards; press and hold on a card shows the context menu with the watchlist action; Select opens the
        // title's page, which has the same action as a button (HIG Context menus: also in the main interface).
        app = launch("-UITestFixtures", tab: "search", extra: ["-UITestFakeDiscover"])
        if waitForScreen("screen.search", in: app), waitFor("Sample Suggestion 1", in: app, timeout: 30) {
            settle(); shot("75-search-discover-cards")
            let card: XCUIElement = app.buttons["Sample Suggestion 1"]
            if focus(card, in: app) {
                XCUIRemote.shared.press(.select, forDuration: 1.5)
                if waitFor("Add to Watchlist", in: app, timeout: 10) { sleep(1); shot("75-discover-card-menu") }
                else { notReached("75-discover-card-menu", "Press and hold on the card showed no “Add to Watchlist” (focus on \(focusedLabel(in: app))).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))") }
                XCUIRemote.shared.press(.menu); sleep(1)
                if focus(card, in: app) {
                    XCUIRemote.shared.press(.select)
                    if waitFor("Where to watch", in: app, timeout: 10) {
                        settle(); shot("75-discover-title-page")
                        let button: Bool = app.buttons[ControlID.discoverWatchlist].exists
                        let notInSearch: Bool = !app.buttons["Sample Suggestion 2"].exists
                        note("75-discover-title-page-PAGE", (button && notInSearch ? "TITLE PAGE OK" : "TITLE PAGE WRONG")
                             + "\nwatchlist button: \(button)\nDiscover shelf gone (a page was pushed): \(notInSearch)")
                        XCTAssertTrue(button && notInSearch, "75-discover-title-page: button \(button), page pushed \(notInSearch)")
                    } else { notReached("75-discover-title-page", "Select on the card did not open the title's page (focus on \(focusedLabel(in: app))).") }
                } else { notReached("75-discover-title-page", "The focus did not return to the card after the menu closed.") }
            } else { notReached("75-discover-card-menu", "Could not move the focus to Sample Suggestion 1 (focus on \(focusedLabel(in: app))).") }
        } else { hierarchy("75-search-discover-cards", of: app); notReached("75-search-discover-cards", "The invented Discover suggestions did not appear.") }
        app.terminate()
        // 77 and 78 (the old Discover tab) are gone: Discover is part of Search (screen 75, OPEN_QUESTIONS R167 (c)). 79 (Top
        // Shelf) is part of the system Home Screen, not this app, so a UI test cannot open it: it is checked on a device
        // (docs/DEVICE_TEST_CHECKLIST_VISUAL.md, V-TS1). #15 item 1.3.
    }

    // MARK: Accessibility settings (rule 17, docs/DESIGN_REFERENCES.md)

    /// The first five screens of the accessibility set (rule 17), as before #16 item 1.10.
    static let coreAccessibilityScreens = ["home", "movies", "settings", "files-root", "movie-detail"]
    /// #16 item 1.10 and #17 E: the rest of the set. "movie-detail-logo" is Sample Movie 2 and "show-page" is Sample Show 1,
    /// the two sample titles with a generated title logo (#15 Part 9, UITestFixtures.logos); "settings-backup" is the Backup page
    /// (#17 D, captured at the default size, Larger Text and Bold Text); "source-form" is the WebDAV form.
    static let moreAccessibilityScreens = ["movie-detail-logo", "show-page", "settings-backup", "add-source", "source-form", "search"]

    /// Numbers for `keys`, counting from `first`.
    func numbered(_ keys: [String], from first: Int) -> [(Int, String)] {
        keys.enumerated().map { (first + $0.offset, $0.element) }
    }

    /// Launches with `extra` and goes to the accessibility-set screen `key`. Returns the app when that screen is shown;
    /// otherwise writes a NOT-REACHED note for `name`, closes the app and returns nil. Every wait is at most 10 s.
    func reachAccessibilityScreen(_ key: String, name: String, extra: [String]) -> XCUIApplication? {
        let wait: TimeInterval = 10
        func fail(_ app: XCUIApplication, _ reason: String) -> XCUIApplication? {
            notReached(name, reason); app.terminate(); return nil
        }
        // `open` writes its own NOT-REACHED note when a row cannot be focused.
        func step(_ app: XCUIApplication, _ text: String) -> Bool {
            if open(text, in: app, name: name) { return true }
            app.terminate(); return false
        }
        switch key {
        case "home", "movies", "settings", "search":
            let ready = ["home": "Sample", "movies": "Sample", "settings": "Playback", "search": ""][key] ?? ""
            let app = launch("-UITestFixtures", tab: key, extra: extra, launchTimeout: wait)
            guard waitForScreen("screen.\(key)", in: app, timeout: wait), ready.isEmpty || waitFor(ready, in: app, timeout: wait) else {
                return fail(app, "The \(key) screen did not appear (or showed no “\(ready)”) within \(Int(wait)) s.")
            }
            return app
        case "files-root":
            let app = launch("-UITestFixtures", tab: "files", extra: extra, launchTimeout: wait)
            guard waitForScreen("screen.files", in: app, timeout: wait), waitFor("Sample Library", in: app, timeout: wait) else {
                return fail(app, "The sample source did not appear in Files within \(Int(wait)) s.")
            }
            return step(app, "Sample Library") ? app : nil
        case "movie-detail", "movie-detail-logo":
            let title = key == "movie-detail" ? "Sample Movie 1" : "Sample Movie 2"
            let app = launch("-UITestFixtures", open: title, extra: extra, launchTimeout: wait)
            guard waitForScreen("screen.item", in: app, timeout: wait), waitFor(title, in: app, timeout: wait) else {
                return fail(app, "The page of \(title) did not open within \(Int(wait)) s.")
            }
            return app
        case "show-page":
            let app = launch("-UITestFixtures", open: "Sample Show 1", extra: extra, launchTimeout: wait)
            guard waitForScreen("screen.series", in: app, timeout: wait), waitFor("Season 1", in: app, timeout: wait) else {
                return fail(app, "The page of Sample Show 1 did not open within \(Int(wait)) s.")
            }
            return app
        case "settings-backup":
            let app = launch("-UITestFixtures", tab: "settings", extra: extra, launchTimeout: wait)
            guard waitForScreen("screen.settings", in: app, timeout: wait), waitFor("Playback", in: app, timeout: wait) else {
                return fail(app, "Settings did not open within \(Int(wait)) s.")
            }
            return step(app, "Backup") ? app : nil
        case "add-source", "source-form":
            let app = launch("-UITestEmpty", extra: extra, launchTimeout: wait)
            guard waitForScreen("screen.home", in: app, timeout: wait), waitFor("Add a Source", in: app, timeout: wait) else {
                return fail(app, "Home with “Add a Source” did not appear within \(Int(wait)) s.")
            }
            rememberPage(app)
            guard step(app, "Add a Source") else { return nil }
            // #24 C: 93, 94, 99 and 100 were NOT REACHED here. "Type an Address" is a section header further down the list;
            // at Larger Text it is below the screen, and a lazy list does not build it yet. "Search Your Network" is the
            // first row (App/Features/Sources/SourceKindListView.swift), on screen at every text size.
            guard waitForScreen(ControlID.searchYourNetwork, in: app, timeout: wait) else {
                return fail(app, "The source type list did not open (no “Search Your Network” row within \(Int(wait)) s).")
            }
            if key == "add-source" {
                // #30: full screen at every text size and with Bold Text (93, 99, 110), R228.
                checkFullScreen(anchor: ControlID.searchYourNetwork, label: "Search Your Network", in: app, name: name)
                return app
            }
            guard open("WebDAV", id: ControlID.sourceKind("webdav"), in: app, name: name) else { app.terminate(); return nil }
            _ = waitUntilStill(control(id: ControlID.sourceConnect, label: "Connect", in: app))
            // #30: 94, 100, 111. At Larger Text the Connect row may not be built yet (a lazy list); `fullScreenRow` then
            // measures the cover's first Cell and says so in the note (#33 C). R324: the forms have no Cancel.
            checkFullScreen(anchor: ControlID.sourceConnect, label: "Connect", in: app, name: name)
            return app
        default:
            XCTFail("Unknown accessibility screen \(key)")
            return nil
        }
    }

    /// The screens `screens` (number, key) under one accessibility variant, named "NN-<variant>-<key>" (NN may have three
    /// digits). A screen that is not reached is a NOT-REACHED note, never a long wait.
    func accessibilityShots(_ variant: String, screens: [(Int, String)], extra: [String] = []) {
        for (number, key) in screens {
            let name = String(format: "%02d", number) + "-\(variant)-\(key)"
            guard let app = reachAccessibilityScreen(key, name: name, extra: extra) else { continue }
            settle(); shot(name)
            // R331 (replaces R265 and R295's -SAFE-AREA of text fields): at Larger Text, Down from the top of the WebDAV form
            // reaches every field row and Connect, and Connect is inside the 60 pt safe area while focused.
            if key == "source-form" && variant == "larger-text" { rowsReachable(name, in: app) }
            // #15 item 1.5: "Settings" was cut to "Sett" under Larger Text; the tab bar must read TAB BAR OK here too.
            if key == "home" { tabBarCheck(name, in: app) }
            recordOrCompareTexts(variant: variant, key: key, name: name, in: app)
            app.terminate()
        }
    }

    /// R321, R331 (docs/SOURCE_SETUP_DESIGN.md): the Name row of the WebDAV form opens its entry page, whose heading is
    /// "Name"; Select on the entry page's field shows the keyboard screen, "11-form-webdav-keyboard-name", and the
    /// "-KEYBOARD-HEADING" note says whether that screen names the field ("Name") and not the example ("Living Room", the
    /// heading the run of 20 Nov showed; R262). Back closes the keyboard, Back again the entry page.
    func keyboardOfNameRow(in app: XCUIApplication) {
        let name: String = "11-form-webdav-keyboard-name"
        let row: XCUIElement = control(id: ControlID.sourceField("name"), label: "Name", in: app)
        guard row.waitForExistence(timeout: 5), focus(row, in: app, maxPresses: 20) else {
            return notReached(name, "The Name row could not be focused (focus on \(focusedLabel(in: app))).\n" + focusPathText())
        }
        XCUIRemote.shared.press(.select)
        let field: XCUIElement = app.descendants(matching: .any).matching(identifier: ControlID.entryField).firstMatch
        guard field.waitForExistence(timeout: 10) else {
            return notReached(name, "Select on the Name row did not open its entry page.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
        settle(); shot("11-form-webdav-entry-name")
        let pageHeading: Bool = app.staticTexts.matching(NSPredicate(format: "label == %@", "Name")).firstMatch.exists
        // R352 (item 3): the example is in the entry page's description now, not the field's prompt.
        let exampleInDescription: Bool = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "For example, Living Room.")).firstMatch.exists
        if !field.hasFocus { _ = focus(field, in: app, maxPresses: 5) }
        XCUIRemote.shared.press(.select)
        guard app.keyboards.firstMatch.waitForExistence(timeout: 10) else {
            back()
            return notReached(name, "No keyboard screen appeared after Select on the Name entry field.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
        sleep(1); shot(name)
        // Top first, so the heading (if tvOS draws one) is early in the list.
        let statics: [XCUIElement] = app.staticTexts.allElementsBoundByIndex.prefix(60).filter { $0.exists }
            .sorted { (a: XCUIElement, b: XCUIElement) -> Bool in a.frame.minY < b.frame.minY }
        let texts: [String] = statics.map(\.label)
        let result: CheckResult = ScreenRules.keyboardHeading(texts: texts, fieldName: "Name", example: "Living Room")
        let inputs: [String] = (app.textFields.allElementsBoundByIndex + app.searchFields.allElementsBoundByIndex).map {
            "\u{201C}\($0.label)\u{201D} placeholder \u{201C}\($0.placeholderValue ?? "")\u{201D} \($0.frame)"
        }
        var exampleLine: String = "entry page description with the example: NOT SHOWN"
        if exampleInDescription { exampleLine = "entry page description with the example: shown" }
        note("11-form-webdav-KEYBOARD-HEADING", "entry page heading \u{201C}Name\u{201D}: " + (pageHeading ? "shown" : "NOT SHOWN") + "\n" + exampleLine + "\n" + result.text
             + "\ntext fields on the keyboard screen:\n" + inputs.joined(separator: "\n"))
        hierarchy(name, of: app)
        XCTAssertTrue(pageHeading, "\(name): the entry page has no \u{201C}Name\u{201D} heading")
        XCTAssertTrue(exampleInDescription, "\(name): the entry page's description does not give the example (R352)")
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
        back()
        back()
    }

    /// R326, R328 (docs/SOURCE_SETUP_DESIGN.md): from the found server's form (21-search-your-network-server-details), Back
    /// twice to Add a Source; the SMB form starts with its own Search Your Network row; choosing it lists the synthetic SMB
    /// server ("12-form-smb-network-search"); choosing that goes back to the SAME form with the Server ID row and the server
    /// filled in ("12-form-smb-network-found"). The focus is expected on the Shared Folder row, the one required field the
    /// search cannot know (R325). "-FORM-SEARCH" note; a failure fails the test.
    func formSearchPicksServer(in app: XCUIApplication) {
        let name: String = "12-form-smb-network-found"
        back(); back()
        guard waitForScreen(ControlID.searchYourNetwork, in: app, timeout: 10),
              open("SMB", id: ControlID.sourceKind("smb"), in: app, name: "12-form-smb-network-search") else {
            return notReached("12-form-smb-network-search", "Back twice did not return to Add a Source, or the SMB form did not open.")
        }
        guard waitForScreen(ControlID.formSearchYourNetwork, in: app, timeout: 10),
              open("Search Your Network", id: ControlID.formSearchYourNetwork, in: app, name: "12-form-smb-network-search"),
              waitFor("Sample NAS", in: app, timeout: 10) else {
            return notReached("12-form-smb-network-search", "The SMB form has no Search Your Network row, or the search did not list “Sample NAS”.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
        settle(); shot("12-form-smb-network-search")
        guard open("Sample NAS", in: app, name: name), waitForScreen(ControlID.serverID, in: app, timeout: 10) else {
            return notReached(name, "Choosing “Sample NAS” did not bring the form back with its Server ID row.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))")
        }
        settle(); shot(name)
        let server: String = (control(id: ControlID.sourceField("host"), label: "Server", in: app).value as? String) ?? ""
        let focused: String = focusedLabel(in: app)
        let sameForm: Bool = app.descendants(matching: .any).matching(identifier: ControlID.formSearchYourNetwork).firstMatch.exists
        let filled: Bool = server == "nas.sample.invalid"
        let lines: [String] = ["Server row value: \u{201C}\(server)\u{201D}" + (filled ? " OK" : " NOT FILLED"),
                               "back on the SMB form (its Search Your Network row is there): " + (sameForm ? "yes OK" : "NO"),
                               "focus on: \(focused) (expected the Shared Folder row; UNVERIFIED whether tvOS applies it)"]
        note(name + "-FORM-SEARCH", lines.joined(separator: "\n"))
        XCTAssertTrue(filled, "\(name): the found server did not fill the Server row (\(server))")
        XCTAssertTrue(sameForm, "\(name): choosing the server did not go back to the SMB form")
    }

    /// R322, R331: on an empty form no field row reports "Optional", "Required" or an example as its value. Field rows are
    /// found by identifier ("sourceField." + field kind); the FTP Encryption picker always shows its answer and is left out.
    /// Written to "<name>-NO-PLACEHOLDER-VALUES"; a failure fails the test.
    func checkNoPlaceholderValues(_ name: String, in app: XCUIApplication) {
        let rows: [XCUIElement] = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", ControlID.sourceField(""))).allElementsBoundByIndex
            .filter { (row: XCUIElement) -> Bool in row.identifier != ControlID.sourceField("security") }
        var seen: Set<String> = []
        var pairs: [(name: String, value: String)] = []
        for row in rows where !seen.contains(row.identifier) {
            seen.insert(row.identifier)
            pairs.append((name: row.label, value: (row.value as? String) ?? ""))
        }
        // The catalog's examples and the two words that are not examples (AppLogic SourceCatalog; R322).
        let placeholders: Set<String> = ["Optional", "Required", "Living Room", "https://nas.local", "nas.local", "445", "Videos",
                                         "/videos", "22", "/", "21", "http://nas.local:8200", "http://nas.local:8096",
                                         "https://nas.local/a.mkv"]
        let result: CheckResult = ScreenRules.noPlaceholderValues(rows: pairs, placeholders: placeholders)
        note(name + "-NO-PLACEHOLDER-VALUES", result.text)
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
    }

    /// R324, R331: the form's action buttons are exactly Connect (no Cancel since R324), and Connect shows a shape at rest
    /// (its bezel against the page, `ScreenRules.fieldShapeAtRest`, measured without the focus). When Connect is below the
    /// screen the focus goes to the last field row first, so the form scrolls Connect into view without focusing it.
    /// Written to "<name>-ACTIONS"; a failure fails the test.
    func checkActions(_ name: String, in app: XCUIApplication) {
        let connect: XCUIElement = control(id: ControlID.sourceConnect, label: "Connect", in: app)
        let cancel: XCUIElement = control(id: ControlID.sourceCancel, label: "Cancel", in: app)
        var actions: [String] = []
        if connect.exists { actions.append("Connect") }
        if cancel.exists { actions.append("Cancel") }
        let window: CGRect = app.windows.firstMatch.frame
        var lines: [String] = []
        if connect.exists, window.width > 0, !window.contains(connect.frame) {
            let rows: [XCUIElement] = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", ControlID.sourceField(""))).allElementsBoundByIndex
            if let last = rows.last, focus(last, in: app, maxPresses: 15) { settle() }
            lines.append("Connect was below the screen; focus moved to the last field row (\(focusedLabel(in: app)))")
        }
        var shape: CheckResult?
        if connect.exists, window.width > 0, window.contains(connect.frame), let image = RGBImage(screenshot: XCUIScreen.main.screenshot()) {
            let scale: Double = Double(image.width) / Double(window.width)
            shape = ScreenRules.fieldShapeAtRest(image, fields: [ScreenRules.FieldAtRest(name: "Connect", frame: AXRect(connect.frame),
                                                                                            isFocused: connect.hasFocus)], scale: scale)
            if connect.hasFocus { lines.append("Connect HAS THE FOCUS: not at rest") }
        }
        let result: CheckResult = ScreenRules.oneProminentAction(actions: actions, expected: "Connect", shape: shape)
        note(name + "-ACTIONS", (lines + result.lines).joined(separator: "\n"))
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
    }

    /// R331 (Larger Text, replaces R265 and R295's -SAFE-AREA of text fields): from the top of the WebDAV form, Down until the
    /// focus stops; the identifier of what has the focus is recorded after each press. Every field row and Connect must have
    /// taken the focus, in order, and Connect must be inside the 60 pt safe area while focused. "<name>-ROWS-REACHABLE".
    func rowsReachable(_ name: String, in app: XCUIApplication) {
        let rows: [String] = ["name", "address", "username", "password"].map { ControlID.sourceField($0) }
        let remote = XCUIRemote.shared
        for _ in 0..<12 { remote.press(.up); usleep(250_000) }
        var path: [String] = []
        var lastInside: Bool?
        var unmoved: Int = 0
        for _ in 0..<20 {
            let focused: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let id: String = focused.exists ? (focused.identifier.isEmpty ? "\u{201C}\(focused.label)\u{201D}" : focused.identifier) : "none"
            if id == ControlID.sourceConnect {
                let inside: CheckResult = ScreenRules.insideSafeArea([(name: "Connect", frame: AXRect(focused.frame))],
                                                                     window: AXRect(app.windows.firstMatch.frame))
                lastInside = inside.passed
            }
            if path.last == id { unmoved += 1; if unmoved >= 2 { break } } else { unmoved = 0 }
            path.append(id)
            remote.press(.down); usleep(400_000)
        }
        let result: CheckResult = ScreenRules.everyRowReached(rows: rows, last: ControlID.sourceConnect, focusPath: path, lastInside: lastInside)
        note(name + "-ROWS-REACHABLE", result.text)
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
    }

    /// #30 item 5: the app's own texts on screen under each accessibility variant (label to frame), kept by test06 for
    /// test11. Both run in ONE xcodebuild call of the accessibility job (compile-check.yml), so one runner process, test06
    /// first (tests run in name order).
    nonisolated(unsafe) static var variantTexts: [String: (name: String, texts: [String: CGRect])] = [:]

    /// The static texts on screen with a label, outside the tab bar (the system's tab bar keeps the simulator's setting, so it
    /// never changes here). One snapshot of the tree, so it is quick. The first frame of each label is kept.
    func visibleTexts(in app: XCUIApplication) -> [String: CGRect] {
        guard let root: any XCUIElementSnapshot = try? app.snapshot() else { return [:] }
        let window: CGRect = app.windows.firstMatch.frame
        var found: [String: CGRect] = [:]
        var stack: [any XCUIElementSnapshot] = [root]
        while let node = stack.popLast() {
            if node.elementType == .tabBar { continue }
            let frame: CGRect = node.frame
            let onScreen: Bool = window.isEmpty || window.intersects(frame)
            if node.elementType == .staticText, !node.label.isEmpty, frame.width > 0, frame.height > 0, onScreen, found[node.label] == nil {
                found[node.label] = frame
            }
            stack.append(contentsOf: node.children)
        }
        return found
    }

    /// #30 item 5: Larger Text and Bold Text must SHOW in their pictures. test06 records the texts of each variant picture;
    /// test11 (the default pictures) compares them, text by text (same label on the same screen), and fails when:
    /// - Larger Text: the median height of the matched texts is less than 1.2 times the default (accessibility3 is far
    ///   larger than the default size; 1.2 leaves room for texts that scale down to fit, R229);
    /// - Bold Text: no matched text is at least 1 % wider than at the default size (bold glyphs are wider; the height may
    ///   not change);
    /// - nothing could be matched (then the test cannot tell, so it fails rather than pass silently).
    /// A note "<variant picture>-TEXT-APPLIED" gives the numbers. When test06 did not run in this process, the default
    /// picture notes "NOT COMPARED" and does not fail (test11 run on its own).
    func recordOrCompareTexts(variant: String, key: String, name: String, in app: XCUIApplication) {
        let texts: [String: CGRect] = visibleTexts(in: app)
        if variant == "larger-text" || variant == "bold-text" {
            Self.variantTexts[variant + "|" + key] = (name, texts)
            return
        }
        guard variant == "default" else { return }
        for checked in ["larger-text", "bold-text"] {
            guard let recorded = Self.variantTexts[checked + "|" + key] else {
                note(name + "-TEXT-APPLIED-" + checked, "NOT COMPARED: no \(checked) picture of \(key) was taken in this test process.")
                continue
            }
            let labels: [String] = recorded.texts.keys.filter { texts[$0] != nil }.sorted()
            var ratios: [CGFloat] = []
            for label in labels {
                guard let base = texts[label], let other = recorded.texts[label] else { continue }
                let size: CGFloat = checked == "larger-text" ? base.height : base.width
                let grown: CGFloat = checked == "larger-text" ? other.height : other.width
                if size > 0 { ratios.append(grown / size) }
            }
            let sorted: [CGFloat] = ratios.sorted()
            var median: CGFloat = 0
            if !sorted.isEmpty { median = sorted[sorted.count / 2] }
            let wider: Int = ratios.filter { $0 >= 1.01 }.count
            var applied: Bool = false
            if checked == "larger-text" { applied = median >= 1.2 } else { applied = wider > 0 }
            if ratios.isEmpty { applied = false }
            let measure: String = checked == "larger-text" ? "height" : "width"
            let lines: [String] = ["\(recorded.name) against \(name): \(ratios.count) texts matched by label",
                                   "median \(measure) ratio \(String(format: "%.2f", median)); texts at least 1 % wider: \(wider)",
                                   "matched: " + labels.prefix(12).joined(separator: " | "),
                                   applied ? "SETTING APPLIED OK" : "SETTING NOT VISIBLE"]
            note(recorded.name + "-TEXT-APPLIED", lines.joined(separator: "\n"))
            XCTAssertTrue(applied, "\(recorded.name): the \(checked) setting does not show in the picture (\(lines[1]); \(ratios.count) texts matched)")
        }
    }

    /// Larger Text and Bold Text, drawn by the app itself in UI-test mode (App/Support/UITestAccessibility.swift): an
    /// imitation of the system settings, not the settings themselves (docs/COVERAGE.md). The system's own parts (the tab
    /// bar) keep the simulator's setting, so they do NOT change here. Numbers: the first five screens keep 80-84 (Larger
    /// Text) and 85-89 (Bold Text); the rest of the set is 90-95 (Larger Text) and 96-101 (Bold Text).
    func test06_LargerTextAndBoldText() {
        let larger = ["-UITestTextSize", "accessibility3"], bold = ["-UITestBoldText"]
        accessibilityShots("larger-text", screens: numbered(Self.coreAccessibilityScreens, from: 80), extra: larger)
        accessibilityShots("bold-text", screens: numbered(Self.coreAccessibilityScreens, from: 85), extra: bold)
        accessibilityShots("larger-text", screens: numbered(Self.moreAccessibilityScreens, from: 90), extra: larger)
        accessibilityShots("bold-text", screens: numbered(Self.moreAccessibilityScreens, from: 96), extra: bold)
    }

    /// The same eleven screens with no override (102-112), in the same job: scripts/ci-a11y-compare.py compares every
    /// Larger Text and Bold Text screenshot with these and fails when one is identical outside the tab bar (#17 A: in the
    /// reviewed CI run the Bold Text screenshots differed from the normal ones only in the tab bar).
    func test11_AccessibilityDefaults() {
        accessibilityShots("default", screens: numbered(Self.coreAccessibilityScreens + Self.moreAccessibilityScreens, from: 102))
    }

    // The next three are run only by the CI job, each on its own, AFTER it has turned the setting on in the simulator
    // (scripts/ci-a11y-setting.sh). In the main run they are skipped (-skip-testing), because there they would only repeat
    // the normal screens under a misleading name. Numbers 113-117 (each setting has its own folder).

    func test07_IncreaseContrast() { accessibilityShots("increase-contrast", screens: numbered(Self.coreAccessibilityScreens, from: 113)) }

    func test08_ReduceTransparency() { accessibilityShots("reduce-transparency", screens: numbered(Self.coreAccessibilityScreens, from: 113)) }

    func test09_ReduceMotion() { accessibilityShots("reduce-motion", screens: numbered(Self.coreAccessibilityScreens, from: 113)) }

    // MARK: Sorting screens (docs/SORTING.md, addendum #18 B and C)

    /// Movies with the "Needs Review (N)" button, Needs Review (the sample library has 8 unsorted files, one with a very long
    /// name and one with no year), the Move choice and sheet, How This Was Sorted, and the long-press menu with Move to Shows;
    /// each at the default size and the main ones again with Larger Text. Numbers 63 to 69 (free in the main set).
    func sortingShots(suffix: String, extra: [String]) {
        var app = launch("-UITestFixtures", tab: "movies", extra: extra)
        guard waitForScreen("screen.movies", in: app), waitFor("Sample", in: app, timeout: 60) else {
            return notReached("63-movies-needs-review-button\(suffix)", "Movies showed no “Needs Review” button within 60 s.")
        }
        settle(); shot("63-movies-needs-review-button\(suffix)")
        if openToolbarControl("Needs Review", id: ControlID.needsReview, in: app, name: "64-needs-review\(suffix)"), waitForScreen("screen.needsReview", in: app) {
            settle(); shot("64-needs-review\(suffix)"); hierarchy("64-needs-review\(suffix)", of: app)
            let reviewTop: String = focusedLabel(in: app)
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("64-needs-review-scrolled-\(step)\(suffix)") }
            if suffix.isEmpty { scrollUpCheck("64-needs-review", top: reviewTop, in: app) }
            if open("Sample Clip", in: app, name: "65-needs-review-choice\(suffix)") {
                // #25 A3: the choice is open when its Move to Shows item is there.
                if waitForAny(["Move to Shows"], in: app) != nil { sleep(1); shot("65-needs-review-choice\(suffix)") }
                else { notReached("65-needs-review-choice\(suffix)", "The choice did not open (no “Move to Shows” item).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))") }
                rememberPage(app)
                if open("Move to Shows", in: app, name: "66-move-sheet\(suffix)") {
                    // #25 A3: retaken after the sheet's animation: wait for its last element (Cancel) to stand still.
                    if waitUntilStill(control(id: nil, label: "Cancel", in: app)) {
                        shot("66-move-sheet\(suffix)"); checkCover("66-move-sheet\(suffix)", in: app)
                        moveRows(in: app, suffix: suffix)
                    }
                    else { notReached("66-move-sheet\(suffix)", "The move sheet's Cancel button did not appear or kept moving.\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))") }
                    back()
                }
            }
        }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1", extra: extra)
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 1", in: app) {
            rememberPage(app)
            if open("More", id: ControlID.more, in: app, name: "67-sorted-how\(suffix)"), waitForAny(["How This Was Sorted"], in: app) != nil,
               open("How This Was Sorted", in: app, name: "67-sorted-how\(suffix)") {
                settle(); shot("67-sorted-how\(suffix)"); checkCover("67-sorted-how\(suffix)", in: app)
            }
        } else { notReached("67-sorted-how\(suffix)", "The movie page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", tab: "movies", extra: extra)
        if waitForScreen("screen.movies", in: app), waitFor("Sample Movie", in: app, timeout: 60), focus(control("Sample Movie", in: app), in: app) {
            XCUIRemote.shared.press(.select, forDuration: 1.5); sleep(1)
            shot("68-card-long-press-move\(suffix)")
        } else { notReached("68-card-long-press-move\(suffix)", "No movie card could be focused.") }
        app.terminate()

        // The Jellyfin/Emby setting: the sample server's source page (never scanned or contacted in UI-test mode).
        app = launch("-UITestFixtures", tab: "settings", extra: extra)
        if waitForScreen("screen.settings", in: app), open("Sources", in: app, name: "69-source-sort-by-filename\(suffix)"),
           open("Sample Server", in: app, name: "69-source-sort-by-filename\(suffix)") {
            settle()
            // #24 C: the toggle is the page's first control, so it has the focus on arrival and 69 equalled -focused (run on
            // fa00af8). The plain picture is now taken with the focus on Check Connection, the -focused one on the toggle.
            let toggle = control("Sort by Filename", in: app)
            if focus(control("Check Connection", in: app), in: app) {
                sleep(1); shot("69-source-sort-by-filename\(suffix)")
            } else {
                notReached("69-source-sort-by-filename\(suffix)", "The focus could not leave the toggle for Check Connection (focus on \(focusedLabel(in: app))).")
            }
            if toggle.exists, focus(toggle, in: app) {
                sleep(1); shot("69-source-sort-by-filename-focused\(suffix)")
            } else {
                notReached("69-source-sort-by-filename-focused\(suffix)", "The Sort by Filename toggle was not found or could not be focused (focus on \(focusedLabel(in: app))).")
            }
        }
        app.terminate()
    }

    func test10_SortingScreens() {
        sortingShots(suffix: "", extra: [])
        sortingShots(suffix: "-larger-text", extra: ["-UITestTextSize", "accessibility3"])
    }
}
