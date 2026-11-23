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
