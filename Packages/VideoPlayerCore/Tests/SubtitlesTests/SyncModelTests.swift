import XCTest
@testable import Subtitles

final class SyncModelTests: XCTestCase {

    // MARK: Plan per path

    func testAVPlayerLeavesOutputLatencyToTheSystem() {
        let p = SyncModel.plan(path: .avPlayer, userDelay: 0.120, systemOutputLatency: 0.25)
        XCTAssertEqual(p.outputLatencyOwner, .system)
        XCTAssertEqual(p.appCompensation, 0)
        XCTAssertEqual(p.userDelay, 0.120, accuracy: 1e-9)
        XCTAssertEqual(p.effectiveAudioDelay, 0.120, accuracy: 1e-9, "only the per-file delay is added")
        XCTAssertEqual(p.reportedOutputLatency, 0.25, accuracy: 1e-9)
    }

    func testFallbackEngineAppliesOutputLatencyItself() {
        let p = SyncModel.plan(path: .fallbackEngine, userDelay: 0.120, systemOutputLatency: 0.25)
        XCTAssertEqual(p.outputLatencyOwner, .app)
        XCTAssertEqual(p.appCompensation, -0.25, accuracy: 1e-9)
        XCTAssertEqual(p.effectiveAudioDelay, 0.120 - 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.equivalentVideoDelay, 0.25 - 0.120, accuracy: 1e-9)
    }

    func testFallbackEngineBehindSystemSynchronisedRendererDoesNotDoubleApply() {
        let p = SyncModel.plan(path: .fallbackEngine, userDelay: 0.1, systemOutputLatency: 0.25, settings: SyncSettings(fallbackOutputIsSystemSynchronised: true))
        XCTAssertEqual(p.outputLatencyOwner, .system)
        XCTAssertEqual(p.appCompensation, 0)
        XCTAssertEqual(p.effectiveAudioDelay, 0.1, accuracy: 1e-9)
    }

    /// The core rule: whatever the path, the output latency is accounted for by exactly one party.
    func testNoDoubleApplyAcrossAllPaths() {
        let latencies: [TimeInterval?] = [nil, 0, 0.001, 0.05, 0.25, 0.9, 2.0, 3.0, 10, -1, .nan, .infinity]
        let delays: [TimeInterval] = [-9, -5, -1.234, -0.001, 0, 0.0004, 0.5, 4.9996, 5, 100, .nan, .infinity, -.infinity]
        for path in PlaybackPath.allCases {
            for sync in [false, true] {
                let settings = SyncSettings(fallbackOutputIsSystemSynchronised: sync)
                for l in latencies {
                    for d in delays {
                        let p = SyncModel.plan(path: path, userDelay: d, systemOutputLatency: l, settings: settings)
                        let owner = SyncModel.owner(for: path, settings: settings)
                        XCTAssertEqual(p.outputLatencyOwner, owner)
                        switch owner {
                        case .system: XCTAssertEqual(p.appCompensation, 0, "system owns it, app adds nothing: \(path) \(String(describing: l)) \(d)")
                        case .app: XCTAssertEqual(p.appCompensation, -p.reportedOutputLatency, accuracy: 1e-12)
                        }
                        XCTAssertEqual(p.effectiveAudioDelay, p.userDelay + p.appCompensation, accuracy: 1e-12)
                        XCTAssertTrue(p.effectiveAudioDelay.isFinite)
                        XCTAssertLessThanOrEqual(abs(p.userDelay), SyncModel.maxUserDelay)
                        XCTAssertGreaterThanOrEqual(p.reportedOutputLatency, 0)
                        XCTAssertLessThanOrEqual(p.reportedOutputLatency, SyncModel.maxPlausibleLatency)
                    }
                }
            }
        }
    }

