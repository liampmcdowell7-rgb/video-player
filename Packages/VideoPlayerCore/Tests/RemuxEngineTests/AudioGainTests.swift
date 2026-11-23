import XCTest
@testable import RemuxEngine

/// R458: Volume Boost on the PCM the app decodes itself. FIXTURE: invented sample values.
final class AudioGainTests: XCTestCase {
    func testAFactorOfOneLeavesTheSamplesAlone() {
        var s: [Int32] = [0, 1000, -1000, Int32.max, Int32.min]
        let before = s
        AudioGain.apply(&s, gain: 1)
        XCTAssertEqual(s, before)
    }

    func testSixDecibelsAboutDoublesTheLevel() {
        var s: [Int32] = [1_000_000, -1_000_000, 0]
        AudioGain.apply(&s, gain: AudioGain.factor(decibels: 6))
        XCTAssertEqual(Double(s[0]), 1_995_262, accuracy: 2)
        XCTAssertEqual(Double(s[1]), -1_995_262, accuracy: 2)
        XCTAssertEqual(s[2], 0)
    }

    func testLoudSamplesAreHeldAtFullScaleNotWrapped() {
        var s: [Int32] = [Int32.max - 10, Int32.min + 10, 1_500_000_000, -1_500_000_000]
        AudioGain.apply(&s, gain: 2)
        XCTAssertEqual(s, [Int32.max, Int32.min, Int32.max, Int32.min])
    }

    func testTheDecibelFactors() {
        XCTAssertEqual(AudioGain.factor(decibels: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(AudioGain.factor(decibels: 3), 1.4125, accuracy: 0.001)
        XCTAssertEqual(AudioGain.factor(decibels: -6), 0.5012, accuracy: 0.001)
    }
}
