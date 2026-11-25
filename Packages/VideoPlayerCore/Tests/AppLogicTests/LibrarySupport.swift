import Foundation
import XCTest
import VideoPlayerCore
import LibraryIndex

/// On Apple platforms the test imports also bring in DeveloperToolsSupport (which import does is not verified), which has its
/// own `LibraryItem` (an Xcode library entry,
/// https://developer.apple.com/documentation/developertoolssupport/libraryitem), so the bare name is ambiguous there (fourth
/// CI run: TestSupport.swift:286). A declaration in this module wins over both imports, so every use in this test target means
/// the library index's item, on Linux and on tvOS alike.
typealias LibraryItem = LibraryIndex.LibraryItem

let epoch = Date(timeIntervalSince1970: 1_700_000_000)
func dayOffset(_ n: Double) -> Date { epoch.addingTimeInterval(n * 86_400) }

/// A small in-memory folder tree behind the `MediaSource` contract (the index's own test fake is internal to its tests).
final class TreeSource: MediaSource, @unchecked Sendable {
    let kind: SourceKind = .webdav
    let capabilities = SourceCapabilities(authMethods: [.none], byteRanges: false, changeSignals: [.modified, .size])
    private let lock = NSLock()
    private var tree: [String: [SourceEntry]] = ["/": []]

    func authenticate() async throws {}
    func info(_ path: String) async throws -> SourceEntry { throw SourceError.notFound }
    func read(_ path: String, range: ByteRange) async throws -> Data { Data() }
    func playbackAccess(for path: String) async throws -> PlaybackAccess { .byteReader }
    func list(_ path: String) async throws -> [SourceEntry] { lock.withLock { tree[path] ?? [] } }

    func put(_ path: String, size: Int64 = 1_000, modified: Date = epoch) {
        lock.withLock {
            let parent = Self.parent(path)
            ensureFolders(parent, at: modified)
            tree[parent, default: []].append(SourceEntry(path: path, name: Self.name(path), isDirectory: false, size: size, modified: modified))
        }
    }

    private func ensureFolders(_ path: String, at date: Date) {
        if path == "/" || tree[path] != nil { return }
        ensureFolders(Self.parent(path), at: date)
        tree[path] = []
        tree[Self.parent(path), default: []].append(SourceEntry(path: path, name: Self.name(path), isDirectory: true, modified: date))
    }

    static func parent(_ path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.isEmpty ? "/" : "/" + parts.joined(separator: "/")
    }
    static func name(_ path: String) -> String { String(path.split(separator: "/").last ?? "") }
}

/// A real in-memory SQLite index filled through the real syncer.
struct LibraryRig {
    static let sourceID = "src1"
    let store: SQLiteLibraryStore
    let source: TreeSource

    static func make() throws -> LibraryRig {
        LibraryRig(store: try SQLiteLibraryStore(path: ":memory:"), source: TreeSource())
    }

    /// 3 movies, 2 shows (one with Season 0 specials), a non-media file.
    func fill() async throws {
        try await store.upsertSource(LibrarySourceRecord(id: Self.sourceID, kind: .webdav, name: "Test", addedAt: epoch))
        source.put("/Movies/Hexfall (1995)/Hexfall (1995).mkv", size: 10_000, modified: dayOffset(1))
        source.put("/Movies/Aftlander (1979)/Aftlander (1979).mkv", size: 9_000, modified: dayOffset(2))
        source.put("/Movies/Zornwick (2007)/Zornwick (2007).mkv", size: 8_000, modified: dayOffset(3))
        for e in 1...3 { source.put("/TV/Show One (2010)/Season 1/Show One - S01E0\(e) - Ep \(e).mkv", size: 5_000, modified: dayOffset(Double(10 + e))) }
        source.put("/TV/Show One (2010)/Season 2/Show One - S02E01 - Return.mkv", size: 5_000, modified: dayOffset(20))
        source.put("/TV/Show One (2010)/Season 0/Show One - S00E01 - Special.mkv", size: 4_000, modified: dayOffset(21))
        source.put("/TV/Show Two (2015)/Season 1/Show Two - S01E01 - Start.mkv", size: 5_000, modified: dayOffset(22))
        source.put("/Docs/readme.txt", size: 10, modified: dayOffset(1))
        let syncer = LibrarySyncer(store: store, source: source, sourceID: Self.sourceID, clock: { epoch.addingTimeInterval(100 * 86_400) })
        let summary = try await syncer.sync()
        XCTAssertEqual(summary.status, .completed)
    }

    func movieID(_ title: String) async throws -> Int64 {
        var f = ItemFilter()
        f.kinds = [.movie]
        let page = try await store.page(ItemQuery(filter: f, sort: ItemSort(key: .title, ascending: true)), limit: 50, after: nil)
        return try XCTUnwrap(page.items.first { $0.title == title }, "no movie \(title)").id
    }

    func episodes(ofSeriesTitle title: String) async throws -> [LibraryItem] {
        var f = ItemFilter()
        f.kinds = [.episode]
        let page = try await store.page(ItemQuery(filter: f, sort: ItemSort(key: .title, ascending: true)), limit: 100, after: nil)
        return page.items.filter { $0.seriesTitle == title }
    }
}

struct Boom: LocalizedError { var errorDescription: String? { "The library could not be read." } }

