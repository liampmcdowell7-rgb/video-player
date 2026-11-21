import XCTest
import Foundation
@testable import ScreenChecks

/// R351: the contrast measure on a frame much wider than its text (a whole Form row with a one-word label) reads the
/// glyphs, not the row platter's shading; on the run of 21 Nov 2026 (VP_RUN_ARTIFACTS) the rows that read 1.20 to 4.45:1
/// read as the white or black text they are, and the real dim texts (36's status lines) still read below 4.5:1.
final class ContrastRowTests: XCTestCase {
    func testAOneWordLabelInAWideRowIsMeasuredByItsGlyphsNotThePlattersShading() throws {
        // A 1133 x 35 row: platter #191919 with a 3-pixel lighter band (#292929, the platter's shading) along the top and
        // bottom, and a short white word (about 1 % of the frame).
        var image: RGBImage = RGBImage(width: 1133, height: 35, fill: RGB(r: 25, g: 25, b: 25))
        for x in 0..<1133 { for y in [0, 1, 2, 32, 33, 34] { image.set(x, y, RGB(r: 41, g: 41, b: 41)) } }
        for x in stride(from: 0, to: 60, by: 4) { for y in 8..<27 { image.set(x, y, RGB(r: 255, g: 255, b: 255)); image.set(x + 1, y, RGB(r: 140, g: 140, b: 140)) } }
        let m: Contrast.Measurement = try XCTUnwrap(Contrast.measure(image, frame: AXRect(x: 0, y: 0, width: 1133, height: 35), scale: 1))
        XCTAssertEqual(m.foreground, RGB(r: 255, g: 255, b: 255), m.description)
        XCTAssertGreaterThan(m.ratio, 15, m.description)
    }

    func picture(_ path: String) throws -> RGBImage {
        guard let root = ProcessInfo.processInfo.environment["VP_RUN_ARTIFACTS"], !root.isEmpty else {
            throw XCTSkip("VP_RUN_ARTIFACTS is not set: the CI run's pictures are not on this machine")
        }
        let url: URL = URL(fileURLWithPath: root).appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("\(path) is not in \(root)") }
        return try PNGDecoder.decode([UInt8](try Data(contentsOf: url)))
    }

    /// The frames are those of the run's -CONTRAST notes (1920 x 1080, scale 1).
    func testRunArtifactsTheRowLabelsOf12And19And66PassAndThe36StatusLinesDoNot() throws {
        let rows: [(String, String, AXRect)] = [
            ("12 Name", "screenshots/12-form-smb.png", AXRect(x: 393, y: 302, width: 1133, height: 35)),
            ("12 Server (focused)", "screenshots/12-form-smb.png", AXRect(x: 389.1, y: 381.9, width: 1140.7, height: 35.2)),
            ("12 Port", "screenshots/12-form-smb.png", AXRect(x: 393, y: 462, width: 1133, height: 35)),
            ("19 Link (focused)", "screenshots/19-form-web-link.png", AXRect(x: 389.1, y: 323.9, width: 1140.7, height: 35.2)),
            ("66 Year", "screenshots/66-move-sheet.png", AXRect(x: 393, y: 288, width: 1133, height: 35)),
        ]
        for (name, path, frame) in rows {
            let image: RGBImage = try picture(path)
            let m: Contrast.Measurement = try XCTUnwrap(Contrast.measure(image, frame: frame, scale: 1), name)
            print("CONTRAST-R351 \(name): \(m)")
            XCTAssertGreaterThanOrEqual(m.ratio, 4.5, "\(name): \(m)")
        }
        let status: [(String, AXRect)] = [
            ("36 Online lookup is off", AXRect(x: 80, y: 333, width: 517, height: 37)),
            ("36 Free Data Sources are off", AXRect(x: 80, y: 405, width: 352, height: 37)),
        ]
        let settings: RGBImage = try picture("screenshots/36-settings-online-lookup.png")
        for (name, frame) in status {
            let m: Contrast.Measurement = try XCTUnwrap(Contrast.measure(settings, frame: frame, scale: 1), name)
            print("CONTRAST-R351 \(name): \(m)")
            XCTAssertLessThan(m.ratio, 4.5, "\(name): \(m)")
        }
    }
}
