import XCTest
@testable import AppLogic

/// R319 (item 9(b)): the sample clip's frames are one even colour each (no band that read as a strip at the left edge),
/// change every second and are never black.
final class SampleClipFramesTests: XCTestCase {
    private let fps = 10

    private func same(_ a: (red: UInt8, green: UInt8, blue: UInt8), _ b: (red: UInt8, green: UInt8, blue: UInt8)) -> Bool {
        a.red == b.red && a.green == b.green && a.blue == b.blue
    }

    func testEveryFrameOfOneSecondHasTheSameColour() {
        for second in 0..<40 {
            let first = SampleClipFrames.colour(frame: second * fps, framesPerSecond: fps)
            for frame in second * fps..<(second + 1) * fps {
                XCTAssertTrue(same(SampleClipFrames.colour(frame: frame, framesPerSecond: fps), first), "frame \(frame)")
            }
        }
    }

    func testTheColourChangesEverySecondAndGoesRoundTwelveHues() {
        let cycle = (0..<SampleClipFrames.hueSteps).map { SampleClipFrames.colour(frame: $0 * fps, framesPerSecond: fps) }
        for i in 1..<cycle.count { XCTAssertFalse(same(cycle[i], cycle[i - 1]), "second \(i)") }
        XCTAssertEqual(Set(cycle.map { "\($0.red),\($0.green),\($0.blue)" }).count, SampleClipFrames.hueSteps)
        XCTAssertTrue(same(SampleClipFrames.colour(frame: SampleClipFrames.hueSteps * fps, framesPerSecond: fps), cycle[0]))
    }

    func testNoFrameIsBlackOrWhite() {
        for frame in 0..<(40 * fps) {
            let c = SampleClipFrames.colour(frame: frame, framesPerSecond: fps)
            let top = max(c.red, c.green, c.blue)
            XCTAssertGreaterThan(top, 100, "frame \(frame) is too dark")
            XCTAssertLessThan(top, 200, "frame \(frame) is too light for white subtitles")
        }
    }

    func testOddInputsDoNotCrash() {
        XCTAssertTrue(same(SampleClipFrames.colour(frame: -5, framesPerSecond: fps), SampleClipFrames.colour(frame: 0, framesPerSecond: fps)))
        XCTAssertTrue(same(SampleClipFrames.colour(frame: 7, framesPerSecond: 0), SampleClipFrames.colour(frame: 0, framesPerSecond: fps)))
    }
}
