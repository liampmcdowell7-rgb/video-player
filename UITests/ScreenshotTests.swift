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
    func shot(_ name: String) {
        guard let app = current, appIsInFront(app, timeout: 2) else {
            let state = current.map { "\($0.state.rawValue)" } ?? "not launched"
            XCTFail("\(name): the app is not in the foreground (state \(state)); no screenshot taken.")
            note(name + "-APP-NOT-IN-FRONT", "The app was not in the foreground (state \(state)), so no screenshot was taken.")
            return
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A screen that was not reached: a note with the reason, and a screenshot of what IS on screen instead (when the app
    /// is in front), named "NN-name-NOT-REACHED", so the reason can be seen.
    func notReached(_ name: String, _ reason: String) {
        note(name + "-NOT-REACHED", reason)
        if let app = current, appIsInFront(app, timeout: 2) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name + "-NOT-REACHED"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// Waits for text containing `text` anywhere on screen.
    func waitFor(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }

    /// The focusable element (button or cell) whose label contains `text`.
    func control(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        return app.cells.matching(predicate).firstMatch
    }

    /// Moves the focus with the remote's arrows until `target` has it. Direction comes from where the target is relative to
    /// the focused element. Run 44401030622 pressed Left 311 times on Settings: the focused element was the ROW (a cell)
    /// around the target button, so `target.hasFocus` stayed false and the frames overlapped. Now a focused element that
    /// contains the target's centre (or lies inside the target) counts as the target, and the loop stops when three
    /// presses in a row leave the focus where it was.
    func focus(_ target: XCUIElement, in app: XCUIApplication, maxPresses: Int = 30) -> Bool {
        let remote = XCUIRemote.shared
        var lastFrame: CGRect?
        var unmoved = 0
        for _ in 0..<maxPresses {
            guard target.exists else { remote.press(.down); continue }
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard focused.exists else { remote.press(.down); continue }
            let f = focused.frame, t = target.frame
            if f.contains(CGPoint(x: t.midX, y: t.midY)) || t.contains(CGPoint(x: f.midX, y: f.midY)) { return true }
            if f == lastFrame { unmoved += 1; if unmoved >= 3 { return false } } else { unmoved = 0 }
            lastFrame = f
            if t.minY >= f.maxY - 2 { remote.press(.down) }
            else if t.maxY <= f.minY + 2 { remote.press(.up) }
            else if t.midX > f.midX { remote.press(.right) }
            else { remote.press(.left) }
        }
        return target.exists && target.hasFocus
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
    func open(_ text: String, in app: XCUIApplication, name: String) -> Bool {
        let target = control(text, in: app)
        guard target.waitForExistence(timeout: 10) else {
            notReached(name, "No button or row labelled “\(text)” was found on the screen before it.")
            return false
        }
        guard focus(target, in: app) else {
            notReached(name, "The focus could not be moved to “\(text)” with the remote's arrows.")
            return false
        }
        XCUIRemote.shared.press(.select)
        return true
    }

    func back() { XCUIRemote.shared.press(.menu); sleep(1) }

    func settle() { sleep(2) }

    // MARK: Empty library (clean start)

    func test01_FirstLaunchAndEmptyScreens() {
        let app = launch("-UITestEmpty")
        shot("01-first-launch")
        if waitForScreen("screen.home", in: app) {
            _ = waitFor("Add a Source", in: app, timeout: 10)
            settle(); shot("02-home-empty")
        } else { notReached("02-home-empty", "The Home screen (screen.home) did not appear within 30 s.") }
        app.terminate()

        for (n, tab) in [("03", "movies"), ("04", "shows"), ("05", "files"), ("06", "discover"), ("07", "search")] {
            let a = launch("-UITestEmpty", tab: tab)
            if waitForScreen("screen.\(tab)", in: a) { settle(); shot("\(n)-\(tab)-empty") }
            else { notReached("\(n)-\(tab)-empty", "The \(tab) screen (screen.\(tab)) did not appear within 30 s.") }
            a.terminate()
        }
    }

    func test02_AddASource() {
        let app = launch("-UITestEmpty")
        guard waitForScreen("screen.home", in: app), waitFor("Add a Source", in: app),
              open("Add a Source", in: app, name: "10-add-source-types") else { return }
        guard waitFor("Type an Address", in: app) else { return notReached("10-add-source-types", "The source type list did not open.") }
        settle()
        shot("10-add-source-types")
        let kinds = [("11", "WebDAV"), ("12", "SMB"), ("13", "NFS"), ("14", "SFTP"), ("15", "FTP"), ("16", "UPnP/DLNA"),
                     ("17", "Jellyfin"), ("18", "Emby"), ("19", "Web Link")]
        for (n, kind) in kinds {
            let name = "\(n)-form-" + kind.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: " ", with: "-")
            guard open(kind, in: app, name: name) else { continue }
            settle()
            shot(name)
            back()
        }
        // The types that cannot be set up yet, with their reasons (bottom of the list).
        if focus(control("Cancel", in: app), in: app) { settle(); shot("20-add-source-not-available") } else { notReached("20-add-source-not-available", "Could not move down to the end of the list.") }
        // Network search last: it may ask for local-network permission, which a test cannot answer reliably.
        if open("Search Your Network", in: app, name: "21-search-your-network") { sleep(4); shot("21-search-your-network") }
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
            if page == "Sources", open("Sample Library", in: app, name: "34-settings-source-detail") {
                settle(); shot("34-settings-source-detail"); back()
            }
            back()
        }
        guard open("About", in: app, name: "40-about") else { return }
        settle()
        shot("40-about")
        // Text rows are not focusable; moving down to the licence link scrolls the page past Data Sources and Trademarks.
        for step in 1...3 {
            XCUIRemote.shared.press(.down); sleep(1)
            shot("41-about-scrolled-\(step)")
        }
        if open("Full Licence Texts", in: app, name: "42-licence-texts") {
            settle(); shot("42-licence-texts")
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("43-licence-texts-scrolled-\(step)") }
        }
    }

    // MARK: Library screens with the sample library

    func test04_LibraryScreens() {
        var app = launch("-UITestFixtures", tab: "home")
        if waitForScreen("screen.home", in: app), waitFor("Sample", in: app, timeout: 60) { settle(); shot("50-home-rows"); XCUIRemote.shared.press(.down); sleep(1); shot("51-home-rows-lower") }
        else { notReached("50-home-rows", "No sample title appeared on Home within 60 s (the sample library did not load).") }
        // The card long-press menu on the focused Home card.
        XCUIRemote.shared.press(.select, forDuration: 1.5)
        sleep(1)
        shot("52-card-long-press-menu")
        app.terminate()

        for (n, tab) in [("53", "movies"), ("54", "shows")] {
            app = launch("-UITestFixtures", tab: tab)
            if waitForScreen("screen.\(tab)", in: app), waitFor("Sample", in: app, timeout: 60) { settle(); shot("\(n)-\(tab)") } else { notReached("\(n)-\(tab)", "No sample title appeared.") }
            app.terminate()
        }

        app = launch("-UITestFixtures", open: "Sample Show 1")
        if waitForScreen("screen.series", in: app, timeout: 60), waitFor("Season 1", in: app, timeout: 20) {
            settle(); shot("55-show-page"); hierarchy("55-show-page", of: app)
            // Seasons are sections of the show page (there is no separate season page); move down to season 2.
            if focus(control("S2", in: app), in: app) || focus(control("Season 2", in: app), in: app) { settle(); shot("56-show-season-2-episode-row") }
            else { notReached("56-show-season-2-episode-row", "Could not move the focus to a season 2 episode row.") }
        } else { hierarchy("55-show-page", of: app); notReached("55-show-page", "The show page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 1", in: app) {
            settle(); shot("57-movie-detail"); hierarchy("57-movie-detail", of: app)
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("58-movie-detail-scrolled-\(step)") }
            if open("Fix Match", in: app, name: "59-fix-match") { settle(); shot("59-fix-match"); back() }
        } else { hierarchy("57-movie-detail", of: app); notReached("57-movie-detail", "The movie detail page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 2")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 2", in: app) {
            settle(); shot("60-movie-detail-two-versions")
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("61-movie-detail-two-versions-scrolled-\(step)") }
        } else { notReached("60-movie-detail-two-versions", "The detail page did not open.") }
        app.terminate()

        // Pressing Play on a sample file shows the playback error screen (sample files have no video).
        app = launch("-UITestFixtures", open: "Sample Movie 5")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 5", in: app), open("Play", in: app, name: "62-playback-error") {
            sleep(5); shot("62-playback-error")
        }
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
                    if open("Sample Movie 1 (2021)", in: app, name: "73-files-movie-folder") {
                        settle(); shot("73-files-movie-folder")
                        if open("2160p.mkv", in: app, name: "74-file-details") { settle(); shot("74-file-details") }
                    }
                }
            }
        } else { notReached("70-files-sources", "The sample source did not appear in Files.") }
        app.terminate()

        app = launch("-UITestFixtures", tab: "search")
        if waitForScreen("screen.search", in: app) { settle(); shot("75-search-prompt") }
        else { notReached("75-search-prompt", "The Search screen (screen.search) did not appear within 30 s.") }
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

        app = launch("-UITestFixtures", tab: "discover")
        if waitForScreen("screen.discover", in: app) { settle(); shot("77-discover-no-key") }
        else { notReached("77-discover-no-key", "The Discover screen (screen.discover) did not appear within 30 s.") }
        notReached("78-discover-results", "Discover results need an online lookup key and the network; UI-test mode makes no network calls.")
        notReached("79-top-shelf", "The Top Shelf is part of the Home Screen, not the app; a UI test of this app cannot open it.")
        app.terminate()
    }

    // MARK: Accessibility settings (rule 17, docs/DESIGN_REFERENCES.md)

    /// The five main screens (Home, Movies, Settings, a Files folder, a movie page) under one accessibility setting, numbered
    /// from `first` and named "NN-<variant>-<screen>". Every wait is at most 10 s; a screen that does not appear in time is a
    /// NOT-REACHED note, never a long wait.
    func accessibilityShots(_ variant: String, first: Int, extra: [String] = []) {
        let wait: TimeInterval = 10
        func name(_ offset: Int, _ screen: String) -> String { String(format: "%02d", first + offset) + "-\(variant)-\(screen)" }
        for (offset, tab, ready) in [(0, "home", "Sample"), (1, "movies", "Sample"), (2, "settings", "Playback")] {
            let app = launch("-UITestFixtures", tab: tab, extra: extra, launchTimeout: wait)
            if waitForScreen("screen.\(tab)", in: app, timeout: wait), waitFor(ready, in: app, timeout: wait) { settle(); shot(name(offset, tab)) }
            else { notReached(name(offset, tab), "The \(tab) screen with “\(ready)” did not appear within \(Int(wait)) s.") }
            app.terminate()
        }
        var app = launch("-UITestFixtures", tab: "files", extra: extra, launchTimeout: wait)
        if waitForScreen("screen.files", in: app, timeout: wait), waitFor("Sample Library", in: app, timeout: wait) {
            // `open` writes its own NOT-REACHED note when the row cannot be focused.
            if open("Sample Library", in: app, name: name(3, "files-root")) { settle(); shot(name(3, "files-root")) }
        } else { notReached(name(3, "files-root"), "The sample source did not appear in Files within \(Int(wait)) s.") }
        app.terminate()
        app = launch("-UITestFixtures", open: "Sample Movie 1", extra: extra, launchTimeout: wait)
        if waitForScreen("screen.item", in: app, timeout: wait), waitFor("Sample Movie 1", in: app, timeout: wait) {
            settle(); shot(name(4, "movie-detail"))
        } else { notReached(name(4, "movie-detail"), "The movie page did not open within \(Int(wait)) s.") }
        app.terminate()
    }

    /// Larger Text and Bold Text, drawn by the app itself in UI-test mode (App/Support/UITestAccessibility.swift): SwiftUI lets
    /// an app set these two. The system's own parts (the tab bar) keep the simulator's setting, so they do NOT grow here.
    func test06_LargerTextAndBoldText() {
        accessibilityShots("larger-text", first: 80, extra: ["-UITestTextSize", "accessibility3"])
        accessibilityShots("bold-text", first: 85, extra: ["-UITestBoldText"])
    }

    // The next three are run only by the CI job, each on its own, AFTER it has turned the setting on in the simulator
    // (scripts/ci-a11y-setting.sh). In the main run they are skipped (-skip-testing), because there they would only repeat
    // the normal screens under a misleading name.

    func test07_IncreaseContrast() { accessibilityShots("increase-contrast", first: 90) }

    func test08_ReduceTransparency() { accessibilityShots("reduce-transparency", first: 90) }

    func test09_ReduceMotion() { accessibilityShots("reduce-motion", first: 90) }
}
