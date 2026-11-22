import XCTest
@testable import RemuxEngine

/// R390: the loopback's first requests and answers, for the start report of converted playback.
final class LoopbackServeLogTests: XCTestCase {
    final class Clock: @unchecked Sendable { var now: Double = 50 }

    func testAnsweredFailedAndUnansweredRequests() {
        let clock = Clock()
        let log = LoopbackServeLog(clock: { [clock] in clock.now })
        clock.now = 51
        let master = log.asked("/master.m3u8")
        clock.now = 51.2
        log.answered(master, status: 200)
        let segment = log.asked("/seg_video_0.m4s")
        let audio = log.asked("/seg_audio_2_0.m4s")
        clock.now = 53.2
        log.failed(audio, error: "cancelled")
        XCTAssertNotNil(segment)
        XCTAssertEqual(log.lines(), [
            "master.m3u8: asked at 1.0 s, answered 200 after 0.2 s",
            "seg_video_0.m4s: asked at 1.2 s, no answer yet",
            "seg_audio_2_0.m4s: asked at 1.2 s, failed after 2.0 s: cancelled",
        ])
        XCTAssertEqual(log.lines(serverStartedAt: 10).first, "master.m3u8: asked at 11 s, answered 200 after 0.2 s")
        XCTAssertEqual(log.missing(), ["video.m3u8", "init_video.mp4"])
    }

    func testOnlyTheFirstRequestOfAResourceAndTheFirstSegmentsAreKept() {
        let log = LoopbackServeLog()
        XCTAssertNotNil(log.asked("/video.m3u8"))
        XCTAssertNil(log.asked("/video.m3u8"), "the first request counts")
        for k in 0..<6 { _ = log.asked("/seg_video_\(k).m4s") }
        XCTAssertEqual(log.all.map(\.name), ["video.m3u8", "seg_video_0.m4s", "seg_video_1.m4s", "seg_video_2.m4s"])
        XCTAssertNil(log.asked("/subs_3.vtt"))
    }

    func testAResumeStartLogsItsFirstSegmentFurtherOn() {
        let log = LoopbackServeLog()
        XCTAssertNotNil(log.asked("/seg_video_120.m4s"))
        XCTAssertNil(log.asked("/seg_video_121.m4s"))
        XCTAssertNotNil(log.asked("/seg_audio_1_120.m4s"))
        XCTAssertEqual(log.missing(), ["master.m3u8", "video.m3u8", "init_video.mp4"])
    }

    func testTheLogIsCapped() {
        let log = LoopbackServeLog()
        for n in 0..<40 { _ = log.asked("/audio_\(n).m3u8") }
        XCTAssertEqual(log.all.count, LoopbackServeLog.capacity)
    }
}
