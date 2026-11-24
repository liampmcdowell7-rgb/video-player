import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

// FIXTURE: hand-written NFO files, invented titles and ratings, a fake file reader; nothing is contacted.

/// R460: a title gets its rating when it is scanned (the same `SourceRatings.storedRating` path the Read Ratings button uses), so
/// with Allow Unrated off a new title does not wait hidden for the button; and the page's count of titles without a rating.
final class RatingPassTests: XCTestCase {
    private final class Reader: SidecarReading, @unchecked Sendable {
        private let lock = NSLock()
        var files: [String: Data] = [:]
        private(set) var reads: [String] = []
        func read(sourceID: String, path: String, maxBytes: Int) async throws -> Data {
            lock.withLock { reads.append(path) }
            guard let data = files[path] else { throw SourceError.notFound }
            return data
        }
    }

    private static func nfo(_ rating: String) -> Data { Data("<movie><title>T</title><mpaa>\(rating)</mpaa></movie>".utf8) }

    private let rule = LibraryRestrictions.RatingRule(movieLabels: ["G", "PG", "PG13"], episodeLabels: ["TVPG"], allowUnrated: false)

    private func scan(_ store: SQLiteLibraryStore, _ tree: TreeSource, day: Double) async throws {
        let summary = try await LibrarySyncer(store: store, source: tree, sourceID: "src", clock: { dayOffset(day) }).sync()
        XCTAssertEqual(summary.status, .completed)
    }

    private func put(_ tree: TreeSource, _ reader: Reader, _ name: String, rating: String) {
        tree.put("/Movies/\(name) (2001)/\(name) (2001).mkv")
        let nfoPath = "/Movies/\(name) (2001)/\(name) (2001).nfo"
        let data = Self.nfo(rating)
        tree.put(nfoPath, size: Int64(data.count))
        reader.files[nfoPath] = data
    }

    private func shown(_ store: SQLiteLibraryStore) async throws -> Set<String> {
        Set(try await store.page(ItemQuery(), limit: 100, after: nil).items.map(\.title))
    }

    func testANewTitleGetsItsRatingOnTheScanAndAppearsWithoutTheButton() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        try await store.upsertSource(LibrarySourceRecord(id: "src", kind: .webdav, name: "Source", addedAt: epoch))
        let tree = TreeSource()
        let reader = Reader()
        put(tree, reader, "Arnvale", rating: "Rated PG-13")
        try await scan(store, tree, day: 100)
        await store.setRestrictions(LibraryRestrictions(ratings: rule))
        let hiddenBefore = try await shown(store)
        XCTAssertFalse(hiddenBefore.contains("Arnvale"), "no rating kept yet: hidden while Allow Unrated is off")

        let first = await RatingPass.read(store: store, server: nil, reader: reader)
        XCTAssertEqual(first, 1)
        let afterFirst = try await shown(store)
        XCTAssertTrue(afterFirst.contains("Arnvale"))

        // A second title arrives with a later scan: only the new title is read, and it shows after the pass.
        put(tree, reader, "Borrowdale", rating: "R")
        put(tree, reader, "Calmore", rating: "PG")
        try await scan(store, tree, day: 101)
        let second = await RatingPass.read(store: store, server: nil, reader: reader)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(reader.reads.count, 3, "each title's file is read once; the first title is not read again")
        let afterSecond = try await shown(store)
        XCTAssertTrue(afterSecond.contains("Calmore"))
        XCTAssertFalse(afterSecond.contains("Borrowdale"), "its rating R is above the allowed ones")
        let third = await RatingPass.read(store: store, server: nil, reader: reader)
        XCTAssertEqual(third, 0, "nothing is left to read")
    }

    func testTheCountOfTitlesWithoutARatingFollowsTheReading() async throws {
        let store = try SQLiteLibraryStore(path: ":memory:")
        try await store.upsertSource(LibrarySourceRecord(id: "src", kind: .webdav, name: "Source", addedAt: epoch))
        let tree = TreeSource()
        let reader = Reader()
        put(tree, reader, "Arnvale", rating: "PG")
        put(tree, reader, "Plainfilm", rating: "Not Rated")
        tree.put("/Movies/Nofile (2003)/Nofile (2003).mkv")
        try await scan(store, tree, day: 100)
        let before = try await store.unratedCount()
        XCTAssertEqual(before, 3, "nothing read yet: all three have no rating")
        _ = await RatingPass.read(store: store, server: nil, reader: reader)
        let after = try await store.unratedCount()
        XCTAssertEqual(after, 2, "Arnvale is rated; \"Not Rated\" and a title with no file stay without a rating")
    }
}
