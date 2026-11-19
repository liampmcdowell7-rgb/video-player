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
