import XCTest
@testable import AppLogic

/// R390: the checkpoints tell "never ready" from "ready, no frame" from "a frame, then stopped".
final class PlaybackCheckpointsTests: XCTestCase {
    final class Clock: @unchecked Sendable {
        var now: Double = 100
    }

    func testNothingReachedBeforeTheItemExistsHasNoVerdict() {
        let marks = PlaybackCheckpoints(path: .direct)
        XCTAssertNil(marks.verdict, "a failure before the player got the file is told by its step")
        XCTAssertTrue(marks.shown.allSatisfy { !$0.isReached })
        XCTAssertEqual(marks.shown.first?.value, "Not reached")
    }

    func testTheThreeBlackScreensAreToldApart() {
        var marks = PlaybackCheckpoints(path: .converted)
        marks.reach(.fileOpened, at: 1)
        marks.reach(.loopbackReady, at: 1.5)
        marks.reach(.itemCreated, at: 2)
        XCTAssertEqual(marks.verdict, .neverReady)
        marks.reach(.itemReady, at: 4)
        XCTAssertEqual(marks.verdict, .readyNoFrame)
        marks.reach(.firstFrame, at: 5)
        XCTAssertEqual(marks.verdict, .frameThenStopped)
        marks.reach(.playheadMoved5, at: 10)
        XCTAssertEqual(marks.verdict, .frameThenStopped, "5 s is not yet established playback")
        marks.reach(.playheadMoved30, at: 35)
        XCTAssertEqual(marks.verdict, .playing)
        XCTAssertNotEqual(PlaybackStartVerdict.neverReady.text, PlaybackStartVerdict.readyNoFrame.text)
        XCTAssertNotEqual(PlaybackStartVerdict.readyNoFrame.text, PlaybackStartVerdict.frameThenStopped.text)
    }

    func testTheFirstTimeCountsAndAMissingDetailIsAdded() {
        var marks = PlaybackCheckpoints(path: .direct)
        marks.reach(.videoTrackFound, at: 3)
        marks.reach(.videoTrackFound, at: 9, detail: "HEVC (hvc1), 3840 × 2160")
        XCTAssertEqual(marks.entry(.videoTrackFound)?.seconds, 3)
        XCTAssertEqual(marks.entry(.videoTrackFound)?.value, "Reached at 3.0 s · HEVC (hvc1), 3840 × 2160")
        marks.reach(.videoTrackFound, at: 12, detail: "other")
        XCTAssertEqual(marks.entry(.videoTrackFound)?.detail, "HEVC (hvc1), 3840 × 2160")
    }

    func testTheLoopbackRowOnlyInConvertedPlayback() {
        XCTAssertFalse(PlaybackCheckpoints(path: .direct).shown.contains { $0.kind == .loopbackReady })
        XCTAssertTrue(PlaybackCheckpoints(path: .converted).shown.contains { $0.kind == .loopbackReady })
    }

    func testRowsAndScreenLines() {
        var marks = PlaybackCheckpoints(path: .converted)
        marks.reach(.itemCreated, at: 2)
        marks.describe(.videoTrackFound, detail: "No video track in the item")
        marks.note("video segment 0: asked at 3.0 s, no answer yet")
        let rows = Dictionary(uniqueKeysWithValues: marks.rows.map { ($0.label, $0.value) })
        XCTAssertEqual(rows["Path"], "Converted")
        XCTAssertEqual(rows["Start Result"], PlaybackStartVerdict.neverReady.text)
        XCTAssertEqual(rows["Item Created"], "Reached at 2.0 s")
        XCTAssertEqual(rows["Video Track Found"], "Not reached · No video track in the item")
        XCTAssertEqual(marks.screenLines.first, "Result: " + PlaybackStartVerdict.neverReady.text)
        XCTAssertTrue(marks.screenLines.contains("Note: video segment 0: asked at 3.0 s, no answer yet"))
    }

    func testNotesAreKeptOnceAndCapped() {
        var marks = PlaybackCheckpoints()
        marks.note("a")
        marks.note("a")
        XCTAssertEqual(marks.notes, ["a"])
        for i in 0..<30 { marks.note("n\(i)") }
        XCTAssertEqual(marks.notes.count, PlaybackCheckpoints.noteCapacity)
        XCTAssertEqual(marks.notes.last, "n29")
    }

