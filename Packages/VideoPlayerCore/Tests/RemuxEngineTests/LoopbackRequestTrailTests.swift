import XCTest
import Foundation
@testable import RemuxEngine

/// R471 (90): the loopback request trail for Settings > Playback is capped, redacted and newest first.
final class LoopbackRequestTrailTests: XCTestCase {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t: Double = 100
        var now: Double { lock.withLock { t } }
        func advance(_ s: Double) { lock.withLock { t += s } }
    }

    func testTheTrailKeepsTheLastTwentyNewestFirst() {
        let c = Clock()
        let trail = LoopbackRequestTrail(clock: { c.now })
        for k in 0..<30 {
            let token = trail.asked("/seg_video_\(k).m4s")
            trail.answered(token, status: 200)
            c.advance(0.1)
        }
        let names = trail.newestFirst.map(\.name)
        XCTAssertEqual(names.count, LoopbackRequestTrail.capacity)
        XCTAssertEqual(LoopbackRequestTrail.capacity, 20)
        XCTAssertEqual(names.first, "seg_video_29.m4s", "newest first")
        XCTAssertEqual(names.last, "seg_video_10.m4s", "the oldest kept is the twentieth from the end")
    }

    func testTimesAreTheAnswerAndTheGapBeforeEachRequest() {
        let c = Clock()
        let trail = LoopbackRequestTrail(clock: { c.now })
        let a = trail.asked("/seg_video_12.m4s")
        c.advance(0.012)
        trail.answered(a, status: 200)
        c.advance(0.238)
        let b = trail.asked("/seg_audio_2_11.m4s")
        c.advance(0.5)
        let rows = trail.rows
        XCTAssertEqual(rows.map(\.label), ["seg_audio_2_11.m4s", "seg_video_12.m4s"])
        XCTAssertEqual(rows[0].value, "no answer · +250 ms", "no answer yet; 250 ms after the request before it")
        XCTAssertEqual(rows[1].value, "200 · 12 ms", "the first request has no gap")
        trail.answered(b, status: 500)
        XCTAssertEqual(trail.rows[0].value, "500 · 500 ms · +250 ms")
    }

    func testAnAnswerAfterItsEntryWasDroppedChangesNothing() {
        let trail = LoopbackRequestTrail()
        let first = trail.asked("/master.m3u8")
        for k in 0..<LoopbackRequestTrail.capacity { _ = trail.asked("/seg_video_\(k).m4s") }
        trail.answered(first, status: 200)
        XCTAssertFalse(trail.newestFirst.contains { $0.name == "master.m3u8" })
        XCTAssertTrue(trail.newestFirst.allSatisfy { $0.status == nil })
    }

    func testOnlyPlainResourceNamesReachThePage() {
        XCTAssertEqual(LoopbackRequestTrail.resourceName("/seg_video_12.m4s"), "seg_video_12.m4s")
        XCTAssertEqual(LoopbackRequestTrail.resourceName("/video.m3u8?token=x1"), "video.m3u8", "the query is dropped")
        XCTAssertEqual(LoopbackRequestTrail.resourceName("http://192.168.1.20:32400/library/parts/1/file.mkv"), "file.mkv",
                       "only the last component, never the address")
        XCTAssertEqual(LoopbackRequestTrail.resourceName("/My Film (2020).mkv"), LoopbackRequestTrail.otherName,
                       "a name with spaces or brackets (a title) is not shown")
        XCTAssertEqual(LoopbackRequestTrail.resourceName("/token=abc%20def"), LoopbackRequestTrail.otherName)
        XCTAssertEqual(LoopbackRequestTrail.resourceName(""), LoopbackRequestTrail.otherName)
        XCTAssertEqual(LoopbackRequestTrail.resourceName("/" + String(repeating: "a", count: 65)), LoopbackRequestTrail.otherName)
    }

    /// The host records every request of a converted play, resource names only.
    final class CapturingServer: LoopbackServer, @unchecked Sendable {
        private let lock = NSLock()
        private var _handler: LoopbackHandler?
        var handler: LoopbackHandler? { lock.withLock { _handler } }
        func start(handler: @escaping LoopbackHandler) throws -> URL {
            lock.withLock { _handler = handler }
            return URL(string: "http://127.0.0.1:1/test/")!
        }
        func stop() {}
    }

    func testTheHostRecordsThePlayersRequests() async throws {
        let r = SynthMKV(seconds: 6).build()
        var o = RemuxOptions(); o.targetSegmentSeconds = 2
        let server = CapturingServer()
        let host = RemuxHost(reader: CountingReader(r.data), options: o, server: server)
        _ = try await host.start()
        let handler = try XCTUnwrap(server.handler)
        for name in ["master.m3u8", "video.m3u8", "init_video.mp4", "seg_video_0.m4s"] {
            _ = try await handler(LoopbackRequest(method: "GET", path: "/" + name, headers: [:]))
        }
        await host.stop()
        let rows = host.requestTrail.rows
        XCTAssertEqual(rows.map(\.label), ["seg_video_0.m4s", "init_video.mp4", "video.m3u8", "master.m3u8"])
        XCTAssertTrue(rows.allSatisfy { $0.value.hasPrefix("200") }, "\(rows)")
    }
}
