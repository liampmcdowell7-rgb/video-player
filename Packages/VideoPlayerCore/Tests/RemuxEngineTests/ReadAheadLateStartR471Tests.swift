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
}