    func testChangingLatencyOnlyChangesTheFallbackPath() {
        let av0 = SyncModel.plan(path: .avPlayer, userDelay: 0.3, systemOutputLatency: 0)
        let av1 = SyncModel.plan(path: .avPlayer, userDelay: 0.3, systemOutputLatency: 2.0)
        XCTAssertEqual(av0.effectiveAudioDelay, av1.effectiveAudioDelay)
        let fb0 = SyncModel.plan(path: .fallbackEngine, userDelay: 0.3, systemOutputLatency: 0)
        let fb1 = SyncModel.plan(path: .fallbackEngine, userDelay: 0.3, systemOutputLatency: 2.0)
        XCTAssertNotEqual(fb0.effectiveAudioDelay, fb1.effectiveAudioDelay)
        XCTAssertEqual(fb0.effectiveAudioDelay - fb1.effectiveAudioDelay, 2.0, accuracy: 1e-9)
    }

    func testUnknownLatencyMeansZero() {
        let p = SyncModel.plan(path: .fallbackEngine, userDelay: 0.2, systemOutputLatency: nil)
        XCTAssertEqual(p.appCompensation, 0)
        XCTAssertEqual(p.effectiveAudioDelay, 0.2, accuracy: 1e-9)
    }

    // MARK: Clamp

    func testClampedDelay() {
        XCTAssertEqual(SyncModel.clampedDelay(0.1234), 0.123, accuracy: 1e-12)
        XCTAssertEqual(SyncModel.clampedDelay(0.1235), 0.124, accuracy: 1e-12)
        XCTAssertEqual(SyncModel.clampedDelay(7), 5)
        XCTAssertEqual(SyncModel.clampedDelay(-7), -5)
        XCTAssertEqual(SyncModel.clampedDelay(.nan), 0)
        XCTAssertEqual(SyncModel.clampedDelay(.infinity), 0)
        XCTAssertEqual(SyncModel.clampedDelay(-.infinity), 0)
        XCTAssertEqual(SyncModel.clampedDelay(0.0004), 0)
    }

    // MARK: Drift

