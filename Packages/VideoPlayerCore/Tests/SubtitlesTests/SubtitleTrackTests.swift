import XCTest
@testable import Subtitles

final class SubtitleTrackTests: XCTestCase {

    private func cue(_ start: Double, _ end: Double, _ text: String = "x", layer: Int = 0) -> SubtitleCue {
        SubtitleCue(start: start, end: end, runs: [SubtitleRun(text)], format: .srt, layer: layer)
    }

    // MARK: activeCues

    func testActiveCuesBoundaries() {
        let t = SubtitleTrack(cues: [cue(1, 2, "a"), cue(2, 3, "b")], format: .srt)
        XCTAssertEqual(t.activeCues(at: 0.999).count, 0)
        XCTAssertEqual(t.activeCues(at: 1).map(\.plainText), ["a"])      // start is inclusive
        XCTAssertEqual(t.activeCues(at: 1.999).map(\.plainText), ["a"])
        XCTAssertEqual(t.activeCues(at: 2).map(\.plainText), ["b"])      // end is exclusive
        XCTAssertEqual(t.activeCues(at: 3).count, 0)
        XCTAssertEqual(t.activeCues(at: -5).count, 0)
        XCTAssertEqual(t.activeCues(at: .infinity).count, 0)
    }

    func testEmptyTrack() {
        let t = SubtitleTrack(cues: [], format: .srt)
        XCTAssertTrue(t.isEmpty)
        XCTAssertEqual(t.activeCues(at: 1).count, 0)
        XCTAssertNil(t.nextChange(after: 0))
    }

    func testNestedAndOverlappingCuesAreAllFound() {
        let t = SubtitleTrack(cues: [cue(0, 100, "long"), cue(10, 20, "a"), cue(15, 30, "b"), cue(16, 17, "c"), cue(50, 60, "d")], format: .srt)
        XCTAssertEqual(t.activeCues(at: 16.5).map(\.plainText), ["long", "a", "b", "c"])
        XCTAssertEqual(t.activeCues(at: 40).map(\.plainText), ["long"])
        XCTAssertEqual(t.activeCues(at: 55).map(\.plainText), ["long", "d"])
    }

    func testMatchesBruteForceOnRandomOverlappingCues() {
        var rng = SplitMix64(seed: 42)
        var cues: [SubtitleCue] = []
        for i in 0..<2000 {
            let start = Double(rng.int(10_000)) / 10
            let length = Double(rng.int(300)) / 10 + 0.1
            cues.append(cue(start, start + length, "c\(i)"))
        }
        let t = SubtitleTrack(cues: cues, format: .srt)
        for _ in 0..<500 {
            let q = Double(rng.int(11_000)) / 10
            let expected = Set(cues.filter { $0.start <= q && q < $0.end }.map(\.plainText))
            let got = t.activeCues(at: q)
            XCTAssertEqual(Set(got.map(\.plainText)), expected, "t=\(q)")
            XCTAssertEqual(got.count, expected.count)
            XCTAssertEqual(got.map(\.start), got.map(\.start).sorted(), "results are in start order")
        }
    }

    func testFiftyThousandCuesQueryIsFastAndCorrect() {
        // 50,000 cues, each 4 s long, one every 0.1 s: about 40 cues overlap at any moment.
        var cues: [SubtitleCue] = []
        cues.reserveCapacity(50_000)
        for i in 0..<50_000 { cues.append(cue(Double(i) * 0.1, Double(i) * 0.1 + 4, "n\(i)")) }
        var shuffleRNG = SeededGenerator(seed: 7)
        cues.shuffle(using: &shuffleRNG)
        let built = Date()
        let t = SubtitleTrack(cues: cues, format: .srt)
        let buildTime = Date().timeIntervalSince(built)
        XCTAssertEqual(t.count, 50_000)

        let start = Date()
        var total = 0
        for k in 0..<20_000 {
            let q = Double(k) * 0.25 + 0.05
            let active = t.activeCues(at: q)
            total += active.count
            if k % 997 == 0 {
                let expected = cues.filter { $0.start <= q && q < $0.end }.count
                XCTAssertEqual(active.count, expected, "t=\(q)")
            }
        }
        let queryTime = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(total, 20_000 * 30)
        // 20,000 queries of ~40 hits each. A linear scan would need 10^9 comparisons; the index does it well inside this bound.
        XCTAssertLessThan(queryTime, 5.0, "queries took \(queryTime)s")
        XCTAssertLessThan(buildTime, 10.0, "build took \(buildTime)s")
    }

    func testOneHugeCueSpanningEverythingStillFast() {
        var cues = (0..<50_000).map { cue(Double($0), Double($0) + 0.5, "s\($0)") }
        cues.append(cue(0, 1_000_000, "everything"))
        let t = SubtitleTrack(cues: cues, format: .srt)
        let start = Date()
        for k in 0..<5000 {
            let a = t.activeCues(at: Double(k * 9) + 0.25)
            XCTAssertEqual(a.count, 2)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5.0)
    }

