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
        return CheckResult(passed: false, lines: ["page screens still in the accessibility tree: \(visible.joined(separator: ", "))", "PAGE BEHIND THE COVER IS EXPOSED"])
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
    public static func coverLayout(in dump: AccessibilityDump, safeTop: Double = 60) -> CheckResult {
        guard let cover = dump.coverRoot else { return CheckResult(passed: false, lines: ["no cover subtree in the tree", "COVER NOT FOUND"]) }
        var lines: [String] = []
        var passed: Bool = true
        // The title is the cover's FIRST static text in tree order (the page header). Not the topmost one: rows a list has
        // built off screen report frames at y 0 (10-add-source-types: “Google Drive, No sign-in for TVs”).
        let texts: [Int] = dump.descendants(of: cover).filter { dump.nodes[$0].type == "StaticText" && !(dump.nodes[$0].frame?.isEmpty ?? true) }
        if let title = texts.first, let frame = dump.nodes[title].frame {
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
                let contained: Bool = overlap == a.1 || overlap == b.1
                // A field inside its row is nesting, not overlap; two rows sharing more than 4 pt of height is overlap.
                if !overlap.isEmpty, !contained, overlap.height > 4 { overlaps.append("“\(a.0)” and “\(b.0)”") }
            }
        }
        if !overlaps.isEmpty { passed = false; lines.append("rows overlap: " + overlaps.joined(separator: "; ")) }
        lines.append(passed ? "COVER LAYOUT OK" : "COVER LAYOUT PROBLEM")
        return CheckResult(passed: passed, lines: lines)
    }

    /// #34 3: the width the full toolbar row needs, from the controls' frames in order (first group, then second group),
    /// the explicit gaps of `GridToolbarLayout` and the count's width, against the width between the side margins.
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

    /// #33 E: every episode card ("S2 E3, Title", a Button or Cell) has the same size, within 1 pt. Picture 55 of the run of
    /// 20 Nov had S2 E3 at 378 x 566 beside 410 x 615 cards.
    public static func equalEpisodeCards(in dump: AccessibilityDump) -> CheckResult {
        let pattern: NSRegularExpression = try! NSRegularExpression(pattern: "^S[0-9]+ E[0-9]+, ")
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

    // MARK: L: pictures that must change

    /// #33 L: two captures of a step that was meant to change the screen. Identical pixels fail with the reason.
    public static func changed(_ before: [UInt8], _ after: [UInt8], step: String) -> CheckResult {
        if before == after {
            return CheckResult(passed: false, lines: ["identical, pixel for pixel: \(step) did not change the screen", "SCREEN UNCHANGED"])
        }
        return CheckResult(passed: true, lines: ["the screen changed after \(step)", "SCREEN CHANGED OK"])
    }
}
