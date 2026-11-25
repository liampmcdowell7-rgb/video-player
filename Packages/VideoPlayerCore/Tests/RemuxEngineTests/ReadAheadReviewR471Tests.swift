import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

/// R471 (57), PROVISIONAL (owner 25 Nov 2026 round 6, Part B item 1): the review of the read-ahead fix R471 (55).
/// The test failed before its fix: a window a request waits for must stay in the session's cache, so a second request
/// for the same segment joins it instead of reading the window again.
final class ReadAheadReviewR471Tests: XCTestCase {
    typealias Reader = PlexConvertedPathR471Tests.AfterOpenReader

    private func status(_ session: MatroskaRemuxSession, _ name: String) async -> Int {
        do { return try await session.resource(path: name).status } catch { return 500 }
    }

    /// R471 (57): read-ahead no longer cancels the video request's window 4 when the audio request for segment 2 comes
    /// (R471 (55)), but it still dropped window 4 from the cache, so the audio request for segment 4 read it a second time.
    func testAWindowARequestWaitsForStaysInTheCache() async throws {
        let data = PlexConvertedPathR471Tests.shape(seconds: 24).build().data
        let reader = Reader(data, mode: .slow(seconds: 0.4, onCancel: CancellationError()))
        var small = EngineBudget(memoryBytes: 1)
        small.minimumWindows = 2
        let session = MatroskaRemuxSession(reader: reader, options: PlexConvertedPathR471Tests.options(budget: small))
        _ = try await session.prepare()
        reader.arm()
        _ = try await session.resource(path: "seg_video_0.m4s")
        let loadsBefore = await session.windowLoads
        let video4 = Task { await self.status(session, "seg_video_4.m4s") }
        try await Task.sleep(nanoseconds: 100_000_000)
        let audio2 = Task { await self.status(session, "seg_audio_2_2.m4s") }
        try await Task.sleep(nanoseconds: 100_000_000)
        let audio4 = Task { await self.status(session, "seg_audio_2_4.m4s") }
        let statuses = [await video4.value, await audio2.value, await audio4.value]
        let loads = await session.windowLoads - loadsBefore
        await session.cancel()
        print("R471 (57) | statuses \(statuses) | window loads \(loads)")
        XCTAssertEqual(statuses, [200, 200, 200])
        XCTAssertEqual(loads, 2, "window 4 once (the audio request joins it) and window 2")
    }
}