    private func samples(driftMsPerHour: Double, offset0: Double = 0, count: Int = 13, span: Double = 3600, noise: Double = 0, seed: UInt64 = 5) -> [ClockSample] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { i in
            let t = span * Double(i) / Double(count - 1)
            let n = noise == 0 ? 0 : (Double(rng.next() % 2001) / 1000 - 1) * noise
            let video = t
            let audio = t + offset0 + driftMsPerHour / 1000 * (t / 3600) + n
            return ClockSample(elapsed: t, audioClock: audio, videoClock: video)
        }
    }

    func testDriftSlopeIsRecovered() throws {
        for ms in [-300.0, -60, 0, 25, 120, 900] {
            let r = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: ms)))
            XCTAssertEqual(r.driftMillisecondsPerHour, ms, accuracy: 0.001, "drift \(ms)")
            XCTAssertTrue(r.isReliable)
            XCTAssertEqual(r.sampleCount, 13)
            XCTAssertEqual(r.span, 3600, accuracy: 1e-9)
        }
    }

    func testDriftSlopeWithNoise() throws {
        let r = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 200, count: 200, noise: 0.004)))
        XCTAssertEqual(r.driftMillisecondsPerHour, 200, accuracy: 15)
    }

    func testConstantOffsetIsNotDrift() throws {
        let r = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 0, offset0: 0.4)))
        XCTAssertEqual(r.driftMillisecondsPerHour, 0, accuracy: 1e-6)
        XCTAssertFalse(r.needsCorrection, "a steady offset is for the delay setting, not the drift check")
        XCTAssertEqual(r.suggestedAudioDelayChange, 0, accuracy: 1e-9)
    }

    func testCorrectionThreshold() throws {
        let under = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 30)))
        XCTAssertFalse(under.needsCorrection)
        let over = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 100)))
        XCTAssertTrue(over.needsCorrection)
        // Audio ahead (positive) is corrected by delaying audio: a positive suggestion.
        XCTAssertGreaterThan(over.suggestedAudioDelayChange, 0)
        let behind = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: -100)))
        XCTAssertLessThan(behind.suggestedAudioDelayChange, 0)
        let custom = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 100), thresholdMilliseconds: 500))
        XCTAssertFalse(custom.needsCorrection)
    }

    func testDriftReliabilityNeedsSamplesAndSpan() throws {
        let two = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 100, count: 2)))
        XCTAssertFalse(two.isReliable)
        let short = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 100, count: 20, span: 10)))
        XCTAssertFalse(short.isReliable)
        let ok = try XCTUnwrap(DriftCheck.evaluate(samples(driftMsPerHour: 100, count: 20, span: 600)))
        XCTAssertTrue(ok.isReliable)
    }

    func testDriftRejectsBadInput() {
        XCTAssertNil(DriftCheck.evaluate([]))
        XCTAssertNil(DriftCheck.evaluate([ClockSample(elapsed: 0, audioClock: 0, videoClock: 0)]))
        XCTAssertNil(DriftCheck.evaluate([
            ClockSample(elapsed: .nan, audioClock: 0, videoClock: 0),
            ClockSample(elapsed: 1, audioClock: .infinity, videoClock: 0),
            ClockSample(elapsed: 2, audioClock: 0, videoClock: 0),
        ]))
        // Samples at the same instant: no slope, no crash.
        let same = DriftCheck.evaluate([ClockSample(elapsed: 5, audioClock: 1, videoClock: 0), ClockSample(elapsed: 5, audioClock: 2, videoClock: 0)])
        XCTAssertEqual(same?.driftMillisecondsPerHour, 0)
    }

    func testDriftSamplesNeedNotBeSorted() throws {
        var s = samples(driftMsPerHour: 120)
        var rng = SeededGenerator(seed: 3)
        s.shuffle(using: &rng)
        let r = try XCTUnwrap(DriftCheck.evaluate(s))
        XCTAssertEqual(r.driftMillisecondsPerHour, 120, accuracy: 0.001)
    }

    // MARK: Per-file delay storage

    func testDelayTableSetGetAndClamp() {
        var t = SyncDelayTable()
        let k = SyncFileKey(sourceID: "nas", path: "/tv/Show/S01E01.mkv", size: 1_234_567)
        XCTAssertEqual(t.delay(for: k), 0)
        t.setDelay(0.2504, for: k)
        XCTAssertEqual(t.delay(for: k), 0.25, accuracy: 1e-12)
        t.setDelay(99, for: k)
        XCTAssertEqual(t.delay(for: k), 5)
        t.setDelay(0, for: k)
        XCTAssertEqual(t.count, 0, "zero removes the entry")
    }

    func testDelayKeyIncludesSourceAndSize() {
        var t = SyncDelayTable()
        let a = SyncFileKey(sourceID: "nas", path: "/m/a.mkv", size: 100)
        let b = SyncFileKey(sourceID: "nas", path: "/m/a.mkv", size: 101)
        let c = SyncFileKey(sourceID: "usb", path: "/m/a.mkv", size: 100)
        t.setDelay(0.1, for: a)
        XCTAssertEqual(t.delay(for: b), 0)
        XCTAssertEqual(t.delay(for: c), 0)
        XCTAssertEqual(t.delay(for: a), 0.1, accuracy: 1e-12)
        let unknownSize = SyncFileKey(sourceID: "nas", path: "/m/a.mkv", size: nil)
        XCTAssertEqual(t.delay(for: unknownSize), 0)
    }

    func testDelayTablePersistsToDisk() throws {
        var t = SyncDelayTable()
        let k1 = SyncFileKey(sourceID: "nas", path: "/a/é 映画.mkv", size: 42)
        let k2 = SyncFileKey(sourceID: "nas", path: "/b.mkv", size: nil)
        t.setDelay(-0.35, for: k1)
        t.setDelay(1.5, for: k2)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("delays.json")
        try t.save(to: url)
        let loaded = SyncDelayTable.load(from: url)
        XCTAssertEqual(loaded, t)
        XCTAssertEqual(loaded.delay(for: k1), -0.35, accuracy: 1e-12)
        XCTAssertEqual(loaded.delay(for: k2), 1.5, accuracy: 1e-12)
    }

    func testDelayTableLoadTolerance() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(SyncDelayTable.load(from: dir.appendingPathComponent("missing.json")).count, 0)
        let bad = dir.appendingPathComponent("bad.json")
        try Data("{ not json".utf8).write(to: bad)
        XCTAssertEqual(SyncDelayTable.load(from: bad).count, 0)
        try Data().write(to: bad)
        XCTAssertEqual(SyncDelayTable.load(from: bad).count, 0)
    }
}
