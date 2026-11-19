import XCTest
import VideoPlayerCore
@testable import LibraryIndex

final class FoundationTests: XCTestCase {
    // MARK: SQLite wrapper

    func testStatementsBindEveryValueTypeAndRoundTripUnicode() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.exec("CREATE TABLE t (i INTEGER, d REAL, s TEXT, n TEXT)")
        let text = "Amélise ✨ \"quoted\" 'single' \n newline 日本語 \u{1F3AC}"
        try db.run("INSERT INTO t VALUES (?, ?, ?, ?)", [.int(Int64.max), .double(0.1 + 0.2), .text(text), .null])
        let row = try db.first("SELECT i, d, s, n, n IS NULL FROM t") { s in (s.int64(0), s.double(1), s.text(2), s.optText(3), s.bool(4)) }
        XCTAssertEqual(row?.0, Int64.max)
        XCTAssertEqual(row?.1, 0.1 + 0.2)
        XCTAssertEqual(row?.2, text)
        XCTAssertNil(row?.3)
        XCTAssertEqual(row?.4, true)
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 1)
        XCTAssertEqual(SQLValue(Optional<Int>.none).description, "null")
    }

    func testTransactionsCommitRollBackAndNest() throws {
        let db = try SQLiteDatabase(path: ":memory:")
        try db.exec("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT UNIQUE)")
        try db.transaction {
            try db.run("INSERT INTO t (v) VALUES ('a')")
            try db.transaction { try db.run("INSERT INTO t (v) VALUES ('b')") }   // joins the outer transaction
        }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 2)

        struct Boom: Error {}
        XCTAssertThrowsError(try db.transaction {
            try db.run("INSERT INTO t (v) VALUES ('c')")
            throw Boom()
        })
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 2, "rolled back")
        XCTAssertEqual(db.transactionDepth, 0)

        XCTAssertThrowsError(try db.transaction {
            try db.run("INSERT INTO t (v) VALUES ('d')")
            try db.run("INSERT INTO t (v) VALUES ('a')")   // unique violation
        }) { error in
            guard case let LibraryIndexError.sqlite(code, _) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(code, 19, "SQLITE_CONSTRAINT")
        }
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 2)
        try db.run("INSERT INTO t (v) VALUES ('e')")   // still usable
        XCTAssertEqual(try db.scalarInt("SELECT COUNT(*) FROM t"), 3)
        XCTAssertThrowsError(try db.exec("THIS IS NOT SQL"))
    }

    func testRealSQLiteIsLinked() {
        XCTAssertTrue(SQLiteInfo.version.hasPrefix("3."), SQLiteInfo.version)
    }

    // MARK: Schema

    func testSchemaIsCreatedOnceAndReopeningKeepsEverything() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.registerSource()
        try await h.syncer.sync()
        try await expectEqual(try await h.store.schemaVersion(), LibrarySchema.currentVersion)
        try await expectEqual(try await h.store.integrityCheck(), "ok")
        let before = try await h.store.snapshot()
        let counts = try await h.store.counts()
        try await h.store.checkpoint()

        let reopened = try SQLiteLibraryStore(path: h.dbPath)
        try await expectEqual(try await reopened.schemaVersion(), LibrarySchema.currentVersion)
        try await expectEqual(try await reopened.counts(), counts)
        try await expectEqual(try await reopened.snapshot(), before)
        try await expectEqual(try await reopened.sources().map(\.id), [Harness.sourceID])
        try await expectEqual(try await reopened.sources().first?.kind, .webdav)
    }

    func testADatabaseFromANewerAppIsRefusedAndNotModified() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("libidx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("newer.sqlite").path
        do {
            let db = try SQLiteDatabase(path: path)
            try db.exec("CREATE TABLE from_the_future (x INTEGER); PRAGMA user_version = 99;")
        }
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        do {
            _ = try SQLiteLibraryStore(path: path)
            XCTFail("should refuse")
        } catch let e as LibraryIndexError {
            XCTAssertEqual(e, .newerSchema(found: 99, supported: LibrarySchema.currentVersion))
        }
        let after = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(before, after, "the file is untouched")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "-wal"))
    }

    func testEveryMigrationStepLeavesTheVersionAtTheNextNumber() throws {
        XCTAssertEqual(LibrarySchema.migrations.count, LibrarySchema.currentVersion)
        let db = try SQLiteDatabase(path: ":memory:")
        try db.prepareLibrarySchema()
        XCTAssertEqual(try db.scalarInt("PRAGMA user_version"), LibrarySchema.currentVersion)
        try db.prepareLibrarySchema()   // idempotent
        XCTAssertEqual(try db.scalarInt("PRAGMA user_version"), LibrarySchema.currentVersion)
        let tables = try db.rows("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name") { $0.text(0) }
        XCTAssertEqual(tables, ["file_tracks", "files", "folders", "item_genres", "items", "scan_queue", "scans", "series", "sources", "views"])
    }

    // MARK: Text helpers

    func testNormalizeAndSortKeys() {
        XCTAssertEqual(LibraryText.normalize("  The  Amélise!! (2001) "), "the amelise 2001")
        XCTAssertEqual(LibraryText.normalize("Kite-Man: Far From Shore"), "kite man far from shore")
        XCTAssertEqual(LibraryText.normalize("ÀÉÎÕÜ ñ ß"), "aeiou n ß".replacingOccurrences(of: "ß", with: LibraryText.normalize("ß")))
        XCTAssertEqual(LibraryText.normalize("!!!"), "")
        XCTAssertEqual(LibraryText.sortKey("The Marrowgate", dropArticle: true), "marrowgate")
        XCTAssertEqual(LibraryText.sortKey("The Marrowgate", dropArticle: false), "the marrowgate")
        XCTAssertEqual(LibraryText.sortKey("A", dropArticle: true), "a", "a lone article stays")
        XCTAssertEqual(LibraryText.sortKey("Aquila 13", dropArticle: true), "aquila 00000013")
        XCTAssertLessThan(LibraryText.sortKey("Episode 2", dropArticle: false), LibraryText.sortKey("Episode 10", dropArticle: false))
        XCTAssertEqual(LibraryText.titleSortValue("1871").letter, "#")
        XCTAssertEqual(LibraryText.titleSortValue("Amélise").letter, "A")
        XCTAssertEqual(LibraryText.titleSortValue("日本語").letter, "#")
        XCTAssertEqual(LibraryText.titleSortValue("The End").letter, "E")
        XCTAssertLessThan(LibraryText.titleSortValue("日本語").value, LibraryText.titleSortValue("Aardvark").value, "the # bucket sorts before A")
        XCTAssertLessThan(LibraryText.titleSortValue("Zebra").value, LibraryText.titleSortValue("zzz").value)
    }

    func testPathHelpers() {
        XCTAssertEqual(LibraryPath.parent(of: "/a/b/c.mkv"), "/a/b")
        XCTAssertEqual(LibraryPath.parent(of: "/c.mkv"), "/")
        XCTAssertEqual(LibraryPath.parent(of: "/"), "")
        XCTAssertEqual(LibraryPath.ancestorNames(of: "/TV/Show/Season 1/x.mkv"), ["Season 1", "Show", "TV"])
        XCTAssertEqual(LibraryPath.stem("Hexfall (1995).en.srt"), "Hexfall (1995).en")
        XCTAssertEqual(LibraryPath.stem(".hidden"), ".hidden")
        XCTAssertNil(LibraryPath.descendantBounds(of: "/"))
        let b = LibraryPath.descendantBounds(of: "/TV")
        XCTAssertEqual(b?.lower, "/TV/")
        XCTAssertEqual(b?.upper, "/TV0")
    }

    func testResolutionClassesCoverScopeAndOddSizes() {
        XCTAssertEqual(ResolutionClass.classify(width: 3840, height: 2160), .uhd4k)
        XCTAssertEqual(ResolutionClass.classify(width: 3840, height: 1600), .uhd4k)
        XCTAssertEqual(ResolutionClass.classify(width: 1920, height: 800), .hd1080)
        XCTAssertEqual(ResolutionClass.classify(width: 1920, height: 1080), .hd1080)
        XCTAssertEqual(ResolutionClass.classify(width: 1280, height: 720), .hd720)
        XCTAssertEqual(ResolutionClass.classify(width: 1280, height: 536), .hd720)
        XCTAssertEqual(ResolutionClass.classify(width: 720, height: 480), .sd)
        XCTAssertEqual(ResolutionClass.classify(width: 1920, height: nil), .hd1080)
        XCTAssertNil(ResolutionClass.classify(width: nil, height: nil))
        XCTAssertLessThan(ResolutionClass.sd, .uhd4k)
    }

    // MARK: Grouping rules

    func testSeedsGroupFilmsAndEpisodes() {
        let a = ItemGrouping.seed(fileName: "Hexfall (1995) 2160p.mkv", path: "/Movies/Hexfall (1995)/Hexfall (1995) 2160p.mkv")
        let b = ItemGrouping.seed(fileName: "Hexfall (1995).mp4", path: "/Backup/Hexfall (1995).mp4")
        XCTAssertEqual(a.key, b.key)
        XCTAssertEqual(a.kind, .movie)
        XCTAssertEqual(a.title, "Hexfall")
        XCTAssertEqual(a.year, 1995)

        let dotted = ItemGrouping.seed(fileName: "The.Marrowgate.1999.1080p.BluRay.x264-GRP.mkv", path: "/M/The.Marrowgate.1999.1080p.BluRay.x264-GRP.mkv")
        XCTAssertEqual(dotted.key, "m|the marrowgate|1999")
        XCTAssertTrue(dotted.versionLabel?.contains("1080p") == true, dotted.versionLabel ?? "nil")

        let other = ItemGrouping.seed(fileName: "Hexfall (1996).mkv", path: "/M/Hexfall (1996).mkv")
        XCTAssertNotEqual(a.key, other.key, "a different year is a different film")

        let ep = ItemGrouping.seed(fileName: "Show One - S01E02 - Second.mkv", path: "/TV/Show One/Season 1/Show One - S01E02 - Second.mkv")
        XCTAssertEqual(ep.kind, .episode)
        XCTAssertEqual(ep.key, "e|show one|1|2")
        XCTAssertEqual(ep.seriesKey, "s|show one")
        XCTAssertEqual(ep.seriesTitle, "Show One")
        XCTAssertEqual(ep.title, "Second")
        XCTAssertEqual([ep.season, ep.episode, ep.episodeEnd], [1, 2, nil])

        let multi = ItemGrouping.seed(fileName: "Show One - S01E03E04.mkv", path: "/TV/Show One/Season 1/Show One - S01E03E04.mkv")
        XCTAssertEqual([multi.episode, multi.episodeEnd], [3, 4])

        let special = ItemGrouping.seed(fileName: "Show One - S00E05 - Bloopers.mkv", path: "/TV/Show One/Specials/Show One - S00E05 - Bloopers.mkv")
        XCTAssertEqual(special.season, 0)

        let bare = ItemGrouping.seed(fileName: "05 - Pilot.mkv", path: "/TV/Show One (2010)/Season 2/05 - Pilot.mkv")
        XCTAssertEqual(bare.kind, .episode)
        XCTAssertEqual(bare.seriesKey, "s|show one")
        XCTAssertEqual([bare.season, bare.episode], [2, 5])

        let nfc = ItemGrouping.seed(fileName: "Amélise (2001).mkv", path: "/A/Amélise (2001).mkv")
        let nfd = ItemGrouping.seed(fileName: "Ame\u{301}lise (2001).mkv", path: "/B/Ame\u{301}lise (2001).mkv")
        XCTAssertEqual(nfc.key, nfd.key, "composed and decomposed accents are the same film")
    }

    func testPartsOfOneFilmAreNotMergedIntoVersions() {
        let cd1 = ItemGrouping.seed(fileName: "Long Film (2001) CD1.avi", path: "/M/Long Film (2001) CD1.avi")
        let cd2 = ItemGrouping.seed(fileName: "Long Film (2001) CD2.avi", path: "/M/Long Film (2001) CD2.avi")
        XCTAssertNotEqual(cd1.key, cd2.key)
    }

    func testAFileWithNothingUsableInItsNameStandsAlone() {
        let seed = ItemGrouping.seed(fileName: "IMG_0042.mov", path: "/Camera/IMG_0042.mov")
        XCTAssertEqual(seed.kind, .movie)
        XCTAssertFalse(seed.title.isEmpty)
        XCTAssertFalse(seed.key.isEmpty)
    }

    func testFilenameAnnotatorReadsContainerResolutionAndHDRFromTheName() {
        let entry = SourceEntry(path: "/M/Movie (2020) 2160p HDR10.mkv", name: "Movie (2020) 2160p HDR10.mkv", isDirectory: false)
        let parsed = FilenameParser.parse(fileName: entry.name, folders: ["M"])
        let info = FilenameAnnotator().technicalInfo(for: entry, parsed: parsed)
        XCTAssertEqual(info?.container, .mkv)
        XCTAssertEqual(info?.resolution, .uhd4k)
        XCTAssertEqual(info?.height, 2160)
        XCTAssertEqual(info?.hdrFormats, [.hdr10])

        let plain = SourceEntry(path: "/M/Old.avi", name: "Old.avi", isDirectory: false)
        let none = FilenameAnnotator().technicalInfo(for: plain, parsed: FilenameParser.parse(fileName: plain.name))
        XCTAssertEqual(none?.container, .avi)
        XCTAssertNil(none?.resolution)
        XCTAssertEqual(none?.hdrFormats, [])

        let weird = SourceEntry(path: "/M/x.flv", name: "x.flv", isDirectory: false)
        XCTAssertEqual(FilenameAnnotator().technicalInfo(for: weird, parsed: ParsedMedia())?.container, ContainerFormat.other)
    }

    func testDecomposedAndComposedFileNamesBecomeVersionsOfOneItem() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/A/Amélise (2001).mkv", size: 10, modified: day(1))
        h.source.put("/B/Ame\u{301}lise (2001).mp4", size: 20, modified: day(2))
        try await h.syncer.sync()
        let counts = try await h.store.counts()
        XCTAssertEqual(counts.items, 1)
        XCTAssertEqual(counts.files, 2)
    }

    // MARK: Thread safety

    func testManyTasksCanUseOneStoreAtTheSameTime() async throws {
        let fx = try await Fixture.build(count: 120)
        defer { fx.h.cleanup() }
        let store = fx.h.store
        let ids = fx.movies.map(\.id)
        let total = fx.movies.count
        try await withThrowingTaskGroup(of: Int.self) { group in
            for worker in 0..<24 {
                group.addTask {
                    var seen = 0
                    for round in 0..<20 {
                        switch (worker + round) % 4 {
                        case 0:
                            let p = try await store.page(ItemQuery(sort: ItemSort(key: .rating, ascending: round % 2 == 0)), limit: 25, after: nil)
                            seen += p.items.count
                        case 1:
                            try await store.updateProgress(itemID: ids[(worker * 7 + round) % ids.count], position: Double(10 + round), duration: 6_000, at: day(Double(50 + round)))
                        case 2:
                            seen += try await store.continueWatching(limit: 10, now: day(100), retentionDays: 60).count
                        default:
                            seen += try await store.count(ItemQuery())
                        }
                    }
                    return seen
                }
            }
            for try await _ in group {}
        }
        // A scan runs while queries are going on.
        let scanning = Task { try await fx.h.syncer.sync() }
        for _ in 0..<30 { _ = try await store.page(ItemQuery(), limit: 10, offset: 0) }
        let summary = try await scanning.value
        XCTAssertEqual(summary.status, .completed)
        let remaining = try await store.counts().items
        XCTAssertEqual(remaining, total)
        try await expectEqual(try await store.integrityCheck(), "ok")
    }
}

extension SQLValue {
    var description: String {
        switch self {
        case .null: return "null"
        case .int(let v): return "int(\(v))"
        case .double(let v): return "double(\(v))"
        case .text(let v): return "text(\(v))"
        }
    }
}
