import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// #21 C (OPEN_QUESTIONS R192): the header details kept per file. Synthetic names only.
final class TrackDetailsTests: XCTestCase {
    private let details = FileTrackDetails(
        frameRate: 23.976,
        audio: [FileTrackDetails.Audio(codec: "truehd", channels: 8, language: "eng", name: nil, isDefault: true),
                FileTrackDetails.Audio(codec: "aac", channels: 2, language: "fre", name: "Sample commentary", isDefault: false, isCommentary: true)],
        subtitles: [FileTrackDetails.Subtitle(codec: "PGS", language: "eng", name: nil, isForced: true, isHearingImpaired: false)])

    private func movieFileID(_ h: Harness) async throws -> Int64 {
        let movies = try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.kinds = [.movie]; return f }()), limit: 10, offset: 0)
        return try XCTUnwrap(movies.first?.preferredFileID)
    }

    func testDetailsRoundTripAndAreDroppedWhenTheFileChangesSize() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Movies/Sample Movie (2020)/Sample Movie (2020).mkv", size: 10_000, modified: day(1))
        _ = try await h.syncer.sync()
        let id = try await movieFileID(h)

        let before = try await h.store.trackDetails(fileID: id)
        XCTAssertNil(before, "nothing until the header is read")
        try await h.store.setTrackDetails(fileID: id, details)
        let after = try await h.store.trackDetails(fileID: id)
        XCTAssertEqual(after, details)

        // A replaced file (new size) is read again.
        h.source.put("/Movies/Sample Movie (2020)/Sample Movie (2020).mkv", size: 12_000, modified: day(2), bump: day(2))
        _ = try await h.syncer.sync()
        let id2 = try await movieFileID(h)
        let stale = try await h.store.trackDetails(fileID: id2)
        XCTAssertNil(stale, "the cached details belong to the old size")
    }

    func testSettingDetailsForAnUnknownFileThrows() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        do {
            try await h.store.setTrackDetails(fileID: 999_999, details)
            XCTFail("expected notFound")
        } catch {}
    }

    func testDetailsOfARemovedSourceAreDeleted() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Movies/Sample Movie (2020)/Sample Movie (2020).mkv", size: 10_000, modified: day(1))
        _ = try await h.syncer.sync()
        let id = try await movieFileID(h)
        try await h.store.setTrackDetails(fileID: id, details)
        try await h.store.removeSource(id: Harness.sourceID)
        let left = try await h.store.trackDetails(fileID: id)
        XCTAssertNil(left)
        let rows = try await h.store.rawCount("file_tracks")
        XCTAssertEqual(rows, 0, "no orphan rows")
    }
}

private extension SQLiteLibraryStore {
    func rawCount(_ table: String) throws -> Int {
        try db.first("SELECT COUNT(*) FROM \(table)", []) { $0.int(0) } ?? 0
    }
}
