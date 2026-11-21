import XCTest
@testable import PlaybackLogic

/// #27 item 2 (safeguard for R208): online intro and recap timings without a reference duration (IntroDB) are used only
/// while the playhead is inside the returned window, never seek past the end of the file, and are dropped when the file
/// is shorter than the returned end. Synthetic files and timings only.
final class OnlineSkipSafeguardTests: XCTestCase {
    private func file(_ duration: TimeInterval) -> FileIdentity {
        FileIdentity(path: "/tv/Show/S01E02.mkv", size: 2_000_000, duration: duration)
    }

    private func online(_ type: SegmentType, _ start: TimeInterval, _ end: TimeInterval, on f: FileIdentity) -> SkipSegment {
        SkipSegment(type: type, start: start, end: end, source: .onlineDatabase, confidence: 0.9, file: f, referenceDuration: nil)
    }

    private func session(_ segments: [SkipSegment], file f: FileIdentity, settings: SkipSettings = SkipSettings()) -> PlaybackSession {
        let resolved = SegmentResolver.resolve(file: f, candidates: segments)
        return PlaybackSession(resolved: resolved, duration: f.duration, settings: settings, next: .none(.endOfSeries), clock: ManualClock())
    }

    // MARK: Short file

    func testSEG15_aShortFileDropsAnOnlineIntroThatEndsAfterIt() {
        let short = file(80)
        let r = SegmentResolver.resolve(file: short, candidates: [online(.intro, 30, 95, on: short)])
        XCTAssertTrue(r.segments.isEmpty, "not trimmed to the end of the file")
        XCTAssertEqual(r.rejected.first?.reason, .endsAfterFile)
    }

    func testSEG15_aShortFileDropsAnOnlineRecapThatEndsAfterIt() {
        let short = file(40)
        let r = SegmentResolver.resolve(file: short, candidates: [online(.recap, 0, 45, on: short)])
        XCTAssertTrue(r.segments.isEmpty)
        XCTAssertEqual(r.rejected.first?.reason, .endsAfterFile)
    }

    func testSEG15_anOnlineIntroEndingExactlyAtTheEndIsKept() {
        let f = file(100)
        XCTAssertEqual(SegmentResolver.resolve(file: f, candidates: [online(.intro, 40, 100, on: f)]).segments.count, 1)
    }

    func testSEG15_trimmingStillAppliesToSourcesThatAreNotUnreferencedOnline() {
        // Chapters and sidecars keep the old behaviour: an end past the file is trimmed, not dropped.
        let f = file(100)
        let chapter = SkipSegment(type: .intro, start: 40, end: 120, source: .embeddedChapters, confidence: 0.9, file: f)
        XCTAssertEqual(SegmentResolver.resolve(file: f, candidates: [chapter]).segments.first?.end, 100)
    }

    // MARK: A different cut

    /// IntroDB timings made for a longer cut (intro 120–200 s) on a much shorter cut of the same episode: the window
    /// ends after this file, so it is dropped and no Skip button ever appears.
    func testSESS8_aDifferentShorterCutDropsTheTimingAndShowsNoButton() {
        let cut = file(150)
        var s = session([online(.intro, 120, 200, on: cut)], file: cut)
        XCTAssertTrue(s.resolved.segments.isEmpty)
        for t in stride(from: 0.0, through: 150, by: 10) {
            XCTAssertEqual(s.playhead(t, kind: .natural).skip, .none, "at \(t)")
        }
        XCTAssertNil(s.skipPressed(.intro).seek)
    }

    /// The same timings on a different cut that is long enough: nothing can tell the cuts apart, so the button is shown
    /// only while the playhead is inside 120–200 s, a press outside the window does nothing, and the seek is 200 s.
    func testSESS9_aDifferentLongerCutUsesTheTimingOnlyInsideTheWindow() {
        let cut = file(1500)
        var s = session([online(.intro, 120, 200, on: cut)], file: cut)
        XCTAssertEqual(s.playhead(100, kind: .natural).skip, .none)
        XCTAssertNil(s.skipPressed(.intro).seek, "before the window: a press does nothing")
        XCTAssertEqual(s.playhead(130, kind: .natural).skip,
                       .button(SkipButton(type: .intro, title: "Skip Intro", target: 200)))
        XCTAssertEqual(s.playhead(250, kind: .natural).skip, .none)
        XCTAssertNil(s.skipPressed(.intro).seek, "after the window: a late press does nothing")
        _ = s.playhead(150, kind: .seek)
        XCTAssertEqual(s.skipPressed(.intro).seek, 200)
    }

    func testSESS10_automaticSkipOfAnOnlineIntroHappensOnlyInsideTheWindow() {
        let cut = file(1500)
        // R314: an online timing skips by itself only once the audio confirmed it (R288); unconfirmed it shows the button.
        var confirmed = online(.intro, 120, 200, on: cut)
        confirmed.audioConfirmed = true
        var s = session([confirmed], file: cut, settings: SkipSettings(intro: .automatic))
        XCTAssertNil(s.playhead(119, kind: .natural).seek)
        XCTAssertEqual(s.playhead(121, kind: .natural).seek, 200)
        XCTAssertNil(s.playhead(260, kind: .natural).seek)
    }

    // MARK: Never past the end

    func testSESS11_theSkipTargetNeverGoesPastTheEndOfTheFile() {
        let f = file(100)
        // A segment that did not go through the resolver, with an end past the file.
        let raw = SkipSegment(type: .intro, start: 40, end: 130, source: .userMarked, confidence: 1, file: f)
        XCTAssertEqual(SkipController(segments: [raw]).target(for: raw), 100)
        var s = PlaybackSession(resolved: ResolvedSegments(segments: [raw], postCreditsStart: nil, rejected: []),
                                duration: 100, next: .none(.endOfSeries), clock: ManualClock())
        _ = s.playhead(50, kind: .natural)
        XCTAssertEqual(s.skipPressed(.intro).seek, 100)
        var auto = PlaybackSession(resolved: ResolvedSegments(segments: [raw], postCreditsStart: nil, rejected: []),
                                   duration: 100, settings: SkipSettings(intro: .automatic), next: .none(.endOfSeries), clock: ManualClock())
        XCTAssertEqual(auto.playhead(45, kind: .natural).seek, 100)
    }

    func testSESS12_otherSourcesStillSkipOnAPressWithoutTheWindowRule() {
        let f = file(1500)
        let chapter = SkipSegment(type: .intro, start: 60, end: 120, source: .embeddedChapters, confidence: 0.9, file: f)
        var s = session([chapter], file: f)
        _ = s.playhead(300, kind: .natural)
        XCTAssertEqual(s.skipPressed(.intro).seek, 120, "unchanged behaviour for chapters, sidecars and marks")
    }
}
