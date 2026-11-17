import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

final class ReadAheadPlannerTests: XCTestCase {
    func planner(bitrate: Double = 80e6, seconds: Double = 4, count: Int = 100, budget: EngineBudget = EngineBudget()) -> ReadAheadPlanner {
        ReadAheadPlanner(config: .init(budget: budget, bitrate: bitrate, segmentSeconds: seconds, segmentCount: count))
    }

    func testCapacityFollowsTheBudget() {
        let p = planner()
        XCTAssertEqual(p.segmentBytes, 40_000_000)
        XCTAssertEqual(p.windowBytes, 60_000_000)
        XCTAssertEqual(p.capacity, 3)                                      // floor(192 MiB / 60 MB)
        XCTAssertEqual(planner(bitrate: 10e6, seconds: 6).capacity, 5, "capped at maxAhead + 1")
        XCTAssertEqual(planner(bitrate: 400e6, seconds: 2).capacity, 1, "over budget: one window")
    }

    func testFirstRequestReadsOneSegmentAhead() {
        var p = planner()
        let r = p.requested(0, now: 0)
        XCTAssertEqual(r.fetch, [1]); XCTAssertEqual(r.cancel, [])
        XCTAssertEqual(p.health, .unknown)
    }

    func testFastReaderGetsMoreReadAheadUpToTheBudget() {
        var p = planner()
        _ = p.requested(0, now: 0)
        p.started(0); p.finished(0, bytes: 60_000_000, seconds: 2)       // 30 MB/s = 240 Mbps against 80 Mbps
        XCTAssertEqual(p.health, .healthy)
        let r = p.requested(1, now: 4)
        XCTAssertEqual(r.fetch, [2, 3], "needs 2 segments ahead; the budget allows capacity - 1 = 2")
        // A 20 Mbps media file has room for four segments ahead.
        var small = planner(bitrate: 20e6, seconds: 6)
        _ = small.requested(0, now: 0); small.started(0); small.finished(0, bytes: 22_000_000, seconds: 0.2)
        XCTAssertEqual(small.requested(1, now: 6).fetch, [2, 3])
    }

    func testHealthClassification() {
        var p = planner()
        p.started(0); p.finished(0, bytes: 12_000_000, seconds: 1)         // 96 Mbps against 80 Mbps: 1.2x
        XCTAssertEqual(p.health, .tight)
        var slow = planner()
        slow.started(0); slow.finished(0, bytes: 5_000_000, seconds: 1)    // 40 Mbps
        XCTAssertEqual(slow.health, .starved)
        var fast = planner()
        fast.started(0); fast.finished(0, bytes: 30_000_000, seconds: 1)
        XCTAssertEqual(fast.health, .healthy)
    }

    func testThroughputIsSmoothed() {
        var p = planner()
        p.started(0); p.finished(0, bytes: 10_000_000, seconds: 1)
        p.started(1); p.finished(1, bytes: 40_000_000, seconds: 1)
        XCTAssertEqual(p.throughput ?? 0, 19_000_000, accuracy: 1, "0.7 x old + 0.3 x new")
    }

    func testSeekCancelsFarAwayWorkAndDropsOldWindows() {
        var p = planner()
        _ = p.requested(0, now: 0); p.started(1)
        let r = p.requested(60, now: 10)
        XCTAssertEqual(r.cancel, [1])
        XCTAssertFalse(p.inFlight.contains(1)); XCTAssertFalse(p.held.contains(0))
        XCTAssertEqual(p.playhead, 60)
        XCTAssertTrue(p.held.contains(60))
    }

    func testWindowsBehindThePlayheadAreReleased() {
        var p = planner(bitrate: 20e6, seconds: 6)
        for k in 0..<6 { _ = p.requested(k, now: Double(k) * 6); p.started(k); p.finished(k, bytes: 1_000_000, seconds: 0.1) }
        XCTAssertTrue(p.held.isSubset(of: Set(4...9)), "kept: one behind the playhead and the read-ahead, got \(p.held.sorted())")
        XCTAssertLessThanOrEqual(p.held.count, p.capacity + 1)
    }

