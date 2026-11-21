import XCTest
import Foundation
@testable import ScreenChecks

/// R345: the focused-row pixel check (`FocusRoom`) passes a whole rounded platter and fails one cut flat by its list's
/// edge; on the run of 21 Nov 2026 (VP_RUN_ARTIFACTS) it fails 31-settings-playback and passes 10-add-source-types.
final class FocusRoomTests: XCTestCase {
    static let backdrop: RGB = RGB(r: 40, g: 42, b: 46)
    static let platter: RGB = RGB(r: 254, g: 254, b: 254)

    /// A dark picture with a white rounded platter (radius `radius`) from x0 to x1, y0 to y1, with dark "text" in it, cut
    /// at `clipLeft` (pixels left of it stay backdrop), as the list did.
    func picture(x0: Int, x1: Int, y0: Int, y1: Int, radius: Int = 24, clipLeft: Int? = nil) -> RGBImage {
        var image: RGBImage = RGBImage(width: 1920, height: 1080, fill: Self.backdrop)
        for y in y0...y1 {
            for x in x0...x1 {
                let cx: Int = x < x0 + radius ? x0 + radius : (x > x1 - radius ? x1 - radius : x)
                let cy: Int = y < y0 + radius ? y0 + radius : (y > y1 - radius ? y1 - radius : y)
                let dx: Int = x - cx, dy: Int = y - cy
                guard dx * dx + dy * dy <= radius * radius else { continue }
                if let clipLeft, x < clipLeft { continue }
                image.set(x, y, Self.platter)
            }
        }
        // The row's title: dark glyph-like bars with gaps narrower than `FocusRoom.gap`.
        for y in (y0 + 25)...(y1 - 25) {
            for x in stride(from: x0 + 20, to: x0 + 420, by: 30) {
                for dx in 0..<14 { image.set(x + dx, y, RGB(r: 20, g: 20, b: 20)) }
            }
        }
        return image
    }

    func testAWholeRoundedFocusedRowPasses() {
        let result: CheckResult = FocusRoom.check(picture(x0: 986, x1: 1843, y0: 188, y1: 261))
        XCTAssertTrue(result.passed, result.text)
        XCTAssertTrue(result.text.contains("corners intact"), result.text)
    }

    func testARowCutFlatByItsListsLeftEdgeFails() {
        let result: CheckResult = FocusRoom.check(picture(x0: 982, x1: 1843, y0: 188, y1: 261, clipLeft: 990))
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("CUT FLAT ON THE LEFT"), result.text)
    }

    func testARowOutsideTheVisibleContainerFails() {
        let image: RGBImage = picture(x0: 986, x1: 1843, y0: 188, y1: 261)
        let result: CheckResult = FocusRoom.check(image, container: AXRect(x: 990, y: 0, width: 930, height: 1080))
        XCTAssertFalse(result.passed, result.text)
        XCTAssertTrue(result.text.contains("OUTSIDE THE VISIBLE CONTAINER"), result.text)
    }

    func testAPictureWithoutAFocusedRowIsNotMeasured() {
        let result: CheckResult = FocusRoom.check(RGBImage(width: 1920, height: 1080, fill: Self.backdrop))
        XCTAssertTrue(result.passed)
        XCTAssertTrue(result.text.contains("not measured"))
    }

    func testALongLineOfWhiteTextIsNotAPlatter() {
        var image: RGBImage = RGBImage(width: 1920, height: 1080, fill: Self.backdrop)
        for y in 300..<360 {
            for x in stride(from: 100, to: 1500, by: 20) {
                for dx in 0..<4 { image.set(x + dx, y, Self.platter) }
            }
        }
        XCTAssertTrue(FocusRoom.platters(in: image).isEmpty)
    }

    // MARK: Run artifacts: the pictures of 21 Nov 2026 on a0ae4a6

    func picture(_ path: String) throws -> RGBImage {
        guard let root = ProcessInfo.processInfo.environment["VP_RUN_ARTIFACTS"], !root.isEmpty else {
            throw XCTSkip("VP_RUN_ARTIFACTS is not set: the CI run's pictures are not on this machine")
        }
        let url: URL = URL(fileURLWithPath: root).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(path) is not in \(root)") }
        return try PNGDecoder.decode([UInt8](try Data(contentsOf: url)))
    }

    func testRunArtifactsTheSettingsRowOf31IsCutAndTheAddASourceRowOf10IsWhole() throws {
        let cut: CheckResult = FocusRoom.check(try picture("screenshots/31-settings-playback.png"))
        print("31-settings-playback:\n\(cut.text)")
        XCTAssertFalse(cut.passed, cut.text)
        XCTAssertTrue(cut.text.contains("x 990 to"), cut.text)
        let whole: CheckResult = FocusRoom.check(try picture("screenshots/10-add-source-types.png"))
        print("10-add-source-types:\n\(whole.text)")
        XCTAssertTrue(whole.passed, whole.text)
    }
}
