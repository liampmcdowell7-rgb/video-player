import Foundation
import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// On Apple platforms the test imports also bring in DeveloperToolsSupport (which import does is not verified), which has its
/// own `LibraryItem` (an Xcode library entry,
/// https://developer.apple.com/documentation/developertoolssupport/libraryitem), so the bare name is ambiguous there (fourth
/// CI run: TestSupport.swift:286). A declaration in this module wins over both imports, so every use in this test target means
/// the library index's item, on Linux and on tvOS alike.
typealias LibraryItem = LibraryIndex.LibraryItem

let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func day(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func with<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
    var get: T { with { $0 } }
}

// MARK: Fake source

/// An in-memory folder tree behind the `MediaSource` contract. Changing a file bumps the modified date of every
/// folder above it, like a source whose folder versions reflect what is below them.
final class FakeSource: MediaSource, @unchecked Sendable {
    let kind: SourceKind = .webdav
    let capabilities = SourceCapabilities(authMethods: [.none], byteRanges: false, changeSignals: [.modified, .size])
    private let lock = NSLock()
    private var tree: [String: [SourceEntry]] = ["/": []]
    private var calls: [String: Int] = [:]
    private var failing: Set<String> = []
    private var empty: Set<String> = []
    private var hook: (@Sendable (String) -> Void)?
    private var failureOverride: Error?

    func authenticate() async throws {}
    func info(_ path: String) async throws -> SourceEntry { throw SourceError.notFound }
    func read(_ path: String, range: ByteRange) async throws -> Data { Data() }
    func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }

    func list(_ path: String) async throws -> [SourceEntry] {
        let (result, hook, failure): ([SourceEntry]?, (@Sendable (String) -> Void)?, Error?) = lock.withLock {
            calls[path, default: 0] += 1
            if failing.contains(path) { return (nil, hook, failureOverride ?? SourceError.transport("boom")) }
            if empty.contains(path) { return ([], hook, nil) }
            return (tree[path] ?? [], hook, nil)
        }
        hook?(path)
        if let failure { throw failure }
        return result ?? []
    }

    // Inspection
    var totalListCalls: Int { lock.withLock { calls.values.reduce(0, +) } }
    func listCalls(_ path: String) -> Int { lock.withLock { calls[path] ?? 0 } }
    var calledPaths: Set<String> { lock.withLock { Set(calls.keys) } }
    func resetCalls() { lock.withLock { calls = [:] } }
    var folderCount: Int { lock.withLock { tree.count } }
    var fileCount: Int { lock.withLock { tree.values.reduce(0) { $0 + $1.filter { !$0.isDirectory }.count } } }

    // Behaviour switches
    func setFailing(_ paths: Set<String>, error: Error? = nil) { lock.withLock { failing = paths; failureOverride = error } }
    func setEmpty(_ paths: Set<String>) { lock.withLock { empty = paths } }
    func onList(_ body: (@Sendable (String) -> Void)?) { lock.withLock { hook = body } }

    // Editing
    /// A file that reports no size, date or tag at all.
    func putBlind(_ path: String) { put(path, size: nil, modified: nil) }

    func put(_ path: String, size: Int64? = 1_000, modified: Date? = t0, etag: String? = nil, token: String? = nil, bump: Date? = nil) {
        lock.withLock {
            let parent = Self.parent(path)
            let modified: Date? = modified
            let bump = bump ?? modified ?? t0
            ensureFolders(parent, at: bump)
            let entry = SourceEntry(path: path, name: Self.name(path), isDirectory: false, size: size, modified: modified, etag: etag, serverToken: token)
            if let i = tree[parent]?.firstIndex(where: { $0.path == path }) { tree[parent]?[i] = entry } else { tree[parent, default: []].append(entry) }
            bumpAncestors(parent, to: bump)
        }
    }

    func putFolder(_ path: String, modified: Date = t0) {
        lock.withLock { ensureFolders(path, at: modified) }
    }

    func remove(_ path: String, bump: Date = t0) {
        lock.withLock {
            let parent = Self.parent(path)
            tree[parent]?.removeAll { $0.path == path }
            if tree[path] != nil { for key in tree.keys where key == path || key.hasPrefix(path + "/") { tree[key] = nil } }
            bumpAncestors(parent, to: bump)
        }
    }

    /// Fast load for generated libraries: files grouped by folder, folders created once.
    func bulkLoad(_ files: [(path: String, size: Int64, modified: Date)]) {
        lock.withLock {
            var knownFolders = Set(tree.keys)
            for f in files {
                let parent = Self.parent(f.path)
                var chain: [String] = []
                var p = parent
                while !knownFolders.contains(p) { chain.append(p); p = Self.parent(p) }
                for folder in chain.reversed() {
                    knownFolders.insert(folder)
                    tree[folder] = []
                    tree[Self.parent(folder), default: []].append(SourceEntry(path: folder, name: Self.name(folder), isDirectory: true, modified: t0))
                }
                tree[parent, default: []].append(SourceEntry(path: f.path, name: Self.name(f.path), isDirectory: false, size: f.size, modified: f.modified))
            }
        }
    }

    private func ensureFolders(_ path: String, at date: Date) {
        if path == "/" || tree[path] != nil { return }
        ensureFolders(Self.parent(path), at: date)
        tree[path] = []
        tree[Self.parent(path), default: []].append(SourceEntry(path: path, name: Self.name(path), isDirectory: true, modified: date))
    }

    private func bumpAncestors(_ folder: String, to date: Date) {
        var p = folder
        while p != "/" {
            let parent = Self.parent(p)
            if let i = tree[parent]?.firstIndex(where: { $0.path == p }) { tree[parent]?[i].modified = date }
            p = parent
        }
    }

    static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[path.startIndex..<slash])
    }

    static func name(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }
}

