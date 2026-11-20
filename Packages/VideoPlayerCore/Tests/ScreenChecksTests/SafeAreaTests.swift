import XCTest
@testable import ScreenChecks

/// #36 group 3 (OPEN_QUESTIONS R265): the fields, Connect and Cancel of a form lie inside the 60 pt safe area.
final class SafeAreaTests: XCTestCase {
    let window = AXRect(x: 0, y: 0, width: 1920, height: 1080)

    /// 94-larger-text-source-form of the third run of 20 Nov (its -HIERARCHY note): the Password field at y 1056.8 and
    /// Connect and Cancel at y 1167, below the bottom of the safe area (1020) and of the screen. The check fails there.
    func testTheRunsLargerTextFormFailsTheSafeArea() {
        let elements: [(name: String, frame: AXRect?)] = [
            (name: "Name", frame: AXRect(x: 389, y: 369.7, width: 1142, height: 72.5)),
            (name: "Address", frame: AXRect(x: 389, y: 598.7, width: 1142, height: 72.5)),
            (name: "User Name", frame: AXRect(x: 389, y: 827.7, width: 1142, height: 72.5)),
            (name: "Password", frame: AXRect(x: 389, y: 1056.8, width: 1142, height: 70.5)),
            (name: "Connect", frame: AXRect(x: 393, y: 1167, width: 537, height: 96)),
            (name: "Cancel", frame: AXRect(x: 990, y: 1167, width: 537, height: 96)),
        ]
        let result: CheckResult = ScreenRules.insideSafeArea(elements, window: window)
        XCTAssertFalse(result.passed, result.text)
        let verdict: String = result.lines.last ?? ""
        XCTAssertTrue(verdict.contains("“Password”") && verdict.contains("“Connect”") && verdict.contains("“Cancel”"), result.text)
        XCTAssertFalse(verdict.contains("“Name”"), result.text)
    }

    func testAFormThatFitsPassesAndAMissingButtonFails() {
        let fits: [(name: String, frame: AXRect?)] = [
            (name: "Name", frame: AXRect(x: 389, y: 300, width: 1142, height: 66)),
            (name: "Connect", frame: AXRect(x: 393, y: 900, width: 537, height: 96)),
            (name: "Cancel", frame: AXRect(x: 990, y: 900, width: 537, height: 96)),
        ]
        XCTAssertTrue(ScreenRules.insideSafeArea(fits, window: window).passed)
        // Exactly on the edges (60 and 1020) is inside.
        XCTAssertTrue(ScreenRules.insideSafeArea([(name: "Edge", frame: AXRect(x: 0, y: 60, width: 10, height: 960))], window: window).passed)
        XCTAssertFalse(ScreenRules.insideSafeArea([(name: "High", frame: AXRect(x: 0, y: 40, width: 10, height: 50))], window: window).passed)
        XCTAssertFalse(ScreenRules.insideSafeArea(fits + [(name: "Done", frame: nil)], window: window).passed)
    }
}
