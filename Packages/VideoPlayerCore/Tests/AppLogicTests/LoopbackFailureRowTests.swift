import XCTest
import Foundation
@testable import AppLogic

/// R472: the first screen of Last Playback Problem names the resource the loopback answered with 500 and the error the
/// session threw, in the Last Event row, so one photo is enough. (Build 202611250008: the row said "HTTP 500" with no
/// resource and no reason; the reason was only in the notes lower on the screen.)
final class LoopbackFailureRowTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_764_000_000)
    let utc = TimeZone(identifier: "UTC")!

    func event() -> PlaybackEvent {
        PlaybackEvent(name: "-16847 - HTTP 500: Internal Server Error", position: 0, elapsed: 25, at: at)
    }

    func row(_ p: PlaybackProblem) -> String? { p.rows.first { $0.label == "Last Event" }?.value }

    func testTheRowAddsTheResourceAndTheTextAfterThePlayersEvent() throws {
        let p = PlaybackProblem(step: .playerReady, sourceKind: "Plex", container: "MKV", codecs: "hvc1.2.4.L120.90, ec-3",
                                error: "x", at: at, events: [event()], loopbackFailure: "seg_video_1.m4s: httpStatus(500)")
        let value = try XCTUnwrap(row(p))
        XCTAssertTrue(value.hasPrefix("-16847 - HTTP 500: Internal Server Error · video at 0:00 · 25 s after the player opened"), value)
        XCTAssertTrue(value.hasSuffix(" · Loopback seg_video_1.m4s: httpStatus(500)"), value)
        XCTAssertTrue(p.fullText(timeZone: utc).contains("Last Event: -16847"), "the full report has the same row")
        XCTAssertTrue(p.fullText(timeZone: utc).contains("Loopback seg_video_1.m4s: httpStatus(500)"))
    }

    func testWithoutAFailureTheRowIsUnchanged() {
        let p = PlaybackProblem(step: .playerReady, sourceKind: "Plex", container: "MKV", codecs: nil, error: "x", at: at, events: [event()])
        XCTAssertEqual(row(p), event().line())
        let none = PlaybackProblem(step: .playerReady, sourceKind: nil, container: nil, codecs: nil, error: "x", at: at)
        XCTAssertEqual(row(none), PlaybackProblem.notKnown)
    }

    func testAFailureWithoutAnEventStillShows() {
        let p = PlaybackProblem(step: .playerReady, sourceKind: nil, container: nil, codecs: nil, error: "x", at: at,
                                loopbackFailure: "init_video.mp4: not found: init_video.mp4")
        XCTAssertEqual(row(p), "Loopback init_video.mp4: not found: init_video.mp4")
    }

    func testTheTrackerKeepsTheFirstFailureAndRedactsItAgain() {
        let tracker = PlaybackStartTracker(clock: { 0 })
        tracker.describe(secrets: ["SECRET-TOKEN-1234"])
        tracker.enter(.playerReady)
        tracker.noteLoopbackFailure("seg_video_1.m4s: io: GET http://10.0.0.2:32400/x?X-Plex-Token=SECRET-TOKEN-1234 failed")
        tracker.noteLoopbackFailure("seg_audio_2_1.m4s: later")
        let p = tracker.problem(PlaybackFailures.startTimedOut(.playerReady, seconds: 30), events: [event()], at: at)
        let failure = p.loopbackFailure ?? ""
        XCTAssertTrue(failure.hasPrefix("seg_video_1.m4s: "), failure)
        XCTAssertFalse(failure.contains("SECRET-TOKEN-1234"), failure)
        XCTAssertFalse((row(p) ?? "").contains("SECRET-TOKEN-1234"))
    }

    func testAProblemStoredBeforeR472StillDecodes() throws {
        let old = PlaybackProblem(step: .playerReady, sourceKind: "Plex", container: "MKV", codecs: nil, error: "x", at: at)
        var json = try XCTUnwrap(String(data: try XCTUnwrap(old.encoded()), encoding: .utf8))
        json = json.replacingOccurrences(of: ",\"loopbackFailure\":null", with: "")
        XCTAssertFalse(json.contains("loopbackFailure"))
        let decoded = try XCTUnwrap(PlaybackProblem.decoded(Data(json.utf8)))
        XCTAssertNil(decoded.loopbackFailure)
        let withFailure = PlaybackProblem(step: .playerReady, sourceKind: nil, container: nil, codecs: nil, error: "x", at: at,
                                          loopbackFailure: "seg_video_0.m4s: y")
        XCTAssertEqual(PlaybackProblem.decoded(withFailure.encoded())?.loopbackFailure, "seg_video_0.m4s: y")
    }
}
