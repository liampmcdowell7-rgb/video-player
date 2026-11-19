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
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // #15 item 1.6: every capture must show something new. The CI run for 8bb0f0c saved 58 and 61 "scrolled" three
        // times each, pixel for pixel the same as the page before: Down moved nothing. Same pixels = a failed step.
        let png = screenshot.pngRepresentation
        if let previous = lastShot, previous.png == png {
            XCTFail("\(name): the screen did not change since \(previous.name) (identical pixels).")
            note(name + "-UNCHANGED", "Identical, pixel for pixel, to \(previous.name): the step before it did not change the screen.")
        }
        lastShot = (name, png)
    }

    /// The last capture, for the changed-screen check in `shot`.
    private var lastShot: (name: String, png: Data)?

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

    /// The focusable element (button or cell) labelled `text`, never a tab-bar button (#15 item 1.3).
    /// Order: a label exactly `text`, then a label starting with `text` and a separator (", " or " "), then any label
    /// containing it. Before this, "Movies" matched the Movies TAB before the Movies folder row (so 72 showed the Movies tab
    /// and 73 was not reached), and "FTP" matched the SFTP row first (14 and 15 identical).
    func control(_ text: String, in app: XCUIApplication) -> XCUIElement {
        let tabBar = app.tabBars.firstMatch
        let tabFrame = tabBar.exists ? tabBar.frame : .null
        let predicates = [NSPredicate(format: "label == %@", text),
                          NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", text + ",", text + " "),
                          NSPredicate(format: "label CONTAINS %@", text)]
        for predicate in predicates {
            for query in [app.buttons.matching(predicate), app.cells.matching(predicate)] {
                for element in query.allElementsBoundByIndex.prefix(12) where element.exists {
                    if !tabFrame.isNull, tabFrame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) { continue }
                    return element
                }
            }
        }
        // Nothing yet (a lazy list may not have built the row): a query that `focus` can wait on while moving down.
        return app.cells.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The label of the element that has the focus now ("none" when nothing has it), for NOT-REACHED reasons.
    func focusedLabel(in app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? "“\(focused.label)”" : "none"
    }

    /// Presses Down until the focus stops moving (three presses in a row with the same focused frame) or `maxPresses`.
    /// True when the focus stopped, i.e. the end of the list was reached.
    func moveFocusToEnd(in app: XCUIApplication, maxPresses: Int = 40) -> Bool {
        var last: CGRect?
        var unmoved = 0
        for _ in 0..<maxPresses {
            XCUIRemote.shared.press(.down); usleep(400_000)
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let frame = focused.exists ? focused.frame : .null
            if frame == last { unmoved += 1; if unmoved >= 3 { return true } } else { unmoved = 0 }
            last = frame
        }
        return false
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
        guard focus(target, in: app, maxPresses: 40) else {
            notReached(name, "The focus could not be moved to “\(text)” with the remote's arrows (focus stayed on \(focusedLabel(in: app))).")
            return false
        }
        XCUIRemote.shared.press(.select)
        return true
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
        shot("01-first-launch")
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
        app.terminate()

        // 20: the types that cannot be set up yet, with their reasons, at the bottom of the list (#15 item 1.3). A fresh launch,
        // so nothing left open by the forms above can stop it; then Down until the focus stops (the Cancel row is last, the
        // "Not Available Yet" rows above it are not focusable).
        let end = launch("-UITestEmpty")
        if waitForScreen("screen.home", in: end), waitFor("Add a Source", in: end), open("Add a Source", in: end, name: "20-add-source-not-available"),
           waitFor("Type an Address", in: end) {
            if moveFocusToEnd(in: end), waitFor("Not Available Yet", in: end, timeout: 5) { settle(); shot("20-add-source-not-available") }
            else { notReached("20-add-source-not-available", "Moving down did not reach “Not Available Yet” (focus on \(focusedLabel(in: end))).") }
            // Network search last: it may ask for local-network permission, which a test cannot answer reliably.
            end.terminate()
        }
        let network = launch("-UITestEmpty")
        if waitForScreen("screen.home", in: network), waitFor("Add a Source", in: network), open("Add a Source", in: network, name: "21-search-your-network"),
           waitFor("Type an Address", in: network), open("Search Your Network", in: network, name: "21-search-your-network") {
            sleep(4); shot("21-search-your-network")
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
            if page == "Sources", open("Sample Library", in: app, name: "34-settings-source-detail") {
                settle(); shot("34-settings-source-detail"); back()
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
        // Text rows are not focusable; moving down to the licence link scrolls the page past Data Sources and Trademarks.
        for step in 1...3 {
            XCUIRemote.shared.press(.down); sleep(1)
            shot("41-about-scrolled-\(step)")
        }
        if open("Full Licence Texts", in: about, name: "42-licence-texts") {
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
            // #15 item 1.6: the scrolled states of the show page (each must differ from the one before).
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("55-show-page-scrolled-\(step)") }
            for _ in 0..<2 { XCUIRemote.shared.press(.up) }; sleep(1)
            // Seasons are sections of the show page (there is no separate season page); move down to season 2.
            if focus(control("S2", in: app), in: app) || focus(control("Season 2", in: app), in: app) { settle(); shot("56-show-season-2-episode-row") }
            else { notReached("56-show-season-2-episode-row", "Could not move the focus to a season 2 episode row.") }
        } else { hierarchy("55-show-page", of: app); notReached("55-show-page", "The show page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 1", in: app) {
            settle(); shot("57-movie-detail"); hierarchy("57-movie-detail", of: app)
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("58-movie-detail-scrolled-\(step)") }
            // Fix Match is in the More menu (ItemDetailContentView.moreMenu), not a button on the page: the old test looked for
            // it on the page and never found it (#15 item 1.3). Up to the action row first: the focus is below it after 58.
            for _ in 0..<6 { XCUIRemote.shared.press(.up) }; sleep(1)
            if open("More", in: app, name: "59-fix-match"), waitFor("Fix Match", in: app, timeout: 5), open("Fix Match", in: app, name: "59-fix-match") {
                settle(); shot("59-fix-match"); back()
            }
        } else { hierarchy("57-movie-detail", of: app); notReached("57-movie-detail", "The movie detail page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 2")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 2", in: app) {
            settle(); shot("60-movie-detail-two-versions")
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("61-movie-detail-two-versions-scrolled-\(step)") }
        } else { notReached("60-movie-detail-two-versions", "The detail page did not open.") }
        app.terminate()

        detailActionShots()

        // Pressing Play on a sample file shows the playback error screen (sample files have no video).
        app = launch("-UITestFixtures", open: "Sample Movie 5")
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 5", in: app), open("Play", in: app, name: "62-playback-error") {
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
            if open("More", in: app, name: "44-movie-more-menu"), waitFor("Mark as Watched", in: app, timeout: 5) {
                sleep(1); shot("44-movie-more-menu")
                if open("Mark as Watched", in: app, name: "45-movie-mark-watched-result") {
                    sleep(2)
                    if open("More", in: app, name: "45-movie-mark-watched-result"), waitFor("Mark as Unwatched", in: app, timeout: 5) {
                        sleep(1); shot("45-movie-mark-watched-result")
                    } else { notReached("45-movie-mark-watched-result", "After Mark as Watched, More did not offer “Mark as Unwatched”.") }
                    if open("Add to Favorites", in: app, name: "46-movie-add-favorite-result") {
                        sleep(2)
                        if open("More", in: app, name: "46-movie-add-favorite-result"), waitFor("Remove from Favorites", in: app, timeout: 5) {
                            sleep(1); shot("46-movie-add-favorite-result")
                        } else { notReached("46-movie-add-favorite-result", "After Add to Favorites, More did not offer “Remove from Favorites”.") }
                    }
                }
            }
            app.terminate()
        }

        // 47: the Versions menu open (two versions).
        if let app = openMovie("Sample Movie 2", "47-movie-versions-menu") {
            if open("Versions", in: app, name: "47-movie-versions-menu") { sleep(1); shot("47-movie-versions-menu") }
            app.terminate()
        }

        // 48: the Extras menu open.
        if let app = openMovie("Sample Movie 1", "48-movie-extras") {
            if open("Extras", in: app, name: "48-movie-extras") { sleep(1); shot("48-movie-extras") }
            app.terminate()
        }

        // 49: Start Over focused, then what selecting it shows (sample files have no video: the playback error).
        if let app = openMovie("Sample Movie 1", "49-movie-start-over") {
            if focus(control("Start Over", in: app), in: app) {
                sleep(1); shot("49-movie-start-over")
                XCUIRemote.shared.press(.select); sleep(5); shot("49-movie-start-over-result")
            } else { notReached("49-movie-start-over", "No “Start Over” button could be focused (focus on \(focusedLabel(in: app))).") }
            app.terminate()
        }
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
                    let filesTab = app.tabBars.buttons["Files"]
                    if filesTab.exists, !filesTab.isSelected {
                        notReached("72-files-folder", "After opening the Movies folder the Files tab is not selected (selected: \(app.tabBars.buttons.matching(NSPredicate(format: "isSelected == true")).firstMatch.label)).")
                    }
                    if open("Sample Movie 1 (2021)", in: app, name: "73-files-movie-folder") {
                        settle(); shot("73-files-movie-folder")
                        if open("2160p.mkv", in: app, name: "74-file-details") { settle(); shot("74-file-details") }
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
    /// #16 item 1.10 and #17 E: the rest of the set. "movie-detail-logo" is Sample Movie 2, the sample title with a title
    /// logo once #15 Part 9 gives it one (until then its page shows the text title); "settings-backup" is the Backup page
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
            guard step(app, "Add a Source") else { return nil }
            guard waitFor("Type an Address", in: app, timeout: wait) else { return fail(app, "The source type list did not open.") }
            if key == "add-source" { return app }
            return step(app, "WebDAV") ? app : nil
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
            app.terminate()
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
        guard waitForScreen("screen.movies", in: app), waitFor("Needs Review", in: app, timeout: 60) else {
            return notReached("63-movies-needs-review-button\(suffix)", "Movies showed no “Needs Review” button within 60 s.")
        }
        settle(); shot("63-movies-needs-review-button\(suffix)")
        if open("Needs Review", in: app, name: "64-needs-review\(suffix)"), waitForScreen("screen.needsReview", in: app) {
            settle(); shot("64-needs-review\(suffix)"); hierarchy("64-needs-review\(suffix)", of: app)
            for step in 1...2 { XCUIRemote.shared.press(.down); sleep(1); shot("64-needs-review-scrolled-\(step)\(suffix)") }
            if open("Sample Clip", in: app, name: "65-needs-review-choice\(suffix)") {
                settle(); shot("65-needs-review-choice\(suffix)")
                if open("Move to Shows", in: app, name: "66-move-sheet\(suffix)") { settle(); shot("66-move-sheet\(suffix)"); back() }
            }
        }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1", extra: extra)
        if waitForScreen("screen.item", in: app, timeout: 60), waitFor("Sample Movie 1", in: app) {
            if open("More", in: app, name: "67-sorted-how\(suffix)"), open("How This Was Sorted", in: app, name: "67-sorted-how\(suffix)") {
                settle(); shot("67-sorted-how\(suffix)")
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
            settle(); shot("69-source-sort-by-filename\(suffix)")
            if focus(control("Sort by Filename", in: app), in: app) { sleep(1); shot("69-source-sort-by-filename-focused\(suffix)") }
        }
        app.terminate()
    }

    func test10_SortingScreens() {
        sortingShots(suffix: "", extra: [])
        sortingShots(suffix: "-larger-text", extra: ["-UITestTextSize", "accessibility3"])
    }
}
