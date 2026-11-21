import XCTest
@testable import ScreenChecks

/// OPEN_QUESTIONS R273: a field without the focus shows a shape (a fill or an outline), and the form's fields lie inside the
/// safe area. Synthetic pictures at 1 px per pt; the form layout is the WebDAV form's (Name, Address, User Name, Password).
final class FieldShapeTests: XCTestCase {
    let page = RGB(r: 0, g: 0, b: 0)
    let fieldFill = RGB(r: 58, g: 58, b: 60)
    let white = RGB(r: 255, g: 255, b: 255)
    let window = AXRect(x: 0, y: 0, width: 1920, height: 1080)

    /// The four WebDAV fields, label above, 66 pt high, as R265 lays them out.
    func webdavFrames() -> [(String, AXRect)] {
        [("Name", AXRect(x: 389, y: 260, width: 1142, height: 66)),
         ("Address", AXRect(x: 389, y: 400, width: 1142, height: 66)),
         ("User Name", AXRect(x: 389, y: 540, width: 1142, height: 66)),
         ("Password", AXRect(x: 389, y: 680, width: 1142, height: 66))]
    }

    func picture(fill: RGB?, outline: RGB? = nil, prompt: Bool = true, labels: Bool = true) -> RGBImage {
        var image = RGBImage(width: 1920, height: 1080, fill: page)
        for (_, frame) in webdavFrames() {
            if labels { image.fill(AXRect(x: frame.x, y: frame.y - 45, width: 160, height: 35), scale: 1, with: white) }
            if let fill { image.fill(frame, scale: 1, with: fill) }
            if let outline {
                image.fill(AXRect(x: frame.x, y: frame.y, width: frame.width, height: 2), scale: 1, with: outline)
                image.fill(AXRect(x: frame.x, y: frame.maxY - 2, width: frame.width, height: 2), scale: 1, with: outline)
                image.fill(AXRect(x: frame.x, y: frame.y, width: 2, height: frame.height), scale: 1, with: outline)
                image.fill(AXRect(x: frame.maxX - 2, y: frame.y, width: 2, height: frame.height), scale: 1, with: outline)
            }
            // The prompt ("Living Room") in the middle of the field, in the system's grey.
            if prompt { image.fill(AXRect(x: frame.x + 20, y: frame.y + 16, width: 220, height: 34), scale: 1, with: RGB(r: 150, g: 150, b: 155)) }
        }
        return image
    }

    func fields(focused: String? = nil) -> [ScreenRules.FieldAtRest] {
        webdavFrames().map { ScreenRules.FieldAtRest(name: $0.0, frame: $0.1, isFocused: $0.0 == focused) }
    }

    /// The owner's report (TestFlight, 21 Nov 2026): labels, maybe the prompt, but no field shape. Must fail and name the fields.
    func testFieldsWithNoShapeAtRestFail() {
        let result = ScreenRules.fieldShapeAtRest(picture(fill: nil), fields: fields(), scale: 1)
        XCTAssertFalse(result.passed, result.text)
        let verdict: String = result.lines.last ?? ""
        for name in ["Name", "Address", "User Name", "Password"] { XCTAssertTrue(verdict.contains("\u{201C}\(name)\u{201D}"), result.text) }
    }

    /// The prompt text alone is not a shape.
    func testAPromptAloneIsNotAShape() {
        let result = ScreenRules.fieldShapeAtRest(picture(fill: nil, prompt: true), fields: fields(), scale: 1)
        XCTAssertFalse(result.passed, result.text)
    }

    func testAFilledFieldPasses() {
        let result = ScreenRules.fieldShapeAtRest(picture(fill: fieldFill), fields: fields(), scale: 1)
        XCTAssertTrue(result.passed, result.text)
        XCTAssertEqual(result.lines.last, "FIELDS VISIBLE AT REST OK")
    }

    func testAnOutlinedFieldWithoutAFillPasses() {
        let result = ScreenRules.fieldShapeAtRest(picture(fill: nil, outline: RGB(r: 110, g: 110, b: 115)), fields: fields(), scale: 1)
        XCTAssertTrue(result.passed, result.text)
    }

    /// A fill so close to the page that it reads as nothing (ratio under 1.1) fails.
    func testANearlyInvisibleFillFails() {
        let result = ScreenRules.fieldShapeAtRest(picture(fill: RGB(r: 3, g: 3, b: 3)), fields: fields(), scale: 1)
        XCTAssertFalse(result.passed, result.text)
    }

    /// The focused field is skipped (the system draws its focused look); the others must still have a shape.
    func testTheFocusedFieldIsSkippedTheOthersStillCount() {
        var image = picture(fill: nil)
        image.fill(webdavFrames()[0].1, scale: 1, with: white)
        let failing = ScreenRules.fieldShapeAtRest(image, fields: fields(focused: "Name"), scale: 1)
        XCTAssertFalse(failing.passed, failing.text)
        XCTAssertFalse((failing.lines.last ?? "").contains("\u{201C}Name\u{201D}"), failing.text)
        let passing = ScreenRules.fieldShapeAtRest(picture(fill: fieldFill), fields: fields(focused: "Name"), scale: 1)
        XCTAssertTrue(passing.passed, passing.text)
    }

    /// A field missing from the screen, or a form where every field has the focus (nothing checked), fails.
    func testAMissingFieldOrNothingToCheckFails() {
        var list = fields()
        list.append(ScreenRules.FieldAtRest(name: "Port", frame: nil, isFocused: false))
        XCTAssertFalse(ScreenRules.fieldShapeAtRest(picture(fill: fieldFill), fields: list, scale: 1).passed)
        XCTAssertFalse(ScreenRules.fieldShapeAtRest(picture(fill: fieldFill), fields: [], scale: 1).passed)
    }

    /// Retina pictures: 2 px per pt.
    func testScaleTwo() {
        var image = RGBImage(width: 3840, height: 2160, fill: page)
        for (_, frame) in webdavFrames() { image.fill(frame, scale: 2, with: fieldFill) }
        XCTAssertTrue(ScreenRules.fieldShapeAtRest(image, fields: fields(), scale: 2).passed)
        let empty = RGBImage(width: 3840, height: 2160, fill: page)
        XCTAssertFalse(ScreenRules.fieldShapeAtRest(empty, fields: fields(), scale: 2).passed)
    }

    /// The same four fields are inside the 60 pt safe area (the check the UI test now runs at the default text size too).
    func testTheWebDAVFieldsAreInsideTheSafeArea() {
        let elements: [(name: String, frame: AXRect?)] = webdavFrames().map { (name: $0.0, frame: $0.1) }
        XCTAssertTrue(ScreenRules.insideSafeArea(elements, window: window).passed)
    }
}
