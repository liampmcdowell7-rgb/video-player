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
    /// (accessibility identifier "screen.<name>", App/Shell/RootView.swift) or its tab bar present.
    func appIsInFront(_ app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        guard app.wait(for: .runningForeground, timeout: timeout) else { return false }
        let screen = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "screen.")).firstMatch
        return screen.waitForExistence(timeout: timeout) || app.tabBars.firstMatch.exists
    }

    /// Waits for the screen with the accessibility identifier `id` ("screen.home", "screen.item", ...).
    func waitForScreen(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        app.descendants(matching: .any).matching(identifier: id).firstMatch.waitForExistence(timeout: timeout)
    }

    /// A screenshot named `name`, taken only while the app is in front. Otherwise a failure and a text note, never a picture
    /// of the system Home Screen saved under the name of one of the app's screens.
    func shot(_ name: String, mustChangeAfter step: String? = nil) {
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
        } else if let previous = lastShot, previous.png == png {
            print("WARNING: \(name): the screen did not change since \(previous.name) (identical pixels).")
            note(name + "-UNCHANGED", "Identical, pixel for pixel, to \(previous.name): the step before it did not change the screen.")
        }
        lastShot = (name, png)
    }

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
        let tabBar = app.tabBars.firstMatch
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
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<maxPresses {
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            if focused.exists, !(tabBar.exists && tabBar.frame.contains(CGPoint(x: focused.frame.midX, y: focused.frame.midY))) { return true }
            XCUIRemote.shared.press(.down); usleep(500_000)
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
    /// when the focus has left `expected`: the comparison would say nothing about the marquee.
    func laterPictures(_ name: String, expected: String, step: String, in app: XCUIApplication, firstLine: String) {
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
        shot(name + "-later", mustChangeAfter: step)
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
    /// found or cannot be focused.
    func typeOnKeyboard(_ text: String, in app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        for character in text {
            let label = String(character)
            let candidates = [keyboard.keys[label], keyboard.buttons[label], keyboard.keys[label.uppercased()], keyboard.buttons[label.uppercased()]]
            guard let key = candidates.first(where: { $0.exists }), focus(key, in: app, maxPresses: 40) else { return false }
            XCUIRemote.shared.press(.select)
        }
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

    /// #25 B2: a toolbar control of Movies or Shows. #34 3: no longer through the More menu: the full row fits at both sizes
    /// (GridToolbarLayout, OPEN_QUESTIONS R233), so a control that is not on the line is a failure of `checkToolbarGroups`
    /// and a NOT-REACHED note here, never a detour through More.
    func openToolbarControl(_ text: String, id: String, in app: XCUIApplication, name: String) -> Bool {
        open(text, id: id, in: app, name: name)
    }

    /// The tab bar from the accessibility tree (OPEN_QUESTIONS R167 (c)): six tabs Home, Movies, Shows, Files, Search,
    /// Settings, each whole inside the window and not overlapping the next. Written as "NN-name-TABBAR" (in the
    /// screenshots-logs artifact) with every tab's label and frame and a final "TAB BAR OK" or "TAB BAR PROBLEM: ...".
    /// A fade at the bar's edge is drawn, not reported in the tree; the screenshot shows that.
    func tabBarCheck(_ name: String, in app: XCUIApplication) {
        let expected = ["Home", "Movies", "Shows", "Files", "Search", "Settings"]
        let window = app.windows.firstMatch.frame
        let buttons = app.tabBars.firstMatch.buttons.allElementsBoundByIndex
        var lines = buttons.map { "\($0.label)\t\(String(describing: $0.frame))" }
        var problems: [String] = []
        let labels = buttons.map(\.label)
        if labels != expected { problems.append("tabs are \(labels), expected \(expected)") }
        for b in buttons where b.frame.isEmpty || !window.contains(b.frame) {
            problems.append("“\(b.label)” is not whole inside the window \(String(describing: window))")
        }
        for (a, b) in zip(buttons, buttons.dropFirst()) where a.frame.maxX > b.frame.minX + 1 {
            problems.append("“\(a.label)” overlaps “\(b.label)”")
        }
        lines.append(problems.isEmpty ? "TAB BAR OK" : "TAB BAR PROBLEM: " + problems.joined(separator: "; "))
        note(name + "-TABBAR", lines.joined(separator: "\n"))
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
            // The form is ready when its Cancel row (the last row but one) stands still.
            _ = waitUntilStill(control(id: ControlID.sourceCancel, label: "Cancel", in: app))
            shot(name)
            checkNoKeyField(in: app, name: name)
            checkFullScreen(anchor: ControlID.sourceCancel, label: "Cancel", in: app, name: name)
            back()
            _ = waitForScreen(ControlID.searchYourNetwork, in: app, timeout: 5)
        }
        // #25 B1: the type notes moved to "About Source Types" (Learn More); its page, once.
        if open("About Source Types", id: ControlID.learnMore, in: app, name: "10-add-source-learn-more") {
            settle(); shot("10-add-source-learn-more"); back()
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
                settle(); shot("20-add-source-not-available"); checkCover("20-add-source-not-available", in: end)
            }
            if !onCancel {
                notReached("20-add-source-not-available", "Moving down did not reach Cancel (focus on \(focusedLabel(in: end))).\n" + focusPathText())
                XCTFail("20-add-source-not-available: the remote's Down did not reach Cancel below the Not Available Yet rows")
            }
            // Network search last: it may ask for local-network permission, which a test cannot answer reliably.
            end.terminate()
        }
        let network = launch("-UITestEmpty")
        if waitForScreen("screen.home", in: network), waitFor("Add a Source", in: network), open("Add a Source", in: network, name: "21-search-your-network"),
           waitForScreen(ControlID.searchYourNetwork, in: network, timeout: 15),
           open("Search Your Network", id: ControlID.searchYourNetwork, in: network, name: "21-search-your-network") {
            sleep(4); shot("21-search-your-network"); checkCover("21-search-your-network", in: network)
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
                        settle(); shot("21-search-your-network-server-details"); checkCover("21-search-your-network-server-details", in: fake)
                    }
                    else { notReached("21-search-your-network-server-details", "The Server ID row did not take the focus (focus on \(focusedLabel(in: fake))).") }
                    let value: String = (row.value as? String) ?? ""
                    note("21-search-your-network-server-details-ROW", "Server ID row value: \(value)\nframe: \(row.frame)\n" + (value == rawName ? "WHOLE ID OK" : "ID NOT WHOLE"))
                    XCTAssertEqual(value, rawName, "21-search-your-network-server-details: the Server ID row does not carry the whole identifier")
                    // #33 D: the Name field starts with the readable name only. The tree carries a field's whole value, not
                    // what is drawn, so a "…" cut cannot be read here; the picture 21-search-your-network-server-details shows it.
                    let fieldValues: [String] = fake.textFields.allElementsBoundByIndex.map { (field: XCUIElement) -> String in
                        guard let value = field.value as? String else { return "" }
                        return value
                    }
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
            shot(name)
            // #36 T6: every Settings page from 31 to 38 gets a -CONTRAST note of all its texts.
            textContrast(name, in: app)
            if page == "Playback" {
                checkContrast(name, prefixes: ["How titles play", "Skip buttons appear", "Playback Stats adds"], in: app)
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
        // #24 C: the run on fa00af8 had 41-1/2/3 identical to 40: the page is longer than the screen, but its text rows were
        // not focusable, so Down had nothing to move to. The rows now take focus (App/Features/Settings/AboutView.swift);
        // four Down presses per picture move the focus, and the page with it, a screen further.
        for step in 1...3 {
            for _ in 0..<4 { XCUIRemote.shared.press(.down); usleep(400_000) }
            sleep(1)
            shot("41-about-scrolled-\(step)")
        }
        // #25 A2: by its identifier; the long notices moved to Learn More pages (B9), so the link is nearer the top.
        if open("Full Licence Texts", id: ControlID.fullLicenceTexts, in: about, name: "42-licence-texts") {
            settle(); shot("42-licence-texts")
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("43-licence-texts-scrolled-\(step)") }
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
            for _ in 0..<6 { XCUIRemote.shared.press(.down); usleep(400_000) }
            sleep(1)
            shot("36-settings-online-lookup-key-set-scrolled")
            back()
        }
        if open("Sources", in: keyed, name: "39-second-source-no-key-field"), open("Add a Source", in: keyed, name: "39-second-source-no-key-field"),
           waitForScreen(ControlID.searchYourNetwork, in: keyed, timeout: 15),
           open("WebDAV", id: ControlID.sourceKind("webdav"), in: keyed, name: "39-second-source-no-key-field") {
            _ = waitUntilStill(control(id: ControlID.sourceCancel, label: "Cancel", in: keyed))
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
    func checkCover(_ name: String, anchor: String? = nil, in app: XCUIApplication) {
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
        take("cover layout (A)", ScreenRules.coverLayout(in: dump))
        // #36 S-C (R255): buttons side by side are the same size and at least 66 pt high.
        if let cover = dump.coverRoot { take("buttons side by side (#36 S-C)", ScreenRules.sideBySideButtons(in: dump, root: cover)) }
        let tabBar: XCUIElement = app.tabBars.firstMatch
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
        if waitForScreen("screen.home", in: app), waitFor("Sample", in: app, timeout: 60) { settle(); shot("50-home-rows"); XCUIRemote.shared.press(.down); sleep(1); shot("51-home-rows-lower") }
        else { notReached("50-home-rows", "No sample title appeared on Home within 60 s (the sample library did not load).") }
        // The card long-press menu on the focused Home card. #25 A3: the focus starts on the tab bar, so move it into the
        // content first, and wait for the menu's items before the picture.
        if focusContent(in: app) {
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            if waitForAny(["Mark as Watched", "Mark as Unwatched"], in: app) != nil { sleep(1); shot("52-card-long-press-menu") }
            else { notReached("52-card-long-press-menu", "The long-press menu did not open (no “Mark as Watched/Unwatched” item; focus on \(focusedLabel(in: app))).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))") }
        } else { notReached("52-card-long-press-menu", "The focus could not leave the tab bar for a card (focus on \(focusedLabel(in: app))).") }
        app.terminate()

        // #34 5a (R229): the Continue Watching caption is now inside the focused button, so the system marquee can scroll it.
        // Sample Movie 7 (the long title, 20 % watched) is in Continue Watching; its wide card is focused, and two pictures
        // 3 s apart must differ (the marquee moved), as 56-show-long-episode-caption does for an episode caption.
        app = launch("-UITestFixtures", tab: "home")
        if waitForScreen("screen.home", in: app), waitFor("Sample", in: app, timeout: 60), focusContent(in: app),
           focus(control("Sample Movie 7", in: app), in: app) {
            let focusedFrame: CGRect = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch.frame
            let isWide: Bool = focusedFrame.width > focusedFrame.height
            let firstLine: String = "focused \(focusedLabel(in: app)) frame \(focusedFrame) wide \(isWide)"
            note("50-home-continue-watching-caption-FOCUS", firstLine)
            if isWide {
                // #36 8 T4: Sample Movie 7 is the long title (a short one fits and has nothing to scroll); the focus is
                // asserted before the wait and written to the -FOCUS note.
                laterPictures("50-home-continue-watching-caption", expected: "Sample Movie 7",
                              step: "3 s of focus on the Continue Watching card of Sample Movie 7 (the system marquee, #34 5a)",
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
            if waitForScreen("screen.\(tab)", in: app), waitFor("Sample", in: app, timeout: 60) { settle(); shot("\(n)-\(tab)") } else { notReached("\(n)-\(tab)", "No sample title appeared.") }
            app.terminate()
        }

        app = launch("-UITestFixtures", open: "Sample Show 1")
        if waitForScreen("screen.series", in: app, timeout: 60), waitFor("Season 1", in: app, timeout: 20) {
            settle(); shot("55-show-page")
            // #33 E: every episode card the same size (55 of the run of 20 Nov: S2 E3 378 x 566 beside 410 x 615).
            let pageTree: String = app.debugDescription
            note("55-show-page-HIERARCHY", pageTree)
            let cards: CheckResult = ScreenRules.equalEpisodeCards(in: AccessibilityDump(pageTree))
            note("55-show-page-CARDS", cards.text)
            XCTAssertTrue(cards.passed, "55-show-page: " + cards.verdict)
            checkGap("55-show-page", tree: pageTree, anchors: [ControlID.play, ControlID.more], kinds: ["StaticText"], minimum: 40, what: "buttons to the first season heading")
            // #15 item 1.6: the scrolled states of the show page (each must differ from the one before).
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); let mustChange: String? = step == 1 ? "Down on the show page" : nil; shot("55-show-page-scrolled-\(step)", mustChangeAfter: mustChange) }
            for _ in 0..<2 { XCUIRemote.shared.press(.up) }; sleep(1)
            // Seasons are sections of the show page (there is no separate season page); move down to season 2.
            if focus(control("S2", in: app), in: app) || focus(control("Season 2", in: app), in: app) { settle(); shot("56-show-season-2-episode-row") }
            else { notReached("56-show-season-2-episode-row", "Could not move the focus to a season 2 episode row.") }
            // #30 Part 2 (R229): S2 E3 has the caption too long even at the readable floor. Focused, the system marquee should
            // scroll it; the two pictures 3 s apart show whether it moves (default text size).
            if focus(control("S2 E3", in: app), in: app) || focus(control("S2 E3, A very long episode title that is wider than any episode card on the show page", in: app), in: app) {
                // #33 L: the marquee was meant to move the caption; identical pictures fail (unverified that it runs).
                // #36 8 T4: S2 E3 is the long title; the focus is asserted before the wait and written to the -FOCUS note.
                laterPictures("56-show-long-episode-caption", expected: "S2 E3",
                              step: "3 s of focus on S2 E3 (the system marquee)", in: app,
                              firstLine: "focused \(focusedLabel(in: app)) after moving to S2 E3")
            } else {
                notReached("56-show-long-episode-caption", "Could not move the focus to S2 E3 (focus on \(focusedLabel(in: app))).")
            }
        } else { hierarchy("55-show-page", of: app); notReached("55-show-page", "The show page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 1", in: app) {
            settle(); shot("57-movie-detail")
            let movieTree: String = app.debugDescription
            note("57-movie-detail-HIERARCHY", movieTree)
            checkGap("57-movie-detail", tree: movieTree, anchors: [ControlID.play, ControlID.more], kinds: ["StaticText"], minimum: 40, what: "buttons to the next heading")
            focusCheck("57-movie-detail", expected: ControlID.play, in: app)
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); let mustChange: String? = step == 1 ? "Down on the movie page" : nil; shot("58-movie-detail-scrolled-\(step)", mustChangeAfter: mustChange) }
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
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("61-movie-detail-two-versions-scrolled-\(step)") }
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
        // #36 8 T5: the S1 E1 card by its full spoken label (the button's label is "S1 E1, A quiet beginning"), so no other
        // control can match; the focus is checked on that card before Select, and the path goes into the note.
        let episodeLabel: String = "S1 E1, A quiet beginning"
        guard open(episodeLabel, in: app, name: "22-player-skip-intro"), waitForScreen("screen.item", in: app, timeout: 20) else {
            notReached("22-player-skip-intro", "The S01E01 page did not open (focus on \(focusedLabel(in: app))).\n" + focusPathText())
            app.terminate(); return
        }
        settle()
        // S01E01 is watched in the sample library, so its button says "Play Again" ("Play" matches it).
        guard open("Play", id: ControlID.play, in: app, name: "22-player-skip-intro") else { app.terminate(); return }
        // The clip is written on first use (a few seconds), then plays; Skip Intro shows from 2 s to 20 s.
        if waitFor("Skip Intro", in: app, timeout: 30) { sleep(1); shot("22-player-skip-intro") }
        else { shot("22-player-skip-intro-missing"); notReached("22-player-skip-intro", "No “Skip Intro” within 30 s of Play.") }

        // The transport bar and controls: one press of Play/Pause pauses and shows them.
        XCUIRemote.shared.press(.playPause); sleep(2); shot("23-player-controls")
        // The info panel: down from the transport bar.
        XCUIRemote.shared.press(.down); sleep(2); shot("24-player-info-panel")
        XCUIRemote.shared.press(.up); sleep(1)
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

        // Next Episode: play on to the end of the clip; the Up Next card names Sample Show 1 S01E02 ("The long way round").
        XCUIRemote.shared.press(.playPause)
        if waitFor("The long way round", in: app, timeout: 60) { sleep(1); shot("27-player-next-episode") }
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
            if open("Sample synopsis", in: app, name: "77-movie-long-synopsis-page") { settle(); shot("77-movie-long-synopsis-page"); back() }
            for _ in 0..<4 { XCUIRemote.shared.press(.down) }; sleep(1); shot("77-movie-long-synopsis-cast")
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
            if open("Sample synopsis", in: app, name: "77-show-long-synopsis-page") { settle(); shot("77-show-long-synopsis-page"); back() }
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
    /// FAIL the test when the toolbar groups are not clear or a menu is wrong (OPEN_QUESTIONS R233 to R236):
    /// - `checkToolbarGroups`: the gaps inside the view-control group (Sort, Filter, Saved Views) differ by more than 2 pt,
    ///   or the gap to the second group (Needs Review, Jump to Letter) is not at least 2 times the in-group gap (#33 G, was 1.5);
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

    /// One toolbar and its menus: "<prefix><suffix>", then "<prefix>-sort-menu<suffix>", "-filter-menu", "-filter-submenu"
    /// (the Resolution group open) and "-saved-views-menu" (with no saved view: what the Save View button opens).
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
        if openToolbarControl("Sort", id: ControlID.sort, in: app, name: prefix + "-sort-menu" + suffix) {
            sleep(1); shot(prefix + "-sort-menu" + suffix)
            checkMenu(prefix + "-sort-menu" + suffix, expected: ["Title", "Year", "Date Added"], before: closed, in: app)
            back(); _ = focusContent(in: app)
        }
        if openToolbarControl("Filter", id: ControlID.filter, in: app, name: prefix + "-filter-menu" + suffix) {
            sleep(1); shot(prefix + "-filter-menu" + suffix)
            checkMenu(prefix + "-filter-menu" + suffix, expected: ["Watched", "Resolution", "Dynamic Range", "Sound", "Clear All Filters"], before: closed, in: app)
            let filterOpen: Set<String> = Set(controlLabels(in: app).map { $0.0 })
            if open("Resolution", in: app, name: prefix + "-filter-submenu" + suffix) {
                sleep(1); shot(prefix + "-filter-submenu" + suffix)
                checkMenu(prefix + "-filter-submenu" + suffix, expected: [], before: filterOpen, in: app)
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

    /// #32 F / #33 G: the toolbar's groups. Writes "<name>-GROUPS" with every control's frame, the two gaps and the verdict
    /// (`ScreenRules.toolbarGroups`, ratio 2: the gap between the groups at least twice the gap inside the first group, at
    /// the default size and at Larger Text; proven in ScreenChecksTests on the run's frames, 76 vs 60, which fail). When the
    /// row is collapsed (the More menu, R200) only the first group is checked.
    func checkToolbarGroups(_ name: String, in app: XCUIApplication) {
        let first: [(String, String)] = [("Sort", ControlID.sort), ("Filter", ControlID.filter), ("Saved Views", ControlID.savedViews), ("More", ControlID.moreControls)]
        let second: [(String, String)] = [("Needs Review", ControlID.needsReview), ("Jump to Letter", ControlID.jumpToLetter)]
        func frames(_ list: [(String, String)]) -> [(String, AXRect)] {
            list.compactMap { (label: String, id: String) -> (String, AXRect)? in
                let element: XCUIElement = app.descendants(matching: .any).matching(identifier: id).firstMatch
                guard element.exists, !element.frame.isEmpty else { return nil }
                return (label, AXRect(element.frame))
            }.sorted { (a: (String, AXRect), b: (String, AXRect)) -> Bool in a.1.x < b.1.x }
        }
        let result: CheckResult = ScreenRules.toolbarGroups(first: frames(first), second: frames(second), ratio: 2)
        note(name + "-GROUPS", result.text)
        XCTAssertTrue(result.passed, "\(name): " + result.verdict)
    }

    /// #33 I (R239): a vertical gap (`ScreenRules.gapBelow`), written as "<name>-GAP"; fails below `minimum`.
    func checkGap(_ name: String, tree: String, anchors: [String], kinds: Set<String>, minimum: Double, what: String) {
        let result: CheckResult = ScreenRules.gapBelow(in: AccessibilityDump(tree), anchors: anchors, kinds: kinds, minimum: minimum, what: what)
        note(name + "-GAP", result.text)
        XCTAssertTrue(result.passed, "\(name): " + result.lines.joined(separator: " "))
    }

    /// #33 C: the toolbar's own controls, which are never menu items.
    static let toolbarControlIDs: Set<String> = [ControlID.sort, ControlID.filter, ControlID.savedViews, ControlID.moreControls,
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
            // #25 A3: into the content first (the focus starts on the tab bar), then the long press; the picture waits
            // for the menu's Go to item, so it shows the menu open.
            guard focusContent(in: app) else {
                notReached("08-card-long-press-go-to", "The focus could not leave the tab bar for a card (focus on \(focusedLabel(in: app)))."); app.terminate(); return
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
            if typeOnKeyboard("sam", in: app) {
                sleep(3)
                shot("76-search-results")
            } else {
                hierarchy("76-search-results", of: app)
                notReached("76-search-results", "The keys of the on-screen keyboard could not be reached with the remote.")
            }
        } else {
            notReached("76-search-results", "No on-screen keyboard appeared (search field found: \(field != nil)).")
        }
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
            _ = waitUntilStill(control(id: ControlID.sourceCancel, label: "Cancel", in: app))
            // #30: 94, 100, 111. At Larger Text the Cancel row may not be built yet (a lazy list); `fullScreenRow` then
            // measures the cover's first Cell and says so in the note (#33 C).
            checkFullScreen(anchor: ControlID.sourceCancel, label: "Cancel", in: app, name: name)
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
            // #15 item 1.5: "Settings" was cut to "Sett" under Larger Text; the tab bar must read TAB BAR OK here too.
            if key == "home" { tabBarCheck(name, in: app) }
            recordOrCompareTexts(variant: variant, key: key, name: name, in: app)
            app.terminate()
        }
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
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("64-needs-review-scrolled-\(step)\(suffix)") }
            if open("Sample Clip", in: app, name: "65-needs-review-choice\(suffix)") {
                // #25 A3: the choice is open when its Move to Shows item is there.
                if waitForAny(["Move to Shows"], in: app) != nil { sleep(1); shot("65-needs-review-choice\(suffix)") }
                else { notReached("65-needs-review-choice\(suffix)", "The choice did not open (no “Move to Shows” item).\nAccessibility tree (first 80 lines):\n\(trimmedHierarchy(app, lines: 80))") }
                rememberPage(app)
                if open("Move to Shows", in: app, name: "66-move-sheet\(suffix)") {
                    // #25 A3: retaken after the sheet's animation: wait for its last element (Cancel) to stand still.
                    if waitUntilStill(control(id: nil, label: "Cancel", in: app)) { shot("66-move-sheet\(suffix)"); checkCover("66-move-sheet\(suffix)", in: app) }
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
