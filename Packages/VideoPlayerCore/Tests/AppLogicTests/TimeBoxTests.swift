import XCTest
@testable import AppLogic

// Launch time-box (OPEN_QUESTIONS R169): the launch never waits longer than the box for iCloud, and the iCloud work is not
// stopped when the box runs out.

private actor Flag {
    var done = false
    func set() { done = true }
}

final class TimeBoxTests: XCTestCase {
    func testWorkThatFinishesInTimeGivesItsResult() async {
        // R471 (109): the injected box is the full 60 s it names (was 5 s): under the whole suite's load the trivial work was
        // once not scheduled within 5 s (26 Nov 2026, a nil). A normal run is not slower: the timer is cancelled, and its
        // sleep ends, as soon as the work gives its result.
        let result = await TimeBox.wait(atMost: 60, sleep: { _ in try? await Task.sleep(nanoseconds: 60_000_000_000) }) { 42 }
        XCTAssertEqual(result, 42)
    }

    func testSlowWorkGivesNilAtOnceAndStillFinishesInTheBackground() async throws {
        let flag = Flag()
        let gate = AsyncStream<Void>.makeStream()
        let started = Date()
        // The "iCloud" work waits until the test lets it go; the box ends immediately (injected sleep).
        let result: Int? = await TimeBox.wait(atMost: 8, sleep: { _ in }) {
            for await _ in gate.stream { break }
            await flag.set()
            return 1
        }
        XCTAssertNil(result, "the box ran out first")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "the caller did not wait for the work")
        let early = await flag.done
        XCTAssertFalse(early)
        gate.continuation.yield()
        var tries = 0
        while !(await flag.done), tries < 200 { tries += 1; try await Task.sleep(nanoseconds: 10_000_000) }
        let finished = await flag.done
        XCTAssertTrue(finished, "the work was not cancelled and finished after the box ran out")
    }

    func testTheLaunchWaitIsShort() {
        XCTAssertLessThanOrEqual(TimeBox.launchWait, 10)
    }
}