// MARK: Annotators

/// Technical facts by file name, for tests that need exact values.
struct TableAnnotator: FileAnnotator {
    var table: [String: FileTechnicalInfo]
    func technicalInfo(for entry: SourceEntry, parsed: ParsedMedia) -> FileTechnicalInfo? {
        table[entry.name] ?? FileTechnicalInfo(container: ContainerFormat.from(extension: FileClassifier.fileExtension(of: entry.name)))
    }
}

/// Deterministic pseudo-random technical facts from the path (for generated libraries).
struct HashAnnotator: FileAnnotator {
    func technicalInfo(for entry: SourceEntry, parsed: ParsedMedia) -> FileTechnicalInfo? {
        let h = fnv(entry.path)
        var info = FileTechnicalInfo(container: ContainerFormat.from(extension: FileClassifier.fileExtension(of: entry.name)))
        let r = Int(h % 100)
        if r < 10 { info.width = 3840; info.height = 2160 } else if r < 80 { info.width = 1920; info.height = 1080 } else if r < 95 { info.width = 1280; info.height = 720 } else { info.width = 720; info.height = 480 }
        if info.height == 2160 {
            info.hdrFormats = (h >> 8) % 3 == 0 ? [.dolbyVision, .hdr10] : [.hdr10]
            if info.hdrFormats.contains(.dolbyVision) { info.dolbyVisionProfile = (h >> 12) % 2 == 0 ? 8 : 5 }
        }
        info.audioChannels = [2, 6, 8][Int((h >> 16) % 3)]
        info.hasAtmos = info.audioChannels == 8 && (h >> 20) % 2 == 0
        info.duration = Double(3_000 + Int((h >> 24) % 6_000))
        return info
    }
}

func fnv(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return h
}

/// Small deterministic generator.
struct LCG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
}

// MARK: Harness

struct Harness {
    let store: SQLiteLibraryStore
    let source: FakeSource
    let syncer: LibrarySyncer
    let dir: URL
    let dbPath: String

    static let sourceID = "src1"