    func testNextChange() {
        let t = SubtitleTrack(cues: [cue(1, 5, "a"), cue(3, 4, "b"), cue(10, 12, "c")], format: .srt)
        XCTAssertEqual(t.nextChange(after: 0), 1)
        XCTAssertEqual(t.nextChange(after: 1), 3)
        XCTAssertEqual(t.nextChange(after: 3), 4)     // b ends before the next start
        XCTAssertEqual(t.nextChange(after: 4), 5)
        XCTAssertEqual(t.nextChange(after: 5), 10)
        XCTAssertEqual(t.nextChange(after: 10), 12)
        XCTAssertNil(t.nextChange(after: 12))
    }

    // MARK: Offset

    func testShiftLaterAndEarlier() {
        let t = SubtitleTrack(cues: [cue(1, 2, "a"), cue(5, 6, "b")], format: .srt)
        let later = t.shifted(by: 2.5)
        XCTAssertEqual(later.cues.map(\.start), [3.5, 7.5])
        XCTAssertEqual(later.cues.map(\.end), [4.5, 8.5])
        let earlier = t.shifted(by: -0.5)
        XCTAssertEqual(earlier.cues.map(\.start), [0.5, 4.5])
        XCTAssertEqual(earlier.activeCues(at: 0.6).map(\.plainText), ["a"])
    }

    func testShiftNeverProducesNegativeStartsAndDropsCuesThatEndBeforeZero() {
        let t = SubtitleTrack(cues: [cue(0.5, 1.5, "a"), cue(2, 3, "b"), cue(4, 5, "c")], format: .srt)
        let s = t.shifted(by: -2.5)
        XCTAssertEqual(s.cues.map(\.plainText), ["b", "c"])
        XCTAssertEqual(s.cues[0].start, 0)                      // clamped
        XCTAssertEqual(s.cues[0].end, 0.5, accuracy: 1e-9)
        XCTAssertTrue(s.cues.allSatisfy { $0.start >= 0 })
        XCTAssertEqual(t.shifted(by: -100).count, 0)
        XCTAssertEqual(t.shifted(by: 0).cues, t.cues)
    }

    func testShiftIsPerTrackAndLeavesTheOriginalAlone() {
        let a = SubtitleTrack(cues: [cue(1, 2)], format: .srt)
        let b = a.shifted(by: 10)
        XCTAssertEqual(a.cues[0].start, 1)
        XCTAssertEqual(b.cues[0].start, 11)
    }

    // MARK: Merge

    func testMergingIdenticalNeighbours() {
        let t = SubtitleTrack(cues: [cue(1, 2, "same"), cue(2, 3, "same"), cue(3.0005, 4, "same"), cue(6, 7, "same"), cue(2, 3, "other")], format: .srt)
        let m = t.mergingIdenticalNeighbours(maxGap: 0.001)
        XCTAssertEqual(m.cues.filter { $0.plainText == "same" }.map { [$0.start, $0.end] }, [[1, 4], [6, 7]])
        XCTAssertEqual(m.cues.filter { $0.plainText == "other" }.count, 1)
    }

    func testMergingCollapsesOverlappingDuplicatesButNotDifferentStyles() {
        var italic = cue(1, 3, "dup")
        italic.runs = [SubtitleRun("dup", italic: true)]
        let t = SubtitleTrack(cues: [cue(1, 3, "dup"), cue(2, 4, "dup"), italic], format: .srt)
        let m = t.mergingIdenticalNeighbours()
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m.cues.first { !($0.runs.first?.italic ?? false) }?.end, 4)
    }

    func testMergeDoesNotJoinAcrossAGap() {
        let t = SubtitleTrack(cues: [cue(1, 2, "x"), cue(2.5, 3, "x")], format: .srt)
        XCTAssertEqual(t.mergingIdenticalNeighbours(maxGap: 0.1).count, 2)
        XCTAssertEqual(t.mergingIdenticalNeighbours(maxGap: 0.6).count, 1)
    }

    func testTrackFlagsPropagateToCues() {
        let t = SubtitleTrack(cues: [cue(1, 2)], format: .srt, language: "en", isForced: true, isSDH: true)
        XCTAssertTrue(t.cues[0].isForced)
        XCTAssertTrue(t.cues[0].isSDH)
        XCTAssertTrue(t.shifted(by: 1).cues[0].isForced)
    }

    func testSortOrderTiesByLayerThenEnd() {
        let t = SubtitleTrack(cues: [cue(1, 5, "L1", layer: 1), cue(1, 3, "L0b", layer: 0), cue(1, 2, "L0a", layer: 0)], format: .srt)
        XCTAssertEqual(t.cues.map(\.plainText), ["L0a", "L0b", "L1"])
    }
}

/// Deterministic generator so shuffles are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var inner: SplitMix64
    init(seed: UInt64) { inner = SplitMix64(seed: seed) }
    mutating func next() -> UInt64 { inner.next() }
}
