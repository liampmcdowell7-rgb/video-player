import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R471 (82), PROVISIONAL (owner 25 Nov 2026 round 9, finding (B) of R471 (81)): a player plays straight through, its audio
/// requests one segment behind its video requests. No window should be read twice.
final class LaggingTrackR471Tests: XCTestCase {
    /// Window loads by segment index, from the session's load observer.
    final class Loads: @unchecked Sendable {
        private let lock = NSLock()
        private var byIndex: [Int: Int] = [:]
        func add(_ k: Int) { lock.withLock { byIndex[k, default: 0] += 1 } }
        var all: [(key: Int, value: Int)] { lock.withLock { byIndex.sorted { $0.key < $1.key } } }
        var twice: [Int] { all.filter { $0.value > 1 }.map(\.key) }
    }

    func session(seconds: Int) -> MatroskaRemuxSession {
        let r = SynthMKV(seconds: seconds).build()
        var o = RemuxOptions(); o.targetSegmentSeconds = 2
        return MatroskaRemuxSession(reader: CountingReader(r.data), options: o)
    }

    /// Lets every read-ahead task started so far run to its end (they are short on an in-memory file).
    func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    func testAudioOneSegmentBehindVideoReadsEachWindowOnce() async throws {
        let s = session(seconds: 24)
        let loads = Loads()
        await s.setLoadObserver { k, _ in loads.add(k) }
        _ = try await s.prepare()
        let count = 12
        for k in 0..<count {
            _ = try await s.resource(path: "seg_video_\(k).m4s")
            await settle()
            if k > 0 { _ = try await s.resource(path: "seg_audio_2_\(k - 1).m4s"); await settle() }
        }
        _ = try await s.resource(path: "seg_audio_2_\(count - 1).m4s")
        print("R471 (82) | audio one behind | loads after the start \(loads.all.map { "\($0.key):\($0.value)" }.joined(separator: " "))"
              + " | read twice \(loads.twice)")
        XCTAssertEqual(loads.twice, [], "windows read twice while the audio track plays one segment behind the video")
    }

    func planner() -> ReadAheadPlanner {
        ReadAheadPlanner(config: ReadAheadPlanner.Config(budget: EngineBudget(), bitrate: 1_000_000, segmentSeconds: 2, segmentCount: 50))
    }

    /// The planner: a request one segment behind keeps the playhead and the window read ahead of it.
    func testALagWithinTheBudgetIsNotASeek() {
        var p = planner()
        XCTAssertGreaterThanOrEqual(p.capacity, 3, "the default budget holds at least three windows here")
        _ = p.requested(10, now: 0)
        p.started(11)
        p.finished(11, bytes: 100_000, seconds: 0.01)
        let lag = p.requested(9, now: 0.1)
        XCTAssertEqual(p.playhead, 10, "the playhead stays with the leading track")
        XCTAssertTrue(p.held.contains(11), "the window read ahead of the playhead is kept")
        XCTAssertTrue(p.held.contains(9), "the lagging track's window is held too")
        XCTAssertEqual(lag.fetch, [], "nothing new to read for a lagging track")
        XCTAssertFalse(lag.cancel.contains(11))
    }

    /// The planner: a jump back further than the budget can hold beside the read-ahead is still a seek.
    func testAFarJumpBackIsStillASeek() {
        var p = planner()
        _ = p.requested(20, now: 0)
        p.started(21)
        let back = p.requested(5, now: 0.1)
        XCTAssertEqual(p.playhead, 5)
        XCTAssertTrue(back.cancel.contains(21), "the window in flight far ahead is cancelled")
        XCTAssertTrue(back.fetch.contains(6), "read-ahead starts from the new position")
    }
}
