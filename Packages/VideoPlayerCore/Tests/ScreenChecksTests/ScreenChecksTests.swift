import XCTest
import Foundation
@testable import ScreenChecks

/// #33 B, C, G, L, N (2): every check the screenshot UI tests run, proven here on Linux. Each must PASS on a right screen
/// and FAIL on a wrong one. Fixtures/ holds two accessibility notes of the CI run of 20 Nov on b0093d2 (10-add-source-types
/// and 74-file-details, the query-chain tail removed). The pictures of that run are too large to keep in the repository:
/// the tests marked "run artifacts" read them from the folder named by VP_RUN_ARTIFACTS (the unzipped artifacts:
/// screenshots/, screenshots-library/, …) and are SKIPPED, with that reason, when it is not set.
final class ScreenChecksTests: XCTestCase {
    // MARK: Fixtures

    func fixture(_ name: String) throws -> AccessibilityDump {
        let url: URL = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return AccessibilityDump(try String(contentsOf: url, encoding: .utf8))
    }

    /// A fixture's text, as written by the UI tests.
    func fixtureText(_ name: String) throws -> String {
        let url: URL = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func artifact(_ path: String) throws -> URL {
        guard let root = ProcessInfo.processInfo.environment["VP_RUN_ARTIFACTS"], !root.isEmpty else {
            throw XCTSkip("VP_RUN_ARTIFACTS is not set: the CI run's pictures are not on this machine")
        }
        let url: URL = URL(fileURLWithPath: root).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(path) is not in \(root)") }
        return url
    }

    func picture(_ path: String) throws -> RGBImage {
        try PNGDecoder.decode([UInt8](try Data(contentsOf: try artifact(path))))
    }

    // MARK: The accessibility dump

    func testTheDumpOfTheRunIsReadWithFramesLabelsAndTheTwoTopLevelSubtrees() throws {
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let window: Int = try XCTUnwrap(dump.window)
        XCTAssertEqual(dump.nodes[window].frame, AXRect(x: 0, y: 0, width: 1920, height: 1080))
        let home: Int = try XCTUnwrap(dump.first(identifier: "screen.home"))
        XCTAssertEqual(dump.nodes[home].type, "StaticText")
        XCTAssertEqual(dump.nodes[home].label, "Home")
        let cover: Int = try XCTUnwrap(dump.coverRoot)
        let page: Int = try XCTUnwrap(dump.pageRoot)
        XCTAssertNotEqual(cover, page)
        XCTAssertTrue(dump.descendants(of: page).contains(home))
        XCTAssertFalse(dump.descendants(of: cover).contains(home))
        let focused: [AXNode] = dump.nodes.filter(\.isFocused)
        XCTAssertEqual(focused.first?.label, "Search Your Network")
    }

    func testALabelWithAQuoteOrACommaIsReadWhole() {
        let node: AXNode? = AccessibilityDump.parse("      StaticText, 0x1, {{1.0, 2.0}, {3.0, 4.0}}, label: 'It's here, 2 items', value: 3")
        XCTAssertEqual(node?.label, "It's here, 2 items")
        XCTAssertEqual(node?.depth, 6)
        XCTAssertNil(AccessibilityDump.parse("Attributes: Application, 0x1, pid: 1"))
    }

    // MARK: C: the full-screen row check (test02, test06, test11)

    func testTheRowCheckMeasuresTheCellAroundTheAnchorAndPassesOnTheRunsAddASourcePage() throws {
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let result: CheckResult = ScreenRules.fullScreenRow(in: dump, anchor: "control.searchYourNetwork")
        XCTAssertTrue(result.passed, result.text)
        XCTAssertTrue(result.text.contains("Cell around “control.searchYourNetwork”: width 1174 of window 1920"), result.text)
    }

    /// #33 C: test02/06/11 anchor the form check on Cancel. In the run's note 10 the Cancel button has NO Cell (a 0-wide
    /// button in an Other 1174 wide); the old check read the button's own label (90 of 1920 in note
    /// 111-default-source-form-PRESENTATION) and failed every form. The container is measured now.
    func testTheCancelRowIsMeasuredByItsContainerNotByItsLabel() throws {
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let result: CheckResult = ScreenRules.fullScreenRow(in: dump, anchor: "control.sourceCancel")
        XCTAssertTrue(result.passed, result.text)
        XCTAssertTrue(result.text.contains("width 1174 of window 1920"), result.text)
        // The old rule (the label's own width) on the same element: 0 here, 90 in the run's note 111. Below half the window.
        let element: Int = try XCTUnwrap(dump.first(identifier: "control.sourceCancel"))
        XCTAssertLessThan(dump.nodes[element].frame?.width ?? 0, 960)
    }

    /// #33 B (2): with the page hidden from accessibility, the cover can be the window's only subtree.
    func testALoneSubtreeWithoutATabBarIsTheCover() {
        let dump: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x5, {{393.0, 66.0}, {270.0, 69.0}}, label: 'File Details'
        """)
        XCTAssertNotNil(dump.coverRoot)
        XCTAssertTrue(ScreenRules.coverLayout(in: dump).passed, ScreenRules.coverLayout(in: dump).text)
        let page: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
                TabBar, 0x6, {{0.0, 46.0}, {1920.0, 68.0}}
        """)
        XCTAssertNil(page.coverRoot)
    }

