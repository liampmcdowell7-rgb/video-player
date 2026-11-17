import XCTest
@testable import PlaybackLogic

/// Precedence, de-duplication and overlap resolution across segment sources. A 1000 s file (Fixture.file in SegmentTests.swift).
final class SegmentMergeTests: XCTestCase {
    private let file = Fixture.file

    private func seg(_ type: SegmentType, _ start: TimeInterval, _ end: TimeInterval, confidence: Double = 0.9) -> SkipSegment {
        Fixture.seg(type, start, end, confidence: confidence)
    }

    func testMG1_userMarkBeatsChaptersBeatsSidecar() {
        let inputs = SegmentSourceInputs(
            userMarked: [seg(.intro, 20, 80, confidence: 1.0)],
            localSidecar: [seg(.intro, 30, 90, confidence: 0.8), seg(.recap, 0, 20, confidence: 0.8)],
            embeddedChapters: [seg(.intro, 25, 85), seg(.recap, 0, 15)])
        let r = SegmentMerger.merge(file: file, inputs: inputs)
        XCTAssertEqual(r.segment(of: .intro)?.source, .userMarked)
        XCTAssertEqual(r.segment(of: .intro)?.start, 20)
        XCTAssertEqual(r.segment(of: .recap)?.source, .embeddedChapters, "chapters beat the sidecar for a type the user did not mark")
        XCTAssertEqual(r.segments.count, 2)
        XCTAssertEqual(r.rejected.filter { if case .outranked = $0.reason { return true } else { return false } }.count, 3)
    }