/// Forwards everything to a real store, and throws from the read calls the screens use while `failing` is set.
final class FlakyStore: LibraryStore, @unchecked Sendable {
    let inner: any LibraryStore
    private let lock = NSLock()
    private var isFailing = false
    init(_ inner: any LibraryStore) { self.inner = inner }
    var failing: Bool {
        get { lock.withLock { isFailing } }
        set { lock.withLock { isFailing = newValue } }
    }
    private func check() throws { if failing { throw Boom() } }

    func upsertSource(_ source: LibrarySourceRecord) async throws { try await inner.upsertSource(source) }
    func sources() async throws -> [LibrarySourceRecord] { try check(); return try await inner.sources() }
    func removeSource(id: String) async throws { try await inner.removeSource(id: id) }
    func counts() async throws -> LibraryCounts { try check(); return try await inner.counts() }
    func page(_ query: ItemQuery, limit: Int, after: ItemCursor?) async throws -> ItemPage { try check(); return try await inner.page(query, limit: limit, after: after) }
    func page(_ query: ItemQuery, limit: Int, offset: Int) async throws -> [LibraryItem] { try check(); return try await inner.page(query, limit: limit, offset: offset) }
    func count(_ query: ItemQuery) async throws -> Int { try check(); return try await inner.count(query) }
    func alphabetIndex(_ query: ItemQuery) async throws -> [AlphabetEntry] { try check(); return try await inner.alphabetIndex(query) }
    func item(id: Int64) async throws -> LibraryItem? { try await inner.item(id: id) }
    func versions(of itemID: Int64) async throws -> [StoredFile] { try await inner.versions(of: itemID) }
    func setPreferredVersion(itemID: Int64, fileID: Int64?) async throws { try await inner.setPreferredVersion(itemID: itemID, fileID: fileID) }
    func continueWatching(limit: Int, now: Date, retentionDays: Int) async throws -> [LibraryItem] { try check(); return try await inner.continueWatching(limit: limit, now: now, retentionDays: retentionDays) }
    func nextUp(limit: Int, now: Date, retentionDays: Int) async throws -> [NextUpEntry] { try check(); return try await inner.nextUp(limit: limit, now: now, retentionDays: retentionDays) }
    func recentlyAdded(limit: Int, kind: ItemKind?) async throws -> [LibraryItem] { try check(); return try await inner.recentlyAdded(limit: limit, kind: kind) }
    func episodes(ofSeries seriesID: Int64) async throws -> [LibraryItem] { try check(); return try await inner.episodes(ofSeries: seriesID) }
    func children(sourceID: String, folder: String, sort: FileSort, limit: Int, offset: Int) async throws -> [FolderChild] {
        try check()
        return try await inner.children(sourceID: sourceID, folder: folder, sort: sort, limit: limit, offset: offset)
    }
    func sidecars(for fileID: Int64) async throws -> [StoredFile] { try await inner.sidecars(for: fileID) }
    func extraVideos(sourceID: String, folder: String) async throws -> [StoredFile] { try await inner.extraVideos(sourceID: sourceID, folder: folder) }
    func setMetadata(itemID: Int64, _ metadata: ItemMetadata) async throws { try await inner.setMetadata(itemID: itemID, metadata) }
    func clearMatch(itemIDs: [Int64]) async throws { try await inner.clearMatch(itemIDs: itemIDs) }
    func removeFromLibrary(itemIDs: [Int64], at date: Date) async throws { try await inner.removeFromLibrary(itemIDs: itemIDs, at: date) }
    func setTechnicalInfo(fileID: Int64, _ info: FileTechnicalInfo) async throws { try await inner.setTechnicalInfo(fileID: fileID, info) }
    func trackDetails(fileID: Int64) async throws -> FileTrackDetails? { try await inner.trackDetails(fileID: fileID) }
    func setTrackDetails(fileID: Int64, _ details: FileTrackDetails) async throws { try await inner.setTrackDetails(fileID: fileID, details) }
    func updateProgress(itemID: Int64, position: Double, duration: Double?, at date: Date) async throws { try await inner.updateProgress(itemID: itemID, position: position, duration: duration, at: date) }
    func markWatched(itemIDs: [Int64], watched: Bool, at date: Date) async throws { try await inner.markWatched(itemIDs: itemIDs, watched: watched, at: date) }
    func markSeries(seriesID: Int64, season: Int?, watched: Bool, at date: Date) async throws { try await inner.markSeries(seriesID: seriesID, season: season, watched: watched, at: date) }
    func setFavorite(itemID: Int64, favorite: Bool) async throws { try await inner.setFavorite(itemID: itemID, favorite: favorite) }
    func hideFromContinue(itemID: Int64, hidden: Bool) async throws { try await inner.hideFromContinue(itemID: itemID, hidden: hidden) }
    func saveView(name: String, scope: ViewScope, query: ItemQuery, pinned: Bool) async throws -> SavedView { try await inner.saveView(name: name, scope: scope, query: query, pinned: pinned) }
    func updateView(_ view: SavedView) async throws { try await inner.updateView(view) }
    func deleteView(id: Int64) async throws { try await inner.deleteView(id: id) }
    func views(scope: ViewScope) async throws -> [SavedView] { try await inner.views(scope: scope) }
    func pinnedViews() async throws -> [SavedView] { try await inner.pinnedViews() }
    func needsReview(limit: Int) async throws -> [ReviewEntry] { try check(); return try await inner.needsReview(limit: limit) }
    func needsReviewCount() async throws -> Int { try check(); return try await inner.needsReviewCount() }
    func sortInfo(itemID: Int64) async throws -> ItemSortInfo? { try await inner.sortInfo(itemID: itemID) }
}
