import XCTest
import MetadataOnline
@testable import AppLogic

/// #15 9.3: the title-logo selection rules (OPEN_QUESTIONS R179). Synthetic pictures only.
final class TitleLogoTests: XCTestCase {
    private func ref(_ path: String, _ lang: String?, vote: Double = 5, width: Int? = 800) -> ImageRef {
        ImageRef(path: path, width: width, height: width.map { $0 / 4 }, language: lang, voteAverage: vote)
    }

    func testLanguageOrderIsUserThenEnglishThenNoneThenAny() {
        let refs = [ref("/fr", "fr"), ref("/none", nil), ref("/de", "de"), ref("/en", "en")]
        XCTAssertEqual(TitleLogoRules.ordered(refs, userLanguage: "de-DE").map(\.path), ["/de", "/en", "/none", "/fr"])
        XCTAssertEqual(TitleLogoRules.ordered(refs, userLanguage: "en").map(\.path), ["/en", "/none", "/fr", "/de"])
        XCTAssertEqual(TitleLogoRules.ordered(refs, userLanguage: nil).map(\.path), ["/en", "/none", "/fr", "/de"])
    }

    func testWithinALanguageTheHigherVoteThenTheWiderPictureWins() {
        let refs = [ref("/a", "en", vote: 5, width: 900), ref("/b", "en", vote: 7, width: 400), ref("/c", "en", vote: 5, width: 1200)]
        XCTAssertEqual(TitleLogoRules.ordered(refs, userLanguage: "en").map(\.path), ["/b", "/c", "/a"])
    }

    func testTinyPicturesAreLeftOutAndUnknownWidthsAreKept() {
        let refs = [ref("/tiny", "en", width: 120), ref("/unknown", "en", width: nil)]
        XCTAssertEqual(TitleLogoRules.ordered(refs, userLanguage: "en").map(\.path), ["/unknown"])
    }

    // MARK: Pixels

    /// A width × height picture: a `fill` rectangle of `inner` share in the middle, the rest `background`.
    private func picture(width: Int, height: Int, fill: (UInt8, UInt8, UInt8, UInt8), background: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0), inner: Double = 0.5) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(width * height * 4)
        let x0 = Int(Double(width) * (1 - inner) / 2), x1 = width - x0
        for _ in 0..<height {
            for x in 0..<width {
                let c = (x >= x0 && x < x1) ? fill : background
                out += [c.0, c.1, c.2, c.3]
            }
        }
        return out
    }

    func testAWhiteTransparentLogoIsAccepted() throws {
        let p = try XCTUnwrap(LogoPixels.measure(rgba: picture(width: 400, height: 100, fill: (255, 255, 255, 255)), width: 400, height: 100))
        XCTAssertTrue(p.hasTransparency)
        XCTAssertEqual(p.meanLuminance, 1, accuracy: 0.001)
        XCTAssertEqual(p.coverage, 0.5, accuracy: 0.01)
        XCTAssertNil(TitleLogoRules.check(p))
    }

    func testADarkLogoOnTheDarkScrimIsRejected() throws {
        let p = try XCTUnwrap(LogoPixels.measure(rgba: picture(width: 400, height: 100, fill: (20, 20, 30, 255)), width: 400, height: 100))
        XCTAssertEqual(TitleLogoRules.check(p), .tooDark)
    }

    func testAWhiteLogoOnALightScrimIsTooLight() throws {
        let p = try XCTUnwrap(LogoPixels.measure(rgba: picture(width: 400, height: 100, fill: (250, 250, 250, 255)), width: 400, height: 100))
        XCTAssertEqual(TitleLogoRules.check(p, scrimLuminance: 0.9), .tooLight)
    }

    func testAPictureWithABackgroundTinyOrEmptyIsRejected() throws {
        let opaque = try XCTUnwrap(LogoPixels.measure(rgba: picture(width: 400, height: 100, fill: (255, 255, 255, 255), background: (0, 0, 0, 255)), width: 400, height: 100))
        XCTAssertEqual(TitleLogoRules.check(opaque), .notTransparent)
        let tiny = try XCTUnwrap(LogoPixels.measure(rgba: picture(width: 100, height: 30, fill: (255, 255, 255, 255)), width: 100, height: 30))
        XCTAssertEqual(TitleLogoRules.check(tiny), .tooSmall)
        let empty = try XCTUnwrap(LogoPixels.measure(rgba: picture(width: 400, height: 100, fill: (255, 255, 255, 255), inner: 0.01), width: 400, height: 100))
        XCTAssertEqual(TitleLogoRules.check(empty), .nearlyEmpty)
        XCTAssertNil(LogoPixels.measure(rgba: [0, 0, 0], width: 1, height: 1), "wrong buffer size")
    }

    // MARK: Fitting

    func testTheLogoFitsTheBoxKeepsItsShapeAndIsNeverEnlarged() {
        // Wide: limited by the width.
        var s = TitleLogoRules.fittedSize(pixelWidth: 2000, pixelHeight: 400, scale: 1)
        XCTAssertEqual(s.width, 640, accuracy: 0.001); XCTAssertEqual(s.height, 128, accuracy: 0.001)
        // Tall: limited by the height.
        s = TitleLogoRules.fittedSize(pixelWidth: 800, pixelHeight: 800, scale: 1)
        XCTAssertEqual(s.width, 200, accuracy: 0.001); XCTAssertEqual(s.height, 200, accuracy: 0.001)
        // Small: drawn at 1x (400 px at 2x = 200 pt), not enlarged to the box.
        s = TitleLogoRules.fittedSize(pixelWidth: 400, pixelHeight: 100, scale: 2)
        XCTAssertEqual(s.width, 200, accuracy: 0.001); XCTAssertEqual(s.height, 50, accuracy: 0.001)
        s = TitleLogoRules.fittedSize(pixelWidth: 0, pixelHeight: 10, scale: 1)
        XCTAssertEqual(s.width, 0)
    }

    func testSourcesAreOrderedServerThenLocalFileThenOnline() {
        XCTAssertEqual([TitleLogoSource.online, .server, .localFile].sorted(), [.server, .localFile, .online])
    }

    func testTheShowTitleLogosSettingIsOnByDefault() {
        XCTAssertTrue(SettingsKey.showTitleLogos.defaultBool)
    }
}

