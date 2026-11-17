import XCTest
@testable import VideoPlayerCore

/// An in-memory source: proves the contract helpers work for any implementation.
struct FakeSource: MediaSource {
    var kind: SourceKind { .directLink }
    var capabilities: SourceCapabilities {
        SourceCapabilities(authMethods: [.none], byteRanges: true, changeSignals: [.modified, .size])
    }
    let tree: [String: [SourceEntry]]

    func authenticate() async throws {}
    func list(_ path: String) async throws -> [SourceEntry] {
        guard let entries = tree[path] else { throw SourceError.notFound }
        return entries
    }
    func info(_ path: String) async throws -> SourceEntry {
        for entries in tree.values { if let e = entries.first(where: { $0.path == path }) { return e } }
        throw SourceError.notFound
    }
    func read(_ path: String, range: ByteRange) async throws -> Data { Data(count: Int(range.length)) }
    func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }
}

final class SourceContractTests: XCTestCase {
    func testByteRangeHeader() {
        XCTAssertEqual(ByteRange(offset: 0, length: 1).httpHeaderValue, "bytes=0-0")
        XCTAssertEqual(ByteRange(offset: 1_000, length: 500).httpHeaderValue, "bytes=1000-1499")
        let clamped = ByteRange(offset: -5, length: -1)
        XCTAssertEqual(clamped.offset, 0)
        XCTAssertEqual(clamped.length, 0)
    }

    func testVersionComparisonUsesTheStrongestSharedSignal() {
        let t1 = Date(timeIntervalSince1970: 1_000), t2 = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(FileVersion(etag: "a", serverToken: "x").isSame(as: FileVersion(etag: "b", serverToken: "x")), true,
                       "server token beats a different etag")
        XCTAssertEqual(FileVersion(etag: "a").isSame(as: FileVersion(etag: "b")), false)
        XCTAssertEqual(FileVersion(etag: "a").isSame(as: FileVersion(etag: "a")), true)
        XCTAssertEqual(FileVersion(modified: t1, size: 5).isSame(as: FileVersion(modified: t1, size: 5)), true)
        XCTAssertEqual(FileVersion(modified: t1, size: 5).isSame(as: FileVersion(modified: t2, size: 5)), false)
        XCTAssertEqual(FileVersion(modified: t1, size: 5).isSame(as: FileVersion(modified: t1, size: 6)), false)
        XCTAssertEqual(FileVersion(modified: t1).isSame(as: FileVersion(modified: t1)), true)
        XCTAssertEqual(FileVersion(size: 5).isSame(as: FileVersion(size: 6)), false)
        XCTAssertNil(FileVersion(size: 5).isSame(as: FileVersion(size: 5)), "equal size alone proves nothing")
        XCTAssertNil(FileVersion().isSame(as: FileVersion(etag: "a")))
    }

    func testEntryVersionCarriesAllSignals() {
        let entry = SourceEntry(path: "/a", name: "a", isDirectory: false, size: 3,
                                modified: Date(timeIntervalSince1970: 9), etag: "e", serverToken: "t")
        XCTAssertEqual(entry.version, FileVersion(etag: "e", modified: Date(timeIntervalSince1970: 9), size: 3, serverToken: "t"))
    }

    func testWalkVisitsEveryFolderAndHonoursMaxDepth() async throws {
        func dir(_ p: String) -> SourceEntry { SourceEntry(path: p, name: String(p.split(separator: "/").last ?? ""), isDirectory: true) }
        func file(_ p: String) -> SourceEntry { SourceEntry(path: p, name: String(p.split(separator: "/").last ?? ""), isDirectory: false, size: 1) }
        let source = FakeSource(tree: [
            "/": [dir("/A"), file("/root.mkv")],
            "/A": [dir("/A/B"), file("/A/one.mkv")],
            "/A/B": [dir("/A/B/C"), file("/A/B/two.mkv")],
            "/A/B/C": [file("/A/B/C/deep.mkv")]
        ])
        let all = try await source.walk()
        XCTAssertEqual(Set(all.map(\.path)), ["/A", "/root.mkv", "/A/B", "/A/one.mkv", "/A/B/C", "/A/B/two.mkv", "/A/B/C/deep.mkv"])
        let shallow = try await source.walk("/", maxDepth: 1)
        // maxDepth 1 lists the root and one level below it: /A/B is seen but not opened.
        XCTAssertFalse(shallow.contains { $0.path == "/A/B/two.mkv" })
        XCTAssertTrue(shallow.contains { $0.path == "/A/one.mkv" })
        XCTAssertTrue(shallow.contains { $0.path == "/A/B" })
    }

    func testWalkPropagatesErrors() async {
        let source = FakeSource(tree: [:])
        do { _ = try await source.walk(); XCTFail("expected error") }
        catch { XCTAssertEqual(error as? SourceError, .notFound) }
    }

    func testEverySourceKindIsListedOnce() {
        XCTAssertEqual(SourceKind.allCases.count, 13)
        XCTAssertEqual(Set(SourceKind.allCases.map(\.rawValue)).count, 13)
    }
}
