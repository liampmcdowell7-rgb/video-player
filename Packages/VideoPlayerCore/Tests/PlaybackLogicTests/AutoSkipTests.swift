import XCTest
@testable import PlaybackLogic

/// R314: automatic skips only from trusted segments, the "Watch Intro" way back, and online timings confirmed by the audio.
final class AutoSkipTests: XCTestCase {
    private let file = FileIdentity(path: "/tv/Show/S01E03.mkv", size: 1_000_000, duration: 1500)

    private func seg(_ type: SegmentType, _ start: TimeInterval, _ end: TimeInterval, _ source: SegmentSource,
                     confidence: Double = 0.9, confirmed: Bool? = nil) -> SkipSegment {
        SkipSegment(type: type, start: start, end: end, source: source, confidence: confidence, file: file, audioConfirmed: confirmed)
    }

    private let auto = SkipSettings(recap: .automatic, intro: .automatic, credits: .automatic)

    func testFileExactSourcesSkipWithoutAPress() {
        for source in [SegmentSource.userMarked, .embeddedChapters, .localSidecar, .serverMarkers] {
            var c = SkipController(segments: [seg(.intro, 60, 120, source)], settings: auto)
            XCTAssertEqual(c.update(playhead: 60, kind: .natural), .jump(type: .intro, target: 120), "\(source)")
        }
    }

    func testAnUnconfirmedOnlineTimingShowsTheButtonInstead() {
        var c = SkipController(segments: [seg(.intro, 60, 120, .onlineDatabase, confidence: 1)], settings: auto)
        XCTAssertEqual(c.update(playhead: 60, kind: .natural), .button(SkipButton(type: .intro, title: "Skip Intro", target: 120)))
    }

    func testAnOnlineTimingConfirmedByTheAudioSkips() {
        var c = SkipController(segments: [seg(.intro, 60, 120, .onlineDatabase, confirmed: true)], settings: auto)
        XCTAssertEqual(c.update(playhead: 60, kind: .natural), .jump(type: .intro, target: 120))
    }

    func testDetectionSkipsOnlyWhenTwoEpisodesAgree() {
        var one = SkipController(segments: [seg(.intro, 60, 120, .onDeviceDetection, confidence: SeasonSegmentMemory.confidence(votes: 1))], settings: auto)
        XCTAssertEqual(one.update(playhead: 60, kind: .natural), .button(SkipButton(type: .intro, title: "Skip Intro", target: 120)))
        var two = SkipController(segments: [seg(.intro, 60, 120, .onDeviceDetection, confidence: SeasonSegmentMemory.confidence(votes: 2))], settings: auto)
        XCTAssertEqual(two.update(playhead: 60, kind: .natural), .jump(type: .intro, target: 120))
    }

    func testTheFallbackFollowsShowSkipButtons() {
        let hidden = SkipSettings(recap: .automatic, intro: .automatic, credits: .automatic, untrustedFallback: .off)
        var c = SkipController(segments: [seg(.intro, 60, 120, .onlineDatabase)], settings: hidden)
        XCTAssertEqual(c.update(playhead: 60, kind: .natural), .none)
    }

    func testWatchIntroShowsWhereTheSkipLandedForFiveSeconds() {
        var c = SkipController(segments: [seg(.intro, 60, 120, .serverMarkers)], settings: auto)
        XCTAssertEqual(c.update(playhead: 60, kind: .natural), .jump(type: .intro, target: 120))
        let back = SkipOutput.button(SkipButton(type: .intro, title: "Watch Intro", target: 60, action: .back))
        XCTAssertEqual(c.update(playhead: 120, kind: .seek), back, "the skip's own seek lands at the end")
        XCTAssertEqual(c.update(playhead: 124, kind: .natural), back)
        XCTAssertEqual(c.update(playhead: 125, kind: .natural), .none, "gone after 5 s")
        XCTAssertEqual(c.update(playhead: 121, kind: .seek), .none, "and it does not come back")
    }

    func testAScrubAwayEndsTheWayBack() {
        var c = SkipController(segments: [seg(.intro, 60, 120, .serverMarkers)], settings: auto)
        _ = c.update(playhead: 60, kind: .natural)
        XCTAssertEqual(c.update(playhead: 400, kind: .seek), .none)
    }

    func testWatchIntroGoesBackAndTheIntroPlays() {
        var s = PlaybackSession(resolved: ResolvedSegments(merged: [seg(.intro, 60, 120, .serverMarkers)]), duration: 1500,
                                settings: auto, next: .none(.endOfSeries), clock: ManualClock())
        XCTAssertEqual(s.playhead(60, kind: .natural).seek, 120)
        XCTAssertEqual(s.playhead(120, kind: .seek).skip, .button(SkipButton(type: .intro, title: "Watch Intro", target: 60, action: .back)))
        XCTAssertEqual(s.backPressed(to: 60).seek, 60)
        // Back at the start of the intro it plays through: no second jump, the plain button only if the setting asks.
        XCTAssertEqual(s.playhead(60, kind: .seek).seek, nil)
        XCTAssertNil(s.playhead(61, kind: .natural).seek)
    }

    func testTheMergerConfirmsAnOnlineTimingThatDetectionFoundToo() {
        let online = seg(.intro, 60, 120, .onlineDatabase)
        let near = seg(.intro, 61, 119, .onDeviceDetection, confidence: 0.75)
        let confirmed = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(onlineDatabase: [online], onDeviceDetection: [near]))
        XCTAssertEqual(confirmed.segment(of: .intro)?.source, .onlineDatabase)
        XCTAssertEqual(confirmed.segment(of: .intro)?.audioConfirmed, true)
        let far = seg(.intro, 70, 130, .onDeviceDetection, confidence: 0.75)
        let unconfirmed = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(onlineDatabase: [online], onDeviceDetection: [far]))
        XCTAssertNil(unconfirmed.segment(of: .intro)?.audioConfirmed)
    }

    func testServerMarkersRankBelowChaptersAndAboveOnlineTimings() {
        XCTAssertGreaterThan(SegmentSource.embeddedChapters.priority, SegmentSource.serverMarkers.priority)
        XCTAssertGreaterThan(SegmentSource.serverMarkers.priority, SegmentSource.onlineDatabase.priority)
        let merged = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(onlineDatabase: [seg(.intro, 50, 110, .onlineDatabase)],
                                                                                serverMarkers: [seg(.intro, 60, 120, .serverMarkers)]))
        XCTAssertEqual(merged.segment(of: .intro)?.source, .serverMarkers)
    }

    func testOldStoredSettingsWithoutTheFallbackStillDecode() throws {
        let data = Data(#"{"recap":"ask","intro":"automatic","credits":"off"}"#.utf8)
        let decoded = try JSONDecoder().decode(SkipSettings.self, from: data)
        XCTAssertEqual(decoded, SkipSettings(recap: .ask, intro: .automatic, credits: .off))
    }
}
