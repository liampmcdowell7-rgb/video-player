import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R471 (58), PROVISIONAL (owner 25 Nov 2026 round 6, Part B item 1): second finding of the review of R471 (55).
final class ReadAheadLateFailureR471Tests: XCTestCase {
    typealias Reader = PlexConvertedPathR471Tests.AfterOpenReader

    private func status(_ session: MatroskaRemuxSession, _ name: String) async -> Int {
        do { return try await session.resource(path: name).status } catch { return 500 }
    }

    /// R471 (58): a cancelled read-ahead load that gives up late must not throw away the newer load of the same segment.
    /// Read-ahead of segment 2 is cancelled by a seek; segment 2 is then asked for and loaded again; the cancelled load
    /// ends after that and removed the NEW window from the cache (and told the planner segment 2 failed), so asking for
    /// segment 2 once more read it a third time.
    func testALateFailureOfACancelledLoadKeepsTheNewerWindow() async throws {
        let data = PlexConvertedPathR471Tests.shape(seconds: 24).build().data
        let reader = Reader(data, mode: .slow(seconds: 0.3, onCancel: CancellationError(), cancelDelay: 0.5))
        let session = MatroskaRemuxSession(reader: reader, options: PlexConvertedPathR471Tests.options())
        _ = try await session.prepare()
        reader.arm()
        _ = try await session.resource(path: "seg_video_0.m4s")
        let one = Task { await self.status(session, "seg_video_1.m4s") }        // read-ahead of 2 starts with it
        try await Task.sleep(nanoseconds: 100_000_000)
        let far = Task { await self.status(session, "seg_video_10.m4s") }       // a seek: read-ahead of 2 is cancelled
        try await Task.sleep(nanoseconds: 100_000_000)
        let two = await status(session, "seg_video_2.m4s")                      // loaded again; the old load ends meanwhile
        let loadsBefore = await session.windowLoads
        let again = await status(session, "seg_video_2.m4s")
        let loads = await session.windowLoads - loadsBefore
        let statuses = [await one.value, await far.value, two, again]
        await session.cancel()
        print("R471 (58) | statuses \(statuses) | loads for the repeat \(loads) | cancelled reads \(reader.cancelledReads)")
        XCTAssertGreaterThanOrEqual(reader.cancelledReads, 1, "the read-ahead of segment 2 was cancelled")
        XCTAssertEqual(statuses, [200, 200, 200, 200])
        XCTAssertEqual(loads, 0, "segment 2 asked again comes from the cache")
    }
}
