import XCTest
import VideoPlayerCore
import PlaybackLogic
import UserData
@testable import AppLogic

/// The "Mark Intro / Recap / Credits" flow over a real ledger. A 1500 s title: credits must start at 900 s or later.
final class SegmentMarkFlowTests: XCTestCase {
    private let key = "show-s01e01"
    private let duration: TimeInterval = 1500

    private func ledger() -> UserDataLedger { UserDataLedger(deviceID: "T", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }
    private func date(_ n: Double) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + n) }

    private func session(_ l: UserDataLedger) -> SegmentMarkSession { SegmentMarkSession(itemKey: key, ledger: l) }

    // MARK: Start, end, save

    func testMK1_firstPressRemembersTheStartSecondPressSavesWithFullConfidence() async throws {
        let l = ledger()
        let s = session(l)
        XCTAssertEqual(s.press(.intro, at: 62, duration: duration, date: date(1)), .startMarked(.intro, at: 62))
        XCTAssertEqual(s.state.pending, MarkMenuState.PendingMark(kind: .intro, start: 62))
        XCTAssertTrue(l.segmentMarks(forItemKey: key).isEmpty, "nothing is stored before the end is marked")
        XCTAssertEqual(s.press(.intro, at: 150.4, duration: duration, date: date(2)), .saved(.intro, MarkedRange(start: 62, end: 150.4)))
        XCTAssertNil(s.state.pending)
        XCTAssertEqual(s.state.marks[.intro], MarkedRange(start: 62, end: 150.4))
        // The stored mark becomes a user-marked segment with confidence 1.0 when the file is collected.
        let collected = await SegmentCollector().collect(file: SegmentFileInfo(path: "/a.mkv", size: 1, duration: duration), source: nil, marks: l.segmentMarks(forItemKey: key))
        let seg = try XCTUnwrap(collected.resolved.segment(of: .intro))
        XCTAssertEqual(seg.source, .userMarked)
        XCTAssertEqual(seg.confidence, 1.0)
        XCTAssertEqual(seg.start, 62)
    }

    func testMK2_aMarkSurvivesANewSessionAndAFileRoundTripOfTheLedger() throws {
        let l = ledger()
        session(l).press(.recap, at: 5, duration: duration, date: date(1))
        session(l).press(.recap, at: 5, duration: duration, date: date(1))   // a second session has no pending start: this is a new start
        XCTAssertTrue(l.segmentMarks(forItemKey: key).isEmpty)
        let first = session(l)
        first.press(.recap, at: 5, duration: duration, date: date(1))
        first.press(.recap, at: 45, duration: duration, date: date(2))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("marks-\(UUID().uuidString).json")
        try l.save(to: url)
        let restored = UserDataLedger(deviceID: "T2")
        XCTAssertEqual(restored.load(from: url), .loaded(records: 1))
        XCTAssertEqual(session(restored).state.marks[.recap], MarkedRange(start: 5, end: 45), "restored marks show in the menu state of a new playback")
    }

    func testMK3_anEndAtOrBeforeTheStartKeepsTheStart() {
        let s = session(ledger())
        s.press(.intro, at: 100, duration: duration)
        XCTAssertEqual(s.press(.intro, at: 100.2, duration: duration), .endNotAfterStart(.intro, start: 100))
        XCTAssertEqual(s.press(.intro, at: 90, duration: duration), .endNotAfterStart(.intro, start: 100))
        XCTAssertEqual(s.state.pending?.start, 100)
        XCTAssertEqual(s.press(.intro, at: 160, duration: duration, date: date(1)), .saved(.intro, MarkedRange(start: 100, end: 160)))
    }

    func testMK4_theLimitsRefuseAndSayWhyAndTheStartStays() {
        let l = ledger()
        let s = session(l)
        s.press(.intro, at: 100, duration: duration)
        let tooShort = s.press(.intro, at: 105, duration: duration)
        guard case .refused(.intro, let reason) = tooShort else { return XCTFail("\(tooShort)") }
        XCTAssertEqual(reason, "An intro has to be between 10 seconds and 3 minutes long.")
        XCTAssertEqual(s.state.pending?.start, 100, "a better end can be marked without starting over")
        XCTAssertTrue(l.segmentMarks(forItemKey: key).isEmpty)
        // Credits that start in the first 60 percent.
        s.press(.credits, at: 300, duration: duration)
        let early = s.press(.credits, at: 1500, duration: duration)
        XCTAssertEqual(early, .refused(.credits, reason: "Credits have to start in the last 40 percent of the title."))
        // A recap that starts after the first minute.
        s.press(.recap, at: 100, duration: duration)
        XCTAssertEqual(s.press(.recap, at: 150, duration: duration), .refused(.recap, reason: "A recap has to start within the first 60 seconds."))
        XCTAssertTrue(l.segmentMarks(forItemKey: key).isEmpty)
    }

    func testMK5_withoutALengthTheRangeCannotBeCheckedSoItIsNotSaved() {
        let l = ledger()
        let s = session(l)
        s.press(.intro, at: 10, duration: nil)
        guard case .refused = s.press(.intro, at: 80, duration: nil) else { return XCTFail("expected a refusal") }
        XCTAssertTrue(l.segmentMarks(forItemKey: key).isEmpty)
        XCTAssertEqual(s.press(.intro, at: 80, duration: 1500, date: date(1)), .saved(.intro, MarkedRange(start: 10, end: 80)), "the start was kept")
    }

    func testMK6_anEndPastTheEndOfTheFileIsClampedToIt() {
        let s = session(ledger())
        s.press(.credits, at: 1400, duration: duration)
        XCTAssertEqual(s.press(.credits, at: 1530, duration: duration, date: date(1)), .saved(.credits, MarkedRange(start: 1400, end: 1500)))
    }

    func testMK7_noPlayheadMeansNothingHappens() {
        let s = session(ledger())
        XCTAssertEqual(s.press(.intro, at: nil, duration: duration), .noPlayhead)
        XCTAssertEqual(s.press(.intro, at: -4, duration: duration), .noPlayhead)
        XCTAssertEqual(s.press(.intro, at: .infinity, duration: duration), .noPlayhead)
        XCTAssertNil(s.state.pending)
    }

    // MARK: Pending

    func testMK8_aDifferentKindReplacesThePendingStartAndCancelClearsIt() {
        let s = session(ledger())
        s.press(.intro, at: 30, duration: duration)
        XCTAssertEqual(s.press(.recap, at: 3, duration: duration), .startMarked(.recap, at: 3))
        XCTAssertEqual(s.state.pending, MarkMenuState.PendingMark(kind: .recap, start: 3))
        XCTAssertEqual(s.cancelPending(), .pendingCancelled(.recap))
        XCTAssertEqual(s.cancelPending(), .noPendingMark)
        XCTAssertNil(s.state.pending)
    }

    // MARK: Delete and undo

    func testMK9_deleteRemovesTheMarkAndUndoBringsItBack() {
        let l = ledger()
        let s = session(l)
        s.press(.intro, at: 30, duration: duration, date: date(1))
        s.press(.intro, at: 100, duration: duration, date: date(2))
        XCTAssertEqual(s.delete(.intro, date: date(3)), .deleted(.intro))
        XCTAssertNil(s.state.marks[.intro])
        XCTAssertEqual(s.delete(.intro, date: date(4)), .nothingToDelete(.intro))
        XCTAssertEqual(s.undo(date: date(5)), .undone(.intro, restored: MarkedRange(start: 30, end: 100)))
        XCTAssertEqual(s.state.marks[.intro], MarkedRange(start: 30, end: 100))
        XCTAssertEqual(l.segmentMarks(forItemKey: key).first?.fileDuration, duration, "the length the mark was made on comes back too")
    }

    func testMK10_undoOfASaveRestoresTheEarlierMarkOrRemovesTheFirstOne() {
        let l = ledger()
        let s = session(l)
        s.press(.intro, at: 30, duration: duration, date: date(1))
        s.press(.intro, at: 100, duration: duration, date: date(2))          // first mark 30...100
        s.press(.intro, at: 40, duration: duration, date: date(3))
        s.press(.intro, at: 130, duration: duration, date: date(4))          // replaces it: 40...130
        XCTAssertEqual(s.state.marks[.intro], MarkedRange(start: 40, end: 130))
        XCTAssertEqual(s.undo(date: date(5)), .undone(.intro, restored: MarkedRange(start: 30, end: 100)))
        XCTAssertEqual(s.undo(date: date(6)), .undone(.intro, restored: nil), "undoing the first save removes the mark")
        XCTAssertNil(s.state.marks[.intro])
        XCTAssertEqual(s.undo(date: date(7)), .nothingToUndo)
        XCTAssertFalse(s.state.canUndo)
    }

    func testMK11_undoWinsOverTheChangeItRevertsOnAnotherDevice() {
        let zero = date(0)
        let a = UserDataLedger(deviceID: "A", clock: { zero }), b = UserDataLedger(deviceID: "B", clock: { zero })
        let s = session(a)
        s.press(.intro, at: 30, duration: duration, date: date(1))
        s.press(.intro, at: 100, duration: duration, date: date(2))
        s.delete(.intro, date: date(3))
        s.undo(date: date(4))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertEqual(session(b).state.marks[.intro], MarkedRange(start: 30, end: 100))
    }

    func testMK12_aDeleteSyncsAsADeletionNotAsAMissingRecord() {
        let a = ledger(), b = ledger()
        let s = session(a)
        s.press(.credits, at: 1000, duration: duration, date: date(1))
        s.press(.credits, at: 1500, duration: duration, date: date(2))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertEqual(session(b).state.marks[.credits], MarkedRange(start: 1000, end: 1500))
        s.delete(.credits, date: date(3))
        for r in a.allRecords() { b.apply(r) }
        XCTAssertNil(session(b).state.marks[.credits])
    }

    // MARK: Text

    func testMK13_theMessagesSayExactlyWhatHappened() {
        XCTAssertEqual(MarkOutcome.startMarked(.intro, at: 65).message, "Intro start marked at 1:05. Choose Mark Intro again where it ends.")
        XCTAssertEqual(MarkOutcome.saved(.credits, MarkedRange(start: 3725, end: 3900)).message, "Credits saved: 1:02:05 to 1:05:00.")
        XCTAssertEqual(MarkOutcome.deleted(.recap).message, "Recap mark deleted.")
        XCTAssertEqual(MarkOutcome.undone(.recap, restored: nil).message, "Recap mark removed.")
        XCTAssertEqual(MarkOutcome.nothingToUndo.message, "Nothing to undo.")
        XCTAssertTrue(MarkOutcome.saved(.intro, MarkedRange(start: 1, end: 2)).changedMarks)
        XCTAssertFalse(MarkOutcome.startMarked(.intro, at: 1).changedMarks)
        XCTAssertEqual(MarkMenuState(pending: .init(kind: .intro, start: 5)).title(for: .intro), "Mark Intro End")
        XCTAssertEqual(MarkMenuState(pending: .init(kind: .intro, start: 5)).title(for: .recap), "Mark Recap Start")
    }
}
