import Foundation

/// #33: the verdicts of the screenshot checks, each a pure function so a Linux test can run it on the notes of a CI run
/// and on fixtures that are deliberately wrong. Every result carries its numbers and one verdict line for the note.
public struct CheckResult: Equatable, Sendable {
    public var passed: Bool
    public var lines: [String]

    public init(passed: Bool, lines: [String]) {
        self.passed = passed
        self.lines = lines
    }

    public var text: String { lines.joined(separator: "\n") }
}

public enum ScreenRules {
    // MARK: C: a task page is full screen (R228)

    /// #33 C: the width of the ROW that holds the element with identifier `anchor`: the nearest Cell around it, otherwise
    /// the nearest Table or CollectionView. The run of 20 Nov measured the Cancel BUTTON (its label, 90 of 1920 wide) and
    /// called every form a small sheet; the row (Cell) is 1174 of 1920 wide (note 10-add-source-types-HIERARCHY).
    /// Passes when that row is wider than half the window. No anchor, no row or no window is a failure with its reason.
    public static func fullScreenRow(in dump: AccessibilityDump, anchor: String) -> CheckResult {
        guard let window = dump.window, let windowFrame = dump.nodes[window].frame, windowFrame.width > 0 else {
            return CheckResult(passed: false, lines: ["no window in the tree", "PAGE NOT MEASURED"])
        }
        var found: Int? = dump.first(identifier: anchor)
        var prefix: [String] = []
        if found == nil, let cover = dump.coverRoot,
           let cell = dump.descendants(of: cover).first(where: { dump.nodes[$0].type == "Cell" && !(dump.nodes[$0].frame?.isEmpty ?? true) }) {
            // At Larger Text a lazy list may not have built the anchor row yet (94-larger-text-source-form): the cover's
            // first Cell is measured instead, and the note says so.
            found = dump.nodes[cell].children.first ?? cell
            prefix = ["“\(anchor)” is not in the tree (not built yet); the cover's first Cell “\(dump.text(of: cell))” is measured instead"]
        }
        guard let element = found else {
            return CheckResult(passed: false, lines: ["no element with identifier “\(anchor)” and no Cell in a cover", "PAGE NOT MEASURED"])
        }
        let containers: [String] = ["Cell", "Table", "CollectionView"]
        for kind in containers {
            if let row = dump.ancestors(of: element).first(where: { dump.nodes[$0].type == kind }),
               let frame = dump.nodes[row].frame {
                let share: Double = frame.width / windowFrame.width
                let wide: Bool = share > 0.5
                return CheckResult(passed: wide, lines: prefix + [
                    "\(kind) around “\(anchor)”: width \(Int(frame.width)) of window \(Int(windowFrame.width)) (share \(String(format: "%.2f", share)), must be over 0.50)",
                    wide ? "FULL WIDTH OK" : "PAGE NARROWER THAN HALF THE WINDOW"])
            }
        }
        // A Form row that the list has not turned into a Cell (10-add-source-types: the Cancel button, 0 wide, sits in an
        // Other 1174 wide): the nearest container wider than the element itself, below the window's top-level subtrees
        // (those are always the whole window and would prove nothing).
        let topLevel: Set<Int> = Set(dump.nodes[window].children)
        let width: Double = dump.nodes[element].frame?.width ?? 0
        if let row = dump.ancestors(of: element).first(where: { (index: Int) -> Bool in
            index != window && !topLevel.contains(index) && (dump.nodes[index].frame?.width ?? 0) > width + 1
        }), let frame = dump.nodes[row].frame {
            let share: Double = frame.width / windowFrame.width
            let wide: Bool = share > 0.5
            return CheckResult(passed: wide, lines: prefix + [
                "\(dump.nodes[row].type) (the container of the row) around “\(anchor)”: width \(Int(frame.width)) of window \(Int(windowFrame.width)) (share \(String(format: "%.2f", share)), must be over 0.50)",
                wide ? "FULL WIDTH OK" : "PAGE NARROWER THAN HALF THE WINDOW"])
        }
        return CheckResult(passed: false, lines: ["no Cell, Table, CollectionView or wider container around “\(anchor)”", "PAGE NOT MEASURED"])
    }

    /// #33 B (2): while a cover is open, nothing of the page behind it may be in the accessibility tree: no element whose
    /// identifier starts with "screen." outside the cover (screen.home, screen.folder, …). HIG Modality: a modal view
    /// "prevents interaction with the parent view"; SwiftUI `AccessibilityTraits.isModal`: "When a modal accessibility
    /// element is visible, sibling accessibility elements that are not modal are ignored."
    public static func pageHiddenBehindCover(in dump: AccessibilityDump) -> CheckResult {
        let cover: Int? = dump.coverRoot
        let inCover: Set<Int> = cover.map { Set(dump.descendants(of: $0) + [$0]) } ?? []
        let visible: [String] = dump.nodes.indices.filter { (index: Int) -> Bool in
            dump.nodes[index].identifier.hasPrefix("screen.") && !inCover.contains(index)
        }.map { dump.nodes[$0].identifier }
        if visible.isEmpty { return CheckResult(passed: true, lines: ["no page screen in the tree behind the cover", "PAGE HIDDEN OK"]) }
        // #36 8 T3: each exposed screen's element type and frame, for the report (the dump has no hidden flag: an element in
        // it is exposed to accessibility).
        let details: [String] = dump.nodes.indices.filter { (index: Int) -> Bool in
            dump.nodes[index].identifier.hasPrefix("screen.") && !inCover.contains(index)
        }.map { (index: Int) -> String in
            let node: AXNode = dump.nodes[index]
            var place: String = "no frame"
            if let frame = node.frame { place = frame.description }
            return node.identifier + ": " + node.type + " " + place
        }
        return CheckResult(passed: false, lines: ["page screens still in the accessibility tree: \(visible.joined(separator: ", "))"] + details + ["PAGE BEHIND THE COVER IS EXPOSED"])
    }

