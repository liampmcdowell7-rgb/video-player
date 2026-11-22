import XCTest
import Foundation
@testable import AppLogic

/// R311: the start of a playback that hangs or fails ends with a plain message naming the step, and the last problem is
/// kept with every token removed (the device test of build 5: a black player for about 30 seconds, then no message).
final class PlaybackStartLogTests: XCTestCase {
    /// A clock the test moves by hand.
    final class FakeClock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Double = 1000
        var now: Double { lock.withLock { value } }
        func advance(_ s: Double) { lock.withLock { value += s } }
    }

    // MARK: Steps and limits

    func testEveryStepHasItsOwnTitle() {
        let titles = PlaybackStep.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
    }

    func testResolutionStepsComeBeforeThePlayerSteps() {
        XCTAssertTrue(PlaybackStep.getLink.isResolution)
        XCTAssertTrue(PlaybackStep.checkServer.isResolution)
        XCTAssertFalse(PlaybackStep.playerReady.isResolution)
        XCTAssertFalse(PlaybackStep.resumeSeek.isResolution)
    }

    func testEveryStepButPlayingHasALimit() {
        for step in PlaybackStep.allCases where step != .playing {
            XCTAssertNotNil(PlaybackStartDeadline.limit(for: step), "\(step)")
        }
        XCTAssertNil(PlaybackStartDeadline.limit(for: .playing))
        XCTAssertFalse(PlaybackStartDeadline.isOverdue(.playing, since: 0, now: 100_000))
    }

    func testOverdueAtTheLimitNotBefore() {
        let limit = PlaybackStartDeadline.readySeconds
        XCTAssertFalse(PlaybackStartDeadline.isOverdue(.playerReady, since: 10, now: 10 + limit - 0.1))
        XCTAssertTrue(PlaybackStartDeadline.isOverdue(.playerReady, since: 10, now: 10 + limit))
    }

    func testTimeoutFailureNamesTheStepAndOffersTryAgain() {
        let failure = PlaybackFailures.startTimedOut(.resumeSeek, seconds: 20)
        XCTAssertTrue(failure.message.contains("20 seconds"))
        XCTAssertTrue(failure.message.contains("moving to the saved position"))
        XCTAssertTrue(failure.canTryAgain)
        XCTAssertFalse(failure.isSilentByDesign)
        XCTAssertTrue(failure.advice.contains("Settings > Playback"))
    }

    // MARK: Every failure is shown

    func testEveryFailureIsShownWhileTheScreenIsUp() {
        for failure in [PlaybackFailures.cancelled, PlaybackFailures.noFile, PlaybackFailures.startTimedOut(.getLink, seconds: 60),
                        PlaybackFailures.playerFailure(.network)] {
            XCTAssertTrue(PlaybackFailurePolicy.shows(failure, screenClosed: false), failure.message)
            XCTAssertFalse(PlaybackFailurePolicy.shows(failure, screenClosed: true), failure.message)
        }
    }

    // MARK: Tracker and problem

    func testTrackerFollowsTheStepsAndItsDeadline() {
        let clock = FakeClock()
        let tracker = PlaybackStartTracker(clock: { clock.now })
        XCTAssertEqual(tracker.step.step, .findFile)
        tracker.enter(.getLink)
        XCTAssertEqual(tracker.step.step, .getLink)
        clock.advance(PlaybackStartDeadline.resolutionSeconds - 1)
        XCTAssertFalse(tracker.isOverdue)
        clock.advance(1)
        XCTAssertTrue(tracker.isOverdue)
        tracker.enter(.playerReady)
        XCTAssertFalse(tracker.isOverdue, "a new step starts its own clock")
    }

    func testProblemHoldsStepSourceContainerCodecsAndTheRedactedError() {
        let tracker = PlaybackStartTracker()
        tracker.describe(sourceKind: "Plex", container: "MKV", codecs: "HEVC, E-AC-3", secrets: ["abcd1234token"])
        tracker.enter(.playerReady)
        let failure = PlaybackFailures.playerFailure(.network)
        let problem = tracker.problem(failure, detail: "GET https://10-0-0-2.example.invalid:32400/library/parts/1/file.mkv?X-Plex-Token=abcd1234token failed",
                                      at: Date(timeIntervalSince1970: 5))
        XCTAssertEqual(problem.step, .playerReady)
        XCTAssertEqual(problem.sourceKind, "Plex")
        XCTAssertEqual(problem.container, "MKV")
        XCTAssertEqual(problem.codecs, "HEVC, E-AC-3")
        XCTAssertTrue(problem.error.hasPrefix(failure.message))
        XCTAssertFalse(problem.error.contains("abcd1234token"))
        XCTAssertTrue(problem.error.contains(PlaybackRedaction.placeholder))
        // R386: the player's error code, its underlying errors and the last event joined the rows; the error text stays last.
        XCTAssertEqual(problem.rows.map(\.label), ["Step", "Source", "Container", "Codecs", "Error Code", "Underlying Error",
                                                   "Last Event", "Error"])
    }

    func testDescribeKeepsWhatWasKnownAndUnknownSaysSo() {
        let tracker = PlaybackStartTracker()
        tracker.describe(sourceKind: "SMB", container: "MP4")
        tracker.describe(codecs: "")
        tracker.describe(sourceKind: nil, codecs: "H.264")
        let problem = tracker.problem(PlaybackFailures.noFile)
        XCTAssertEqual(problem.sourceKind, "SMB")
        XCTAssertEqual(problem.codecs, "H.264")
        let empty = PlaybackStartTracker().problem(PlaybackFailures.noFile)
        XCTAssertEqual(empty.rows[1].value, PlaybackProblem.notKnown)
        XCTAssertEqual(empty.rows[0].value, PlaybackStep.findFile.title)
    }

    func testDetailIsNotRepeatedWhenTheMessageHoldsIt() {
        let failure = PlaybackFailure(kind: .other, message: "The file could not be opened.", advice: "")
        XCTAssertEqual(PlaybackStartTracker().problem(failure, detail: "could not be opened").error, "The file could not be opened.")
        XCTAssertEqual(PlaybackStartTracker().problem(failure, detail: nil).error, "The file could not be opened.")
    }

    func testProblemRoundTripsThroughItsStoredForm() {
        let problem = PlaybackProblem(step: .resumeSeek, sourceKind: "Plex", container: "MKV", codecs: nil, error: "x",
                                      at: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(PlaybackProblem.decoded(problem.encoded()), problem)
        XCTAssertNil(PlaybackProblem.decoded(nil))
        XCTAssertNil(PlaybackProblem.decoded(Data("not json".utf8)))
    }

    func testCodecAndContainerNames() {
        XCTAssertEqual(PlaybackStartTracker.codecText(["hvc1", nil, " ", "ec-3", "hvc1"]), "hvc1, ec-3")
        XCTAssertNil(PlaybackStartTracker.codecText([nil, ""]))
        XCTAssertEqual(PlaybackStartTracker.containerName(fileName: "Show S01E01.mkv"), "MKV")
        XCTAssertNil(PlaybackStartTracker.containerName(fileName: "README"))
    }

    // MARK: Redaction

    func testRedactionRemovesTokensPasswordsAndAuthorization() {
        let text = """
        https://h.example.invalid/a?X-Plex-Token=SECRETVALUE1&x=1 token=SECRETVALUE2 \
        Authorization: Bearer SECRETVALUE3 "X-Plex-Token": "SECRETVALUE4" smb://user:SECRETVALUE5@nas.invalid/share \
        api_key=SECRETVALUE6 known-secret-7
        """
        let out = PlaybackRedaction.redact(text, secrets: ["known-secret-7", "ab"])
        for n in 1...6 { XCTAssertFalse(out.contains("SECRETVALUE\(n)"), "\(n): \(out)") }
        XCTAssertFalse(out.contains("known-secret-7"))
        XCTAssertTrue(out.contains("x=1"), "other query items stay")
        XCTAssertTrue(out.contains("nas.invalid/share"))
    }

    func testRedactionLeavesPlainTextAlone() {
        let text = "The server could not be reached. (The request timed out.)"
        XCTAssertEqual(PlaybackRedaction.redact(text), text)
    }

    // MARK: The watch over the resolution

    func testWatchReturnsTheValueWhenTheWorkFinishes() async {
        let tracker = PlaybackStartTracker()
        let outcome = await PlaybackStartWatch.run(tracker: tracker, sleep: { _ in try? await Task.sleep(nanoseconds: 50_000_000) }) { 42 }
        guard case .finished(let value) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(value, 42)
    }

    func testWatchReturnsTheErrorWhenTheWorkThrows() async {
        struct Boom: Error {}
        let outcome = await PlaybackStartWatch.run(tracker: PlaybackStartTracker(), sleep: { _ in try? await Task.sleep(nanoseconds: 50_000_000) }) { () async throws -> Int in
            throw Boom()
        }
        guard case .failed(let error) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(error is Boom)
    }

    /// The device test's case: a step that never finishes. The watch reports the step and its limit instead of waiting.
    func testWatchReportsTheStepThatHangs() async {
        let clock = FakeClock()
        let tracker = PlaybackStartTracker(clock: { clock.now })
        let ticks = Counter()
        let outcome = await PlaybackStartWatch.run(
            tracker: tracker,
            sleep: { s in clock.advance(s); await Task.yield() },
            onTick: { _ in ticks.add() }
        ) { () async throws -> Int in
            tracker.enter(.checkServer)
            // Does not answer until it is cancelled (the watch cancels it when the limit passes).
            while !Task.isCancelled { await Task.yield() }
            return 0
        }
        guard case .overdue(let step, let seconds) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(step, .checkServer)
        XCTAssertEqual(seconds, PlaybackStartDeadline.resolutionSeconds)
        XCTAssertGreaterThan(ticks.value, 0)
    }

    func testAValueThatArrivesAfterTheLimitGoesToOnLate() async {
        let clock = FakeClock()
        let tracker = PlaybackStartTracker(clock: { clock.now })
        let late = Counter()
        let gate = Gate()
        let outcome = await PlaybackStartWatch.run(
            tracker: tracker,
            sleep: { s in clock.advance(s); await Task.yield() },
            onLate: { _ in late.add(); gate.open() }
        ) { () async throws -> Int in
            tracker.enter(.getLink)
            // Finishes only after the watch gave up on it (a late value: the caller must close what it opened).
            while !Task.isCancelled { await Task.yield() }
            return 7
        }
        guard case .overdue(.getLink, _) = outcome else { return XCTFail("\(outcome)") }
        await gate.wait()
        XCTAssertEqual(late.value, 1)
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var value: Int { lock.withLock { n } }
        func add() { lock.withLock { n += 1 } }
    }

    /// Opens once; `wait` returns when it is open (polls, so it cannot miss the opening).
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        func open() { lock.withLock { isOpen = true } }
        func wait() async {
            for _ in 0..<500 where !lock.withLock({ isOpen }) { try? await Task.sleep(nanoseconds: 10_000_000) }
        }
    }
}
