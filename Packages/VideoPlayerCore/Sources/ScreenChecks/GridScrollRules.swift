import Foundation

/// R443 (owner's device test of 23 Nov 2026, Movies and Shows): what a scrolled library grid must look like, as pure
/// checks on frames so a Linux test can run them on fixtures that are deliberately wrong and the UI test can run them on
/// the frames it reads after every scroll step.
public enum GridScrollRules {
    /// Item 1: no control (Sort and Filter, Save View, More) sits on a poster. Frames that overlap by more than one point
    /// each way count; touching edges do not.
    public static func controlsClearOfPosters(controls: [(String, AXRect)], posters: [(String, AXRect)]) -> CheckResult {
        var lines: [String] = controls.map { "control\t\($0.0)\t\($0.1)" }
        var problems: [String] = []
        for control in controls {
            for poster in posters {
                let overlap: AXRect = control.1.intersection(poster.1)
                if overlap.width > 1, overlap.height > 1 { problems.append("“\(control.0)” is on “\(poster.0)”") }
            }
        }
        lines.append(problems.isEmpty ? "CONTROLS CLEAR OF POSTERS OK (\(posters.count) cards)" : "CONTROLS ON POSTERS PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    /// Item 2: a row of cards is fully below the header area or fully above it, never cut by its lower edge.
    /// `headerBottom` is where the header area ends (the bottom of the controls, or the top safe area when they have
    /// scrolled away). Cards are grouped into rows by their top edge (within `rowTolerance`).
    public static func noHalfRowUnderHeader(cards: [(String, AXRect)], headerBottom: Double, rowTolerance: Double = 4) -> CheckResult {
        var problems: [String] = []
        for row in rows(cards, tolerance: rowTolerance) {
            let top: Double = row.map { $0.1.y }.min() ?? 0
            let bottom: Double = row.map { $0.1.maxY }.max() ?? 0
            // Cut by the header's lower edge: it starts above it and ends below it.
            if top < headerBottom - 1, bottom > headerBottom + 1 {
                problems.append("the row of “\(row[0].0)” starts \(Int((headerBottom - top).rounded())) pt above the header's lower edge and ends \(Int((bottom - headerBottom).rounded())) pt below it")
            }
        }
        let lines: [String] = [problems.isEmpty ? "NO HALF ROW UNDER THE HEADER OK (edge at \(Int(headerBottom.rounded())))" : "HALF ROW UNDER THE HEADER PROBLEM: " + problems.joined(separator: "; ")]
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    /// The vertical distance between the tops of consecutive rows, in points (nil with fewer than two rows), and whether
    /// every pitch is the same within `tolerance`.
    public static func rowPitch(cards: [(String, AXRect)], tolerance: Double = 2) -> (pitch: Double?, result: CheckResult) {
        let tops: [Double] = rows(cards, tolerance: 4).map { row in row.map { $0.1.y }.min() ?? 0 }.sorted()
        guard tops.count >= 2 else { return (nil, CheckResult(passed: true, lines: ["ROW PITCH: fewer than two rows"])) }
        let pitches: [Double] = zip(tops, tops.dropFirst()).map { $1 - $0 }
        let first: Double = pitches[0]
        let same: Bool = pitches.allSatisfy { abs($0 - first) <= tolerance }
        let line: String = same ? "ROW PITCH OK: \(Int(first.rounded())) pt" : "ROW PITCH PROBLEM: " + pitches.map { "\(Int($0.rounded()))" }.joined(separator: ", ")
        return (first, CheckResult(passed: same, lines: [line]))
    }

    /// Item 6: no title is cut. `cut` lists the titles whose text fell to the scrolling marquee (the text did not fit at
    /// the readable floor); the app marks them with the identifier `text.marquee`.
    public static func noTitleCut(cut: [String], total: Int) -> CheckResult {
        let line: String = cut.isEmpty ? "NO TITLE CUT OK (\(total) titles)" : "TITLE CUT PROBLEM: " + cut.map { "“\($0)”" }.joined(separator: ", ")
        return CheckResult(passed: cut.isEmpty, lines: [line])
    }

    /// R471 (49), owner's report of 25 Nov 2026 ("only one row displays at a time", one Down "skip[s] several items"):
    /// one press of Down moves the focus to the row right under the one it was on, never further. `before` holds the cards
    /// read before the press (with their frames then), `focusedBefore` and `focusedAfter` the focused card's label before
    /// and after it. Passes on the last row (no row under it) when the focus stays in that row.
    public static func downReachesNextRow(before: [(String, AXRect)], focusedBefore: String, focusedAfter: String,
                                          rowTolerance: Double = 4) -> CheckResult {
        let grouped: [[(String, AXRect)]] = rows(before, tolerance: rowTolerance)
        guard let from = grouped.firstIndex(where: { $0.contains { $0.0 == focusedBefore } }) else {
            return CheckResult(passed: false, lines: ["DOWN ONE ROW PROBLEM: “\(focusedBefore)” was not among the cards before the press"])
        }
        let expected: Int = min(from + 1, grouped.count - 1)
        let landed: Int? = grouped.firstIndex(where: { $0.contains { $0.0 == focusedAfter } })
        let nextLabels: String = grouped[expected].map { "“\($0.0)”" }.joined(separator: ", ")
        if landed == expected {
            return CheckResult(passed: true, lines: ["DOWN ONE ROW OK: “\(focusedBefore)” to “\(focusedAfter)”"])
        }
        let skipped: String = landed.map { "\($0 - from - 1) row(s) skipped" } ?? "a card that was not on the page before the press"
        return CheckResult(passed: false, lines: ["DOWN ONE ROW PROBLEM: “\(focusedBefore)” to “\(focusedAfter)”, \(skipped); the next row was \(nextLabels)"])
    }

    /// R471 (49): after a move the focused card's row is wholly on screen (`screenTop` to `screenBottom`).
    public static func focusedRowWhole(cards: [(String, AXRect)], focused: String, screenTop: Double, screenBottom: Double,
                                       rowTolerance: Double = 4) -> CheckResult {
        guard let row = rows(cards, tolerance: rowTolerance).first(where: { $0.contains { $0.0 == focused } }) else {
            return CheckResult(passed: false, lines: ["FOCUSED ROW WHOLE PROBLEM: “\(focused)” is not a card on the page"])
        }
        let top: Double = row.map { $0.1.y }.min() ?? 0
        let bottom: Double = row.map { $0.1.maxY }.max() ?? 0
        let whole: Bool = top >= screenTop - 1 && bottom <= screenBottom + 1
        return CheckResult(passed: whole, lines: [whole ? "FOCUSED ROW WHOLE OK (\(Int(top.rounded())) to \(Int(bottom.rounded())))"
                                                       : "FOCUSED ROW WHOLE PROBLEM: the row of “\(focused)” runs \(Int(top.rounded())) to \(Int(bottom.rounded())), the screen \(Int(screenTop.rounded())) to \(Int(screenBottom.rounded()))"])
    }

    /// R471 (49): more than one row shows on screen when the grid has more than one row: the focused row and at least part
    /// of a row above or under it (`shown` lists the cards that are drawn, not the ones hidden or off screen).
    public static func moreThanOneRowShown(shown: [(String, AXRect)], totalRows: Int, screenTop: Double, screenBottom: Double,
                                           rowTolerance: Double = 4) -> CheckResult {
        let onScreen: [[(String, AXRect)]] = rows(shown, tolerance: rowTolerance).filter { row in
            row.contains { $0.1.maxY > screenTop + 1 && $0.1.y < screenBottom - 1 }
        }
        let passed: Bool = totalRows < 2 || onScreen.count >= 2
        return CheckResult(passed: passed, lines: [passed ? "ROWS ON SCREEN OK: \(onScreen.count)"
                                                         : "ROWS ON SCREEN PROBLEM: \(onScreen.count) of \(totalRows) rows drawn on screen"])
    }

    /// Cards grouped into rows by their top edge, rows from the top down, cards in a row from the left.
    static func rows(_ cards: [(String, AXRect)], tolerance: Double) -> [[(String, AXRect)]] {
        var rows: [[(String, AXRect)]] = []
        for card in cards.sorted(by: { $0.1.y != $1.1.y ? $0.1.y < $1.1.y : $0.1.x < $1.1.x }) {
            if let last = rows.indices.last, abs((rows[last].first?.1.y ?? 0) - card.1.y) <= tolerance {
                rows[last].append(card)
            } else {
                rows.append([card])
            }
        }
        return rows
    }
}