    /// R415 (run #27, every task cover; PROVISIONAL): B 2 as a rule on what the app controls. XCTest's tree is not proof
    /// that VoiceOver can reach an element: Apple's `exists` page (https://developer.apple.com/documentation/xcuiautomation/xcuielement/exists)
    /// says it is "within the app's current UI hierarchy" and that elements can "exist onscreen but be hidden by another
    /// element, causing their isHittable property to return false". No Apple page read says whether XCTest lists a view
    /// marked `accessibilityHidden(true)`, nor whether VoiceOver can reach one (UNVERIFIED; only VoiceOver on a device
    /// shows it). So `pageHiddenBehindCover` (listed at all) is kept as a record, and B 2 fails when a page screen that
    /// XCTest still lists was NOT told to hide (the app's `HiddenUnderTaskCover` value "cover probe: told hidden true"), or
    /// is hittable, i.e. could be pressed through the cover.
    public static func pageReachableBehindCover(listed: [(identifier: String, value: String, hittable: Bool)]) -> CheckResult {
        if listed.isEmpty { return CheckResult(passed: true, lines: ["no page screen in the tree behind the cover", "PAGE HIDDEN OK"]) }
        var lines: [String] = []
        var faults: [String] = []
        for screen in listed {
            let told: Bool = screen.value.contains("told hidden true")
            lines.append("\(screen.identifier): told hidden \(told), isHittable \(screen.hittable)")
            if !told { faults.append("\(screen.identifier) was not told to hide") }
            if screen.hittable { faults.append("\(screen.identifier) is hittable through the cover") }
        }
        if faults.isEmpty {
            return CheckResult(passed: true, lines: lines + ["listed by XCTest, told hidden and not hittable (whether VoiceOver reaches it: device check)",
                                                             "PAGE HIDDEN OK"])
        }
        return CheckResult(passed: false, lines: lines + faults + ["PAGE BEHIND THE COVER IS REACHABLE"])
    }

    /// #34 2: the cover itself is still in the accessibility tree while the page behind it is hidden. RootView hides the
    /// tab view (`accessibilityHidden(coverPresence.isCovered)`); the cover must not be inside that subtree. In the run of
    /// 20 Nov the cover was its own top-level subtree of the window, beside the tab view (10-add-source-types-HIERARCHY);
    /// Apple's pages do not say whether the hidden state reaches a presented cover, so this checks it on every cover.
    public static func coverExposed(in dump: AccessibilityDump) -> CheckResult {
        guard let cover = dump.coverRoot else {
            return CheckResult(passed: false, lines: ["no cover subtree in the accessibility tree", "COVER HIDDEN FROM ACCESSIBILITY"])
        }
        let labelled: [Int] = dump.descendants(of: cover).filter { (index: Int) -> Bool in
            !dump.nodes[index].label.isEmpty && !(dump.nodes[index].frame?.isEmpty ?? true)
        }
        if labelled.isEmpty {
            return CheckResult(passed: false, lines: ["the cover subtree has no labelled element", "COVER HIDDEN FROM ACCESSIBILITY"])
        }
        return CheckResult(passed: true, lines: ["\(labelled.count) labelled elements in the cover", "COVER EXPOSED OK"])
    }

    /// #33 A: the task page's title starts at or below the 60 pt top safe area (HIG Layout, tvOS) and its interactive rows
    /// (cells and fields of the cover) do not overlap one another.
    /// `scrolled`: the picture was taken after the list was scrolled or the focus moved down it (a name ending in
    /// "-scrolled", or 20-add-source-not-available after moving to Cancel). The title has then legitimately scrolled above
    /// the safe area (third run of 20 Nov, 20: “FTP, Folder on an FTP server” at y -117), so the title rule is SKIPPED and
    /// the note says so with the reason; the overlap rule still runs.
    public static func coverLayout(in dump: AccessibilityDump, safeTop: Double = 60, scrolled: String? = nil) -> CheckResult {
        guard let cover = dump.coverRoot else { return CheckResult(passed: false, lines: ["no cover subtree in the tree", "COVER NOT FOUND"]) }
        var lines: [String] = []
        var passed: Bool = true
        // The title is the cover's FIRST static text in tree order (the page header). Not the topmost one: rows a list has
        // built off screen report frames at y 0 (10-add-source-types: “Google Drive, No sign-in for TVs”).
        let texts: [Int] = dump.descendants(of: cover).filter { dump.nodes[$0].type == "StaticText" && !(dump.nodes[$0].frame?.isEmpty ?? true) }
        if let scrolled {
            var first: String = "no text"
            if let title = texts.first, let frame = dump.nodes[title].frame { first = "“\(dump.nodes[title].label)” at y \(Int(frame.y))" }
            lines.append("safe-area title rule SKIPPED: the picture was taken after \(scrolled), so the first text (\(first)) may "
                         + "have scrolled above the \(Int(safeTop)) pt safe area")
        } else if let title = texts.first, let frame = dump.nodes[title].frame {
            let ok: Bool = frame.y >= safeTop - 1
            lines.append("first text “\(dump.nodes[title].label)” starts at y \(Int(frame.y)) (safe area \(Int(safeTop)))")
            if !ok { passed = false; lines.append("TITLE ABOVE THE SAFE AREA") }
        } else {
            passed = false
            lines.append("no text in the cover")
        }
        let rows: [(String, AXRect)] = dump.descendants(of: cover).compactMap { (index: Int) -> (String, AXRect)? in
            let node: AXNode = dump.nodes[index]
            guard ["Cell", "TextField", "SecureTextField"].contains(node.type), let frame = node.frame, !frame.isEmpty else { return nil }
            return (dump.text(of: index), frame)
        }
        var overlaps: [String] = []
        for (i, a) in rows.enumerated() {
            for b in rows.dropFirst(i + 1) {
                let overlap: AXRect = a.1.intersection(b.1)
                // A field inside its row is nesting, not overlap; two rows sharing more than 4 pt of height is overlap.
                // #36 8 T2: nesting allows `nestingSlack` on every side (a focused field's frame can reach a few points past its
                // row's: notes 66-move-sheet-COVER and 07-*-saved-views-menu-COVER of the second run of 20 Nov reported
                // “Year (Optional)” and “” and “Saved View” and “”, a row and its own unnamed field).
                let nested: Bool = isNested(a.1, in: b.1) || isNested(b.1, in: a.1)
                if !overlap.isEmpty, !nested, overlap.height > 4 { overlaps.append("“\(a.0)” \(a.1) and “\(b.0)” \(b.1)") }
            }
        }
        if !overlaps.isEmpty { passed = false; lines.append("rows overlap: " + overlaps.joined(separator: "; ")) }
        lines.append(passed ? "COVER LAYOUT OK" : "COVER LAYOUT PROBLEM")
        return CheckResult(passed: passed, lines: lines)
    }