    func testVideoTrackTextSaysWhenTheTrackCannotBeShown() {
        XCTAssertEqual(PlaybackCheckpoints.videoTrackText(codec: "HEVC (hvc1)", width: 1920, height: 1080, decodable: true, playable: true),
                       "HEVC (hvc1), 1920 × 1080")
        let bad = PlaybackCheckpoints.videoTrackText(codec: "Codec dvh1", width: 3840, height: 2160, decodable: false, playable: false)
        XCTAssertTrue(bad.contains("cannot decode"))
        XCTAssertTrue(bad.contains("cannot play"))
        XCTAssertEqual(PlaybackCheckpoints.videoTrackText(codec: nil, width: nil, height: nil, decodable: nil, playable: nil),
                       "No details reported")
    }

    func testFourCC() {
        XCTAssertEqual(PlaybackCheckpoints.fourCC(0x6876_6331), "hvc1")
        XCTAssertEqual(PlaybackCheckpoints.fourCC(0x0000_0001), "????")
        XCTAssertEqual(PlaybackCheckpoints.codecName(fourCC: "hvc1"), "HEVC (hvc1)")
        XCTAssertEqual(PlaybackCheckpoints.codecName(fourCC: "dvh1"), "Dolby Vision HEVC (dvh1)")
        XCTAssertEqual(PlaybackCheckpoints.codecName(fourCC: "xyz1"), "Codec xyz1")
    }

    func testSecondsText() {
        XCTAssertEqual(PlaybackCheckpoints.secondsText(2.44), "2.4 s")
        XCTAssertEqual(PlaybackCheckpoints.secondsText(31.6), "32 s")
    }

    // MARK: Through the tracker and the stored problem

    func testTheTrackerTimesCheckpointsFromTheStartAndTheProblemKeepsThemRedacted() throws {
        let clock = Clock()
        let tracker = PlaybackStartTracker(clock: { [clock] in clock.now })
        tracker.describe(secrets: ["SECRETTOKEN9"])
        tracker.setPath(.direct)
        clock.now = 101.5
        tracker.reach(.fileOpened, detail: "link https://h.invalid/a?X-Plex-Token=SECRETTOKEN9")
        clock.now = 102
        tracker.reach(.itemCreated)
        tracker.note("asked for SECRETTOKEN9")
        tracker.enter(.playerReady)
        clock.now = 132
        let problem = tracker.problem(PlaybackFailures.startTimedOut(.playerReady, seconds: 30))
        let marks = try XCTUnwrap(problem.checkpoints)
        XCTAssertEqual(marks.entry(.fileOpened)?.seconds, 1.5)
        XCTAssertEqual(marks.entry(.itemCreated)?.seconds, 2)
        XCTAssertFalse(marks.entry(.fileOpened)!.detail!.contains("SECRETTOKEN9"))
        XCTAssertFalse(marks.notes[0].contains("SECRETTOKEN9"))
        XCTAssertEqual(marks.verdict, .neverReady)
        let lines = problem.screenLines()
        XCTAssertTrue(lines.contains("Step: " + PlaybackStep.playerReady.title))
        XCTAssertTrue(lines.contains("Result: " + PlaybackStartVerdict.neverReady.text))
        XCTAssertTrue(lines.contains("Item Is Ready to Play: Not reached"))
        XCTAssertTrue(problem.fullText().contains("Notes:"))
        XCTAssertEqual(problem.rows.last?.label, "Error")
        let decoded = try XCTUnwrap(PlaybackProblem.decoded(problem.encoded()))
        XCTAssertEqual(decoded.checkpoints, marks)
    }

    func testAProblemStoredBeforeR390StillDecodesWithoutCheckpoints() throws {
        let old = #"{"step":"playerReady","sourceKind":"Plex","container":"MKV","error":"x","at":0}"#
        let problem = try XCTUnwrap(PlaybackProblem.decoded(Data(old.utf8)))
        XCTAssertNil(problem.checkpoints)
        XCTAssertFalse(problem.rows.contains { $0.label == "Item Is Ready to Play" })
    }
}
