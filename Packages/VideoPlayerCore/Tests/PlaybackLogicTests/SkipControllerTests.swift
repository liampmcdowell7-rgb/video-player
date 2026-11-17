import XCTest
@testable import PlaybackLogic

final class SkipControllerTests: XCTestCase {
    private let segments = [
        Fixture.seg(.recap, 0, 40),
        Fixture.seg(.intro, 60, 120),
        Fixture.seg(.credits, 900, 1000),
    ]

    private func controller(_ settings: SkipSettings = SkipSettings()) -> SkipController {
        SkipController(segments: Fixture.resolve(segments).segments, settings: settings)
    }

    // SKIP-1
    func testSKIP1_defaultSettingIsAskForEveryType() {
        let s = SkipSettings()
        for type in SegmentType.allCases { XCTAssertEqual(s.setting(for: type), .ask) }
    }

    // SKIP-2
    func testSKIP2_buttonWording() {
        var c = controller()
        XCTAssertEqual(c.update(playhead: 10, kind: .natural), .button(SkipButton(type: .recap, title: "Skip Recap", target: 40)))
        XCTAssertEqual(c.update(playhead: 70, kind: .natural), .button(SkipButton(type: .intro, title: "Skip Intro", target: 120)))
        XCTAssertEqual(c.update(playhead: 950, kind: .natural), .button(SkipButton(type: .credits, title: "Skip Credits", target: 1000)))
    }

    // SKIP-3
    func testSKIP3_buttonShowsOnlyWhileInsideTheSegment() {
        var c = controller()
        XCTAssertEqual(c.update(playhead: 59.9, kind: .natural), .none)
        XCTAssertNotEqual(c.update(playhead: 60, kind: .natural), .none)
        XCTAssertNotEqual(c.update(playhead: 119.9, kind: .natural), .none)
        XCTAssertEqual(c.update(playhead: 120, kind: .natural), .none)       // end is exclusive
        XCTAssertEqual(c.update(playhead: 500, kind: .natural), .none)
    }

    // SKIP-4
    func testSKIP4_offShowsNothingAndNeverJumps() {
        var c = controller(SkipSettings(recap: .off, intro: .off, credits: .off))
        for t in [10.0, 70, 950] {
            XCTAssertEqual(c.update(playhead: t, kind: .natural), .none)
            XCTAssertEqual(c.update(playhead: t, kind: .started), .none)
        }
    }

    // SKIP-5
    func testSKIP5_automaticJumpsWithoutAnyButton() {
        var c = controller(SkipSettings(intro: .automatic))
        XCTAssertEqual(c.update(playhead: 60, kind: .natural), .jump(type: .intro, target: 120))
    }

    // SKIP-6
    func testSKIP6_automaticJumpsOnlyOncePerType() {
        var c = controller(SkipSettings(intro: .automatic))
        XCTAssertEqual(c.update(playhead: 60, kind: .natural), .jump(type: .intro, target: 120))
        XCTAssertEqual(c.update(playhead: 61, kind: .natural), .none)
    }

    // SKIP-7
    func testSKIP7_steppingBackIntoAnAutomaticallySkippedSegmentDoesNotJumpAgain() {
        var c = controller(SkipSettings(intro: .automatic))
        _ = c.update(playhead: 60, kind: .natural)
        XCTAssertEqual(c.update(playhead: 55, kind: .seek), .none)           // skip-back on the remote
        XCTAssertEqual(c.update(playhead: 70, kind: .seek), .none)           // seek inside the intro
    }

    // SKIP-8
    func testSKIP8_startingPlaybackInsideASegmentSkipsAutomatically() {
        var c = controller(SkipSettings(intro: .automatic))
        XCTAssertEqual(c.update(playhead: 80, kind: .started), .jump(type: .intro, target: 120))
    }

    // SKIP-9
    func testSKIP9_seekIntoAnAutomaticSegmentNeverJumps() {
        var c = controller(SkipSettings(intro: .automatic))
        XCTAssertEqual(c.update(playhead: 80, kind: .seek), .none)
    }

    // SKIP-10
    func testSKIP10_eachTypeHasItsOwnSetting() {
        var c = controller(SkipSettings(recap: .off, intro: .ask, credits: .automatic))
        XCTAssertEqual(c.update(playhead: 10, kind: .natural), .none)
        XCTAssertEqual(c.update(playhead: 70, kind: .natural), .button(SkipButton(type: .intro, title: "Skip Intro", target: 120)))
        XCTAssertEqual(c.update(playhead: 950, kind: .natural), .jump(type: .credits, target: 1000))
    }

    // SKIP-11
    func testSKIP11_creditsTargetIsThePostCreditsChapterWhenThereIsOne() {
        let resolved = Fixture.resolve([Fixture.seg(.credits, 900, 1000)], post: 960)
        var c = SkipController(segments: resolved.segments)
        XCTAssertEqual(c.update(playhead: 920, kind: .natural), .button(SkipButton(type: .credits, title: "Skip Credits", target: 960)))
    }

    // SKIP-12
    func testSKIP12_settingsCanChangeWhileSegmentsStay() {
        var c = controller()
        XCTAssertNotEqual(c.update(playhead: 70, kind: .natural), .none)
        c.settings.intro = .off
        XCTAssertEqual(c.update(playhead: 70, kind: .natural), .none)
    }
}