    /// #36 8 T2: how far a nested frame may reach past its container on any side and still count as inside it.
    public static let nestingSlack: Double = 6

    /// #36 8 T2: `inner` lies inside `outer`, each edge at most `nestingSlack` outside it.
    public static func isNested(_ inner: AXRect, in outer: AXRect) -> Bool {
        inner.x >= outer.x - nestingSlack && inner.y >= outer.y - nestingSlack
            && inner.maxX <= outer.maxX + nestingSlack && inner.maxY <= outer.maxY + nestingSlack
    }

    /// #34 3: the width the full toolbar row needs, from the controls' frames in order (first group, then second group),
    /// the explicit gaps of `GridToolbarLayout` and the count's width, against the width between the side margins.
    /// R375: kept as history; the UI tests use `systemToolbar` since the row became the system toolbar.
    public static func toolbarRowWidth(first: [AXRect], second: [AXRect], count: Double, inGroup: Double, groupGap: Double,
                                       countGap: Double, window: Double = 1920, margin: Double = 80) -> CheckResult {
        let controls: Double = (first + second).reduce(0) { (sum: Double, rect: AXRect) -> Double in sum + rect.width }
        let innerGaps: Double = Double(max(0, first.count - 1) + max(0, second.count - 1)) * inGroup
        let needed: Double = controls + innerGaps + groupGap + countGap + count
        let available: Double = window - 2 * margin
        let fits: Bool = needed <= available
        let ratio: Double = groupGap / max(1, inGroup)
        var verdict: String = "ROW FITS"
        if !fits { verdict = "ROW DOES NOT FIT" }
        return CheckResult(passed: fits && ratio >= 2, lines: [
            "controls \(Int(controls)) + gaps inside groups \(Int(innerGaps)) + between groups \(Int(groupGap)) + before the count \(Int(countGap)) + count \(Int(count)) = \(Int(needed)) of \(Int(available)) between the \(Int(margin)) pt margins (slack \(Int(available - needed)))",
            "ratio between groups / inside a group: " + String(format: "%.2f", ratio),
            verdict])
    }

