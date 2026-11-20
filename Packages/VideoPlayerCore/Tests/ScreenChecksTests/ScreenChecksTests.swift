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
        XCTAssertTrue(result.text.contains("rows overlap: “Title” and “Year”"), result.text)
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
        // #33 G: GridToolbarLayout.groupGap = 140 pt between the groups, 2.33 times the 60 pt gap inside a group.
        let fixed: CheckResult = ScreenRules.toolbarGroups(first: first, second: [("Needs Review", AXRect(x: 488 + 140, y: 158, width: 336, height: 66))])
        XCTAssertTrue(fixed.passed, fixed.text)
        // Larger Text of the run: 60 inside, 76 between; fails the same way.
        let larger: [(String, AXRect)] = [("Sort", AXRect(x: 80, y: 157, width: 125, height: 87)),
                                          ("Filter", AXRect(x: 265, y: 157, width: 114, height: 87)),
                                          ("Saved Views", AXRect(x: 439, y: 157, width: 107, height: 87))]
        XCTAssertFalse(ScreenRules.toolbarGroups(first: larger, second: [("Needs Review", AXRect(x: 622, y: 158, width: 476, height: 85))]).passed)
        XCTAssertTrue(ScreenRules.toolbarGroups(first: larger, second: [("Needs Review", AXRect(x: 546 + 140, y: 158, width: 476, height: 85))]).passed)
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
    func testRunArtifactsTheUnchangedCheckFailsOnTheTwoMarqueePicturesAndPassesOnAScroll() throws {
        let first: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/56-show-long-episode-caption.png")))
        let later: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/56-show-long-episode-caption-later.png")))
        XCTAssertFalse(ScreenRules.changed(first, later, step: "3 s of focus on S2 E3").passed)
        let page: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/55-show-page.png")))
        let scrolled: [UInt8] = [UInt8](try Data(contentsOf: try artifact("screenshots-library/55-show-page-scrolled-1.png")))
        XCTAssertTrue(ScreenRules.changed(page, scrolled, step: "Down").passed)
    }
}