    static func make(annotator: any FileAnnotator = FilenameAnnotator(), clock: @escaping @Sendable () -> Date = { t0.addingTimeInterval(100 * 86_400) }, inMemory: Bool = false) throws -> Harness {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("libidx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = inMemory ? ":memory:" : dir.appendingPathComponent("library.sqlite").path
        let store = try SQLiteLibraryStore(path: path)
        let source = FakeSource()
        let syncer = LibrarySyncer(store: store, source: source, sourceID: sourceID, annotator: annotator, clock: clock)
        return Harness(store: store, source: source, syncer: syncer, dir: dir, dbPath: path)
    }

    func registerSource() async throws {
        try await store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
    }

    func cleanup() { try? FileManager.default.removeItem(at: dir) }

    func syncer(source: FakeSource? = nil, store: (any LibraryScanStore)? = nil, id: String = Harness.sourceID, annotator: any FileAnnotator = FilenameAnnotator(), clock: @escaping @Sendable () -> Date = { t0.addingTimeInterval(100 * 86_400) }) -> LibrarySyncer {
        LibrarySyncer(store: store ?? self.store, source: source ?? self.source, sourceID: id, annotator: annotator, clock: clock)
    }
}

// MARK: Logical snapshot (ids and row order do not matter)

extension SQLiteLibraryStore {
    /// Everything that defines the index, written so two stores with the same content give the same lines
    /// whatever order the rows were inserted in.
    func snapshot() throws -> [String] {
        var lines: [String] = []
        lines += try db.rows(
            """
            SELECT f.source_id, f.path, f.kind, f.size, f.modified, f.etag, f.token, COALESCE(i.key, ''), f.removed_at IS NOT NULL, COALESCE(f.version_label, ''),
                   f.has_tech, f.res, f.hdr_mask, f.channels, f.atmos, COALESCE(f.container, -1), COALESCE(f.duration, -1)
            FROM files f LEFT JOIN items i ON i.id = f.item_id
            """, [], cached: false
        ) { s in
            "F|\(s.text(0))|\(s.text(1))|\(s.int(2))|\(s.optInt64(3) ?? -1)|\(s.optDouble(4) ?? -1)|\(s.optText(5) ?? "")|\(s.optText(6) ?? "")|\(s.text(7))|\(s.int(8))|\(s.text(9))|\(s.int(10))|\(s.int(11))|\(s.int(12))|\(s.int(13))|\(s.int(14))|\(s.int(15))|\(s.double(16))"
        }
        lines += try db.rows(
            """
            SELECT i.key, i.kind, i.title, i.sort_title, i.year, COALESCE(i.series_title, ''), COALESCE(i.season, -1), COALESCE(i.episode, -1), i.version_count,
                   i.max_res, i.hdr_mask, i.dv_mask, i.max_channels, i.atmos, i.container_mask, i.runtime, i.added_at, COALESCE(f.path, '')
            FROM items i LEFT JOIN files f ON f.id = i.effective_file_id
            """, [], cached: false
        ) { s in
            "I|\(s.text(0))|\(s.int(1))|\(s.text(2))|\(s.text(3))|\(s.int(4))|\(s.text(5))|\(s.int(6))|\(s.int(7))|\(s.int(8))|\(s.int(9))|\(s.int(10))|\(s.int(11))|\(s.int(12))|\(s.int(13))|\(s.int(14))|\(s.double(15))|\(s.double(16))|\(s.text(17))"
        }
        lines += try db.rows(
            "SELECT source_id, path, name, scanned, empty_strikes, COALESCE(last_error, ''), removed_at IS NOT NULL, COALESCE(obs_modified, -1), COALESCE(scan_modified, -1) FROM folders",
            [], cached: false
        ) { s in
            "D|\(s.text(0))|\(s.text(1))|\(s.text(2))|\(s.int(3))|\(s.int(4))|\(s.text(5))|\(s.int(6))|\(s.double(7))|\(s.double(8))"
        }
        lines += try db.rows("SELECT key FROM series", [], cached: false) { "S|\($0.text(0))" }
        return lines.sorted()
    }

    /// Number of rows written by SQLite since the connection opened (to prove a rescan wrote nothing).
    func totalChanges() throws -> Int {
        try db.scalarInt("SELECT total_changes()")
    }

    func rawInt(_ sql: String, _ args: [SQLValue] = []) throws -> Int { try db.scalarInt(sql, args) }
    func execRaw(_ sql: String) throws { try db.exec(sql) }
}

// XCTest's assertion autoclosures cannot await, so these take async autoclosures.
func expectEqual<T: Equatable>(_ a: @autoclosure () async throws -> T, _ b: @autoclosure () async throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
    let x = try await a(), y = try await b()
    XCTAssertEqual(x, y, message(), file: file, line: line)
}
func expectNotEqual<T: Equatable>(_ a: @autoclosure () async throws -> T, _ b: @autoclosure () async throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
    let x = try await a(), y = try await b()
    XCTAssertNotEqual(x, y, message(), file: file, line: line)
}
func expectNil<T>(_ a: @autoclosure () async throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
    let x = try await a()
    XCTAssertNil(x, message(), file: file, line: line)
}
func expectNotNil<T>(_ a: @autoclosure () async throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
    let x = try await a()
    XCTAssertNotNil(x, message(), file: file, line: line)
}
func expectTrue(_ a: @autoclosure () async throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws {
    let x = try await a()
    XCTAssertTrue(x, message(), file: file, line: line)
}
func unwrap<T>(_ a: @autoclosure () async throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    let x = try await a()
    return try XCTUnwrap(x, message(), file: file, line: line)
}

func ids(_ items: [LibraryItem]) -> [Int64] { items.map(\.id) }
func titles(_ items: [LibraryItem]) -> [String] { items.map(\.title) }
