import XCTest
@testable import AppLogic

/// R452: the contrast proof, no build. Worst backdrop: pure white; also mid grey. A busy picture is bounded by these two
/// because no pixel is brighter than white; the proof takes the whole text area at that brightness. No system material
/// darkening is counted (Apple's pages state none).
final class ArtReadabilityTests: XCTestCase {
    let a = ArtReadability.scrimMaxOpacity

    func testPrimaryAndSecondaryTextPassOverWhiteAndMidGrey() {
        for backdrop in [1.0, 0.5] {
            XCTAssertGreaterThanOrEqual(ArtReadability.primaryContrast(backdrop: backdrop, opacity: a), 4.5, "primary over \(backdrop)")
            XCTAssertGreaterThanOrEqual(ArtReadability.secondaryContrast(backdrop: backdrop, opacity: a), 4.5, "secondary over \(backdrop)")
        }
    }

    func testLargeTextAndButtonsNeedOnlyThree() {
        XCTAssertGreaterThanOrEqual(ArtReadability.secondaryContrast(backdrop: 1, opacity: a), 3)
        XCTAssertGreaterThanOrEqual(ArtReadability.primaryContrast(backdrop: 1, opacity: a), 3)
    }

    func testTheOpacityIsNoHigherThanTheProofNeeds() {
        // The smallest opacity in steps of 0.05 that passes over white is the constant.
        let needed = stride(from: 0.0, through: 1.0, by: 0.05).first { ArtReadability.secondaryContrast(backdrop: 1, opacity: $0) >= 4.5 }
        XCTAssertEqual(needed ?? -1, a, accuracy: 0.001)
    }

    func testAThinProgressBarKeepsThreeToOneOverWhite() {
        let ground = ArtReadability.covered(backdrop: 1, opacity: ArtReadability.progressScrimOpacity)
        XCTAssertGreaterThanOrEqual(ArtReadability.contrast(ArtReadability.luminance(grey: 1), ArtReadability.luminance(grey: ground)), 3)
    }

    func testTheCoverStartsOneRampAboveTheFirstLineAndClamps() {
        XCTAssertEqual(ArtReadability.coverStart(textTop: 540, height: 1080), 0.5 - ArtReadability.rampFraction, accuracy: 1e-9)
        // R470: no longer clamped at 0 (the ramp must end AT the first line), only at minus one ramp.
        XCTAssertEqual(ArtReadability.coverStart(textTop: 50, height: 1080), 50.0 / 1080 - ArtReadability.rampFraction, accuracy: 1e-9)
        XCTAssertEqual(ArtReadability.coverStart(textTop: -100, height: 1080), -ArtReadability.rampFraction, accuracy: 1e-9)
        XCTAssertEqual(ArtReadability.coverStart(textTop: nil, height: 1080), ArtReadability.fallbackStart)
        XCTAssertEqual(ArtReadability.coverStart(textTop: 400, height: 0), ArtReadability.fallbackStart)
    }
}
