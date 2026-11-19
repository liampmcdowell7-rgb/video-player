import XCTest
import Foundation
import VideoPlayerCore
import UserData
import LibraryBackup
@testable import LibraryIndex

/// The purge simulator with the iCloud backup of generated data (docs/BACKUP.md): after a purge the library index, the
/// metadata answers and the pictures come back from the (fake) backup, with NO rescan of the source, and the watch state
/// merges back from the user-data sync exactly as before.
extension PurgeSimulatorTests {
    func testAPurgeFollowedByARestoreFromTheICloudBackupBringsTheLibraryBackWithoutARescan() async throws {
        let cloud = InMemoryCloud(pageSize: 50)
        let backupCloud = InMemoryBackupCloud()
        let lib = GeneratedLibrary.generate(items: 300)
        let source = lib.source
        let d = try Device(cloud: cloud, source: source)
        defer { d.cleanup() }
        let metadataDir = d.dir.appendingPathComponent("online-metadata", isDirectory: true)
        let artworkDir = d.dir.appendingPathComponent("artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataDir.appendingPathComponent("tmdb"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        try Data("{\"overview\":\"generated\"}".utf8).write(to: metadataDir.appendingPathComponent("tmdb/42.json"))
        let poster = Data((0..<4_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        try poster.write(to: artworkDir.appendingPathComponent("poster-1.png"))
        let matches = d.dir.appendingPathComponent("support/matches.json")
        try FileManager.default.createDirectory(at: matches.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"fix\":1}".utf8).write(to: matches)

        func files(_ store: SQLiteLibraryStore) -> LibraryBackupFiles {
            LibraryBackupFiles(store: store, workDir: d.dir.appendingPathComponent("work"),
                               libraryFolders: [FolderBackupStore(root: metadataDir, prefix: "metadata")],
                               libraryFiles: ["matches.json": matches],
                               artwork: FolderBackupStore(root: artworkDir, prefix: "artwork"))
        }
        func engine(_ store: SQLiteLibraryStore) -> BackupEngine {
            BackupEngine(cloud: backupCloud, content: files(store), staging: d.dir.appendingPathComponent("staging"),
                         forbidden: { ["source-password-123"] })
        }

        // Run 1: scan, use the app, sync user data, back up the generated data.
        let (run1, health1, lost1) = try await launch(d)
        try await run1.store.upsertSource(LibrarySourceRecord(id: Harness.sourceID, kind: .webdav, name: "Test", addedAt: t0))
        _ = try await bootstrap(run1, d, health: health1, lost: lost1)
        try await useTheApp(run1, d, actions: 300, seed: 7)
        let before = try await capture(run1.store)
        let indexBefore = try await run1.store.snapshot()
        let synced = await run1.engine.sync()
        XCTAssertEqual(synced.status, .synced)
        try run1.ledger.save(to: d.ledgerURL)
        let backedUp = await engine(run1.store).backUp(settings: BackupSettings())
        XCTAssertEqual(backedUp.status, .idle)
        XCTAssertGreaterThan(backedUp.uploadedChunks, 0)

        // The system frees space (Caches): database, local user-data copy, metadata and pictures. A reinstall also
        // loses Application Support, so the Fix Match file goes too.
        d.purge()
        try FileManager.default.removeItem(at: metadataDir)
        try FileManager.default.removeItem(at: artworkDir)
        try FileManager.default.removeItem(at: matches)

        // Run 2: the index is missing, so the automatic restore runs BEFORE the bootstrap; the source is never listed.
        source.resetCalls()
        let (run2, health2, lost2) = try await launch(d)
        XCTAssertEqual(health2, .missing)
        let restored = await engine(run2.store).restore(settings: BackupSettings(), into: files(run2.store), replaceLibrary: false)
        XCTAssertEqual(restored.status, .idle)
        XCTAssertEqual(restored.restoredFiles, 4)
        let healthAfterRestore: UDDatabaseHealth = try await run2.store.isEmptyLibrary() ? .empty : .ok
        XCTAssertEqual(healthAfterRestore, .ok)
        _ = try await bootstrap(run2, d, health: healthAfterRestore, lost: lost2)

        XCTAssertEqual(source.totalListCalls, 0, "no rescan: the library came back from the backup")
        try await expectEqual(try await run2.store.counts().items, lib.items)
        let indexAfter = try await run2.store.snapshot()
        XCTAssertEqual(indexAfter, indexBefore, "the index is the same, row for row")
        let after = try await capture(run2.store)
        XCTAssertEqual(after.watch, before.watch, "watch state merges back from the user-data sync")
        XCTAssertEqual(after.views, before.views)
        XCTAssertEqual(try Data(contentsOf: metadataDir.appendingPathComponent("tmdb/42.json")), Data("{\"overview\":\"generated\"}".utf8))
        XCTAssertEqual(try Data(contentsOf: artworkDir.appendingPathComponent("poster-1.png")), poster)
        XCTAssertEqual(try Data(contentsOf: matches), Data("{\"fix\":1}".utf8))
    }

    /// "Only artwork for items in your library": the index lists its picture files (with the size and date the artwork
    /// cache puts in its key); a cached picture that is not one of them (an old copy, a removed source) is left out and
    /// reported, not uploaded. The app maps each file through ArtworkEngine.sidecarCacheKey; here the path is the name.
    func testOnlyArtworkForItemsInTheLibraryLeavesOutPicturesOfNothing() async throws {
        let a = try Harness.make()
        defer { a.cleanup() }
        try await a.registerSource()
        basicLibrary(a.source)
        a.source.put("/Movies/Hexfall (1995)/poster.jpg", size: 20, modified: day(1))
        _ = try await a.syncer.sync()
        let images = try await a.store.indexedImageFiles()
        XCTAssertEqual(images.map(\.path), ["/Movies/Hexfall (1995)/poster.jpg"])
        XCTAssertEqual(images.first?.parent, "/Movies/Hexfall (1995)")
        XCTAssertEqual(images.first?.size, 20)
        XCTAssertEqual(images.first?.modified, day(1))

        let artworkDir = a.dir.appendingPathComponent("artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: artworkDir.appendingPathComponent("poster.jpg"))
        try Data([4, 5, 6]).write(to: artworkDir.appendingPathComponent("old-copy.jpg"))
        let store = a.store
        let content = LibraryBackupFiles(store: store, workDir: a.dir.appendingPathComponent("work"), libraryFolders: [], libraryFiles: [:],
                                         artwork: FolderBackupStore(root: artworkDir, prefix: "artwork"),
                                         artworkNamesInLibrary: {
                                             Set(((try? await store.indexedImageFiles()) ?? []).map { "artwork/" + ($0.path as NSString).lastPathComponent })
                                         })
        let only = try await content.files(for: .artwork, settings: BackupSettings(artworkLibraryOnly: true))
        XCTAssertEqual(only.files.map(\.name), ["artwork/poster.jpg"])
        XCTAssertEqual(only.skipped, [BackupSkip(name: "artwork/old-copy.jpg", size: 3, reason: .notInLibrary)])
        let all = try await content.files(for: .artwork, settings: BackupSettings(artworkLibraryOnly: false))
        XCTAssertEqual(all.files.count, 2)
        XCTAssertTrue(all.skipped.isEmpty)
    }

    func testARestoreNeverReplacesALibraryThatIsNotEmptyUnlessTheUserAsks() async throws {
        let backupCloud = InMemoryBackupCloud()
        let a = try Harness.make()
        defer { a.cleanup() }
        try await a.registerSource()
        basicLibrary(a.source)
        _ = try await a.syncer.sync()
        let content = LibraryBackupFiles(store: a.store, workDir: a.dir.appendingPathComponent("work"), libraryFolders: [], libraryFiles: [:], artwork: nil)
        let e = BackupEngine(cloud: backupCloud, content: content, staging: a.dir.appendingPathComponent("staging"), forbidden: { [] })
        _ = try await e.backUp(.library)

        let b = try Harness.make()
        defer { b.cleanup() }
        try await b.registerSource()
        b.source.put("/Other/Lonely Film (2001).mkv")
        _ = try await b.syncer.sync()
        let mine = try await b.store.snapshot()
        let target = LibraryBackupFiles(store: b.store, workDir: b.dir.appendingPathComponent("work"), libraryFolders: [], libraryFiles: [:], artwork: nil)
        let auto = try await e.restore(.library, into: target, replaceLibrary: false)
        XCTAssertEqual(auto.restoredFiles, 0)
        let untouched = try await b.store.snapshot()
        XCTAssertEqual(untouched, mine, "the automatic restore leaves a library with items alone")
        _ = try await e.restore(.library, into: target, replaceLibrary: true)
        let replaced = try await b.store.snapshot()
        let original = try await a.store.snapshot()
        XCTAssertEqual(replaced, original, "Restore from iCloud replaces it when the user confirms")
    }
}
