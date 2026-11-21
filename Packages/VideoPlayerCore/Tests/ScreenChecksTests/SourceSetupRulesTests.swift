import XCTest
@testable import ScreenChecks

/// R331: the checks of the redesigned source setup screens.
final class SourceSetupRulesTests: XCTestCase {
    // MARK: -KEYBOARD-HEADING

    /// The run of 20 Nov: the Name keyboard showed "Living Room" as its heading and no "Name".
    func testTheRunsKeyboardHeadingFails() {
        let result = ScreenRules.keyboardHeading(texts: ["Living Room", "abc", "Done"], fieldName: "Name", example: "Living Room")
        XCTAssertFalse(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "KEYBOARD HEADING IS NOT THE FIELD NAME")
    }

    func testTheFieldNameAsHeadingPasses() {
        let result = ScreenRules.keyboardHeading(texts: ["Name", "abc", "Done"], fieldName: "Name", example: "Living Room")
        XCTAssertTrue(result.passed, result.text)
    }

    func testNameAndExampleBothAsTextsFails() {
        XCTAssertFalse(ScreenRules.keyboardHeading(texts: ["Name", "Living Room"], fieldName: "Name", example: "Living Room").passed)
        XCTAssertTrue(ScreenRules.keyboardHeading(texts: [" Password "], fieldName: "Password", example: nil).passed)
        XCTAssertFalse(ScreenRules.keyboardHeading(texts: [], fieldName: "Password", example: nil).passed)
    }

    // MARK: -NO-PLACEHOLDER-VALUES

    func testEmptyRowsPass() {
        let result = ScreenRules.noPlaceholderValues(rows: [("Name", ""), ("Address", " ")], placeholders: ["Optional", "Living Room"])
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "NO PLACEHOLDER VALUES OK")
    }

    /// The run of 20 Nov: "Optional" in the User Name and Password fields of the WebDAV form.
    func testOptionalAsAValueFails() {
        let result = ScreenRules.noPlaceholderValues(rows: [("Name", ""), ("User Name", "Optional"), ("Password", "Optional")],
                                                     placeholders: ["Optional", "Required", "Living Room"])
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("\u{201C}User Name\u{201D} shows \u{201C}Optional\u{201D}"), result.text)
    }

    func testAnyValueOnAnEmptyFormAndNoRowsFail() {
        XCTAssertFalse(ScreenRules.noPlaceholderValues(rows: [("Name", "Den")], placeholders: ["Optional"]).passed)
        XCTAssertFalse(ScreenRules.noPlaceholderValues(rows: [], placeholders: ["Optional"]).passed)
    }

    // MARK: -ACTIONS

    private let shapeOK = CheckResult(passed: true, lines: ["FIELDS VISIBLE AT REST OK"])
    private let shapeNone = CheckResult(passed: false, lines: ["FIELD WITHOUT A VISIBLE SHAPE AT REST: \u{201C}Connect\u{201D}"])

    func testConnectAloneWithAShapePasses() {
        let result = ScreenRules.oneProminentAction(actions: ["Connect"], expected: "Connect", shape: shapeOK)
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "ONE PROMINENT ACTION OK")
    }

    /// The run of 20 Nov: Connect and Cancel side by side, drawn alike.
    func testConnectAndCancelFail() {
        XCTAssertFalse(ScreenRules.oneProminentAction(actions: ["Connect", "Cancel"], expected: "Connect", shape: shapeOK).passed)
        XCTAssertFalse(ScreenRules.oneProminentAction(actions: [], expected: "Connect", shape: shapeOK).passed)
    }

    func testNoShapeOrNotMeasuredFails() {
        XCTAssertFalse(ScreenRules.oneProminentAction(actions: ["Connect"], expected: "Connect", shape: shapeNone).passed)
        XCTAssertFalse(ScreenRules.oneProminentAction(actions: ["Connect"], expected: "Connect", shape: nil).passed)
    }

    // MARK: -ROWS-REACHABLE

    func testEveryRowInOrderPasses() {
        let result = ScreenRules.everyRowReached(rows: ["name", "address"], last: "connect",
                                                 focusPath: ["name", "address", "connect", "connect"], lastInside: true)
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "EVERY ROW REACHABLE OK")
    }

    func testAMissedRowFails() {
        let result = ScreenRules.everyRowReached(rows: ["name", "address", "password"], last: "connect",
                                                 focusPath: ["name", "address", "connect"], lastInside: true)
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("password never focused"), result.text)
    }

    func testOutOfOrderOrConnectOutsideFails() {
        XCTAssertFalse(ScreenRules.everyRowReached(rows: ["name", "address"], last: "connect",
                                                   focusPath: ["address", "name", "connect"], lastInside: true).passed)
        XCTAssertFalse(ScreenRules.everyRowReached(rows: ["name"], last: "connect", focusPath: ["name", "connect"], lastInside: false).passed)
        XCTAssertFalse(ScreenRules.everyRowReached(rows: ["name"], last: "connect", focusPath: ["name", "connect"], lastInside: nil).passed)
    }

    /// Rows that are not field rows (Search Your Network, Learn More) may be in the path; they do not count.
    func testOtherRowsInThePathAreIgnored() {
        XCTAssertTrue(ScreenRules.everyRowReached(rows: ["name"], last: "connect",
                                                  focusPath: ["search", "name", "connect", "about"], lastInside: true).passed)
    }
}