    func testMG2_aParserCannotClaimToBeAUserMark() {
        let sneaky = SkipSegment(type: .intro, start: 20, end: 80, source: .userMarked, confidence: 1.0, file: file)
        let r = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(localSidecar: [sneaky], embeddedChapters: [seg(.intro, 25, 85)]))
        XCTAssertEqual(r.segment(of: .intro)?.source, .embeddedChapters, "the list a candidate came from decides its source")
    }

    func testMG3_sourcesFillTheGapsOfEachOther() {
        let inputs = SegmentSourceInputs(
            userMarked: [seg(.credits, 800, 1000, confidence: 1.0)],
            localSidecar: [seg(.intro, 30, 90, confidence: 0.8)],
            embeddedChapters: [seg(.recap, 0, 20)])
        let r = SegmentMerger.merge(file: file, inputs: inputs)
        XCTAssertEqual(r.segments.map(\.type), [.recap, .intro, .credits], "sorted by start")
        XCTAssertEqual(r.segments.map(\.source), [.embeddedChapters, .localSidecar, .userMarked])
    }

    func testMG4_aRejectedHigherSourceNeverBlocksALowerOne() {
        // The user mark is an intro of 5 s (the limit is 10 to 180 s): refused, so the chapter intro is used.
        let inputs = SegmentSourceInputs(userMarked: [seg(.intro, 20, 25, confidence: 1.0)], embeddedChapters: [seg(.intro, 25, 85)])
        let r = SegmentMerger.merge(file: file, inputs: inputs)
        XCTAssertEqual(r.segment(of: .intro)?.source, .embeddedChapters)
        XCTAssertTrue(r.rejected.contains { $0.reason == .introLength && $0.segment.source == .userMarked })
    }

    func testMG5_overlapAcrossTypesDropsTheLowerRankedOne() {
        // A user intro 30...100 and a chapter recap 10...60 overlap by 30 s: the recap loses.
        let inputs = SegmentSourceInputs(userMarked: [seg(.intro, 30, 100, confidence: 1.0)], embeddedChapters: [seg(.recap, 10, 60)])
        let r = SegmentMerger.merge(file: file, inputs: inputs)
        XCTAssertEqual(r.segments.map(\.type), [.intro])
        XCTAssertTrue(r.rejected.contains { $0.reason == .overlapsHigherRanked(.intro) && $0.segment.type == .recap })
    }

    func testMG6_touchingOrNearlyTouchingSegmentsAreNotOverlaps() {
        let touching = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(embeddedChapters: [seg(.recap, 0, 40), seg(.intro, 40, 100)]))
        XCTAssertEqual(touching.segments.count, 2)
        let rounding = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(embeddedChapters: [seg(.recap, 0, 40.8), seg(.intro, 40, 100)]))
        XCTAssertEqual(rounding.segments.count, 2, "0.8 s of overlap is inside the 1 s tolerance")
        let real = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(embeddedChapters: [seg(.recap, 0, 42), seg(.intro, 40, 100)]))
        XCTAssertEqual(real.segments.count, 1, "2 s of overlap is a real overlap")
    }

    func testMG7_sameRankOverlapKeepsTheMoreConfidentThenTheEarlier() {
        let a = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(embeddedChapters: [seg(.recap, 10, 50, confidence: 0.8), seg(.intro, 30, 100, confidence: 0.95)]))
        XCTAssertEqual(a.segments.map(\.type), [.intro], "higher confidence wins at equal source priority")
        let b = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(embeddedChapters: [seg(.recap, 10, 50), seg(.intro, 30, 100)]))
        XCTAssertEqual(b.segments.map(\.type), [.recap], "equal confidence: the earlier start wins")
    }

    func testMG8_creditsEndAtThePostCreditsChapterAndLimitsStillApply() {
        let inputs = SegmentSourceInputs(embeddedChapters: [seg(.credits, 900, 1000)], postCreditsStart: 970)
        let r = SegmentMerger.merge(file: file, inputs: inputs)
        XCTAssertEqual(r.segment(of: .credits)?.end, 970)
        XCTAssertEqual(r.postCreditsStart, 970)
        // Credits that start too early are refused, also for a user mark (SEG-13).
        let early = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(userMarked: [seg(.credits, 300, 1000, confidence: 1.0)]))
        XCTAssertTrue(early.segments.isEmpty)
        XCTAssertEqual(early.rejected.first?.reason, .creditsStartTooEarly)
    }

    func testMG9_aSegmentOfAnotherFileIsDroppedAndNothingBreaksWithNoInput() {
        let other = FileIdentity(path: "/other.mkv", size: 1, duration: 1000)
        let r = SegmentMerger.merge(file: file, inputs: SegmentSourceInputs(embeddedChapters: [Fixture.seg(.intro, 20, 80, file: other)]))
        XCTAssertTrue(r.segments.isEmpty)
        XCTAssertEqual(r.rejected.first?.reason, .differentFile)
        XCTAssertTrue(SegmentMerger.merge(file: file, inputs: SegmentSourceInputs()).segments.isEmpty)
    }

    func testMG10_laterSourcesAreAcceptedAlreadyAndRankLowest() {
        let inputs = SegmentSourceInputs(embeddedChapters: [seg(.intro, 25, 85)],
                                         onlineDatabase: [SkipSegment(type: .intro, start: 30, end: 90, source: .onlineDatabase, confidence: 0.9, file: file, referenceDuration: 1000)],
                                         onDeviceDetection: [seg(.recap, 0, 20, confidence: 0.75)])
        let r = SegmentMerger.merge(file: file, inputs: inputs)
        XCTAssertEqual(r.segment(of: .intro)?.source, .embeddedChapters)
        XCTAssertEqual(r.segment(of: .recap)?.source, .onDeviceDetection)
    }

    func testMG11_mergedSegmentsWrapWithoutRevalidation() {
        // Credits that end at a post-credits chapter 30 s before the end: validating again would stretch them to the end (the 60 s rule).
        let credits = Fixture.seg(.credits, 900, 970, source: .embeddedChapters, confidence: 0.9)
        let wrapped = ResolvedSegments(merged: [credits])
        XCTAssertEqual(wrapped.segment(of: .credits)?.end, 970)
        let again = SegmentResolver.resolve(file: file, candidates: [credits])
        XCTAssertEqual(again.segment(of: .credits)?.end, 1000, "this is why the wrapper exists")
    }

    func testMG12_theSegmentNameIsTheSkipSegmentModel() {
        let s: Segment = seg(.intro, 10, 60)
        XCTAssertEqual(s.type, .intro)
    }
}
