import XCTest
@testable import ScreenChecks

/// #36 group 5b: the focused key of the tvOS linear keyboard is the enlarged one (no key carries the focus flag).
final class KeyboardFocusTests: XCTestCase {
    /// The keys of 76-search-results-HIERARCHY of the third run of 20 Nov (the row from "Numbers" to "delete"): "t" is
    /// {1343, 253.5, 70 x 80}, every other letter 54 x 64. The focus helper of that run stopped there.
    func testTheRunsKeyboardHasItsFocusOnT() {
        var keys: [(label: String, frame: AXRect)] = [
            (label: "Numbers", frame: AXRect(x: 117, y: 261.5, width: 89, height: 64)),
            (label: "SPACE", frame: AXRect(x: 206, y: 261.5, width: 119, height: 64)),
        ]
        let letters: [String] = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
        for (i, letter) in letters.enumerated() {
            if letter == "t" {
                keys.append((label: "t", frame: AXRect(x: 1343, y: 253.5, width: 70, height: 80)))
            } else {
                keys.append((label: letter, frame: AXRect(x: 325 + Double(i) * 54, y: 261.5, width: 54, height: 64)))
            }
        }
        keys.append((label: "delete", frame: AXRect(x: 1729, y: 261.5, width: 74, height: 64)))
        let focused: Int? = ScreenRules.focusedKey(keys)
        XCTAssertEqual(focused.map { keys[$0].label }, "t")
        // "s" is left of "t": the helper presses Left once.
        let s: Int = try! XCTUnwrap(keys.firstIndex { $0.label == "s" })
        XCTAssertLessThan(s, focused ?? 0)
    }

    func testNoEnlargedKeyOrTwoOfThemIsUnknown() {
        let even: [(label: String, frame: AXRect)] = (0..<5).map { (label: "k\($0)", frame: AXRect(x: Double($0) * 54, y: 0, width: 54, height: 64)) }
        XCTAssertNil(ScreenRules.focusedKey(even))
        var two = even
        two[1].frame = AXRect(x: 54, y: -8, width: 70, height: 80)
        two[3].frame = AXRect(x: 162, y: -8, width: 70, height: 80)
        XCTAssertNil(ScreenRules.focusedKey(two))
        var one = even
        one[2].frame = AXRect(x: 108, y: -8, width: 70, height: 80)
        XCTAssertEqual(ScreenRules.focusedKey(one), 2)
    }
}
