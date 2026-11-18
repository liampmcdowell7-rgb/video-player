import XCTest

/// Screenshots of every screen the Siri Remote can reach, for review without a device (docs/GITHUB_ACTIONS_RUNBOOK.md, job 4).
///
/// Each test launches the app in a debug-only UI-test mode (`-UITestEmpty` or `-UITestFixtures`, App/Support/UITestMode.swift):
/// a clean start, no network, and in fixtures mode a synthetic sample library. Every screenshot is an attachment kept
/// always, named "NN-name"; the workflow exports them as NN-name.png in that order.
///
/// A screen that cannot be reached does not stop the run: a text attachment "NN-name-NOT-REACHED" says why, and the test
/// goes on. Remote API: XCUIRemote (https://developer.apple.com/documentation/xcuiautomation/xcuiremote).
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: Helpers

    @discardableResult
    func launch(_ mode: String, tab: String? = nil, open: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var args = [mode]
        if let tab { args += ["-UITestTab", tab] }
        if let open { args += ["-UITestOpen", open] }
        app.launchArguments = args
        app.launch()
        return app
    }

    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func notReached(_ name: String, _ reason: String) {
        let attachment = XCTAttachment(string: reason)
        attachment.name = name + "-NOT-REACHED"
        attachment.lifetime = .keepAlways
        add(attachment)
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
    /// the focused element. Gives up after `maxPresses`.
    func focus(_ target: XCUIElement, in app: XCUIApplication, maxPresses: Int = 30) -> Bool {
        let remote = XCUIRemote.shared
        for _ in 0..<maxPresses {
            guard target.exists else { remote.press(.down); continue }
            if target.hasFocus { return true }
            let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
            guard focused.exists else { remote.press(.down); continue }
            let f = focused.frame, t = target.frame
            if t.minY >= f.maxY - 2 { remote.press(.down) }
            else if t.maxY <= f.minY + 2 { remote.press(.up) }
            else if t.midX > f.midX { remote.press(.right) }
            else { remote.press(.left) }
        }
        return target.exists && target.hasFocus
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
        sleep(1)
        shot("01-first-launch")
        if waitFor("Add a Source", in: app) { settle(); shot("02-home-empty") } else { notReached("02-home-empty", "The empty Home screen text did not appear.") }
        app.terminate()

        for (n, tab) in [("03", "movies"), ("04", "shows"), ("05", "files"), ("06", "discover"), ("07", "search")] {
            let a = launch("-UITestEmpty", tab: tab)
            sleep(4)
            shot("\(n)-\(tab)-empty")
            a.terminate()
        }
    }

    func test02_AddASource() {
        let app = launch("-UITestEmpty")
        guard waitFor("Add a Source", in: app), open("Add a Source", in: app, name: "10-add-source-types") else { return }
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
        guard waitFor("Playback", in: app) else { return notReached("30-settings", "Settings did not open.") }
        settle()
        shot("30-settings")
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
        if waitFor("Sample", in: app, timeout: 60) { settle(); shot("50-home-rows"); XCUIRemote.shared.press(.down); sleep(1); shot("51-home-rows-lower") }
        else { notReached("50-home-rows", "No sample title appeared on Home within 60 s (the sample library did not load).") }
        // The card long-press menu on the focused Home card.
        XCUIRemote.shared.press(.select, forDuration: 1.5)
        sleep(1)
        shot("52-card-long-press-menu")
        app.terminate()

        for (n, tab) in [("53", "movies"), ("54", "shows")] {
            app = launch("-UITestFixtures", tab: tab)
            if waitFor("Sample", in: app, timeout: 60) { settle(); shot("\(n)-\(tab)") } else { notReached("\(n)-\(tab)", "No sample title appeared.") }
            app.terminate()
        }

        app = launch("-UITestFixtures", open: "Sample Show 1")
        if waitFor("Season 1", in: app, timeout: 60) {
            settle(); shot("55-show-page")
            // Seasons are sections of the show page (there is no separate season page); move down to season 2.
            if focus(control("S2", in: app), in: app) || focus(control("Season 2", in: app), in: app) { settle(); shot("56-show-season-2-episode-row") }
            else { notReached("56-show-season-2-episode-row", "Could not move the focus to a season 2 episode row.") }
        } else { notReached("55-show-page", "The show page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 1")
        if waitFor("Sample Movie 1", in: app, timeout: 60) {
            settle(); shot("57-movie-detail")
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("58-movie-detail-scrolled-\(step)") }
            if open("Fix Match", in: app, name: "59-fix-match") { settle(); shot("59-fix-match"); back() }
        } else { notReached("57-movie-detail", "The movie detail page did not open.") }
        app.terminate()

        app = launch("-UITestFixtures", open: "Sample Movie 2")
        if waitFor("Sample Movie 2", in: app, timeout: 60) {
            settle(); shot("60-movie-detail-two-versions")
            for step in 1...3 { XCUIRemote.shared.press(.down); sleep(1); shot("61-movie-detail-two-versions-scrolled-\(step)") }
        } else { notReached("60-movie-detail-two-versions", "The detail page did not open.") }
        app.terminate()

        // Pressing Play on a sample file shows the playback error screen (sample files have no video).
        app = launch("-UITestFixtures", open: "Sample Movie 5")
        if waitFor("Sample Movie 5", in: app, timeout: 60), open("Play", in: app, name: "62-playback-error") {
            sleep(5); shot("62-playback-error")
        }
        app.terminate()
    }

    func test05_FilesSearchDiscover() {
        var app = launch("-UITestFixtures", tab: "files")
        if waitFor("Sample Library", in: app, timeout: 60) {
            settle(); shot("70-files-sources")
            if open("Sample Library", in: app, name: "71-files-root") {
                settle(); shot("71-files-root")
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
        sleep(4)
        shot("75-search-prompt")
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 10), focus(field, in: app) {
            // Select opens the on-screen keyboard; typing then goes to the field that has keyboard focus.
            XCUIRemote.shared.press(.select)
            sleep(2)
            app.typeText("Sample")
            sleep(3)
            shot("76-search-results")
        } else {
            notReached("76-search-results", "No search field was found to type into.")
        }
        app.terminate()

        app = launch("-UITestFixtures", tab: "discover")
        sleep(4)
        shot("77-discover-no-key")
        notReached("78-discover-results", "Discover results need an online lookup key and the network; UI-test mode makes no network calls.")
        notReached("79-top-shelf", "The Top Shelf is part of the Home Screen, not the app; a UI test of this app cannot open it.")
        app.terminate()
    }
}