    func testIdlePlayerShrinksReadAhead() {
        var p = planner(bitrate: 20e6, seconds: 6)
        _ = p.requested(0, now: 0); p.started(0); p.finished(0, bytes: 2_000_000, seconds: 0.1)
        XCTAssertEqual(p.desiredAhead(now: 1), 2)
        XCTAssertEqual(p.desiredAhead(now: 500), 1, "no request for 500 s: the player is paused")
    }

    func testOverBudgetNeverReadsAhead() {
        var p = planner(bitrate: 400e6, seconds: 2)
        let r = p.requested(0, now: 0)
        XCTAssertEqual(r.fetch, [])
        p.started(0); p.finished(0, bytes: 150_000_000, seconds: 1)
        XCTAssertEqual(p.requested(1, now: 2).fetch, [])
    }

    func testEndOfMediaStopsReadAhead() {
        var p = planner(count: 3)
        XCTAssertEqual(p.requested(2, now: 0).fetch, [])
        p.started(1); p.failed(1)
        XCTAssertFalse(p.inFlight.contains(1)); XCTAssertFalse(p.held.contains(1))
    }

    func testManualClock() {
        let c = ManualEngineClock(5)
        XCTAssertEqual(c.now, 5); c.advance(2.5); XCTAssertEqual(c.now, 7.5)
        let s = SystemEngineClock()
        XCTAssertLessThanOrEqual(s.now, s.now + 0.001)
    }
}

/// A discrete-event model of one playback: the player asks for segment k at k x segment length; windows load one after
/// the other through a pipe of `fetchBytesPerSecond`. Memory is the number of windows held or loading times the window size.
struct ReadAheadSimulation {
    struct Outcome {
        var peakBytes: Int64 = 0
        var peakWindows = 0
        var lateSegments = 0
        var worstLateSeconds = 0.0
        var windowBytes: Int64 = 0
        var segmentSeconds = 0.0
        var finalHealth: ReadAheadPlanner.Health = .unknown
    }

    static func run(bitrate: Double, fetchBytesPerSecond: Double, segments: Int, budget: EngineBudget = EngineBudget(), seek: (at: Int, to: Int)? = nil) -> Outcome {
        let seconds = budget.targetSegmentSeconds(bitrate: bitrate)
        var planner = ReadAheadPlanner(config: .init(budget: budget, bitrate: bitrate, segmentSeconds: seconds, segmentCount: segments))
        var out = Outcome()
        out.segmentSeconds = seconds; out.windowBytes = planner.windowBytes
        var finishAt: [Int: Double] = [:]          // when each window is (or will be) loaded
        var pipeFree = 0.0
        func start(_ k: Int, now: Double) {
            guard finishAt[k] == nil else { return }
            planner.started(k)
            let begin = max(now, pipeFree)
            pipeFree = begin + Double(planner.windowBytes) / fetchBytesPerSecond
            finishAt[k] = pipeFree
        }
        func settle(now: Double) {
            for (k, t) in finishAt.sorted(by: { $0.value < $1.value }) where t <= now && planner.inFlight.contains(k) {
                planner.finished(k, bytes: planner.windowBytes, seconds: Double(planner.windowBytes) / fetchBytesPerSecond)
            }
        }
        func sample() {
            let live = planner.held.union(planner.inFlight).count
            out.peakWindows = max(out.peakWindows, live)
            out.peakBytes = max(out.peakBytes, Int64(live) * planner.windowBytes)
        }
        var k = 0, played = 0.0
        var requestedAt = 0.0
        var sequence = 0
        while sequence < segments {
            let index = k
            let now = requestedAt
            settle(now: now)
            let plan = planner.requested(index, now: now)
            for c in plan.cancel { finishAt[c] = nil }
            start(index, now: now)
            for f in plan.fetch { start(f, now: now) }
            sample()
            let ready = finishAt[index] ?? now
            let late = ready - (now + (sequence == 0 ? 0 : seconds))      // the player holds one segment of buffer
            if sequence > 0 && late > 0 { out.lateSegments += 1; out.worstLateSeconds = max(out.worstLateSeconds, late) }
            settle(now: max(now, ready))
            sample()
            played += seconds
            requestedAt = max(requestedAt + seconds, ready)                // a late segment delays everything after it
            k += 1; sequence += 1
            if let s = seek, sequence == s.at { k = s.to }
            if k >= segments { break }
        }
        out.finalHealth = planner.health
        return out
    }
}