/// #15 9.6: the generated fixture logos give the verdicts the screenshots rely on.
final class FixtureLogoTests: XCTestCase {
    func testMovie2AndShow1PassAndTheOthersFallBackToText() throws {
        var verdicts: [String: TitleLogoRules.Rejection?] = [:]
        for (folder, logo) in UITestFixtures.logos {
            let p = try XCTUnwrap(LogoPixels.measure(rgba: logo.rgba, width: logo.width, height: logo.height), folder)
            verdicts[(folder as NSString).lastPathComponent] = TitleLogoRules.check(p)
            XCTAssertTrue(logo.png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "a PNG")
        }
        XCTAssertEqual(verdicts["Sample Movie 2 (2019)"], .some(nil))
        XCTAssertEqual(verdicts["Sample Show 1"], .some(nil))
        XCTAssertEqual(verdicts["Sample Movie 3 (2018)"], .some(.tooDark))
        XCTAssertEqual(verdicts["Sample Movie 5 (2020)"], .some(.notTransparent))
        XCTAssertEqual(verdicts["Sample Movie 6 (2017)"], .some(.tooSmall))
    }

    /// #25 B8: the logo is the plain wordmark "SAMPLE" (block letters), not bars: the first column of ink is the S's top bar
    /// (not its left edge, which starts one row lower), and the gap between two letters has no ink.
    func testTheFixtureLogoIsAWordmark() {
        let logo = LogoPNG(width: 800, height: 200, ink: (245, 245, 245), background: nil)
        let ink = (0..<logo.height).flatMap { y in (0..<logo.width).map { x in (x, y) } }.filter { logo.isInk(x: $0.0, y: $0.1) }
        XCTAssertFalse(ink.isEmpty)
        let cell = max(1, min(800 / (35 + 2), 200 * 3 / 5 / 7))
        let left = (800 - 35 * cell) / 2, top = (200 - 7 * cell) / 2
        XCTAssertFalse(logo.isInk(x: left, y: top), "S: no ink at the top-left corner")
        XCTAssertTrue(logo.isInk(x: left, y: top + cell), "S: its left edge starts on the second row")
        for row in 0..<7 { XCTAssertFalse(logo.isInk(x: left + 5 * cell, y: top + row * cell), "gap between S and A") }
    }
}
