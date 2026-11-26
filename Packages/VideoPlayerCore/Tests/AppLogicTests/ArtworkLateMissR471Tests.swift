import XCTest
import Foundation
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

// FIXTURE: the online provider is a fake; no service is contacted.

/// R471 (75), PROVISIONAL (owner 25 Nov 2026 round 8, Part B item 3, finding G): an older artwork lookup that finds nothing
/// and ends after a newer one found a picture no longer records "found nothing" for the key (kept 15 minutes, which left
/// the card blank for that long).
final class ArtworkLateMissR471Tests: XCTestCase {
    /// The first `imageURL` call waits until `release()` and finds nothing; every later call finds the picture.
    final class SlowFirstOnline: OnlineArtworkProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        private var released = false
        func release() { lock.withLock { released = true } }
        var callCount: Int { lock.withLock { calls } }
        func posterURL(forItem item: LibraryItem, file: StoredFile?) async -> URL? { nil }
        func posterURL(forSeriesID tmdbID: Int) async -> URL? { nil }
        func imageURL(path: String) async -> URL? {
            let first: Bool = lock.withLock { calls += 1; return calls == 1 }
            if first {
                while !lock.withLock({ released }) { try? await Task.sleep(nanoseconds: 5_000_000) }
                return nil
            }
            return URL(string: "https://images.example.invalid/w500" + path)
        }
    }

    struct NoSidecars: SidecarReading {
        func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data { throw SourceError.notFound }
    }

    func testAnOlderMissEndingLastDoesNotHideTheNewerPicture() async throws {
        let rig = try LibraryRig.make()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-late-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let online = SlowFirstOnline()
        let engine = ArtworkEngine(store: rig.store, cache: ArtworkDiskCache(directory: dir, maxBytes: 1_000_000), reader: NoSidecars(),
                                   online: online)
        let key = "remote:/poster-one.jpg"
        let older = Task { await engine.resolve(key: key) }
        while online.callCount < 1 { try await Task.sleep(nanoseconds: 5_000_000) }
        let newer = await engine.resolve(key: key)
        guard case .remote = newer else { return XCTFail("the newer lookup finds the picture: \(newer)") }
        online.release()
        let olderResult = await older.value
        XCTAssertEqual(olderResult, .none, "the older lookup itself found nothing")
        let after = await engine.resolve(key: key)
        print("R471 (75) | lookup after the late miss: \(after)")
        guard case .remote = after else { return XCTFail("the late miss hid the picture for 15 minutes: \(after)") }
    }
}