final class ReadAheadSimulationTests: XCTestCase {
    func report(_ name: String, _ o: ReadAheadSimulation.Outcome) {
        print("[readahead-sim] \(name): segment \(String(format: "%.2f", o.segmentSeconds)) s, window \(o.windowBytes / 1_048_576) MiB, peak \(o.peakWindows) windows = \(o.peakBytes / 1_048_576) MiB, late \(o.lateSegments), worst late \(String(format: "%.2f", o.worstLateSeconds)) s, health \(o.finalHealth)")
    }

    func testHundredTwentyMbpsOverAFastLinkStaysInsideTheBudget() {
        let b = EngineBudget()
        let o = ReadAheadSimulation.run(bitrate: 120e6, fetchBytesPerSecond: 50_000_000, segments: 60, budget: b)    // 400 Mbps link
        report("120 Mbps over 400 Mbps", o)
        XCTAssertLessThanOrEqual(o.peakBytes, b.memoryBytes)
        XCTAssertEqual(o.lateSegments, 0)
        XCTAssertEqual(o.finalHealth, .healthy)
        XCTAssertGreaterThanOrEqual(o.peakWindows, 2, "it does read ahead")
        XCTAssertEqual(o.segmentSeconds, 4.474, accuracy: 0.01)
    }

    func testHundredTwentyMbpsOverASlowLinkIsReportedStarved() {
        let o = ReadAheadSimulation.run(bitrate: 120e6, fetchBytesPerSecond: 10_000_000, segments: 20)               // 80 Mbps link
        report("120 Mbps over 80 Mbps", o)
        XCTAssertEqual(o.finalHealth, .starved)
        XCTAssertGreaterThan(o.lateSegments, 0)
    }

    func testBackPressureNeverExceedsTheBudgetAcrossBitrates() {
        let b = EngineBudget()
        for mbps in [8.0, 30, 60, 100, 120, 160, 200, 250] {
            let o = ReadAheadSimulation.run(bitrate: mbps * 1e6, fetchBytesPerSecond: mbps * 1e6 / 8 * 4, segments: 40, budget: b)
            XCTAssertLessThanOrEqual(o.peakBytes, b.memoryBytes, "\(mbps) Mbps: \(o.peakBytes / 1_048_576) MiB")
        }
    }

    func testOverBudgetBitrateUsesOneWindow() {
        let o = ReadAheadSimulation.run(bitrate: 400e6, fetchBytesPerSecond: 100_000_000, segments: 20)
        report("400 Mbps (over budget)", o)
        XCTAssertEqual(o.peakWindows, 1)
        XCTAssertLessThanOrEqual(o.peakBytes, EngineBudget().memoryBytes)
    }

    func testSeekDoesNotLeakWindows() {
        let b = EngineBudget()
        let o = ReadAheadSimulation.run(bitrate: 120e6, fetchBytesPerSecond: 50_000_000, segments: 80, budget: b, seek: (at: 10, to: 60))
        report("120 Mbps with a seek", o)
        XCTAssertLessThanOrEqual(o.peakBytes, b.memoryBytes)
    }
}
