import XCTest
@testable import PlaybackLogic

/// Synthetic data only. A 1000 s file: B1 tolerance is max(2 s, 5 s) = 5 s, credits must start at 600 s or later.
enum Fixture {
    static let file = FileIdentity(path: "/tv/Show/S01E01.mkv", size: 1_000_000, duration: 1000)

    static func seg(_ type: SegmentType, _ start: TimeInterval, _ end: TimeInterval,
                    source: SegmentSource = .embeddedChapters, confidence: Double = 0.9,
                    reference: TimeInterval? = nil, file: FileIdentity = Fixture.file) -> SkipSegment {
        SkipSegment(type: type, start: start, end: end, source: source, confidence: confidence, file: file,
                    referenceDuration: reference)
    }

    static func resolve(_ candidates: [SkipSegment], post: TimeInterval? = nil) -> ResolvedSegments {
        SegmentResolver.resolve(file: file, candidates: candidates, postCreditsStart: post)
    }
}

final class SegmentTests: XCTestCase {
    // SEG-1
    func testSEG1_segmentOfAnotherFileIsRejected() {
        let other = FileIdentity(path: "/tv/Show/S01E01-other.mkv", size: 1_000_000, duration: 1000)
        let differentSize = FileIdentity(path: Fixture.file.path, size: 999, duration: 1000)
        let differentDuration = FileIdentity(path: Fixture.file.path, size: 1_000_000, duration: 1000.6)
        let sameWithinHalfSecond = FileIdentity(path: Fixture.file.path, size: 1_000_000, duration: 1000.4)
        for file in [other, differentSize, differentDuration] {
            let r = Fixture.resolve([Fixture.seg(.intro, 10, 60, file: file)])
            XCTAssertTrue(r.segments.isEmpty)
            XCTAssertEqual(r.rejected.first?.reason, .differentFile)
        }
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.intro, 10, 60, file: sameWithinHalfSecond)]).segments.count, 1)
    }

    // SEG-2 (table-driven: file duration, reference duration, accepted?)
    func testSEG2_databaseSegmentNeedsMatchingDurationWithinGreaterOfTwoSecondsOrHalfPercent() {
        let rows: [(duration: TimeInterval, reference: TimeInterval, accepted: Bool)] = [
            (1000, 1000, true), (1000, 1005, true), (1000, 995, true),   // 0.5 % of 1000 s is 5 s
            (1000, 1005.1, false), (1000, 994.9, false),
            (100, 102, true), (100, 98, true),                           // short file: 2 s wins over 0.5 s
            (100, 102.1, false), (100, 97.9, false),
        ]
        for row in rows {
            let f = FileIdentity(path: "/a.mkv", size: 1, duration: row.duration)
            let s = Fixture.seg(.intro, 10, 60, source: .onlineDatabase, reference: row.reference, file: f)
            let r = SegmentResolver.resolve(file: f, candidates: [s])
            XCTAssertEqual(!r.segments.isEmpty, row.accepted, "duration \(row.duration) reference \(row.reference)")
            if !row.accepted { XCTAssertEqual(r.rejected.first?.reason, .durationMismatch) }
        }
    }

    // SEG-3
    func testSEG3_onlineSegmentWithoutReferenceDurationIsRejected() {
        let r = Fixture.resolve([Fixture.seg(.intro, 10, 60, source: .onlineDatabase, reference: nil)])
        XCTAssertTrue(r.segments.isEmpty)
        XCTAssertEqual(r.rejected.first?.reason, .durationMismatch)
    }

    // SEG-4
    func testSEG4_confidenceThresholdIsSeventyPercentInclusive() {
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.intro, 10, 60, confidence: 0.7)]).segments.count, 1)
        let low = Fixture.resolve([Fixture.seg(.intro, 10, 60, confidence: 0.699)])
        XCTAssertTrue(low.segments.isEmpty)
        XCTAssertEqual(low.rejected.first?.reason, .lowConfidence)
        XCTAssertTrue(Fixture.resolve([Fixture.seg(.intro, 10, 60, confidence: .nan)]).segments.isEmpty)
    }

    // SEG-5 (table-driven: remove the winner each time)
    func testSEG5_priorityUserThenChaptersThenSidecarThenOnlineThenOnDevice() {
        let order: [SegmentSource] = [.userMarked, .embeddedChapters, .localSidecar, .onlineDatabase, .onDeviceDetection]
        for first in 0..<order.count {
            let sources = Array(order[first...])
            // Different starts so the winner is visible; the lower the priority the earlier the start.
            let candidates = sources.enumerated().map { index, source in
                Fixture.seg(.intro, 10 + Double(sources.count - index) * 5, 100, source: source,
                            reference: source == .onlineDatabase ? 1000 : nil)
            }
            let r = Fixture.resolve(candidates)
            XCTAssertEqual(r.segment(of: .intro)?.source, order[first])
            XCTAssertEqual(r.rejected.count, sources.count - 1)
        }
    }

    // SEG-6
    func testSEG6_invalidHigherPriorityCandidateDoesNotBlockLowerOne() {
        let badUser = Fixture.seg(.intro, 10, 15, source: .userMarked)               // 5 s intro: too short
        let goodOnline = Fixture.seg(.intro, 10, 60, source: .onlineDatabase, reference: 1000)
        let r = Fixture.resolve([badUser, goodOnline])
        XCTAssertEqual(r.segment(of: .intro)?.source, .onlineDatabase)
        XCTAssertEqual(r.rejected.first?.reason, .introLength)
    }

    // SEG-7 (table: length, accepted?)
    func testSEG7_introLengthTenToOneHundredEightySeconds() {
        let rows: [(TimeInterval, Bool)] = [(9.9, false), (10, true), (90, true), (180, true), (180.1, false)]
        for (length, ok) in rows {
            let r = Fixture.resolve([Fixture.seg(.intro, 30, 30 + length)])
            XCTAssertEqual(r.segments.count == 1, ok, "length \(length)")
            if !ok { XCTAssertEqual(r.rejected.first?.reason, .introLength) }
        }
    }

    // SEG-8 (table: start, length, accepted?)
    func testSEG8_recapStartsInFirstSixtySecondsAndIsAtMostOneEightySeconds() {
        let rows: [(TimeInterval, TimeInterval, SegmentRejection?)] = [
            (0, 60, nil), (60, 60, nil), (60.1, 60, .recapStartsTooLate), (120, 30, .recapStartsTooLate),
            (0, 180, nil), (0, 180.1, .recapTooLong),
        ]
        for (start, length, rejection) in rows {
            let r = Fixture.resolve([Fixture.seg(.recap, start, start + length)])
            XCTAssertEqual(r.segments.isEmpty, rejection != nil, "start \(start) length \(length)")
            XCTAssertEqual(r.rejected.first?.reason, rejection)
        }
    }

    // SEG-9
    func testSEG9_creditsMustStartInLastFortyPercent() {
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.credits, 600, 1000)]).segments.count, 1)
        let early = Fixture.resolve([Fixture.seg(.credits, 599.9, 1000)])
        XCTAssertTrue(early.segments.isEmpty)
        XCTAssertEqual(early.rejected.first?.reason, .creditsStartTooEarly)
    }

    // SEG-10
    func testSEG10_creditsRunToEndOrToPostCreditsChapter() {
        // Ends within 60 s of the file end: extended to the end.
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.credits, 900, 940)]).segment(of: .credits)?.end, 1000)
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.credits, 900, 940.0)]).segment(of: .credits)?.end, 1000)
        // More than 60 s remain: the supplied end is kept (real content follows).
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.credits, 800, 900)]).segment(of: .credits)?.end, 900)
        // A post-credits chapter ends the credits there, and Skip Credits goes to it.
        let withPost = Fixture.resolve([Fixture.seg(.credits, 900, 1000)], post: 960)
        XCTAssertEqual(withPost.segment(of: .credits)?.end, 960)
        XCTAssertEqual(withPost.postCreditsStart, 960)
        // A post-credits start outside the file is ignored.
        XCTAssertNil(Fixture.resolve([Fixture.seg(.credits, 900, 1000)], post: 1000).postCreditsStart)
        XCTAssertNil(Fixture.resolve([Fixture.seg(.credits, 900, 1000)], post: 0).postCreditsStart)
    }

    // SEG-11
    func testSEG11_outOfRangeTimesAreClampedAndInvertedSegmentsRejected() {
        let clampedStart = Fixture.resolve([Fixture.seg(.intro, -5, 30)]).segment(of: .intro)
        XCTAssertEqual(clampedStart?.start, 0)
        let clampedEnd = Fixture.resolve([Fixture.seg(.credits, 900, 1200)]).segment(of: .credits)
        XCTAssertEqual(clampedEnd?.end, 1000)
        let inverted = Fixture.resolve([Fixture.seg(.intro, 60, 60)])
        XCTAssertEqual(inverted.rejected.first?.reason, .emptyOrInverted)
        XCTAssertEqual(Fixture.resolve([Fixture.seg(.intro, 60, 20)]).rejected.first?.reason, .emptyOrInverted)
    }

    // SEG-12
    func testSEG12_sameSourceTieBreaksOnConfidenceThenEarlierStart() {
        let r1 = Fixture.resolve([Fixture.seg(.intro, 10, 60, confidence: 0.8), Fixture.seg(.intro, 20, 70, confidence: 0.95)])
        XCTAssertEqual(r1.segment(of: .intro)?.start, 20)
        let r2 = Fixture.resolve([Fixture.seg(.intro, 25, 80), Fixture.seg(.intro, 15, 70)])
        XCTAssertEqual(r2.segment(of: .intro)?.start, 15)
        XCTAssertEqual(r2.rejected.first?.reason, .outranked(by: .embeddedChapters))
    }

    // SEG-13: limits apply to user-marked segments too (documented interpretation)
    func testSEG13_userMarkedSegmentsStillObeySafetyLimits() {
        let r = Fixture.resolve([Fixture.seg(.credits, 100, 1000, source: .userMarked, confidence: 1)])
        XCTAssertTrue(r.segments.isEmpty)
        XCTAssertEqual(r.rejected.first?.reason, .creditsStartTooEarly)
    }

    // SEG-14: one segment per type, sorted by start
    func testSEG14_onePerTypeSortedByStart() {
        let r = Fixture.resolve([Fixture.seg(.credits, 900, 1000), Fixture.seg(.intro, 60, 120), Fixture.seg(.recap, 0, 40)])
        XCTAssertEqual(r.segments.map(\.type), [.recap, .intro, .credits])
    }
}
