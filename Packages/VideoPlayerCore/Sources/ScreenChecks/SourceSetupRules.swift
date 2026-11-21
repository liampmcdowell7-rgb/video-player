import Foundation

/// The UI checks of the redesigned source setup screens (docs/SOURCE_SETUP_DESIGN.md, OPEN_QUESTIONS R331, PROVISIONAL).
/// Plain Swift (no XCTest, no app types), so the same file runs in the UI-test bundle and in the Linux tests.
public extension ScreenRules {
    /// R321: the keyboard screen opened from a field's entry page names the FIELD, not its example (the run of 20 Nov
    /// showed "Living Room" as the heading of the Name keyboard, 11-form-webdav-keyboard-name). `texts` are the static texts
    /// on the keyboard screen, top first. Passes when one of them is the field name and none of them is the example (an
    /// example inside the text field is its placeholder, not a static text).
    static func keyboardHeading(texts: [String], fieldName: String, example: String?) -> CheckResult {
        var lines: [String] = ["keyboard screen texts: " + texts.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")]
        let hasName: Bool = texts.contains { $0.trimmingCharacters(in: .whitespaces) == fieldName }
        let hasExample: Bool = example.map { (ex: String) -> Bool in texts.contains { $0.trimmingCharacters(in: .whitespaces) == ex } } ?? false
        lines.append("field name \u{201C}\(fieldName)\u{201D}: " + (hasName ? "shown" : "NOT SHOWN"))
        if let example { lines.append("example \u{201C}\(example)\u{201D} as a text: " + (hasExample ? "SHOWN" : "not shown")) }
        let passed: Bool = hasName && !hasExample
        lines.append(passed ? "KEYBOARD HEADING IS THE FIELD NAME OK" : "KEYBOARD HEADING IS NOT THE FIELD NAME")
        return CheckResult(passed: passed, lines: lines)
    }

    /// R322: on an EMPTY form no field row shows a placeholder as its value. `rows` are the field rows (name and the value
    /// the row reports); `placeholders` the words that would only look like a value ("Optional", "Required" and the
    /// form's examples). A row with any other value fails too, because the form is empty (pickers are left out by the
    /// caller: they always show their answer).
    static func noPlaceholderValues(rows: [(name: String, value: String)], placeholders: Set<String>) -> CheckResult {
        var lines: [String] = []
        var bad: [String] = []
        for row in rows {
            let value: String = row.value.trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                lines.append("\u{201C}\(row.name)\u{201D}: empty")
            } else if placeholders.contains(value) {
                lines.append("\u{201C}\(row.name)\u{201D}: \u{201C}\(value)\u{201D} PLACEHOLDER AS VALUE")
                bad.append("\u{201C}\(row.name)\u{201D} shows \u{201C}\(value)\u{201D}")
            } else {
                lines.append("\u{201C}\(row.name)\u{201D}: \u{201C}\(value)\u{201D} VALUE ON AN EMPTY FORM")
                bad.append("\u{201C}\(row.name)\u{201D} shows \u{201C}\(value)\u{201D}")
            }
        }
        if rows.isEmpty {
            lines.append("NO FIELD ROW FOUND")
            return CheckResult(passed: false, lines: lines)
        }
        lines.append(bad.isEmpty ? "NO PLACEHOLDER VALUES OK" : "PLACEHOLDER VALUES: " + bad.joined(separator: "; "))
        return CheckResult(passed: bad.isEmpty, lines: lines)
    }

    /// R324: a form has exactly one action button (Connect), no Cancel, and the action shows a shape at rest (its fill
    /// differs from the page by at least `fieldShapeMinimumRatio`, measured by the caller with `fieldShapeAtRest`).
    /// `actions` are the labels of the form's action buttons (bezeled buttons, not rows).
    static func oneProminentAction(actions: [String], expected: String, shape: CheckResult?) -> CheckResult {
        var lines: [String] = ["action buttons: " + actions.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")]
        var problems: [String] = []
        if actions != [expected] { problems.append("expected only \u{201C}\(expected)\u{201D}") }
        if let shape {
            lines.append(contentsOf: shape.lines.map { "  " + $0 })
            if !shape.passed { problems.append("\u{201C}\(expected)\u{201D} has no visible shape at rest") }
        } else {
            lines.append("shape at rest: NOT MEASURED")
            problems.append("shape not measured")
        }
        lines.append(problems.isEmpty ? "ONE PROMINENT ACTION OK" : "ACTIONS PROBLEM: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }

    /// R331 (Larger Text): pressing Down from the top of a form reached every one of `rows` (identifiers) and `last`
    /// (Connect), in that order of first focus. `focusPath` is the identifier focused after each press, top first; `lastInside`
    /// whether `last` was inside the safe area while focused (nil: not measured).
    static func everyRowReached(rows: [String], last: String, focusPath: [String], lastInside: Bool?) -> CheckResult {
        var lines: [String] = ["focus path: " + focusPath.joined(separator: " > ")]
        let missing: [String] = (rows + [last]).filter { !focusPath.contains($0) }
        var problems: [String] = missing.map { "\($0) never focused" }
        let firsts: [String] = focusPath.reduce(into: [String]()) { (seen: inout [String], id: String) in
            if (rows + [last]).contains(id) && !seen.contains(id) { seen.append(id) }
        }
        if missing.isEmpty && firsts != rows + [last] { problems.append("order " + firsts.joined(separator: ", ")) }
        switch lastInside {
        case .some(true): lines.append("\(last) inside the safe area when focused")
        case .some(false): problems.append("\(last) outside the safe area when focused")
        case .none: problems.append("\(last) not measured")
        }
        lines.append(problems.isEmpty ? "EVERY ROW REACHABLE OK" : "ROWS NOT REACHABLE: " + problems.joined(separator: "; "))
        return CheckResult(passed: problems.isEmpty, lines: lines)
    }
}
