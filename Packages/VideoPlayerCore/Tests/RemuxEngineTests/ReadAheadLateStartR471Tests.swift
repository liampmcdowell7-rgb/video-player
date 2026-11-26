import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R471 (79), PROVISIONAL (owner 25 Nov 2026 round 9, Part B item 1): read-ahead tasks that start late. Under load
/// (`SessionTests.testWindowsAreReadOnceAndSmall` failed 11 times in 200 next to four other test processes, 0 in 200 alone)
/// a read-ahead task spawned for a window started only after the player had been served that window and the cache had
/// evicted it, and read it again behind the playhead. The delay is in when the task starts, not in the read, so the tests
/// hold the task's start (`MatroskaRemuxSession.readAheadHold`) instead of a read.
final class ReadAheadLateStartR471Tests: XCTestCase {
    /// Holds the read-ahead tasks a test chooses until `release()`; counts every task that starts, per window.
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var started: [Int: Int] = [:]
        private var open = false
        private let holds: (Int, Int) -> Bool
        /// `holds(window, nth start of a task for it)`: whether that task waits for `release()`.
        init(holds: @escaping (Int, Int) -> Bool) { self.holds = holds }
        func starts(_ k: Int) -> Int { lock.withLock { started[k] ?? 0 } }
        func release() { lock.withLock { open = true } }
        func hold(_ k: Int) async {
            let mustWait: Bool = lock.withLock { started[k, default: 0] += 1; return holds(k, started[k]!) }
            guard mustWait else { return }
            while !lock.withLock({ open }) { try? await Task.sleep(nanoseconds: 2_000_000) }
        }
    }

    func session() -> MatroskaRemuxSession {
        let r = SynthMKV(seconds: 12).build()
        var o = RemuxOptions(); o.targetSegmentSeconds = 2
        return MatroskaRemuxSession(reader: CountingReader(r.data), options: o)
    }

    func ask(_ s: MatroskaRemuxSession, _ k: Int) async throws {
        _ = try await s.resource(path: "seg_video_\(k).m4s")
        _ = try await s.resource(path: "seg_audio_2_\(k).m4s")
        _ = try await s.resource(path: "seg_audio_3_\(k).m4s")
    }

    /// Waits up to `seconds` for `condition`.
    func wait(_ seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return await condition()
    }

    /// The seam: every read-ahead task passes the hold first, with its window.
    func testTheHoldSeesEachReadAheadTask() async throws {
        let s = session()
        let gate = Gate { _, _ in false }
        await s.setReadAheadHold { await gate.hold($0) }
        _ = try await s.prepare()
        try await ask(s, 0)
        let seen = await wait(2) { gate.starts(1) > 0 }
        XCTAssertTrue(seen, "the read-ahead task for window 1 passes the hold")
    }

    /// R471 (80): the traced order, made deterministic. The first read-ahead task for window 1 starts only after the player
    /// has been served segments 0 to 4 (window 1 is evicted by then); it must not read window 1 again.
    func testAReadAheadTaskThatStartsLateDoesNotReadAWindowBehindThePlayhead() async throws {
        let s = session()
        let gate = Gate { k, nth in k == 1 && nth == 1 }
        await s.setReadAheadHold { await gate.hold($0) }
        _ = try await s.prepare()
        for k in 0...4 { try await ask(s, k) }
        // Let the other read-ahead tasks finish, then count.
        _ = await wait(0.3) { false }
        let before = await s.windowLoads
        XCTAssertEqual(gate.starts(1) >= 1, true, "the held task for window 1 has started")
        gate.release()
        let readAgain = await wait(1) { await s.windowLoads > before }
        let after = await s.windowLoads
        print("R471 (80) | late read-ahead | loads before release \(before), after \(after)")
        XCTAssertFalse(readAgain, "the late task read window 1 again behind the playhead (\(before) loads, then \(after))")
    }

    /// R471 (80): one read-ahead task per window while the first has not started. Today each request for segment 0 (video and
    /// two audio tracks) spawned another task for window 1.
    func testOneReadAheadTaskPerWindowUntilItStarts() async throws {
        let s = session()
        let gate = Gate { _, _ in true }
        await s.setReadAheadHold { await gate.hold($0) }
        _ = try await s.prepare()
        try await ask(s, 0)
        _ = await wait(2) { gate.starts(1) >= 1 }
        _ = await wait(0.3) { false }
        let tasks = gate.starts(1)
        gate.release()
        print("R471 (80) | read-ahead tasks for window 1 after three requests for segment 0: \(tasks)")
        XCTAssertEqual(tasks, 1, "one read-ahead task for window 1")
    }
}