    /// R375 (decided by the owner's standing rule R312): the SYSTEM toolbar of Movies and Shows. Its spacing and grouping are
    /// the system's, so they are recorded, never judged (no ratio, no equal widths). It passes when every `expected` control
    /// is there, all on one line (centres within 4 pt), each whole inside the window, none overlapping another, and all
    /// above the first row of content (`firstContentY`, when known).
    public static func systemToolbar(items: [(String, AXRect)], expected: [String], window: AXRect,
                                     firstContentY: Double?) -> CheckResult {
        var lines: [String] = items.map { "\($0.0)\t\($0.1)" }
        var problems: [String] = []
        let found: Set<String> = Set(items.map { $0.0 })
        let missing: [String] = expected.filter { !found.contains($0) }
        if !missing.isEmpty { problems.append("missing from the toolbar: " + missing.joined(separator: ", ")) }
        let centres: [Double] = items.map { (item: (String, AXRect)) -> Double in item.1.y + item.1.height / 2 }
        if let low = centres.min(), let high = centres.max(), high - low > 4 {
            problems.append("not on one line: centres \(centres.map { Int($0) })")
        }
        for item in items where !isNested(item.1, in: window) {
            problems.append("“\(item.0)” \(item.1) is not whole inside the window")
        }
        for (i, a) in items.enumerated() {
            for b in items.dropFirst(i + 1) where !a.1.intersection(b.1).isEmpty {
                problems.append("“\(a.0)” overlaps “\(b.0)”")
            }
        }
        if let top = firstContentY, let low = items.map({ (item: (String, AXRect)) -> Double in item.1.maxY }).max(), low > top {
            problems.append("the toolbar reaches into the first content row (\(Int(low)) below \(Int(top)))")
        }
        let gaps: [Int] = zip(items, items.dropFirst()).map { (pair: ((String, AXRect), (String, AXRect))) -> Int in
            Int(pair.1.1.x - pair.0.1.maxX)
        }
        lines.append("system gaps between the controls (recorded, not judged): \(gaps)")
        lines.append(problems.isEmpty ? "SYSTEM TOOLBAR OK" : "SYSTEM TOOLBAR PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    // MARK: R391: the shared faults of the run on fd9731f

    /// R391 (shared fault 1): badges of one line stand close together. `badges` are the frames of the "badge." elements
    /// of a screen. Badges whose vertical centres are within 4 pt are one line; inside a line, read from the left, the
    /// gap between two neighbours must be at most `maximum` (the run on fd9731f measured 60 to 72 pt; the app gives 8 and
    /// 12 pt, `BadgeSpacing`, a little more at Larger Text). A lone badge passes. No badge at all passes too: whether a
    /// screen must have badges is `badgesNotCutCheck`'s question.
    public static func badgeGaps(badges: [(String, AXRect)], maximum: Double = 24) -> CheckResult {
        var lines: [String] = []
        var problems: [String] = []
        var rows: [[(String, AXRect)]] = []
        for badge in badges.sorted(by: { (a: (String, AXRect), b: (String, AXRect)) -> Bool in a.1.y < b.1.y }) {
            let centre: Double = badge.1.y + badge.1.height / 2
            if let last = rows.last?.first, abs(last.1.y + last.1.height / 2 - centre) <= 4 {
                rows[rows.count - 1].append(badge)
            } else {
                rows.append([badge])
            }
        }
        for row in rows {
            let ordered: [(String, AXRect)] = row.sorted { (a: (String, AXRect), b: (String, AXRect)) -> Bool in a.1.x < b.1.x }
            let gaps: [Double] = zip(ordered, ordered.dropFirst()).map { (pair: ((String, AXRect), (String, AXRect))) -> Double in
                pair.1.1.x - pair.0.1.maxX
            }
            lines.append("line at y \(Int(ordered[0].1.y)): " + ordered.map { $0.0 }.joined(separator: " | ") + "; gaps \(gaps.map { Int($0.rounded()) })")
            for (index, gap) in gaps.enumerated() where gap > maximum {
                problems.append("“\(ordered[index].0)” and “\(ordered[index + 1].0)” are \(Int(gap.rounded())) pt apart (at most \(Int(maximum)))")
            }
        }
        lines.append(problems.isEmpty ? "BADGE GAPS OK" : "BADGE GAPS PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    /// R391 (shared fault 3): controls of one kind side by side are the same size (the toolbar buttons of Movies and
    /// Shows measured 108 x 66, 98 x 81 and 100 x 63 in the run on fd9731f). Every width and every height must be within
    /// `tolerance` of the first control's. Fewer than two controls pass (nothing to compare).
    public static func equalSizes(items: [(String, AXRect)], tolerance: Double = 1) -> CheckResult {
        var lines: [String] = items.map { "\($0.0)\t\(Int($0.1.width.rounded())) x \(Int($0.1.height.rounded()))" }
        var problems: [String] = []
        if let first = items.first {
            for item in items.dropFirst()
            where abs(item.1.width - first.1.width) > tolerance || abs(item.1.height - first.1.height) > tolerance {
                problems.append("“\(item.0)” is \(Int(item.1.width.rounded())) x \(Int(item.1.height.rounded())), “\(first.0)” is \(Int(first.1.width.rounded())) x \(Int(first.1.height.rounded()))")
            }
        }
        lines.append(problems.isEmpty ? "EQUAL SIZES OK" : "EQUAL SIZES PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    // MARK: C: menus (test16)

    /// #33 C: the items of an open menu: the Cells, MenuItems, Buttons and Switches that were not on screen before the menu
    /// opened, each with its own label or its first StaticText's label (`AccessibilityDump.text(of:)`), outside the tab bar.
    public static func menuItems(in dump: AccessibilityDump, before: Set<String>, ignoringIdentifiers: Set<String>) -> [(String, AXRect)] {
        var items: [(String, AXRect)] = []
        for (index, node) in dump.nodes.enumerated() where ["Cell", "MenuItem", "Button", "Switch"].contains(node.type) {
            guard !dump.isInTabBar(index), !ignoringIdentifiers.contains(node.identifier), let frame = node.frame, !frame.isEmpty else { continue }
            let label: String = dump.text(of: index)
            if label.isEmpty || before.contains(label) || items.contains(where: { $0.0 == label }) { continue }
            items.append((label, frame))
        }
        return items
    }

    /// Every label `menuItems` would see with nothing open (the "before" set).
    public static func labels(in dump: AccessibilityDump) -> Set<String> {
        Set(menuItems(in: dump, before: [], ignoringIdentifiers: []).map { $0.0 })
    }

    /// #32 F / #33 C: at least three items, none ending below the window, every expected label present ("Resolution" also
    /// matches "Resolution (2)").
    public static func menu(items: [(String, AXRect)], expected: [String], windowMaxY: Double) -> CheckResult {
        var problems: [String] = []
        if items.count < 3 { problems.append("\(items.count) menu items found, at least 3 expected") }
        for item in items where item.1.maxY > windowMaxY + 1 { problems.append("“\(item.0)” ends at \(Int(item.1.maxY)), below the window (\(Int(windowMaxY)))") }
        for label in expected where !items.contains(where: { $0.0 == label || $0.0.hasPrefix(label + " (") }) {
            problems.append("no item “\(label)”")
        }
        var lines: [String] = items.map { "\($0.0)\t\($0.1)" }
        lines.append(problems.isEmpty ? "MENU OK" : "MENU PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    // MARK: G: toolbar groups

    /// #33 G: the gap between the two toolbar groups must be at least `ratio` (2) times the gap inside the first group, and
    /// the gaps inside the first group may differ by at most 2 pt. Frames sorted left to right.
    /// #36 6 (R258): the symbol controls (first group) must have one size (width and height within 1 pt), every gap inside
    /// either group must be the same (within 2 pt), and the text controls must have the symbols' height (within 1 pt).
    public static func toolbarGroups(first: [(String, AXRect)], second: [(String, AXRect)], ratio: Double = 2) -> CheckResult {
        var lines: [String] = (first + second).map { "\($0.0)\t\($0.1)" }
        var problems: [String] = []
        // #34 1: typed closure (the #29 pattern).
        let inner: [Double] = zip(first, first.dropFirst()).map { (pair: ((String, AXRect), (String, AXRect))) -> Double in
            pair.1.1.x - pair.0.1.maxX
        }
        if first.count < 2 { problems.append("fewer than two view controls found") }
        if let low = inner.min(), let high = inner.max(), high - low > 2 {
            problems.append("gaps inside the view controls differ: \(inner.map { Int($0) })")
        }
        // #36 6: one size for the symbol controls.
        let widths: [Double] = first.map { (item: (String, AXRect)) -> Double in item.1.width }
        let heights: [Double] = first.map { (item: (String, AXRect)) -> Double in item.1.height }
        if let low = widths.min(), let high = widths.max(), let short = heights.min(), let tall = heights.max(), high - low > 1 || tall - short > 1 {
            problems.append("icon controls not the same size: widths \(widths.map { Int($0) }), heights \(heights.map { Int($0) })")
        }
        // #36 6: the gaps inside the second group equal those inside the first.
        let innerSecond: [Double] = zip(second, second.dropFirst()).map { (pair: ((String, AXRect), (String, AXRect))) -> Double in
            pair.1.1.x - pair.0.1.maxX
        }
        let allInner: [Double] = inner + innerSecond
        if !innerSecond.isEmpty, let low = allInner.min(), let high = allInner.max(), high - low > 2 {
            problems.append("gaps inside the groups not equal: \(inner.map { Int($0) }) and \(innerSecond.map { Int($0) })")
        }
        // #36 6: the text controls have the symbols' height.
        if let tall = heights.max() {
            let off: [(String, AXRect)] = second.filter { (item: (String, AXRect)) -> Bool in abs(item.1.height - tall) > 1 }
            if !off.isEmpty {
                problems.append("text controls not the symbols' height (\(Int(tall))): " + off.map { (item: (String, AXRect)) -> String in "\(item.0) \(Int(item.1.height))" }.joined(separator: ", "))
            }
        }
        if let last = first.last, let next = second.first, let gap = inner.max() {
            let between: Double = next.1.x - last.1.maxX
            lines.append("gap inside group \(Int(gap)), gap between groups \(Int(between)) (ratio \(String(format: "%.2f", gap > 0 ? between / gap : 0)), must be at least \(String(format: "%.1f", ratio)))")
            if between < gap * ratio { problems.append("the gap between the groups (\(Int(between))) is not at least \(String(format: "%.1f", ratio)) times the gap inside a group (\(Int(gap)))") }
        } else {
            // #34 3: test16 no longer accepts a row folded into More: every control must be on the line at both sizes.
            lines.append("second group not on the line (collapsed into More, or no Needs Review and no letters)")
            problems.append("the second group is not on the line (the row folded into More)")
        }
        if first.contains(where: { (item: (String, AXRect)) -> Bool in item.0 == "More" }) {
            problems.append("the More menu is on the line: the row did not fit")
        }
        lines.append(problems.isEmpty ? "TOOLBAR GROUPS OK" : "TOOLBAR GROUPS PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    // MARK: L: the focus helper

    public enum Arrow: String, Sendable { case up, down, left, right }

    /// #33 L: the arrow that moves the focus from `focused` toward `target`. An empty target frame (a row a lazy list has
    /// not laid out, reported at the origin) means "further down the list". Otherwise the centres decide: vertical when
    /// they are more than half the smaller height (at least 8 pt) apart, horizontal when not. The old rule (Down only when
    /// the target starts below the focused element's bottom) pressed Up for an empty frame and Left for ever between
    /// overlapping episode cards (run of 20 Nov: 10-add-source-learn-more, 56-show-season-2-episode-row, 65 at Larger Text).
    public static func focusDirection(from focused: AXRect, to target: AXRect) -> Arrow {
        if target.isEmpty { return .down }
        let dy: Double = target.midY - focused.midY
        let dx: Double = target.midX - focused.midX
        if abs(dy) > max(8, min(focused.height, target.height) / 2) { return dy > 0 ? .down : .up }
        return dx > 0 ? .right : .left
    }

    /// #36 8 T5: the focus is on the target when it is the same element (same non-empty label) or when EACH frame holds the
    /// other's centre. The old rule (`oldFocusReached`, one centre inside the other frame) stopped on More on the show page:
    /// 55-show-page-HIERARCHY has More at (344, 489, 171 x 66), centre (429.5, 522), inside the S1 E1 lockup's reported
    /// frame (80, 521, 410 x 615); test12 then pressed Select on More (22-player-skip-intro-NOT-REACHED).
    public static func focusReached(focused: AXRect, focusedLabel: String, target: AXRect, targetLabel: String) -> Bool {
        if !targetLabel.isEmpty && focusedLabel == targetLabel { return true }
        return focused.contains(x: target.midX, y: target.midY) && target.contains(x: focused.midX, y: focused.midY)
    }

    /// The rule of `focus(_:in:)` before #36: one centre inside the other frame.
    public static func oldFocusReached(focused: AXRect, target: AXRect) -> Bool {
        focused.contains(x: target.midX, y: target.midY) || target.contains(x: focused.midX, y: focused.midY)
    }

    /// The old rule of `focus(_:in:)` before #33, kept so the tests show where it went wrong.
    public static func oldFocusDirection(from f: AXRect, to t: AXRect) -> Arrow {
        if t.y >= f.maxY - 2 { return .down }
        if t.maxY <= f.y + 2 { return .up }
        return t.midX > f.midX ? .right : .left
    }

    // MARK: I: spacing

    /// #33 I: the vertical gap between the elements with identifiers `anchors` (their lowest edge) and the topmost element
    /// of `kinds` that starts below them, outside the tab bar. Passes at `minimum` or more. The movie and show pages use
    /// the button row (control.play, control.more) and the next StaticText (a heading); the grids use the toolbar's
    /// controls and the first Button or Cell (a card).
    public static func gapBelow(in dump: AccessibilityDump, anchors: [String], kinds: Set<String>, minimum: Double, what: String) -> CheckResult {
        let anchorFrames: [AXRect] = anchors.flatMap { dump.indices(identifier: $0) }.compactMap { dump.nodes[$0].frame }.filter { !$0.isEmpty }
        guard let bottom = anchorFrames.map(\.maxY).max() else {
            return CheckResult(passed: false, lines: ["none of \(anchors) in the tree", "GAP NOT MEASURED"])
        }
        let below: [(Int, AXRect)] = dump.nodes.indices.compactMap { (index: Int) -> (Int, AXRect)? in
            let node: AXNode = dump.nodes[index]
            guard kinds.contains(node.type), !anchors.contains(node.identifier), !dump.isInTabBar(index),
                  let frame = node.frame, !frame.isEmpty, frame.y >= bottom - 1 else { return nil }
            return (index, frame)
        }
        guard let next = below.min(by: { $0.1.y < $1.1.y }) else {
            return CheckResult(passed: false, lines: ["nothing below y \(Int(bottom))", "GAP NOT MEASURED"])
        }
        let gap: Double = next.1.y - bottom
        let ok: Bool = gap >= minimum - 0.5
        return CheckResult(passed: ok, lines: [
            "\(what): last edge of \(anchors.joined(separator: ", ")) at y \(Int(bottom)), next \(dump.nodes[next.0].type) “\(dump.text(of: next.0))” at y \(Int(next.1.y)): gap \(Int(gap)) pt, minimum \(Int(minimum))",
            ok ? "GAP OK" : "GAP TOO SMALL"])
    }

    // MARK: E: equal episode cards

    /// #33 E: every episode card ("S2, E3, Title" since R358, "S2 E3, Title" before; a Button or Cell) has the same size,
    /// within 1 pt. Picture 55 of the run of
    /// 20 Nov had S2 E3 at 378 x 566 beside 410 x 615 cards.
    public static func equalEpisodeCards(in dump: AccessibilityDump) -> CheckResult {
        let pattern: NSRegularExpression = episodeCardPattern
        let cards: [(String, AXRect)] = dump.nodes.compactMap { (node: AXNode) -> (String, AXRect)? in
            guard ["Button", "Cell"].contains(node.type), let frame = node.frame, !frame.isEmpty,
                  pattern.firstMatch(in: node.label, range: NSRange(node.label.startIndex..., in: node.label)) != nil else { return nil }
            return (node.label, frame)
        }
        guard cards.count >= 2 else { return CheckResult(passed: false, lines: ["\(cards.count) episode cards found, at least 2 expected", "CARDS NOT MEASURED"]) }
        var counts: [String: Int] = [:]
        for card in cards { counts["\(Int(card.1.width.rounded())) x \(Int(card.1.height.rounded()))", default: 0] += 1 }
        let common: String = counts.max { $0.value < $1.value }?.key ?? ""
        let reference: AXRect = cards.first { "\(Int($0.1.width.rounded())) x \(Int($0.1.height.rounded()))" == common }!.1
        let odd: [String] = cards.filter { abs($0.1.width - reference.width) > 1 || abs($0.1.height - reference.height) > 1 }
            .map { "“\($0.0)” \(Int($0.1.width)) x \(Int($0.1.height))" }
        var lines: [String] = ["\(cards.count) episode cards, most are \(common)"]
        if !odd.isEmpty { lines.append("different size: " + odd.joined(separator: "; ")) }
        lines.append(odd.isEmpty ? "EPISODE CARDS EQUAL OK" : "EPISODE CARDS NOT EQUAL")
        return CheckResult(passed: odd.isEmpty, lines: lines)
    }

    // MARK: S-A: text contrast on a task cover (#36 group 1, T6)

    /// #36 S-A (OPEN_QUESTIONS R253, PROVISIONAL): the contrast of every text of a task cover, measured on its screenshot by
    /// `Contrast.measure`. The texts are the leaf StaticText elements under `root` (a StaticText that holds another
    /// StaticText is a combined row label, measured through its parts). The topmost one is the cover's title and must reach
    /// 7:1; every other text 4.5:1. HIG Accessibility table: "Up to 17 pts | All | 4.5:1", "18 pts | All | 3:1". tvOS text is
    /// 23 pt and larger, so the 18 pt row (3:1) would allow less; 4.5:1 is the owner's target (R240, R253) and is used for
    /// every size. The verdict line is "CONTRAST OK" or "CONTRAST PROBLEM" with the texts below their target.
    public static func coverContrast(_ image: RGBImage, scale: Double, in dump: AccessibilityDump, root: Int) -> CheckResult {
        // Texts not wholly inside the safe area (HIG Layout: 60 pt from the top and bottom) are under the system scroll edge
        // effect or off the screen; they are listed, not measured (run of 20 Nov, 10: "Jellyfin" at y 1066 read 1.07:1).
        let window: AXRect = dump.window.flatMap { dump.nodes[$0].frame } ?? AXRect(x: 0, y: 0, width: 1920, height: 1080)
        var skipped: [String] = []
        let leaves: [Int] = dump.descendants(of: root).filter { (index: Int) -> Bool in
            let node: AXNode = dump.nodes[index]
            guard node.type == "StaticText", !node.label.isEmpty, !dump.isInTabBar(index),
                  let frame = node.frame, !frame.isEmpty,
                  !dump.descendants(of: index).contains(where: { dump.nodes[$0].type == "StaticText" }) else { return false }
            if frame.y < window.y + 60 - 10 || frame.maxY > window.maxY - 60 || frame.x < window.x || frame.maxX > window.maxX {
                skipped.append("“\(node.label)” \(frame)")
                return false
            }
            return true
        }
        guard !leaves.isEmpty else { return CheckResult(passed: false, lines: ["no text under the cover", "CONTRAST NOT MEASURED"]) }
        let title: Int = leaves.min { (dump.nodes[$0].frame?.y ?? 0) < (dump.nodes[$1].frame?.y ?? 0) }!
        var lines: [String] = ["targets: title 7:1, other text 4.5:1 (R253); \(leaves.count) texts"]
        if !skipped.isEmpty { lines.append("not measured (outside the 60 pt safe area): " + skipped.joined(separator: "; ")) }
        var below: [String] = []
        var seen: Set<String> = []
        for index in leaves {
            let node: AXNode = dump.nodes[index]
            let frame: AXRect = node.frame!
            let key: String = node.label + frame.description
            guard seen.insert(key).inserted else { continue }
            let target: Double = index == title ? 7 : 4.5
            let role: String = index == title ? "title" : "text"
            guard let m = Contrast.measure(image, frame: frame, scale: scale) else {
                lines.append("\(role) “\(node.label)” \(frame): outside the picture"); continue
            }
            var line: String = "\(role) “\(node.label)” \(frame): \(m)"
            if m.ratio < target {
                line += String(format: " BELOW %.1f", target)
                below.append("“\(node.label)” \(String(format: "%.2f", m.ratio)):1")
            }
            lines.append(line)
        }
        lines.append(below.isEmpty ? "CONTRAST OK" : "CONTRAST PROBLEM: " + below.joined(separator: "; "))
        return CheckResult(passed: below.isEmpty, lines: lines)
    }

    // MARK: S-C: buttons side by side are the same size (#36 group 3)

    /// #36 S-C (OPEN_QUESTIONS R255, PROVISIONAL): the buttons under `root` that stand side by side (centres within 2 pt
    /// vertically, outside the tab bar) must have the same width and height (within 1 pt) AT REST and be at least 66 pt
    /// high (HIG Accessibility, tvOS default control size). A button alone on its line is not compared. Passes with no
    /// such group.
    /// The focused button is drawn larger by the system focus effect (HIG Focus and selection, tvOS: "focusing an item
    /// often increases its scale"; run of 20 Nov, third run: “Connect” focused 545 x 104 beside “Cancel” at rest 537 x 96),
    /// so its frame is not its resting size. It is compared with the resting buttons of its row instead: each side may be
    /// from equal to `focusScale` (1.10) times theirs. The equal-size and 66 pt rules apply to the resting frames.
    public static let focusScale: Double = 1.10

    public static func sideBySideButtons(in dump: AccessibilityDump, root: Int) -> CheckResult {
        let buttons: [(String, AXRect, Bool)] = dump.descendants(of: root).compactMap { (index: Int) -> (String, AXRect, Bool)? in
            let node: AXNode = dump.nodes[index]
            guard node.type == "Button", !dump.isInTabBar(index), let frame = node.frame, !frame.isEmpty else { return nil }
            return (dump.text(of: index), frame, node.isFocused)
        }
        var groups: [[(String, AXRect, Bool)]] = []
        for button in buttons.sorted(by: { $0.1.x < $1.1.x }) {
            if let i = groups.firstIndex(where: { abs($0[0].1.midY - button.1.midY) <= 2 }) {
                // The same element reported twice (a button and its label element) is one button.
                if !groups[i].contains(where: { abs($0.1.x - button.1.x) < 1 && abs($0.1.width - button.1.width) < 1 }) {
                    groups[i].append(button)
                }
            } else {
                groups.append([button])
            }
        }
        var lines: [String] = []
        var problems: [String] = []
        for group in groups where group.count >= 2 {
            let names: String = group.map {
                "“\($0.0)” \(Int($0.1.width.rounded())) x \(Int($0.1.height.rounded()))" + ($0.2 ? " (focused)" : "")
            }.joined(separator: ", ")
            lines.append("side by side: " + names)
            let resting: [AXRect] = group.filter { !$0.2 }.map { $0.1 }
            let focused: [AXRect] = group.filter { $0.2 }.map { $0.1 }
            if let first = resting.first {
                if resting.contains(where: { abs($0.width - first.width) > 1 || abs($0.height - first.height) > 1 }) {
                    problems.append("not the same size at rest: " + names)
                }
                if resting.contains(where: { $0.height < 66 - 0.5 }) { problems.append("lower than 66 pt at rest: " + names) }
                for f in focused {
                    let w: Double = f.width / first.width
                    let h: Double = f.height / first.height
                    if w < 1 - 1 / first.width || h < 1 - 1 / first.height || w > focusScale || h > focusScale {
                        problems.append(String(format: "the focused button is %.3f x %.3f its resting neighbour (allowed 1 to %.2f): ",
                                               w, h, focusScale) + names)
                    }
                }
                if !focused.isEmpty { lines.append("the focused button is compared at up to \(focusScale) times the resting size") }
            } else if group.contains(where: { $0.1.height < 66 - 0.5 }) {
                problems.append("lower than 66 pt: " + names)
            }
        }
        if lines.isEmpty { lines.append("no buttons side by side") }
        lines.append(problems.isEmpty ? "BUTTONS OK" : "BUTTONS PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    // MARK: L: pictures that must change

    /// #33 L: two captures of a step that was meant to change the screen. Identical pixels fail with the reason.
    public static func changed(_ before: [UInt8], _ after: [UInt8], step: String) -> CheckResult {
        if before == after {
            return CheckResult(passed: false, lines: ["identical, pixel for pixel: \(step) did not change the screen", "SCREEN UNCHANGED"])
        }
        return CheckResult(passed: true, lines: ["the screen changed after \(step)", "SCREEN CHANGED OK"])
    }

    // MARK: #36 group 5b: the focused key of the linear keyboard

    /// #36 group 5b: the index of the focused key of the tvOS linear keyboard, or nil. No key carries the focus flag in the
    /// tree (76-search-results-HIERARCHY of the third run of 20 Nov); the focused key is drawn larger ("t" {1343, 253.5,
    /// 70 x 80} beside 54 x 64 keys). The key whose height is at least 8 pt over the median height, and the tallest, is it;
    /// none or two of the same height: nil.
    public static func focusedKey(_ keys: [(label: String, frame: AXRect)]) -> Int? {
        guard keys.count >= 3 else { return nil }
        let heights: [Double] = keys.map(\.frame.height).sorted()
        let median: Double = heights[heights.count / 2]
        let tallest: Double = heights.last ?? 0
        guard tallest >= median + 8 else { return nil }
        let candidates: [Int] = keys.indices.filter { abs(keys[$0].frame.height - tallest) < 0.5 }
        return candidates.count == 1 ? candidates[0] : nil
    }

    // MARK: #36 group 3: a form inside the safe area

    /// #36 group 3 (OPEN_QUESTIONS R265, PROVISIONAL): every named element (the fields, Connect and Cancel of a form) lies
    /// inside the window less `inset` points at the top and the bottom (HIG Layout: the tvOS safe area is 60 pt at the top
    /// and the bottom). 94-larger-text-source-form of the third run of 20 Nov: four fields with a hint line each pushed
    /// Connect and Cancel below the bottom of the screen. A missing element fails too (it was not laid out on screen).
    public static func insideSafeArea(_ elements: [(name: String, frame: AXRect?)], window: AXRect, inset: Double = 60) -> CheckResult {
        let top: Double = window.y + inset
        let bottom: Double = window.maxY - inset
        var lines: [String] = ["safe area: y \(Int(top)) to \(Int(bottom))"]
        var outside: [String] = []
        for element in elements {
            guard let frame = element.frame else {
                lines.append("\u{201C}\(element.name)\u{201D}: not on screen")
                outside.append("\u{201C}\(element.name)\u{201D} not on screen")
                continue
            }
            let inside: Bool = frame.y >= top - 0.5 && frame.maxY <= bottom + 0.5
            lines.append("\u{201C}\(element.name)\u{201D} \(frame): " + (inside ? "inside" : "OUTSIDE"))
            if !inside { outside.append("\u{201C}\(element.name)\u{201D} \(frame)") }
        }
        lines.append(outside.isEmpty ? "INSIDE THE SAFE AREA OK" : "OUTSIDE THE SAFE AREA: " + outside.joined(separator: "; "))
        return CheckResult(passed: outside.isEmpty, lines: lines)
    }

    // MARK: #36 group 1 d / group 4: a card caption is whole, and stays still

    /// How close (in points) to the right edge of its column a caption's ink may come before it counts as cut off.
    public static let captionEdge: Double = 6
    /// R293: a caption taller than this has wrapped onto two or more lines (one line of Caption, 25 pt, or Caption 2,
    /// 23 pt, is about 30 pt high; two lines are 58 pt in the fourth run of 20 Nov).
    public static let captionOneLineMaxHeight: Double = 44

    /// #36 group 4 (OPEN_QUESTIONS R264, PROVISIONAL): the caption of a card is drawn whole, not cut at its column's right
    /// edge. `column` is the space the caption may use (the card's width less its side paddings), `text` the caption's own
    /// frame. A caption narrower than its column is laid out at its own width and whole. One that fills the column is cut
    /// when it has ink in the last `captionEdge` points: third run of 20 Nov, 56 "S2 E3 · A very long episode title that i"
    /// (the "i" at x 1367 to 1370, column ending at 1374: 26 ink pixels) and 50 "… Than Any" (the "y" at about 620, column
    /// ending at 624: 6 ink pixels); the whole S2 E2 caption beside it has none. Ink: a pixel of luminance 0.3 or more and
    /// little colour (the caption is the primary label colour on the darker backdrop). A scaled line whose last glyph ends
    /// within `captionEdge` of the edge would also be reported cut: the check errs towards "cut" (R264, unverified until a run).
    public static func captionFits(_ image: RGBImage, scale: Double, column: AXRect, text: AXRect) -> CheckResult {
        var lines: [String] = ["caption \(text) in column \(column)"]
        if text.maxX > column.maxX + 1 {
            lines.append("the caption is wider than its column")
            lines.append("CAPTION CUT")
            return CheckResult(passed: false, lines: lines)
        }
        if text.width < column.width - 1 {
            lines.append("the caption is narrower than its column: laid out at its own width")
            lines.append("CAPTION WHOLE OK")
            return CheckResult(passed: true, lines: lines)
        }
        // R293: a caption that wrapped was broken into lines by the system at its column's width, so its ink may reach
        // the right edge without anything being cut (fourth run of 20 Nov: 50-later "...Than Any / Card Is Wide" and
        // 56-later "...title that / is wider than any episode card on the / show page", both whole in the pictures, failed
        // with 9 and 27 pixels in the last 6 pt). The edge rule stays for one-line captions.
        if text.height > captionOneLineMaxHeight {
            lines.append("the caption wrapped onto more than one line (\(Int(text.height)) pt high): broken into lines at the column's width")
            lines.append("CAPTION WHOLE OK")
            return CheckResult(passed: true, lines: lines)
        }
        let x0: Int = max(0, Int(((column.maxX - captionEdge) * scale).rounded(.down)))
        let x1: Int = min(image.width, Int((column.maxX * scale).rounded(.up)))
        let y0: Int = max(0, Int((text.y * scale).rounded(.down)))
        let y1: Int = min(image.height, Int((text.maxY * scale).rounded(.up)))
        var ink: Int = 0
        if x0 < x1, y0 < y1 {
            for y in y0..<y1 {
                for x in x0..<x1 {
                    let c: RGB = image.pixel(x, y)
                    let spread: Int = Int(max(c.r, c.g, c.b)) - Int(min(c.r, c.g, c.b))
                    if Contrast.luminance(c) >= 0.3 && spread <= 48 { ink += 1 }
                }
            }
        }
        lines.append("\(ink) caption pixels in the last \(Int(captionEdge)) pt of the column")
        let fits: Bool = ink < 2
        lines.append(fits ? "CAPTION WHOLE OK" : "CAPTION CUT")
        return CheckResult(passed: fits, lines: lines)
    }

    /// #36 group 1 d: the "-later" picture of 50 and 56. The system does NOT scroll a focused long caption (third run of
    /// 20 Nov: 50/50-later and 56/56-later identical, both captions cut), so a moving caption is no longer expected. The
    /// pair passes only when the two pictures are identical (nothing moves on its own) AND the caption is whole.
    public static func stillAndWhole(_ before: [UInt8], _ after: [UInt8], caption: CheckResult) -> CheckResult {
        var lines: [String] = []
        let still: Bool = before == after
        lines.append(still ? "the two pictures are identical: nothing moved during the wait" : "the two pictures differ: something moved during the wait")
        lines += caption.lines
        let passed: Bool = still && caption.passed
        lines.append(passed ? "CAPTION STILL AND WHOLE OK" : "CAPTION PROBLEM: " + [still ? nil : "the screen changed", caption.passed ? nil : "the caption is cut"].compactMap { $0 }.joined(separator: "; "))
        return CheckResult(passed: passed, lines: lines)
    }
}