    /// #34 2: the cover must stay in the tree while the page is hidden: passes on the run's 10 and 74 notes and on a lone
    /// cover, fails when the window has nothing (everything hidden) or only an unlabelled cover.
    func testTheCoverMustStayExposedWhileThePageIsHidden() throws {
        XCTAssertTrue(ScreenRules.coverExposed(in: try fixture("10-add-source-types-HIERARCHY")).passed)
        XCTAssertTrue(ScreenRules.coverExposed(in: try fixture("74-file-details-HIERARCHY")).passed)
        let lone: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x5, {{393.0, 66.0}, {270.0, 69.0}}, label: 'File Details'
        """)
        XCTAssertTrue(ScreenRules.coverExposed(in: lone).passed)
        let empty: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
        """)
        XCTAssertEqual(ScreenRules.coverExposed(in: empty).lines.last, "COVER HIDDEN FROM ACCESSIBILITY")
        let blank: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
        """)
        XCTAssertFalse(ScreenRules.coverExposed(in: blank).passed)
    }

    func testTheRowCheckFailsOnANarrowSheetAndOnAMissingAnchor() {
        let narrow: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                Table, 0x5, {{660.0, 200.0}, {600.0, 700.0}}
                  Cell, 0x6, {{660.0, 600.0}, {600.0, 66.0}}
                    Button, 0x7, {{680.0, 615.0}, {90.0, 35.0}}, identifier: 'control.sourceCancel', label: 'Cancel'
        """)
        let small: CheckResult = ScreenRules.fullScreenRow(in: narrow, anchor: "control.sourceCancel")
        XCTAssertFalse(small.passed, small.text)
        XCTAssertTrue(small.text.contains("width 600 of window 1920"), small.text)
        XCTAssertFalse(ScreenRules.fullScreenRow(in: narrow, anchor: "control.nothing").passed)
    }

    // MARK: B (2): the page behind the cover is hidden from VoiceOver

    func testThePageBehindTheCoverIsReportedExposedInBothNotesOfTheRun() throws {
        let add: CheckResult = ScreenRules.pageHiddenBehindCover(in: try fixture("10-add-source-types-HIERARCHY"))
        XCTAssertFalse(add.passed, add.text)
        XCTAssertTrue(add.text.contains("screen.home"), add.text)
        let details: CheckResult = ScreenRules.pageHiddenBehindCover(in: try fixture("74-file-details-HIERARCHY"))
        XCTAssertFalse(details.passed, details.text)
        XCTAssertTrue(details.text.contains("screen.folder"), details.text)
        // #36 8 T3: the note names the element's type and frame (74-file-details-HIERARCHY line 20).
        XCTAssertTrue(details.text.contains("screen.folder: StaticText"), details.text)
    }

    func testAPageHiddenBehindTheCoverPasses() {
        let dump: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x5, {{393.0, 66.0}, {270.0, 69.0}}, label: 'File Details'
        """)
        XCTAssertTrue(ScreenRules.pageHiddenBehindCover(in: dump).passed)
    }

    // MARK: A: the cover's own layout

    func testTheCoverTitleStartsInTheSafeAreaAndTheRowsDoNotOverlapInTheRunsNotes() throws {
        for name in ["10-add-source-types-HIERARCHY", "74-file-details-HIERARCHY"] {
            let result: CheckResult = ScreenRules.coverLayout(in: try fixture(name))
            XCTAssertTrue(result.passed, "\(name): \(result.text)")
        }
        XCTAssertTrue(ScreenRules.coverLayout(in: try fixture("74-file-details-HIERARCHY")).text.contains("“File Details” starts at y 66"))
    }

    func testOverlappingRowsAndATitleAboveTheSafeAreaFail() {
        let dump: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x5, {{80.0, 20.0}, {400.0, 69.0}}, label: 'Move to Shows'
                Cell, 0x6, {{1000.0, 100.0}, {820.0, 80.0}}, label: 'Title'
                Cell, 0x7, {{1000.0, 150.0}, {820.0, 80.0}}, label: 'Year'
        """)
        let result: CheckResult = ScreenRules.coverLayout(in: dump)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.text.contains("TITLE ABOVE THE SAFE AREA"), result.text)
        XCTAssertTrue(result.text.contains("rows overlap: “Title”") && result.text.contains(" and “Year”"), result.text)
    }

    /// #36 group 1 b: a picture taken after scrolling or after moving the focus down (20-add-source-not-available: "FTP…" at
    /// y -117) skips the safe-area title rule and says which rule and why; the overlap rule still runs.
    func testAScrolledPictureSkipsOnlyTheSafeAreaTitleRule() {
        let dump: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x5, {{393.0, -117.0}, {300.0, 35.0}}, label: 'FTP'
                Cell, 0x6, {{1000.0, 300.0}, {820.0, 80.0}}, label: 'Title'
                Cell, 0x7, {{1000.0, 400.0}, {820.0, 80.0}}, label: 'Year'
        """)
        XCTAssertFalse(ScreenRules.coverLayout(in: dump).passed)
        let skipped: CheckResult = ScreenRules.coverLayout(in: dump, scrolled: "moving the focus down the list to Cancel")
        XCTAssertTrue(skipped.passed, skipped.text)
        XCTAssertTrue(skipped.text.contains("safe-area title rule SKIPPED") && skipped.text.contains("moving the focus down"), skipped.text)
        let overlapping: AccessibilityDump = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x5, {{393.0, -117.0}, {300.0, 35.0}}, label: 'FTP'
                Cell, 0x6, {{1000.0, 100.0}, {820.0, 80.0}}, label: 'Title'
                Cell, 0x7, {{1000.0, 150.0}, {820.0, 80.0}}, label: 'Year'
        """)
        XCTAssertFalse(ScreenRules.coverLayout(in: overlapping, scrolled: "scrolling").passed)
    }

    /// #36 8 T2: a field whose frame reaches up to 6 pt past its row on every side is nesting, not overlap (66 and the Saved
    /// View cover in the second run of 20 Nov); 7 pt past, or two rows sharing 30 pt of height, is still overlap.
    func testAFieldAFewPointsPastItsRowIsNotAnOverlapButTwoRowsAre() {
        func cover(_ rows: String) -> AccessibilityDump {
            AccessibilityDump("""
             →Application, 0x1, pid: 1, label: 'Video Player'
                Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
                  Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
                  Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
                    StaticText, 0x5, {{80.0, 66.0}, {400.0, 69.0}}, label: 'Move to Shows'
            \(rows)
            """)
        }
        let nested: CheckResult = ScreenRules.coverLayout(in: cover("""
                Cell, 0x6, {{80.0, 300.0}, {1760.0, 80.0}}, label: 'Year (Optional)'
                TextField, 0x7, {{1000.0, 296.0}, {846.0, 88.0}}
        """))
        XCTAssertTrue(nested.passed, nested.text)
        let past: CheckResult = ScreenRules.coverLayout(in: cover("""
                Cell, 0x6, {{80.0, 300.0}, {1760.0, 80.0}}, label: 'Year (Optional)'
                TextField, 0x7, {{1000.0, 293.0}, {846.0, 88.0}}
        """))
        XCTAssertFalse(past.passed, past.text)
        let rows: CheckResult = ScreenRules.coverLayout(in: cover("""
                Cell, 0x6, {{80.0, 300.0}, {1760.0, 80.0}}, label: 'Title'
                Cell, 0x7, {{80.0, 350.0}, {1760.0, 80.0}}, label: 'Year'
        """))
        XCTAssertFalse(rows.passed, rows.text)
        XCTAssertTrue(rows.text.contains("rows overlap: “Title”"), rows.text)
    }

    // MARK: C: the menu check (test16)

    /// The run's log (screenshots-library-logs/test.log, test 44 at t = 247 s): with the More menu open, "Mark as Watched"
    /// was matched only by "cells containing label == …" and resolved to "Cell at {{769.0, 583.4}, {416.0, 67.3}}": a tvOS
    /// menu item is a Cell with NO label of its own, its text on a StaticText inside. No tree of an open menu was written in
    /// that run, so this dump is BUILT from that evidence (cell frames spaced as in the log), not copied.
    static let openSortMenu: String = """
     →Application, 0x1, pid: 1, label: 'Video Player'
        Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
          Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
            Button, 0x10, {{80.0, 157.0}, {102.0, 68.0}}, identifier: 'control.sort', label: 'Sort', value: Title, A to Z
            Button, 0x11, {{80.0, 300.0}, {320.0, 480.0}}, label: 'Sample Show 1'
            TabBar, 0x12, {{0.0, 46.0}, {1920.0, 68.0}}, label: 'Menu'
              Button, 0x13, {{406.5, 61.5}, {125.0, 37.0}}, identifier: 'house', label: 'Home'
          Other, 0x4, {{0.0, 0.0}, {1920.0, 1080.0}}
            Cell, 0x20, {{80.0, 245.0}, {416.0, 67.3}}
              StaticText, 0x21, {{100.0, 260.0}, {80.0, 35.0}}, label: 'Title'
            Cell, 0x22, {{80.0, 312.3}, {416.0, 67.3}}
              StaticText, 0x23, {{100.0, 327.0}, {80.0, 35.0}}, label: 'Year'
            Cell, 0x24, {{80.0, 379.6}, {416.0, 67.3}}
              StaticText, 0x25, {{100.0, 394.0}, {150.0, 35.0}}, label: 'Date Added'
    """

    static let closedToolbar: String = """
     →Application, 0x1, pid: 1, label: 'Video Player'
        Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
          Other, 0x3, {{0.0, 0.0}, {1920.0, 1080.0}}
            Button, 0x10, {{80.0, 157.0}, {102.0, 68.0}}, identifier: 'control.sort', label: 'Sort', value: Title, A to Z
            Button, 0x11, {{80.0, 300.0}, {320.0, 480.0}}, label: 'Sample Show 1'
            TabBar, 0x12, {{0.0, 46.0}, {1920.0, 68.0}}, label: 'Menu'
              Button, 0x13, {{406.5, 61.5}, {125.0, 37.0}}, identifier: 'house', label: 'Home'
    """

    func testMenuItemsAreTheNewCellsReadByTheirTextAndThreeOfThemPass() {
        let before: Set<String> = ScreenRules.labels(in: AccessibilityDump(Self.closedToolbar))
        XCTAssertEqual(before, ["Sort", "Sample Show 1"])
        let items = ScreenRules.menuItems(in: AccessibilityDump(Self.openSortMenu), before: before, ignoringIdentifiers: ["control.sort"])
        XCTAssertEqual(items.map(\.0), ["Title", "Year", "Date Added"])
        let result: CheckResult = ScreenRules.menu(items: items, expected: ["Title", "Year", "Date Added"], windowMaxY: 1080)
        XCTAssertTrue(result.passed, result.text)
    }

    /// #36 8 T1: the run's own tree of the open Sort menu (fixture 07-movies-toolbar-sort-menu-HIERARCHY, second run of
    /// 20 Nov, where the note said "MENU PROBLEM: 0 menu items found"): every item is a Cell whose name sits on an `Other`,
    /// with no StaticText. The items are found now; with the names taken out of the tree the check still fails.
    func testTheRunsOpenSortMenuTreeHasItsItemsOnOtherElements() throws {
        let tree: String = try fixtureText("07-movies-toolbar-sort-menu-HIERARCHY")
        let dump: AccessibilityDump = AccessibilityDump(tree)
        // #33 C's rule (own label, else first StaticText) found no Cell in this tree.
        let byStaticText: [Int] = dump.nodes.indices.filter { (i: Int) -> Bool in
            dump.nodes[i].type == "Cell" && dump.descendants(of: i).contains { (c: Int) -> Bool in dump.nodes[c].type == "StaticText" && !dump.nodes[c].label.isEmpty }
        }
        XCTAssertEqual(byStaticText.count, 0)
        // What was on screen before the menu opened: the page's buttons (the cards), as `controlLabels` reads them.
        let before: Set<String> = Set(dump.nodes.filter { (n: AXNode) -> Bool in n.type == "Button" }.map { (n: AXNode) -> String in n.label })
        let items: [(String, AXRect)] = ScreenRules.menuItems(in: dump, before: before, ignoringIdentifiers: ["control.sort"])
        let cells: [String] = items.map { (item: (String, AXRect)) -> String in item.0 }
        XCTAssertTrue(cells.contains("Title") && cells.contains("Year") && cells.contains("Rating") && cells.contains("Date Added"), "\(cells)")
        XCTAssertFalse(cells.contains("selected"), "the checkmark Image is not an item: \(cells)")
        let result: CheckResult = ScreenRules.menu(items: items, expected: ["Title", "Year", "Date Added"], windowMaxY: 1080)
        XCTAssertTrue(result.passed, result.text)

        // Wrong fixture: the same tree without the items' names (as the menu would be if its items were unnamed).
        var stripped: String = tree
        for name in ["Title", "Year", "Rating", "Date Added"] { stripped = stripped.replacingOccurrences(of: ", label: '\(name)'", with: "") }
        let none: [(String, AXRect)] = ScreenRules.menuItems(in: AccessibilityDump(stripped), before: before, ignoringIdentifiers: ["control.sort"])
        let failed: CheckResult = ScreenRules.menu(items: none, expected: ["Title", "Year", "Date Added"], windowMaxY: 1080)
        XCTAssertFalse(failed.passed, failed.text)
        XCTAssertTrue(failed.text.contains("no item “Title”"), failed.text)
    }

    func testTheOldRuleThatReadOnlyOwnLabelsFindsNoItemAndAMenuCutAtTheBottomFails() {
        let dump: AccessibilityDump = AccessibilityDump(Self.openSortMenu)
        // What #32 counted: elements with a label of their own. The run's notes said "0 menu items found".
        let ownLabels: [AXNode] = dump.nodes.filter { ["Cell", "MenuItem"].contains($0.type) && !$0.label.isEmpty }
        XCTAssertEqual(ownLabels.count, 0)
        let cut: [(String, AXRect)] = [("Title", AXRect(x: 80, y: 900, width: 416, height: 67)),
                                       ("Year", AXRect(x: 80, y: 967, width: 416, height: 67)),
                                       ("Date Added", AXRect(x: 80, y: 1034, width: 416, height: 67))]
        let result: CheckResult = ScreenRules.menu(items: cut, expected: ["Title"], windowMaxY: 1080)
        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.text.contains("“Date Added” ends at 1101, below the window"), result.text)
        XCTAssertFalse(ScreenRules.menu(items: Array(cut.prefix(2)), expected: [], windowMaxY: 1080).passed)
    }

    // MARK: G: toolbar groups

    func testTheRunsToolbarFramesFailTheTwoTimesRuleAndTheNewSpacingPassesIt() {
        // 07-movies-toolbar-GROUPS of the run: Sort, Filter, Saved Views 60 apart; Needs Review 76 after Saved Views.
        let first: [(String, AXRect)] = [("Sort", AXRect(x: 80, y: 157, width: 102, height: 68)),
                                         ("Filter", AXRect(x: 242, y: 157, width: 96, height: 68)),
                                         ("Saved Views", AXRect(x: 398, y: 157, width: 90, height: 68))]
        let run: CheckResult = ScreenRules.toolbarGroups(first: first, second: [("Needs Review", AXRect(x: 564, y: 158, width: 336, height: 66))])
        XCTAssertFalse(run.passed, run.text)
        XCTAssertTrue(run.text.contains("gap inside group 60, gap between groups 76"), run.text)
        // #33 G: 140 pt between the groups, 2.33 times the 60 pt gap inside a group (replaced in #34 by 100 and 48, below).
        // #36 6: the ratio is met, but the run's symbols (102, 96, 90 pt) are not one size and Needs Review is 2 pt lower.
        let fixed: CheckResult = ScreenRules.toolbarGroups(first: first, second: [("Needs Review", AXRect(x: 488 + 140, y: 158, width: 336, height: 66))])
        XCTAssertFalse(fixed.passed, fixed.text)
        XCTAssertFalse(fixed.text.contains("is not at least"), fixed.text)
        XCTAssertTrue(fixed.text.contains("icon controls not the same size: widths [102, 96, 90]"), fixed.text)
        // Larger Text of the run: 60 inside, 76 between; fails the same way.
        let larger: [(String, AXRect)] = [("Sort", AXRect(x: 80, y: 157, width: 125, height: 87)),
                                          ("Filter", AXRect(x: 265, y: 157, width: 114, height: 87)),
                                          ("Saved Views", AXRect(x: 439, y: 157, width: 107, height: 87))]
        XCTAssertFalse(ScreenRules.toolbarGroups(first: larger, second: [("Needs Review", AXRect(x: 622, y: 158, width: 476, height: 85))]).passed)
        XCTAssertFalse(ScreenRules.toolbarGroups(first: larger, second: [("Needs Review", AXRect(x: 546 + 140, y: 158, width: 476, height: 85))]).passed)
    }

    /// #36 6 (R258): the row #36 asks for: three symbol controls of one size, the gaps inside both groups equal, the text
    /// controls of the symbols' height, the groups 100 pt apart. Default size and Larger Text, from the run's widths
    /// (the widest symbol, 102 and 125 pt) and the GridToolbarLayout numbers.
    func equalToolbar(icon: Double, height: Double, texts: [(String, Double)], inGroup: Double, groupGap: Double) -> ([(String, AXRect)], [(String, AXRect)]) {
        var x: Double = 80
        var first: [(String, AXRect)] = []
        for name in ["Sort", "Filter", "Saved Views"] {
            first.append((name, AXRect(x: x, y: 157, width: icon, height: height)))
            x += icon + inGroup
        }
        x += groupGap - inGroup
        var second: [(String, AXRect)] = []
        for (name, width) in texts {
            second.append((name, AXRect(x: x, y: 157, width: width, height: height)))
            x += width + inGroup
        }
        return (first, second)
    }

    func testEqualSymbolControlsAndEqualGapsPassTheGroupsCheck() {
        for (icon, height, texts) in [(102.0, 68.0, [("Needs Review", 336.0), ("Jump to Letter", 317.0)]),
                                      (125.0, 87.0, [("Needs Review", 476.0), ("Jump to Letter", 448.0)])] {
            let (first, second) = equalToolbar(icon: icon, height: height, texts: texts, inGroup: 40, groupGap: 100)
            let result: CheckResult = ScreenRules.toolbarGroups(first: first, second: second)
            XCTAssertTrue(result.passed, result.text)
        }
    }

    /// #36 6: the check fails on the uneven rows: the run's own notes (07-*-GROUPS of the run of 20 Nov: symbols 102, 96 and
    /// 90 pt wide, text controls 66 pt beside 68), one symbol 2 pt wider, and unequal gaps between the groups' items.
    func testUnevenToolbarRowsFailTheGroupsCheck() throws {
        for note in ["07-movies-toolbar-GROUPS", "07-movies-toolbar-larger-text-GROUPS"] {
            let frames: [(String, AXRect)] = try groupsNote(note)
            let result: CheckResult = ScreenRules.toolbarGroups(first: Array(frames.prefix(3)), second: Array(frames.suffix(2)))
            XCTAssertFalse(result.passed, result.text)
            XCTAssertTrue(result.text.contains("icon controls not the same size"), "\(note): \(result.text)")
            XCTAssertTrue(result.text.contains("text controls not the symbols' height"), "\(note): \(result.text)")
        }
        let texts: [(String, Double)] = [("Needs Review", 336), ("Jump to Letter", 317)]
        var (first, second) = equalToolbar(icon: 102, height: 68, texts: texts, inGroup: 40, groupGap: 100)
        first[1].1 = AXRect(x: first[1].1.x, y: 157, width: 104, height: 68)
        XCTAssertTrue(ScreenRules.toolbarGroups(first: first, second: second).text.contains("icon controls not the same size"))
        (first, second) = equalToolbar(icon: 102, height: 68, texts: texts, inGroup: 40, groupGap: 100)
        second[1].1 = AXRect(x: second[1].1.x + 20, y: 157, width: 317, height: 68)
        let gaps: CheckResult = ScreenRules.toolbarGroups(first: first, second: second)
        XCTAssertFalse(gaps.passed, gaps.text)
        XCTAssertTrue(gaps.text.contains("gaps inside the groups not equal: [40, 40] and [60]"), gaps.text)
    }

    /// The frames of one 07-*-GROUPS note of the run, in note order ("Label<TAB>(x, y, width, height)").
    func groupsNote(_ name: String) throws -> [(String, AXRect)] {
        let url: URL = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures"))
        let text: String = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").compactMap { (line: Substring) -> (String, AXRect)? in
            let parts: [Substring] = line.split(separator: "\t")
            guard parts.count == 2, parts[1].hasPrefix("(") else { return nil }
            let numbers: [Double] = parts[1].dropFirst().dropLast().split(separator: ",").compactMap { (n: Substring) -> Double? in
                Double(n.trimmingCharacters(in: .whitespaces))
            }
            guard numbers.count == 4 else { return nil }
            return (String(parts[0]), AXRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3]))
        }
    }

    /// A `static let name: CGFloat = N` of App/Shared/GridToolbar.swift, so this test follows the app's numbers.
    func toolbarConstant(_ name: String) throws -> Double {
        // As AttributionNoticeTests: VP_PROJECT_ROOT (scripts/test-core.sh copies only the package), else up from this file.
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent("App/Shared/GridToolbar.swift"))
        }
        let up: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(up.appendingPathComponent("App/Shared/GridToolbar.swift"))
        guard let found = candidates.first(where: { (url: URL) -> Bool in FileManager.default.fileExists(atPath: url.path) }) else {
            #if os(Linux)
            XCTFail("App/Shared/GridToolbar.swift not found (tried \(candidates.map(\.path))). Set VP_PROJECT_ROOT.")
            return 0
            #else
            throw XCTSkip("App/Shared/GridToolbar.swift is not readable from this test host (tried \(candidates.map(\.path))).")
            #endif
        }
        let source: String = try String(contentsOf: found, encoding: .utf8)
        let marker: String = "static let \(name): CGFloat = "
        let line: Substring = try XCTUnwrap(source.split(separator: "\n").first { (l: Substring) -> Bool in l.contains(marker) }, name)
        let value: Substring = try XCTUnwrap(line.components(separatedBy: marker).last.map { Substring($0) }, name)
        return try XCTUnwrap(Double(value.trimmingCharacters(in: .whitespaces)), name)
    }

    /// #34 5a: an app source file (VP_PROJECT_ROOT, else up from this file), as `toolbarConstant`.
    func appSource(_ relative: String) throws -> String? {
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent(relative))
        }
        let up: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(up.appendingPathComponent(relative))
        guard let found = candidates.first(where: { (url: URL) -> Bool in FileManager.default.fileExists(atPath: url.path) }) else {
            #if os(Linux)
            XCTFail("\(relative) not found (tried \(candidates.map(\.path))). Set VP_PROJECT_ROOT.")
            return nil
            #else
            throw XCTSkip("\(relative) is not readable from this test host (tried \(candidates.map(\.path))).")
            #endif
        }
        return try String(contentsOf: found, encoding: .utf8)
    }

    /// The text between the brace that opens after `start` (first `{` at or after it) and its matching `}`.
    static func braceBody(of source: String, after start: String.Index) -> Substring? {
        guard let open = source[start...].firstIndex(of: "{") else { return nil }
        var depth: Int = 0
        var i: String.Index = open
        while i < source.endIndex {
            let c: Character = source[i]
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1; if depth == 0 { return source[source.index(after: open)..<i] } }
            i = source.index(after: i)
        }
        return nil
    }

    /// #34 5a (R229): the wide (Continue Watching) card's title is inside the label closure of its NavigationLink, so the
    /// whole lockup takes the focus; the portrait cards keep the title outside (unchanged). Structure only. #36 group 1 d:
    /// the third run of 20 Nov showed that nothing scrolls a long caption, so 50-home-continue-watching-caption(-later) now
    /// checks that the pair is identical AND the caption whole (ScreenRules.stillAndWhole).
    func testTheContinueWatchingCaptionIsInsideTheFocusedButton() throws {
        guard let source = try appSource("App/Shared/PosterCard.swift") else { return }
        let body: String = String(try XCTUnwrap(source.range(of: "var body: some View").map { source[$0.lowerBound...] }))
        let wideStart: String.Index = try XCTUnwrap(body.range(of: "if wide {")?.lowerBound, "no `if wide {` branch")
        let wideBranch: Substring = try XCTUnwrap(Self.braceBody(of: body, after: wideStart), "the wide branch")
        let wideText: String = String(wideBranch)
        let linkStart: String.Index = try XCTUnwrap(wideText.range(of: "NavigationLink(")?.lowerBound, "no NavigationLink in the wide branch")
        let label: Substring = try XCTUnwrap(Self.braceBody(of: wideText, after: linkStart), "the NavigationLink label")
        // #36 7 (R259): the title (`CardCaption`, one caption line high), the second lines and the highlight on the artwork,
        // all inside the label.
        XCTAssertTrue(label.contains("CardCaption(text: card.title)"),
                      "the Continue Watching title is not inside the button's label:\n\(label)")
        XCTAssertTrue(label.contains("secondLines"), "the Continue Watching second lines are not inside the button's label:\n\(label)")
        XCTAssertTrue(label.contains(".hoverEffect(.highlight)"), "no highlight on the Continue Watching artwork:\n\(label)")
        XCTAssertTrue(wideText.contains(".buttonStyle(.borderless)"), "the wide card is not Apple's borderless lockup")

        // The check itself: the old layout (title after the button) fails it.
        let old: String = "if wide { NavigationLink(value: x) { artwork } .buttonStyle(.card) FittingText(card.title, style: .caption, fadesAtRest: wide) }"
        let oldBranch: String = String(try XCTUnwrap(Self.braceBody(of: old, after: old.startIndex)))
        let oldLabel: Substring = try XCTUnwrap(Self.braceBody(of: oldBranch, after: try XCTUnwrap(oldBranch.range(of: "NavigationLink(")?.lowerBound)))
        XCTAssertFalse(oldLabel.contains("FittingText(card.title"), "the brace matcher must see the old title outside the label")
    }

    /// #36 7 (R259): the episode card's artwork sets the card's width inside the button's label (Apple's media catalog
    /// sample), carries the highlight, and the caption is `CardCaption`. The layout of #34 (the frame only on the button,
    /// which gave S2 E3 378 x 566 beside 410 x 615 in picture 55) fails the same check.
    func testTheEpisodeCardsArtworkSetsItsSizeInsideTheLabel() throws {
        guard let source = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        func labelOfEpisodeCard(_ text: String) throws -> String {
            let card: String.Index = try XCTUnwrap(text.range(of: "struct EpisodeCard")?.lowerBound, "no EpisodeCard")
            let link: String.Index = try XCTUnwrap(text[card...].range(of: "NavigationLink(")?.lowerBound, "no NavigationLink")
            return String(try XCTUnwrap(Self.braceBody(of: text, after: link), "the label"))
        }
        let label: String = try labelOfEpisodeCard(source)
        XCTAssertTrue(label.contains(".containerRelativeFrame(.horizontal, count: 4, spacing: 40)"), "the artwork does not set the width:\n\(label)")
        XCTAssertTrue(label.contains(".hoverEffect(.highlight)"), "no highlight on the episode artwork:\n\(label)")
        XCTAssertTrue(source.contains("CardCaption(text: episode.code"), "the episode title is not a CardCaption")

        let old: String = """
        private struct EpisodeCard: View { var body: some View { NavigationLink(value: x) { VStack { ArtworkView(key: k).overlay { p }
        captions } } .buttonStyle(.borderless) } }
        // in the shelf: EpisodeCard(episode: e).containerRelativeFrame(.horizontal, count: 4, spacing: 40)
        """
        let oldLabel: String = try labelOfEpisodeCard(old)
        XCTAssertFalse(oldLabel.contains(".containerRelativeFrame("), "the #34 card must fail: its frame was outside the label")
        XCTAssertFalse(oldLabel.contains(".hoverEffect(.highlight)"))
    }

    /// #34 3: the full toolbar row at Larger Text, from the run's notes. #36 6: every symbol control as wide as the widest
    /// (the row the app now lays out). The count's width is not in the notes: its glyphs
    /// were measured on the pictures (07-movies-toolbar-larger-text: x 1666 to 1836, 171 pt; shows 1677 to 1835, 159 pt;
    /// default size 1726 to 1837 and 1735 to 1837), plus 8 pt for the text's side bearings.
    func testTheToolbarRowFitsAtLargerTextWithTheseGaps() throws {
        let inGroup: Double = try toolbarConstant("inGroup")
        let groupGap: Double = try toolbarConstant("groupGap")
        let countGap: Double = try toolbarConstant("countGap")
        let cases: [(String, Double)] = [("07-movies-toolbar-larger-text-GROUPS", 171 + 8), ("07-shows-toolbar-larger-text-GROUPS", 159 + 8),
                                         ("07-movies-toolbar-GROUPS", 112 + 8), ("07-shows-toolbar-GROUPS", 103 + 8)]
        for (note, count) in cases {
            let frames: [AXRect] = try groupsNote(note).map { (item: (String, AXRect)) -> AXRect in item.1 }
            XCTAssertEqual(frames.count, 5, note)
            // #36 6 (R258): equal symbol controls, each the widest of the note's three.
            let widest: Double = frames.prefix(3).map { (rect: AXRect) -> Double in rect.width }.max() ?? 0
            let first: [AXRect] = frames.prefix(3).map { (rect: AXRect) -> AXRect in AXRect(x: rect.x, y: rect.y, width: widest, height: rect.height) }
            let second: [AXRect] = Array(frames.suffix(2))
            // #33's numbers (60 inside, 140 between) plus the system's space before the count, which is not known: between
            // 0 and the 60 pt the run shows between Jump to Letter and the count. Movies does not fit even at 0.
            let old: CheckResult = ScreenRules.toolbarRowWidth(first: first, second: second, count: count, inGroup: 60, groupGap: 140, countGap: 0)
            let new: CheckResult = ScreenRules.toolbarRowWidth(first: first, second: second, count: count, inGroup: inGroup, groupGap: groupGap, countGap: countGap)
            print("TOOLBAR \(note) #33: \(old.lines[0]) | #34: \(new.lines[0]) \(new.lines[1])")
            if note == "07-movies-toolbar-larger-text-GROUPS" {
                XCTAssertFalse(old.passed, "\(note): \(old.text)")
                // #34's 48 inside a group no longer fits with equal symbols: 1,762 of 1,760 pt.
                let was: CheckResult = ScreenRules.toolbarRowWidth(first: first, second: second, count: count, inGroup: 48, groupGap: 100, countGap: 40)
                XCTAssertFalse(was.passed, "\(note): \(was.text)")
                XCTAssertTrue(was.lines[0].contains("= 1762 of 1760"), was.lines[0])
            }
            XCTAssertTrue(new.passed, "\(note): \(new.text)")
            // With 60 inside a group, a 120 pt gap (twice 60) fits at Larger Text only if the system's space before the count
            // is under 12 pt (Movies: 1,749 + that space of 1,760); unproven, so the row's spacings are now explicit.
            if note.contains("larger-text") {
                let twice: CheckResult = ScreenRules.toolbarRowWidth(first: first, second: second, count: count, inGroup: 60, groupGap: 120, countGap: 12)
                if note.contains("movies") { XCTAssertFalse(twice.passed, "\(note): \(twice.text)") }
            }
        }
        XCTAssertGreaterThanOrEqual(groupGap / inGroup, 2)
    }

    /// #36 8 T5: the frames of 55-show-page-HIERARCHY (second run of 20 Nov). With the focus on More, the old rule said the
    /// S1 E1 card was reached (More's centre lies inside the card's 615 pt frame) and test12 pressed Select on More; the new
    /// rule does not. The card itself, a child the size of the card, and the same label still count.
    func testTheFocusOnMoreIsNotTheEpisodeCardBelowIt() {
        let more: AXRect = AXRect(x: 344, y: 489, width: 171, height: 66)
        let card: AXRect = AXRect(x: 80, y: 521, width: 410, height: 615)
        XCTAssertTrue(ScreenRules.oldFocusReached(focused: more, target: card), "the old rule must show the run's mistake")
        XCTAssertFalse(ScreenRules.focusReached(focused: more, focusedLabel: "More", target: card, targetLabel: "S1 E1, A quiet beginning"))
        XCTAssertTrue(ScreenRules.focusReached(focused: card, focusedLabel: "S1 E1, A quiet beginning", target: card, targetLabel: "S1 E1, A quiet beginning"))
        XCTAssertTrue(ScreenRules.focusReached(focused: AXRect(x: 84, y: 525, width: 402, height: 607), focusedLabel: "",
                                               target: card, targetLabel: ""))
        XCTAssertTrue(ScreenRules.focusReached(focused: more, focusedLabel: "More", target: AXRect(x: 0, y: 0, width: 1, height: 1), targetLabel: "More"))
    }

    /// #34 3: test16 must not pass on a row folded into More.
    func testAToolbarFoldedIntoMoreFailsTheGroupsCheck() {
        let folded: CheckResult = ScreenRules.toolbarGroups(first: [("Sort", AXRect(x: 80, y: 157, width: 125, height: 87)),
                                                                    ("Filter", AXRect(x: 253, y: 157, width: 114, height: 87)),
                                                                    ("More", AXRect(x: 415, y: 157, width: 110, height: 87))], second: [])
        XCTAssertFalse(folded.passed, folded.text)
        XCTAssertTrue(folded.text.contains("folded into More"), folded.text)
    }

    // MARK: B (1): the cover pixels

    /// A plain opaque cover built from the run's 74-file-details tree: one dark fill, the cover's own texts and rows drawn
    /// where the tree has them, a little noise. Must pass (the check cannot fail a correct screen); with one tab label
    /// drawn into the tab bar band, or one line of the page's text, it must fail.
    func opaqueCover(from dump: AccessibilityDump) throws -> RGBImage {
        var image: RGBImage = RGBImage(width: 1920, height: 1080, fill: RGB(r: 18, g: 18, b: 20))
        var seed: UInt32 = 7
        for i in stride(from: 0, to: image.bytes.count, by: 3) {
            seed = seed &* 1_103_515_245 &+ 12_345
            let noise: UInt8 = UInt8((seed >> 16) % 7)
            image.bytes[i] = 15 + noise; image.bytes[i + 1] = 15 + noise; image.bytes[i + 2] = 17 + noise
        }
        // The dominant corner colour must be one value: the four corners are a flat fill, as an opaque system fill is.
        for corner in [AXRect(x: 0, y: 0, width: 40, height: 40), AXRect(x: 1880, y: 0, width: 40, height: 40),
                       AXRect(x: 0, y: 1040, width: 40, height: 40), AXRect(x: 1880, y: 1040, width: 40, height: 40)] {
            image.fill(corner, scale: 1, with: RGB(r: 18, g: 18, b: 20))
        }
        let cover: Int = try XCTUnwrap(dump.coverRoot)
        for index in dump.descendants(of: cover) {
            let node: AXNode = dump.nodes[index]
            guard let frame = node.frame, !frame.isEmpty, frame.width < 1900 else { continue }
            if node.type == "Cell" { image.fill(frame, scale: 1, with: RGB(r: 60, g: 60, b: 64)) }
            if node.type == "StaticText" { image.fill(frame.padded(by: -6), scale: 1, with: RGB(r: 235, g: 235, b: 240)) }
        }
        return image
    }

    func testAPlainOpaqueCoverPassesTheTabBarAndPageTextRegions() throws {
        let dump: AccessibilityDump = try fixture("74-file-details-HIERARCHY")
        let image: RGBImage = try opaqueCover(from: dump)
        let page: Int = try XCTUnwrap(dump.pageRoot)
        let regions = CoverPixels.regions(pageTexts: dump.textFrames(under: page), window: AXRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertGreaterThan(regions.count, 10)
        let result: CheckResult = CoverPixels.check(image, scale: 1, regions: regions, exclude: CoverPixels.coverElements(in: dump))
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(CoverPixels.background(of: image, scale: 1), RGB(r: 18, g: 18, b: 20))
    }

    func testOneTabLabelOrOneLineOfPageTextThroughTheCoverFails() throws {
        let dump: AccessibilityDump = try fixture("74-file-details-HIERARCHY")
        let page: Int = try XCTUnwrap(dump.pageRoot)
        let regions = CoverPixels.regions(pageTexts: dump.textFrames(under: page), window: AXRect(x: 0, y: 0, width: 1920, height: 1080))
        var tab: RGBImage = try opaqueCover(from: dump)
        tab.fill(AXRect(x: 1000, y: 63, width: 108, height: 33), scale: 1, with: RGB(r: 200, g: 200, b: 205))   // "Files"
        XCTAssertFalse(CoverPixels.check(tab, scale: 1, regions: regions, exclude: CoverPixels.coverElements(in: dump)).passed)
        var text: RGBImage = try opaqueCover(from: dump)
        text.fill(AXRect(x: 80, y: 228, width: 300, height: 35), scale: 1, with: RGB(r: 150, g: 150, b: 155))   // the breadcrumb
        let result: CheckResult = CoverPixels.check(text, scale: 1, regions: regions, exclude: CoverPixels.coverElements(in: dump))
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("SOMETHING SHOWS THROUGH"), result.text)
    }

    // MARK: Run artifacts: the real pictures of 20 Nov

    func testRunArtifactsPicture74FailsThePixelCheckWithItsOwnTree() throws {
        let image: RGBImage = try picture("screenshots/74-file-details.png")
        let dump: AccessibilityDump = try fixture("74-file-details-HIERARCHY")
        let page: Int = try XCTUnwrap(dump.pageRoot)
        let regions = CoverPixels.regions(pageTexts: dump.textFrames(under: page), window: AXRect(x: 0, y: 0, width: 1920, height: 1080))
        let result: CheckResult = CoverPixels.check(image, scale: 1, regions: regions, exclude: CoverPixels.coverElements(in: dump))
        print("74-file-details:\n\(result.text)")
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.lines.first { $0.hasPrefix("tab bar band") }?.contains("SOMETHING SHOWS THROUGH") == true, result.text)
    }

    /// 11 and 66 have no tree in the run (only 10 and 74 wrote one), so only the tab bar band is sampled, with the cover's
    /// own elements in that band measured from the pictures: 11, the title "WebDAV" (same place as "Add a Source" in 10's
    /// tree, {{393, 66}, {332, 69}}); 66, the title "Move to Shows" and the focused "Sample Clip" field.
    func testRunArtifactsPictures11And66FailTheTabBarBand() throws {
        let cases: [(String, [AXRect])] = [
            ("screenshots/11-form-webdav.png", [AXRect(x: 393, y: 66, width: 332, height: 69).padded(by: 4)]),
            ("screenshots/66-move-sheet.png", [AXRect(x: 80, y: 60, width: 400, height: 69).padded(by: 4),
                                               AXRect(x: 1005, y: 97, width: 820, height: 80).padded(by: 40)])]
        for (path, exclude) in cases {
            let image: RGBImage = try picture(path)
            let result: CheckResult = CoverPixels.check(image, scale: 1, regions: [("tab bar band", CoverPixels.tabBarBand)], exclude: exclude)
            print("\(path):\n\(result.text)")
            XCTAssertFalse(result.passed, "\(path): \(result.text)")
        }
    }

    func testRunArtifactsThePNGDecoderReadsTheRunsPictures() throws {
        let image: RGBImage = try picture("screenshots/11-form-webdav.png")
        XCTAssertEqual(image.width, 1920)
        XCTAssertEqual(image.height, 1080)
        // The focused Connect row is white in the picture (x 380 to 1540, y 595 to 660).
        XCTAssertGreaterThan(Int(image.pixel(960, 630).r), 230)
    }

    /// #33 L: 56-show-long-episode-caption-later was the same picture as 56-show-long-episode-caption (the run's -UNCHANGED
    /// note); the check fails on that pair and passes on two pictures that differ (55 and 55 scrolled once).
    /// #33 E: the run's show page had S2 E3 smaller than the other episode cards; equal cards pass.
    func testRunArtifactsTheEpisodeCardsOfPicture55AreNotEqual() throws {
        let text: String = try String(contentsOf: try artifact("screenshots-library/notes/55-show-page-HIERARCHY.txt"), encoding: .utf8)
        let result: CheckResult = ScreenRules.equalEpisodeCards(in: AccessibilityDump(text))
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("378 x 566"), result.text)
    }

    /// #33 L: the frames of the run of 20 Nov. S1 E1 focused (note 55: {{80, 481}, {410, 615}}), S2 E1 the target
    /// ({{80, 908}, {410, 615}}): the old rule pressed Left (the frames overlap vertically), the new one Down. A row not laid
    /// out yet (empty frame at the origin, as About Source Types below the list): old Up, new Down.
    func testTheFocusHelperMovesDownToTheSecondSeasonAndToARowNotLaidOutYet() {
        let s1e1: AXRect = AXRect(x: 80, y: 481, width: 410, height: 615)
        let s2e1: AXRect = AXRect(x: 80, y: 908, width: 410, height: 615)
        XCTAssertEqual(ScreenRules.oldFocusDirection(from: s1e1, to: s2e1), .left)
        XCTAssertEqual(ScreenRules.focusDirection(from: s1e1, to: s2e1), .down)
        let searchRow: AXRect = AXRect(x: 373, y: 300, width: 1174, height: 66)
        let notBuilt: AXRect = AXRect(x: 0, y: 0, width: 0, height: 0)
        XCTAssertEqual(ScreenRules.oldFocusDirection(from: searchRow, to: notBuilt), .up)
        XCTAssertEqual(ScreenRules.focusDirection(from: searchRow, to: notBuilt), .down)
        // Neighbours on one row still go sideways; a row above still goes up.
        XCTAssertEqual(ScreenRules.focusDirection(from: s1e1, to: AXRect(x: 530, y: 481, width: 410, height: 615)), .right)
        XCTAssertEqual(ScreenRules.focusDirection(from: s2e1, to: s1e1), .up)
    }

    /// #33 I: the run's pages had 10 pt between the button row and the next heading (55: Resume ends at 559, “Season 1” at
    /// 569; 57: Resume ends at 554, “Cast” at 564). Both fail the 40 pt minimum; a page with 50 pt passes.
    func testRunArtifactsTheButtonRowGapWas10PointsOnBothPages() throws {
        for (path, heading) in [("screenshots-library/notes/55-show-page-HIERARCHY.txt", "Season 1"), ("screenshots-library/notes/57-movie-detail-HIERARCHY.txt", "Cast")] {
            let dump = AccessibilityDump(try String(contentsOf: try artifact(path), encoding: .utf8))
            let result = ScreenRules.gapBelow(in: dump, anchors: ["control.play", "control.more"], kinds: ["StaticText"], minimum: 40, what: "buttons to heading")
            XCTAssertFalse(result.passed, result.text)
            XCTAssertTrue(result.text.contains("“\(heading)”") && result.text.contains("gap 10 pt"), result.text)
        }
    }

    func testAGapOfFiftyPointsPassesAndTheGridGapIsMeasuredToTheFirstCard() {
        let page = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Button, 0x3, {{76.0, 485.0}, {212.0, 74.0}}, identifier: 'control.play', label: 'Resume'
              StaticText, 0x4, {{80.0, 609.0}, {151.0, 46.0}}, label: 'Season 1'
        """)
        XCTAssertTrue(ScreenRules.gapBelow(in: page, anchors: ["control.play", "control.more"], kinds: ["StaticText"], minimum: 40, what: "x").passed)
        let grid = AccessibilityDump("""
         →Application, 0x1, pid: 1, label: 'Video Player'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Button, 0x3, {{80.0, 157.0}, {102.0, 68.0}}, identifier: 'control.sort', label: 'Sort'
              Button, 0x4, {{80.0, 250.0}, {320.0, 480.0}}, label: 'Sample Movie 1'
        """)
        let tight = ScreenRules.gapBelow(in: grid, anchors: ["control.sort"], kinds: ["Button", "Cell"], minimum: 60, what: "toolbar to cards")
        XCTAssertFalse(tight.passed, tight.text)
        XCTAssertTrue(tight.text.contains("gap 25 pt"), tight.text)
    }

    func testEqualEpisodeCardsPassAndOneSmallerCardFails() {
        func dump(_ third: String) -> AccessibilityDump {
            AccessibilityDump("""
             →Application, 0x1, pid: 1, label: 'Video Player'
                Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
                  Button, 0x3, {{80.0, 481.0}, {410.0, 615.0}}, label: 'S1 E1, A quiet beginning', value: 43 min
                  Button, 0x4, {{530.0, 481.0}, {410.0, 615.0}}, label: 'S1 E2, The long way round', value: 43 min
                  Button, 0x5, \(third), label: 'S2 E3, A very long episode title', value: 43 min
            """)
        }
        XCTAssertTrue(ScreenRules.equalEpisodeCards(in: dump("{{980.0, 481.0}, {410.0, 615.0}}")).passed)
        XCTAssertFalse(ScreenRules.equalEpisodeCards(in: dump("{{980.0, 481.0}, {378.0, 566.0}}")).passed)
    }

    func testRunArtifactsTheUnchangedCheckFailsOnTheTwoCaptionPicturesAndPassesOnAScroll() throws {
        let first: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/56-show-long-episode-caption.png")))
        let later: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/56-show-long-episode-caption-later.png")))
        XCTAssertFalse(ScreenRules.changed(first, later, step: "3 s of focus on S2 E3").passed)
        let page: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/55-show-page.png")))
        let scrolled: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/55-show-page-scrolled-1.png")))
        XCTAssertTrue(ScreenRules.changed(page, scrolled, step: "Down").passed)
    }

    // MARK: Caption whole and still (#36 group 1 d, group 4, R264)

    /// A synthetic caption: a dark backdrop with light "glyph" columns from `from` to `to` (in points, scale 1).
    func captionImage(from: Int, to: Int) -> RGBImage {
        var image: RGBImage = RGBImage(width: 400, height: 60, fill: RGB(r: 55, g: 37, b: 64))
        for x in stride(from: from, to: to, by: 7) { for y in 20..<44 { image.set(x, y, RGB(r: 250, g: 250, b: 250)); image.set(x + 1, y, RGB(r: 190, g: 186, b: 194)) } }
        return image
    }

    func testACaptionNarrowerThanItsColumnIsWhole() {
        let column = AXRect(x: 16, y: 18, width: 368, height: 28)
        let result: CheckResult = ScreenRules.captionFits(captionImage(from: 16, to: 200), scale: 1, column: column,
                                                           text: AXRect(x: 16, y: 18, width: 190, height: 28))
        XCTAssertTrue(result.passed, result.text)
        XCTAssertTrue(result.text.contains("narrower than its column"), result.text)
    }

    func testACaptionThatFillsItsColumnIsCutWhenItsInkReachesTheEdge() {
        let column = AXRect(x: 16, y: 18, width: 368, height: 28)
        let text = AXRect(x: 16, y: 18, width: 368, height: 28)
        // Ink up to x 381, column ending at 384: cut (the 56 of the run: the "i" 4 pt from the edge).
        XCTAssertFalse(ScreenRules.captionFits(captionImage(from: 16, to: 384), scale: 1, column: column, text: text).passed)
        // Ink ending 20 pt before the edge (a wrapped or scaled line that ends at a word): whole.
        XCTAssertTrue(ScreenRules.captionFits(captionImage(from: 16, to: 360), scale: 1, column: column, text: text).passed)
        // Wider than the column: cut without looking at the pixels.
        XCTAssertFalse(ScreenRules.captionFits(captionImage(from: 16, to: 200), scale: 1, column: column,
                                               text: AXRect(x: 16, y: 18, width: 400, height: 28)).passed)
    }

    func testTheLaterPairPassesOnlyWhenIdenticalAndWhole() {
        let whole = CheckResult(passed: true, lines: ["CAPTION WHOLE OK"])
        let cut = CheckResult(passed: false, lines: ["CAPTION CUT"])
        XCTAssertTrue(ScreenRules.stillAndWhole([1, 2, 3], [1, 2, 3], caption: whole).passed)
        let cutResult: CheckResult = ScreenRules.stillAndWhole([1, 2, 3], [1, 2, 3], caption: cut)
        XCTAssertFalse(cutResult.passed)
        XCTAssertTrue((cutResult.lines.last ?? "").contains("the caption is cut"), cutResult.text)
        let moved: CheckResult = ScreenRules.stillAndWhole([1, 2, 3], [1, 2, 4], caption: whole)
        XCTAssertFalse(moved.passed)
        XCTAssertTrue((moved.lines.last ?? "").contains("the screen changed"), moved.text)
    }

    /// The third run of 20 Nov (run artifacts): the cut S2 E3 caption of 56 fails, the whole S2 E2 caption beside it passes,
    /// and the 56 / 56-later pair fails as a whole (identical, but cut). Frames from 55-show-page-HIERARCHY moved up by the
    /// scroll (the button at y 1155 there, 379 in 56's -FOCUS note: 776 pt): S2 E3 caption {996, 629, 378 x 28} in the
    /// column 996 to 1374 (button 980 + 410, inset 16); S2 E2 caption {546, 634, 224 x 30} in 546 to 924.
    func testRunArtifactsThe56CaptionIsCutAndTheS2E2CaptionIsWhole() throws {
        let image: RGBImage = try picture("screenshots-library/56-show-long-episode-caption.png")
        let cutResult: CheckResult = ScreenRules.captionFits(image, scale: 1, column: AXRect(x: 996, y: 629, width: 378, height: 28),
                                                             text: AXRect(x: 996, y: 629, width: 378, height: 28))
        print("56 S2 E3:\n" + cutResult.text)
        XCTAssertFalse(cutResult.passed, cutResult.text)
        let whole: CheckResult = ScreenRules.captionFits(image, scale: 1, column: AXRect(x: 546, y: 634, width: 378, height: 30),
                                                         text: AXRect(x: 546, y: 634, width: 224, height: 30))
        XCTAssertTrue(whole.passed, whole.text)
        let first: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/56-show-long-episode-caption.png")))
        let later: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/56-show-long-episode-caption-later.png")))
        XCTAssertFalse(ScreenRules.stillAndWhole(first, later, caption: cutResult).passed)
    }

    // MARK: Contrast (#33 K, R240)

    func testTheContrastRatioIsWCAGs() {
        XCTAssertEqual(Contrast.ratio(RGB(r: 0, g: 0, b: 0), RGB(r: 255, g: 255, b: 255)), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(RGB(r: 118, g: 118, b: 118), RGB(r: 255, g: 255, b: 255)), 4.54, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(RGB(r: 40, g: 40, b: 40), RGB(r: 40, g: 40, b: 40)), 1, accuracy: 0.001)
    }

    func testTheMeasureFindsTheTextAndTheBackgroundOfASyntheticLabel() throws {
        // A 200 × 40 frame: background #2E2E2E, 6 % of the pixels "ink" #8A8A8A, 6 % anti-aliased halfway.
        var image: RGBImage = RGBImage(width: 200, height: 40, fill: RGB(r: 46, g: 46, b: 46))
        for x in stride(from: 10, to: 190, by: 15) {
            for y in 10..<30 { image.set(x, y, RGB(r: 138, g: 138, b: 138)); image.set(x + 1, y, RGB(r: 92, g: 92, b: 92)) }
        }
        let m: Contrast.Measurement = try XCTUnwrap(Contrast.measure(image, frame: AXRect(x: 0, y: 0, width: 200, height: 40), scale: 1))
        XCTAssertEqual(m.background, RGB(r: 46, g: 46, b: 46))
        XCTAssertEqual(m.foreground, RGB(r: 138, g: 138, b: 138))
        XCTAssertEqual(m.ratio, Contrast.ratio(RGB(r: 138, g: 138, b: 138), RGB(r: 46, g: 46, b: 46)), accuracy: 0.001)
        XCTAssertNil(Contrast.measure(image, frame: AXRect(x: 300, y: 0, width: 10, height: 10), scale: 1))
    }

    /// The run of 20 Nov (run artifacts): the two kinds of text #33 K changes, measured before the change. The frames are
    /// read off the pictures (1920 × 1080, scale 1): no hierarchy note was written for 31 or 78. Printed for the notes; the
    /// assertion only proves that the measure reads a dim text on these pictures (between 1.5 and 7).
    func testTheRunsSettingsFooterAndMediaInfoLabelsAreMeasured() throws {
        let settings: RGBImage = try picture("screenshots/31-settings-playback.png")
        let movie: RGBImage = try picture("screenshots/78-movie-no-synopsis-or-cast.png")
        let cases: [(String, RGBImage, AXRect)] = [
            ("31 footer “Skip buttons appear …”", settings, AXRect(x: 1005, y: 440, width: 655, height: 36)),
            ("31 summary “How titles play …”", settings, AXRect(x: 78, y: 230, width: 545, height: 36)),
            ("78 label “Resolution”", movie, AXRect(x: 78, y: 503, width: 150, height: 36)),
            ("78 label “Frame Rate”", movie, AXRect(x: 78, y: 709, width: 160, height: 36)),
        ]
        for (name, image, frame) in cases {
            let m: Contrast.Measurement = try XCTUnwrap(Contrast.measure(image, frame: frame, scale: 1), name)
            print("CONTRAST \(name): \(m)")
            XCTAssertTrue(m.ratio > 1.5 && m.ratio < 7, "\(name): \(m)")
        }
    }

    /// #34 5b (R240): primary at `alpha` drawn over `background`, composited in sRGB-encoded values (an assumption: how
    /// tvOS blends a text's opacity over vibrancy and material is not documented; CI's -CONTRAST note measures the real one).
    static func composite(_ primary: RGB, alpha: Double, over background: RGB) -> RGB {
        func mix(_ p: UInt8, _ b: UInt8) -> UInt8 { UInt8((alpha * Double(p) + (1 - alpha) * Double(b)).rounded()) }
        return RGB(r: mix(primary.r, background.r), g: mix(primary.g, background.g), b: mix(primary.b, background.b))
    }

    /// #34 5b (R240), run artifacts: the system secondary style as drawn in the run of 20 Nov, against primary at 60, 70, 80
    /// and 90 % on the same measured backgrounds. The primary colour is measured on the same picture (31: the title
    /// "Playback"; 78: the value beside each label). Prints the table for OPEN_QUESTIONS R240; asserts what R240 states.
    func testTheRunsSecondaryTextAgainstPrimaryAtLowerOpacities() throws {
        let settings: RGBImage = try picture("screenshots/31-settings-playback.png")
        let movie: RGBImage = try picture("screenshots/78-movie-no-synopsis-or-cast.png")
        // (name, picture, the secondary text's frame, a primary text's frame on the same picture)
        let cases: [(String, RGBImage, AXRect, AXRect)] = [
            ("31 footer", settings, AXRect(x: 1005, y: 440, width: 655, height: 36), AXRect(x: 80, y: 165, width: 225, height: 50)),
            ("31 summary", settings, AXRect(x: 78, y: 230, width: 545, height: 36), AXRect(x: 80, y: 165, width: 225, height: 50)),
            ("78 Resolution", movie, AXRect(x: 78, y: 503, width: 150, height: 36), AXRect(x: 296, y: 503, width: 250, height: 36)),
            ("78 Frame Rate", movie, AXRect(x: 78, y: 709, width: 160, height: 36), AXRect(x: 296, y: 709, width: 150, height: 36)),
        ]
        let alphas: [Double] = [0.6, 0.7, 0.8, 0.9]
        var minimum: [Double: Double] = [:]
        for (name, image, frame, primaryFrame) in cases {
            let secondary: Contrast.Measurement = try XCTUnwrap(Contrast.measure(image, frame: frame, scale: 1), name)
            let primary: Contrast.Measurement = try XCTUnwrap(Contrast.measure(image, frame: primaryFrame, scale: 1), name)
            var row: String = String(format: "CONTRAST-5B %@: secondary %.2f (%@ on %@); primary %.2f (%@)", name, secondary.ratio,
                                     secondary.foreground.description, secondary.background.description, Contrast.ratio(primary.foreground, secondary.background),
                                     primary.foreground.description)
            for alpha in alphas {
                let colour: RGB = Self.composite(primary.foreground, alpha: alpha, over: secondary.background)
                let r: Double = Contrast.ratio(colour, secondary.background)
                minimum[alpha] = min(minimum[alpha] ?? .infinity, r)
                row += String(format: "; primary %.0f%% %.2f (%@)", alpha * 100, r, colour.description)
            }
            print(row)
            XCTAssertLessThan(secondary.ratio, 4.5, "\(name): the system secondary already passes; R240 keeps it there")
        }
        print("CONTRAST-5B lowest per option: " + alphas.map { String(format: "%.0f%% %.2f", $0 * 100, minimum[$0] ?? 0) }.joined(separator: ", "))
        XCTAssertLessThan(minimum[0.6] ?? 0, 4.5, "60 % fails on one background (78 Resolution, 4.34:1 in the run)")
        XCTAssertGreaterThanOrEqual(minimum[0.7] ?? 0, 4.5, "70 % passes on every background (R240's pick)")
    }

    /// #34 5b (R240): the colours measured on the run of 20 Nov (testTheRunsSecondaryTextAgainstPrimaryAtLowerOpacities,
    /// run artifacts): (secondary text, its background, the primary text on that picture). Runs without the pictures.
    static let measuredSecondary: [(String, RGB, RGB, RGB)] = [
        ("31 footer", RGB(r: 0x6D, g: 0x6E, b: 0x6E), RGB(r: 0x2B, g: 0x2B, b: 0x2B), RGB(r: 0xFF, g: 0xFF, b: 0xFF)),
        ("31 summary", RGB(r: 0x9A, g: 0x9C, b: 0x9F), RGB(r: 0x33, g: 0x37, b: 0x3C), RGB(r: 0xFF, g: 0xFF, b: 0xFF)),
        ("78 Resolution", RGB(r: 0x9A, g: 0xA7, b: 0xAF), RGB(r: 0x34, g: 0x4E, b: 0x5D), RGB(r: 0xFF, g: 0xFF, b: 0xFF)),
        ("78 Frame Rate", RGB(r: 0x96, g: 0x9E, b: 0xA5), RGB(r: 0x2B, g: 0x3B, b: 0x49), RGB(r: 0xFF, g: 0xFF, b: 0xFF)),
    ]

    /// #34 5b (R240): `ReadableSecondary.opacity` (read from App/Shared/LayoutParts.swift) reaches 4.5:1 on every measured
    /// background, the system secondary does not, 10 points less opacity would not (so it is the lowest that passes: the
    /// most hierarchy kept), and the text stays below primary.
    func testTheReadableSecondaryOpacityPassesOnTheRunsBackgrounds() throws {
        guard let source = try appSource("App/Shared/LayoutParts.swift") else { return }
        let marker: String = "static let opacity: Double = "
        let line: Substring = try XCTUnwrap(source.split(separator: "\n").first { (l: Substring) -> Bool in l.contains(marker) }, "ReadableSecondary.opacity")
        let alpha: Double = try XCTUnwrap(Double((line.components(separatedBy: marker).last ?? "").trimmingCharacters(in: .whitespaces)))
        var lowerFails: Bool = false
        for (name, secondary, background, primary) in Self.measuredSecondary {
            let chosen: Double = Contrast.ratio(Self.composite(primary, alpha: alpha, over: background), background)
            let lower: Double = Contrast.ratio(Self.composite(primary, alpha: alpha - 0.1, over: background), background)
            XCTAssertLessThan(Contrast.ratio(secondary, background), 4.5, "\(name): the system secondary passes; keep it (R240)")
            XCTAssertGreaterThanOrEqual(chosen, 4.5, "\(name): primary at \(alpha) is \(chosen):1")
            XCTAssertLessThan(chosen, Contrast.ratio(primary, background), "\(name): not below primary")
            if lower < 4.5 { lowerFails = true }
        }
        XCTAssertTrue(lowerFails, "primary at \(alpha - 0.1) passes everywhere too: R240 picks the lowest opacity that passes")
    }

    // MARK: #36 S-A and T6: text contrast on a task cover

    /// A black picture with a block of `ink` over the left third of every leaf text of `dump`'s cover: a "right" cover.
    func paintedCover(_ dump: AccessibilityDump, root: Int, ink: RGB, title: RGB? = nil) -> RGBImage {
        var image: RGBImage = RGBImage(width: 1920, height: 1080, fill: RGB(r: 0, g: 0, b: 0))
        let leaves: [Int] = dump.descendants(of: root).filter { (index: Int) -> Bool in
            dump.nodes[index].type == "StaticText" && !(dump.nodes[index].frame?.isEmpty ?? true)
                && !dump.descendants(of: index).contains { dump.nodes[$0].type == "StaticText" }
        }
        let top: Int? = leaves.min { (dump.nodes[$0].frame?.y ?? 0) < (dump.nodes[$1].frame?.y ?? 0) }
        for index in leaves {
            guard let frame = dump.nodes[index].frame, !frame.isEmpty else { continue }
            let colour: RGB = (index == top ? title : nil) ?? ink
            let x1: Int = min(1920, Int(frame.x + frame.width / 3))
            let y1: Int = min(1080, Int(frame.maxY))
            guard Int(frame.y) < y1, Int(frame.x) < x1 else { continue }
            for y in Int(frame.y)..<y1 {
                for x in Int(frame.x)..<x1 {
                    let i: Int = (y * 1920 + x) * 3
                    image.bytes[i] = colour.r; image.bytes[i + 1] = colour.g; image.bytes[i + 2] = colour.b
                }
            }
        }
        return image
    }

    func testTheCoverContrastCheckPassesOnWhiteTextAndFailsOnTheRunsDimTitle() throws {
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let cover: Int = try XCTUnwrap(dump.coverRoot)
        let right: CheckResult = ScreenRules.coverContrast(paintedCover(dump, root: cover, ink: RGB(r: 255, g: 255, b: 255)),
                                                           scale: 1, in: dump, root: cover)
        XCTAssertTrue(right.passed, right.text)
        XCTAssertTrue(right.text.contains("title “Add a Source”"), right.text)
        XCTAssertEqual(right.lines.last, "CONTRAST OK")
        // The run's colours (note 10 and picture 11 of 20 Nov): title #4C4C4C, every other text #262626.
        let wrong: CheckResult = ScreenRules.coverContrast(paintedCover(dump, root: cover, ink: RGB(r: 0x26, g: 0x26, b: 0x26),
                                                                        title: RGB(r: 0x4C, g: 0x4C, b: 0x4C)),
                                                           scale: 1, in: dump, root: cover)
        XCTAssertFalse(wrong.passed, wrong.text)
        XCTAssertTrue(wrong.text.contains("“Add a Source” 2.4"), wrong.text)
        XCTAssertTrue(wrong.lines.last?.hasPrefix("CONTRAST PROBLEM") ?? false, wrong.text)
    }

    /// A title at 6.9:1 fails (7:1 for the title), the same grey on a body text passes (4.5:1): the two targets differ.
    func testTheTitleNeedsSevenToOneAndOtherTextFourAndAHalf() throws {
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let cover: Int = try XCTUnwrap(dump.coverRoot)
        let grey: RGB = RGB(r: 0x82, g: 0x82, b: 0x82)   // about 5.7:1 on black
        XCTAssertGreaterThan(Contrast.ratio(grey, RGB(r: 0, g: 0, b: 0)), 4.5)
        XCTAssertLessThan(Contrast.ratio(grey, RGB(r: 0, g: 0, b: 0)), 7)
        let titleGrey: CheckResult = ScreenRules.coverContrast(paintedCover(dump, root: cover, ink: RGB(r: 255, g: 255, b: 255), title: grey),
                                                               scale: 1, in: dump, root: cover)
        XCTAssertFalse(titleGrey.passed, titleGrey.text)
        let bodyGrey: CheckResult = ScreenRules.coverContrast(paintedCover(dump, root: cover, ink: grey, title: RGB(r: 255, g: 255, b: 255)),
                                                              scale: 1, in: dump, root: cover)
        XCTAssertTrue(bodyGrey.passed, bodyGrey.text)
    }

    /// On the run's own picture of 10 with its tree: the check fails. With VP_RUN_ARTIFACTS on the first run of 20 Nov (the
    /// see-through cover) the sentence and headers are caught; on the second run (after #33/#34, opaque cover) the title
    /// too: “Add a Source” 2.45:1 (#4C4C4C on #000000), the sentence 1.39:1, the headers 2.45:1.
    func testTheCoverContrastCheckFailsOnTheRunsPicture10() throws {
        let image: RGBImage = try picture("screenshots/10-add-source-types.png")
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let result: CheckResult = ScreenRules.coverContrast(image, scale: 1, in: dump, root: try XCTUnwrap(dump.coverRoot))
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("“FIND ON YOUR NETWORK”") && result.text.contains("BELOW 4.5"), result.text)
        print(result.text)
    }

    // MARK: #36 S-C: buttons side by side

    func buttonDump(_ second: String) -> AccessibilityDump {
        AccessibilityDump("""
        Window, 0x1, {{0.0, 0.0}, {1920.0, 1080.0}}
          Other, 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
            StaticText, 0x3, {{393.0, 66.0}, {300.0, 69.0}}, label: 'Add a Source'
            Button, 0x4, {{393.0, 700.0}, {573.0, 86.0}}, label: 'Connect'
            \(second)
            Button, 0x6, {{393.0, 820.0}, {1134.0, 66.0}}, label: 'About WebDAV'
        """)
    }

    func testTwoButtonsSideBySidePassWhenTheyAreTheSameSize() throws {
        let dump: AccessibilityDump = buttonDump("Button, 0x5, {{986.0, 700.0}, {573.0, 86.0}}, label: 'Cancel'")
        let result: CheckResult = ScreenRules.sideBySideButtons(in: dump, root: try XCTUnwrap(dump.coverRoot))
        XCTAssertTrue(result.passed, result.text)
        XCTAssertTrue(result.text.contains("“Connect” 573 x 86, “Cancel” 573 x 86"), result.text)
    }

    /// The wrong fixture: Cancel narrower (its label's width, as a plain button would be) and lower than 66 pt.
    func testAnUnevenPairFailsAndAButtonLowerThan66PointsFails() throws {
        let uneven: AccessibilityDump = buttonDump("Button, 0x5, {{986.0, 721.0}, {120.0, 44.0}}, label: 'Cancel'")
        let result: CheckResult = ScreenRules.sideBySideButtons(in: uneven, root: try XCTUnwrap(uneven.coverRoot))
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("not the same size") && result.text.contains("lower than 66 pt"), result.text)
        let low: AccessibilityDump = buttonDump("Button, 0x5, {{986.0, 711.0}, {573.0, 64.0}}, label: 'Cancel'")
        XCTAssertFalse(ScreenRules.sideBySideButtons(in: low, root: try XCTUnwrap(low.coverRoot)).passed)
    }

    /// #36 group-1 a: the third run of 20 Nov (341b43b) failed every form because the focused Connect is drawn larger by
    /// the system focus effect: 545 x 104 focused beside Cancel 537 x 96 at rest. Compared at rest, the pair passes.
    func testTheRunsFocusedConnectBesideCancelAtRestPasses() throws {
        let dump: AccessibilityDump = try fixture("11-form-webdav-HIERARCHY")
        let result: CheckResult = ScreenRules.sideBySideButtons(in: dump, root: try XCTUnwrap(dump.coverRoot))
        XCTAssertTrue(result.passed, result.text)
        XCTAssertTrue(result.text.contains("“Connect” 545 x 104 (focused), “Cancel” 537 x 96"), result.text)
    }

    /// The same pair in a synthetic tree, both cases: a focused button up to 1.10 times its resting neighbour passes; one
    /// more than 1.10 times, or one smaller than its neighbour, fails; two resting buttons of different sizes still fail
    /// even when a third, focused one is in the row; a resting button lower than 66 pt still fails.
    func testAFocusedButtonMayBeUpToTenPercentLargerButRestingButtonsMustBeEqual() throws {
        func row(_ buttons: String) -> AccessibilityDump {
            AccessibilityDump("""
            Window, 0x1, {{0.0, 0.0}, {1920.0, 1080.0}}
              Other, 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
                StaticText, 0x3, {{393.0, 66.0}, {300.0, 69.0}}, label: 'WebDAV'
            \(buttons)
            """)
        }
        func check(_ dump: AccessibilityDump) throws -> CheckResult {
            ScreenRules.sideBySideButtons(in: dump, root: try XCTUnwrap(dump.coverRoot))
        }
        let scaled: CheckResult = try check(row("""
                Button, 0x4, {{389.0, 598.0}, {590.0, 105.0}}, label: 'Connect', Focused
                Button, 0x5, {{990.0, 602.0}, {537.0, 96.0}}, label: 'Cancel'
        """))
        XCTAssertTrue(scaled.passed, scaled.text)   // 1.099 x 1.094
        let tooLarge: CheckResult = try check(row("""
                Button, 0x4, {{389.0, 590.0}, {600.0, 120.0}}, label: 'Connect', Focused
                Button, 0x5, {{990.0, 602.0}, {537.0, 96.0}}, label: 'Cancel'
        """))
        XCTAssertFalse(tooLarge.passed, tooLarge.text)
        XCTAssertTrue(tooLarge.text.contains("the focused button is"), tooLarge.text)
        let smaller: CheckResult = try check(row("""
                Button, 0x4, {{389.0, 610.0}, {500.0, 80.0}}, label: 'Connect', Focused
                Button, 0x5, {{990.0, 602.0}, {537.0, 96.0}}, label: 'Cancel'
        """))
        XCTAssertFalse(smaller.passed, smaller.text)
        let unevenAtRest: CheckResult = try check(row("""
                Button, 0x4, {{100.0, 598.0}, {545.0, 104.0}}, label: 'Move to Shows', Focused
                Button, 0x5, {{700.0, 602.0}, {537.0, 96.0}}, label: 'Sort Automatically'
                Button, 0x6, {{1300.0, 607.0}, {400.0, 86.0}}, label: 'Done'
        """))
        XCTAssertFalse(unevenAtRest.passed, unevenAtRest.text)
        XCTAssertTrue(unevenAtRest.text.contains("not the same size at rest"), unevenAtRest.text)
        let low: CheckResult = try check(row("""
                Button, 0x4, {{389.0, 609.0}, {545.0, 70.0}}, label: 'Connect', Focused
                Button, 0x5, {{990.0, 612.0}, {537.0, 64.0}}, label: 'Cancel'
        """))
        XCTAssertFalse(low.passed, low.text)
        XCTAssertTrue(low.text.contains("lower than 66 pt at rest"), low.text)
    }

    /// The run's own Add a Source page (rows only, no buttons side by side) passes: nothing to compare.
    func testTheRunsAddASourcePageHasNoButtonsSideBySide() throws {
        let dump: AccessibilityDump = try fixture("10-add-source-types-HIERARCHY")
        let result: CheckResult = ScreenRules.sideBySideButtons(in: dump, root: try XCTUnwrap(dump.coverRoot))
        XCTAssertTrue(result.passed, result.text)
    }
}
