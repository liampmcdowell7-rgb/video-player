import XCTest
import VideoPlayerCore
@testable import LibraryIndex

func basicLibrary(_ s: FakeSource) {
    s.put("/Movies/Hexfall (1995)/Hexfall (1995).mkv", size: 10_000, modified: day(1))
    s.put("/Movies/Hexfall (1995)/Hexfall (1995).srt", size: 50, modified: day(1))
    s.put("/TV/Show One (2010)/Season 1/Show One - S01E01 - Pilot.mkv", size: 5_000, modified: day(2))
    s.put("/TV/Show One (2010)/Season 1/Show One - S01E02 - Second.mkv", size: 5_000, modified: day(3))
    s.put("/TV/Show One (2010)/Season 0/Show One - S00E01 - Special.mkv", size: 4_000, modified: day(4))
    s.put("/Docs/readme.txt", size: 10, modified: day(1))
}

/// Used by the kill tests: refuses everything after `limit` folders have been applied, like a process that died.
final class CrashingStore: LibraryScanStore, @unchecked Sendable {
    struct Crash: Error {}
    let inner: SQLiteLibraryStore
    private let state: Locked<(applied: Int, limit: Int)>
    init(_ inner: SQLiteLibraryStore, crashAfterApplies limit: Int) {
        self.inner = inner
        state = Locked((0, limit))
    }
    var applied: Int { state.get.applied }
    private func alive() throws { if state.get.applied >= state.get.limit { throw Crash() } }

    func beginScan(sourceID: String, roots: [String], options: ScanOptions, resume: Bool, now: Date) async throws -> ScanTicket {
        try await inner.beginScan(sourceID: sourceID, roots: roots, options: options, resume: resume, now: now)
    }
    func scan(id: Int64) async throws -> ScanRecord? { try await inner.scan(id: id) }
    func nextFolder(scanID: Int64) async throws -> PendingFolder? { try alive(); return try await inner.nextFolder(scanID: scanID) }
    func storedFiles(sourceID: String, folder: String) async throws -> [StoredFile] { try alive(); return try await inner.storedFiles(sourceID: sourceID, folder: folder) }
    func storedChildFolders(sourceID: String, folder: String) async throws -> [String] { try alive(); return try await inner.storedChildFolders(sourceID: sourceID, folder: folder) }
    func apply(_ change: FolderChange, scanID: Int64) async throws -> FolderApplyResult {
        try alive()
        let r = try await inner.apply(change, scanID: scanID)
        state.with { $0.applied += 1 }
        return r
    }
    func recordFailure(scanID: Int64, sourceID: String, folder: String, message: String, now: Date) async throws {
        try alive()
        try await inner.recordFailure(scanID: scanID, sourceID: sourceID, folder: folder, message: message, now: now)
    }
    func finishScan(scanID: Int64, status: ScanStatus, now: Date) async throws { try alive(); try await inner.finishScan(scanID: scanID, status: status, now: now) }
    func purgeRemoved(olderThan: Date) async throws -> Int { try await inner.purgeRemoved(olderThan: olderThan) }
}

final class SyncTests: XCTestCase {
    func testFirstScanIndexesMoviesEpisodesAndSidecars() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        let summary = try await h.syncer.sync()
        XCTAssertEqual(summary.status, .completed)
        XCTAssertFalse(summary.resumed)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(summary.progress.added, 5)       // 3 episodes + movie + srt; readme.txt is not media
        XCTAssertEqual(summary.progress.filesSeen, 6 - 1)
        XCTAssertEqual(summary.progress.foldersDone, 8)
        XCTAssertEqual(summary.progress.foldersPending, 0)

        let counts = try await h.store.counts()
        XCTAssertEqual(counts.items, 4)
        XCTAssertEqual(counts.files, 5)
        XCTAssertEqual(counts.folders, 8)
        XCTAssertEqual(counts.series, 1)

        let movies = try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.kinds = [.movie]; return f }()), limit: 10, offset: 0)
        XCTAssertEqual(titles(movies), ["Hexfall"])
        XCTAssertEqual(movies.first?.year, 1995)
        let seriesID = try await unwrap(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.kinds = [.episode]; return f }()), limit: 1, offset: 0).first?.seriesID)
        let eps = try await h.store.episodes(ofSeries: seriesID)
        XCTAssertEqual(eps.map { "\($0.season ?? -1)x\($0.episode ?? -1)" }, ["0x1", "1x1", "1x2"])
        XCTAssertEqual(eps.first?.seriesTitle, "Show One")
        XCTAssertEqual(eps[1].title, "Pilot")
        let sidecars = try await h.store.sidecars(for: try XCTUnwrap(movies.first?.preferredFileID))
        XCTAssertEqual(sidecars.map(\.name), ["Hexfall (1995).srt"])
    }

    func testFilesWithTheSameFilmGroupIntoVersions() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995) 1080p.mkv", size: 8_000, modified: day(1))
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995) 2160p.mkv", size: 30_000, modified: day(2))
        h.source.put("/Backup/Hexfall (1995).mp4", size: 3_000, modified: day(3))
        h.source.put("/Movies/Other (2001)/Other (2001).mkv", size: 3_000, modified: day(3))
        try await h.syncer.sync()
        let all = try await h.store.page(ItemQuery(), limit: 10, offset: 0)
        XCTAssertEqual(titles(all), ["Hexfall", "Other"])
        let hexfall = try XCTUnwrap(all.first)
        XCTAssertEqual(hexfall.versionCount, 3)
        XCTAssertEqual(hexfall.maxResolution, .uhd4k)
        XCTAssertEqual(hexfall.containers, [.mkv, .mp4])
        let versions = try await h.store.versions(of: hexfall.id)
        XCTAssertEqual(versions.count, 3)
        XCTAssertEqual(versions.first?.path, "/Movies/Hexfall (1995)/Hexfall (1995) 2160p.mkv")   // best first
        XCTAssertEqual(hexfall.preferredFileID, versions.first?.id)
        try await expectEqual(try await h.store.counts().items, 2)
    }

    func testPreferredVersionIsRememberedAcrossRescansAndFallsBackWhenGone() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/M/Hexfall (1995) 1080p.mkv", size: 8_000, modified: day(1))
        h.source.put("/M/Hexfall (1995) 2160p.mkv", size: 30_000, modified: day(2))
        try await h.syncer.sync()
        let hexfall = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first)
        let versions = try await h.store.versions(of: hexfall.id)
        let small = try XCTUnwrap(versions.last)
        XCTAssertEqual(small.path, "/M/Hexfall (1995) 1080p.mkv")
        try await h.store.setPreferredVersion(itemID: hexfall.id, fileID: small.id)
        try await expectEqual(try await h.store.item(id: hexfall.id)?.preferredFileID, small.id)

        h.source.put("/M/Hexfall (1995) 2160p.mkv", size: 31_000, modified: day(5))   // other version changes
        try await h.syncer.sync()
        try await expectEqual(try await h.store.item(id: hexfall.id)?.preferredFileID, small.id, "choice survives a rescan")

        h.source.remove("/M/Hexfall (1995) 1080p.mkv", bump: day(6))
        try await h.syncer.sync()
        let after = try await unwrap(try await h.store.item(id: hexfall.id))
        XCTAssertEqual(after.versionCount, 1)
        XCTAssertNotEqual(after.preferredFileID, small.id, "falls back to a live version")

        h.source.put("/M/Hexfall (1995) 1080p.mkv", size: 8_000, modified: day(7))
        try await h.syncer.sync()
        try await expectEqual(try await h.store.item(id: hexfall.id)?.preferredFileID, small.id, "choice returns with the file")

        do {
            try await h.store.setPreferredVersion(itemID: hexfall.id, fileID: 999_999)
            XCTFail("expected an error")
        } catch let error as LibraryIndexError {
            if case .invalid = error {} else { XCTFail("wrong error \(error)") }
        }
    }

    func testMultiEpisodeFilesAndSpecials() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/TV/Show Two/Season 1/Show Two - S01E01E02.mkv", size: 1, modified: day(1))
        h.source.put("/TV/Show Two/Season 1/Show Two - S01E03.mkv", size: 1, modified: day(1))
        h.source.put("/TV/Show Two/Specials/Show Two - S00E01 - Bloopers.mkv", size: 1, modified: day(1))
        try await h.syncer.sync()
        let series = try await unwrap(try await h.store.page(ItemQuery(), limit: 1, offset: 0).first?.seriesID)
        let eps = try await h.store.episodes(ofSeries: series)
        XCTAssertEqual(eps.map { "\($0.season ?? -1)/\($0.episode ?? -1)/\($0.episodeEnd ?? -1)" }, ["0/1/-1", "1/1/2", "1/3/-1"])
    }

    func testUnchangedRescanWritesNothing() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.syncer.sync()
        let before = try await h.store.snapshot()
        // Every write to a file or item row from here on is logged in a temp table.
        try await h.store.execRaw("""
            CREATE TEMP TABLE writes (what TEXT);
            CREATE TEMP TRIGGER w1 AFTER INSERT ON main.files BEGIN INSERT INTO writes VALUES ('file+'); END;
            CREATE TEMP TRIGGER w2 AFTER UPDATE ON main.files BEGIN INSERT INTO writes VALUES ('file~'); END;
            CREATE TEMP TRIGGER w3 AFTER INSERT ON main.items BEGIN INSERT INTO writes VALUES ('item+'); END;
            CREATE TEMP TRIGGER w4 AFTER UPDATE ON main.items BEGIN INSERT INTO writes VALUES ('item~'); END;
            """)
        h.source.resetCalls()
        let second = try await h.syncer.sync()
        XCTAssertEqual(second.progress.added, 0)
        XCTAssertEqual(second.progress.changed, 0)
        XCTAssertEqual(second.progress.removed, 0)
        XCTAssertEqual(second.progress.unchanged, 5)
        try await expectEqual(try await h.store.snapshot(), before)
        // Only bookkeeping rows (folder scan stamps, queue, scan record) were written; no file or item row.
        try await expectEqual(try await h.store.rawInt("SELECT COUNT(*) FROM temp.writes"), 0)
        try await expectEqual(try await h.store.rawInt("SELECT COUNT(*) FROM files"), 5)
    }

    func testChangeSignalsDecideWhatIsRewritten() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/A/a (2000).mkv", size: 100, modified: day(1), token: "v1")
        h.source.put("/A/b (2000).mkv", size: 100, modified: day(1), etag: "e1")
        h.source.put("/A/c (2000).mkv", size: 100, modified: day(1))
        h.source.put("/A/d (2000).mkv", size: 100, modified: day(1))
        try await h.syncer.sync()

        // Token wins over date and size; etag wins over date and size; without either, date + size decide.
        h.source.put("/A/a (2000).mkv", size: 999, modified: day(9), token: "v1")
        h.source.put("/A/b (2000).mkv", size: 999, modified: day(9), etag: "e1")
        h.source.put("/A/c (2000).mkv", size: 100, modified: day(9))
        h.source.put("/A/d (2000).mkv", size: 100, modified: day(1))
        var s = try await h.syncer.sync()
        XCTAssertEqual(s.progress.changed, 1, "only c changed (date moved)")
        XCTAssertEqual(s.progress.unchanged, 3)

        h.source.put("/A/a (2000).mkv", size: 999, modified: day(9), token: "v2")
        h.source.put("/A/b (2000).mkv", size: 999, modified: day(9), etag: "e2")
        h.source.put("/A/d (2000).mkv", size: 101, modified: day(1))
        s = try await h.syncer.sync()
        XCTAssertEqual(s.progress.changed, 3)
        XCTAssertEqual(s.progress.unchanged, 1)
        let files = try await h.store.children(sourceID: Harness.sourceID, folder: "/A", sort: FileSort(), limit: 10, offset: 0)
        XCTAssertEqual(files.map(\.size), [999, 999, 100, 101])
    }

    func testFilesWithNothingToCompareAreRewrittenEveryScan() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/A/a (2000).mkv", size: 100, modified: day(1))
        try await h.syncer.sync()
        // A source that reports neither size nor date nor tags: "unknown" is treated as changed.
        let blind = FakeSource()
        blind.putBlind("/A/blind (2001).mkv")
        let s2 = h.syncer(source: blind, id: "blind")
        try await h.store.upsertSource(LibrarySourceRecord(id: "blind", kind: .webdav, name: "Blind", addedAt: t0))
        try await s2.sync()
        let again = try await s2.sync()
        XCTAssertEqual(again.progress.changed, 1)
        XCTAssertEqual(again.progress.unchanged, 0)
    }

    func testRemovedFilesAreTombstonedAndComeBackWithTheirWatchState() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.syncer.sync()
        let hexfall = try await unwrap(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.text = "hexfall"; return f }()), limit: 1, offset: 0).first)
        try await h.store.updateProgress(itemID: hexfall.id, position: 600, duration: 6_000, at: day(99))
        let fileID = try XCTUnwrap(hexfall.preferredFileID)

        h.source.remove("/Movies/Hexfall (1995)/Hexfall (1995).mkv", bump: day(10))
        let s = try await h.syncer.sync()
        XCTAssertEqual(s.progress.removed, 1)
        try await expectEqual(try await h.store.counts().items, 3)
        try await expectNil(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.text = "hexfall"; return f }()), limit: 1, offset: 0).first)
        let hidden = try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60)
        XCTAssertTrue(hidden.isEmpty, "a removed film is not offered for resume")

        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995).mkv", size: 10_000, modified: day(11))
        let back = try await h.syncer.sync()
        XCTAssertEqual(back.progress.added, 1)
        let item = try await unwrap(try await h.store.item(id: hexfall.id))
        XCTAssertEqual(item.versionCount, 1)
        XCTAssertEqual(item.watch.position, 600)
        XCTAssertEqual(item.preferredFileID, fileID, "same file row comes back")
        try await expectEqual(try await h.store.continueWatching(limit: 10, now: day(100), retentionDays: 60).map(\.id), [hexfall.id])
    }

    func testRemovedFolderTombstonesEverythingBelow() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        h.source.put("/TV/notes.txt", size: 1, modified: day(1))   // keeps /TV from listing as empty
        try await h.syncer.sync()
        h.source.remove("/TV/Show One (2010)", bump: day(10))
        let s = try await h.syncer.sync()
        XCTAssertEqual(s.progress.removed, 3 + 3)   // 3 episode files + Season 0, Season 1 and the show folder
        let counts = try await h.store.counts()
        XCTAssertEqual(counts.items, 1)
        XCTAssertEqual(counts.series, 0)
        XCTAssertEqual(counts.folders, 8 - 3)
        try await expectEqual(try await h.store.children(sourceID: Harness.sourceID, folder: "/TV", sort: FileSort(), limit: 10, offset: 0).count, 0)
    }

    func testFolderThatCannotBeListedKeepsItsRows() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.syncer.sync()
        let before = try await h.store.snapshot()

        h.source.setFailing(["/Movies/Hexfall (1995)", "/TV"])
        let s = try await h.syncer.sync()
        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(Set(s.failures.map(\.folder)), ["/Movies/Hexfall (1995)", "/TV"])
        XCTAssertEqual(s.progress.foldersFailed, 2)
        XCTAssertEqual(s.progress.removed, 0)
        try await expectEqual(try await h.store.counts().items, 4, "nothing was deleted because a listing failed")
        try await expectEqual(try await h.store.lastError(sourceID: Harness.sourceID, folder: "/TV")?.isEmpty, false)

        h.source.setFailing([])
        let ok = try await h.syncer.sync()
        XCTAssertTrue(ok.failures.isEmpty)
        try await expectNil(try await h.store.lastError(sourceID: Harness.sourceID, folder: "/TV"))
        // Same index as before apart from the error stamps that are now cleared.
        try await expectEqual(try await h.store.snapshot(), before)
    }

    func testUnauthorizedStopsTheScanAndKeepsItResumable() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.syncer.sync()
        h.source.setFailing(["/"], error: SourceError.unauthorized)
        do {
            try await h.syncer.sync()
            XCTFail("expected unauthorized")
        } catch let e as SourceError {
            XCTAssertEqual(e, .unauthorized)
        }
        try await expectEqual(try await h.store.counts().items, 4)
        let open = try await h.store.unfinishedScan(sourceID: Harness.sourceID)
        XCTAssertEqual(open?.status, .interrupted)
        h.source.setFailing([])
        let s = try await h.syncer.sync()
        XCTAssertTrue(s.resumed)
        XCTAssertEqual(s.status, .completed)
    }

    func testEmptyListingOfAFolderWithContentIsBelievedOnlyTheSecondTime() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.syncer.sync()
        h.source.setEmpty(["/Movies/Hexfall (1995)"])

        var s = try await h.syncer.sync()
        XCTAssertEqual(s.progress.removed, 0, "first empty answer is held")
        try await expectEqual(try await h.store.counts().items, 4)

        h.source.setEmpty([])
        s = try await h.syncer.sync()
        XCTAssertEqual(s.progress.removed, 0)
        try await expectEqual(try await h.store.folderRecord(sourceID: Harness.sourceID, path: "/Movies/Hexfall (1995)")?.emptyStrikes, 0, "a normal listing resets the strike")

        h.source.setEmpty(["/Movies/Hexfall (1995)"])
        _ = try await h.syncer.sync()              // strike 1 again
        s = try await h.syncer.sync()               // strike 2: believed
        XCTAssertEqual(s.progress.removed, 2)
        try await expectEqual(try await h.store.counts().items, 3)
    }

    func testRefreshReadsOnlyTheRequestedFolder() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        try await h.syncer.sync()
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995) 2160p.mkv", size: 40_000, modified: day(20))
        h.source.put("/Movies/New (2020)/New (2020).mkv", size: 1, modified: day(20))
        h.source.resetCalls()

        let s = try await h.syncer.refresh(folder: "/Movies/Hexfall (1995)")
        XCTAssertEqual(s.progress.added, 1)
        XCTAssertEqual(h.source.calledPaths, ["/Movies/Hexfall (1995)"])
        try await expectEqual(try await h.store.counts().items, 4, "the new film in another folder is not read yet")
        let hexfall = try await unwrap(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.text = "hexfall"; return f }()), limit: 1, offset: 0).first)
        XCTAssertEqual(hexfall.versionCount, 2)

        h.source.resetCalls()
        let r = try await h.syncer.refresh(folder: "/Movies", recursive: true)
        XCTAssertEqual(r.progress.added, 1)
        XCTAssertEqual(h.source.calledPaths, ["/Movies", "/Movies/Hexfall (1995)", "/Movies/New (2020)"])
        try await expectEqual(try await h.store.counts().items, 5)
    }

    func testRefreshDoesNotDisturbAnUnfinishedFullScan() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        let crashing = CrashingStore(h.store, crashAfterApplies: 2)
        let first = h.syncer(store: crashing)
        do { try await first.sync(); XCTFail("should have crashed") } catch is CrashingStore.Crash {}
        let open = try await h.store.unfinishedScan(sourceID: Harness.sourceID)
        XCTAssertNotNil(open)
        try await h.syncer.refresh(folder: "/Docs")
        let stillOpen = try await h.store.unfinishedScan(sourceID: Harness.sourceID)
        XCTAssertEqual(stillOpen?.id, open?.id)
        let resumed = try await h.syncer.sync()
        XCTAssertTrue(resumed.resumed)
    }

    func testProgressIsReportedAfterEveryFolder() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        let seen = Locked<[ScanProgress]>([])
        let s = try await h.syncer.sync { p in seen.with { $0.append(p) } }
        let all = seen.get
        XCTAssertGreaterThanOrEqual(all.count, 8)
        XCTAssertEqual(all.map(\.foldersDone).sorted(), all.map(\.foldersDone), "never goes backwards")
        XCTAssertEqual(all.last?.foldersDone, 8)
        XCTAssertEqual(all.last?.foldersPending, 0)
        XCTAssertEqual(s.progress.foldersDone, h.source.totalListCalls)
        XCTAssertTrue(all.contains { $0.currentFolder == "/TV/Show One (2010)/Season 1" })
    }

    func testCancellationStopsAndALaterScanResumesToTheSameIndex() async throws {
        let ref = try Harness.make()
        defer { ref.cleanup() }
        basicLibrary(ref.source)
        try await ref.syncer.sync()

        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        let box = Locked<Task<ScanSummary, Error>?>(nil)
        let listed = Locked(0)
        h.source.onList { _ in
            if listed.with({ $0 += 1; return $0 }) == 3 { box.get?.cancel() }
        }
        let syncer = h.syncer
        // The scan starts only after its handle is stored (addendum #19 B: under load the task listed three folders before
        // the handle was there, so the cancel found nothing). No timing is involved.
        let (handleStored, signalHandleStored) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in handleStored { break }
            return try await syncer.sync()
        }
        box.with { $0 = task }
        signalHandleStored.yield()
        signalHandleStored.finish()
        let cancelled = try await task.value
        XCTAssertEqual(listed.get, 3, "cancelled while the third folder was listed; no further folder was listed")
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertLessThan(cancelled.progress.foldersDone, 8)
        let open = try await h.store.unfinishedScan(sourceID: Harness.sourceID)
        XCTAssertEqual(open?.status, .cancelled)
        XCTAssertGreaterThan(open?.foldersPending ?? 0, 0)

        h.source.onList(nil)
        let resumed = try await h.syncer.sync()
        XCTAssertTrue(resumed.resumed)
        XCTAssertEqual(resumed.status, .completed)
        try await expectEqual(try await h.store.snapshot(), try await ref.store.snapshot())
    }

    func testKilledScanResumesAndEndsWithTheSameIndexAsAnUninterruptedScan() async throws {
        let ref = try Harness.make()
        defer { ref.cleanup() }
        basicLibrary(ref.source)
        let refSummary = try await ref.syncer.sync()
        let folders = refSummary.progress.foldersDone
        let expected = try await ref.store.snapshot()

        for kill in 1..<folders {
            let h = try Harness.make()
            defer { h.cleanup() }
            basicLibrary(h.source)

            // Phase 1: the process "dies" once `kill` folders are stored.
            let crashing = CrashingStore(h.store, crashAfterApplies: kill)
            do {
                try await h.syncer(store: crashing).sync()
                XCTFail("scan should have died (kill=\(kill))")
            } catch is CrashingStore.Crash {}
            XCTAssertEqual(crashing.applied, kill)

            // Phase 2: a new process opens the same file and continues.
            try await h.store.checkpoint()
            let reopened = try SQLiteLibraryStore(path: h.dbPath)
            let open = try await reopened.unfinishedScan(sourceID: Harness.sourceID)
            XCTAssertNotNil(open, "kill=\(kill)")
            XCTAssertEqual(open?.foldersDone, kill)
            h.source.resetCalls()
            let resumed = try await h.syncer(store: reopened).sync()
            XCTAssertTrue(resumed.resumed, "kill=\(kill)")
            XCTAssertEqual(resumed.status, .completed)
            XCTAssertEqual(h.source.totalListCalls, folders - kill, "folders already stored are not listed again (kill=\(kill))")
            let result = try await reopened.snapshot()
            XCTAssertEqual(result, expected, "kill=\(kill)")
            try await expectNil(try await reopened.unfinishedScan(sourceID: Harness.sourceID))
        }
    }

    func testStartingFreshAbandonsTheUnfinishedScan() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        let crashing = CrashingStore(h.store, crashAfterApplies: 2)
        do { try await h.syncer(store: crashing).sync(); XCTFail() } catch is CrashingStore.Crash {}
        h.source.resetCalls()
        let s = try await h.syncer.sync(resume: false)
        XCTAssertFalse(s.resumed)
        XCTAssertEqual(h.source.totalListCalls, 8)
        try await expectNil(try await h.store.unfinishedScan(sourceID: Harness.sourceID))
    }

    func testTrustedFolderVersionsLetAnUnchangedRescanSkipSubtrees() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        basicLibrary(h.source)
        let trust = ScanOptions(trustFolderVersions: true)
        let first = try await h.syncer.sync(options: trust)
        XCTAssertEqual(first.progress.foldersDone, 8)

        h.source.resetCalls()
        let quiet = try await h.syncer.sync(options: trust)
        XCTAssertEqual(h.source.totalListCalls, 1, "only the root is listed when nothing changed")
        XCTAssertEqual(quiet.progress.unchanged, 0)

        h.source.put("/TV/Show One (2010)/Season 1/Show One - S01E03 - Third.mkv", size: 5_000, modified: day(30))
        h.source.resetCalls()
        let changed = try await h.syncer.sync(options: trust)
        XCTAssertEqual(h.source.calledPaths, ["/", "/TV", "/TV/Show One (2010)", "/TV/Show One (2010)/Season 1"])
        XCTAssertEqual(changed.progress.added, 1)
        try await expectEqual(try await h.store.counts().items, 5)

        // Without trust every folder is listed again.
        h.source.resetCalls()
        _ = try await h.syncer.sync()
        XCTAssertEqual(h.source.totalListCalls, 8)
    }

    func testTwoSourcesShareOneItemAndRemovingASourceKeepsTheOther() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        try await h.registerSource()
        try await h.store.upsertSource(LibrarySourceRecord(id: "src2", kind: .smb, name: "NAS", addedAt: t0))
        let other = FakeSource()
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995).mkv", size: 10, modified: day(1))
        other.put("/Films/Hexfall (1995).mkv", size: 20, modified: day(2))
        other.put("/Films/Only Here (2005).mkv", size: 20, modified: day(2))
        try await h.syncer.sync()
        try await h.syncer(source: other, id: "src2").sync()

        try await expectEqual(try await h.store.counts().items, 2)
        let hexfall = try await unwrap(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.text = "hexfall"; return f }()), limit: 1, offset: 0).first)
        XCTAssertEqual(hexfall.versionCount, 2)
        try await expectEqual(Set(try await h.store.versions(of: hexfall.id).map(\.sourceID)), [Harness.sourceID, "src2"])

        var f = ItemFilter()
        f.sourceID = "src2"
        try await expectEqual(try await h.store.count(ItemQuery(filter: f)), 2)
        f.sourceID = Harness.sourceID
        try await expectEqual(try await h.store.count(ItemQuery(filter: f)), 1)

        try await h.store.removeSource(id: "src2")
        try await expectEqual(try await h.store.counts().items, 1)
        try await expectEqual(try await h.store.item(id: hexfall.id)?.versionCount, 1)
        try await expectEqual(try await h.store.sources().map(\.id), [Harness.sourceID])
        try await h.store.removeSource(id: Harness.sourceID)
        try await expectEqual(try await h.store.counts(), LibraryCounts(items: 0, files: 0, folders: 0, series: 0))
        try await expectEqual(try await h.store.rawInt("SELECT COUNT(*) FROM items"), 0)
    }

    func testPurgeRemovesOldTombstonesButKeepsWatchHistory() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/M/Hexfall (1995).mkv", size: 1, modified: day(1))
        h.source.put("/M/Vanished Wren (2000).mkv", size: 1, modified: day(1))
        h.source.put("/M/notes.txt", size: 1, modified: day(1))   // keeps the folder from listing as empty
        try await h.syncer.sync()
        let hexfall = try await unwrap(try await h.store.page(ItemQuery(filter: { var f = ItemFilter(); f.text = "hexfall"; return f }()), limit: 1, offset: 0).first)
        try await h.store.markWatched(itemIDs: [hexfall.id], watched: true, at: day(50))
        h.source.remove("/M/Hexfall (1995).mkv", bump: day(60))
        h.source.remove("/M/Vanished Wren (2000).mkv", bump: day(60))
        try await h.syncer.sync()   // clock is day 100
        try await expectEqual(try await h.store.purgeRemoved(olderThan: day(99)), 0)
        try await expectEqual(try await h.store.purgeRemoved(olderThan: day(101)), 2)
        try await expectNotNil(try await h.store.item(id: hexfall.id), "watch history is kept")
        try await expectEqual(try await h.store.rawInt("SELECT COUNT(*) FROM items"), 1)
        try await expectEqual(try await h.store.rawInt("SELECT COUNT(*) FROM files"), 0)
    }

    func testDirectBrowsingListsFoldersFirstInNaturalOrderAndPages() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        for n in [1, 2, 10, 11, 3] { h.source.put("/Show/Episode \(n).mkv", size: Int64(n * 100), modified: day(Double(n))) }
        h.source.put("/Show/Extras/Making of.mkv", size: 5, modified: day(1))
        h.source.put("/Show/Notes.nfo", size: 3, modified: day(1))
        try await h.syncer.sync()
        let all = try await h.store.children(sourceID: Harness.sourceID, folder: "/Show", sort: FileSort(), limit: 100, offset: 0)
        XCTAssertEqual(all.map(\.name), ["Extras", "Episode 1.mkv", "Episode 2.mkv", "Episode 3.mkv", "Episode 10.mkv", "Episode 11.mkv", "Notes.nfo"])
        XCTAssertTrue(all[0].isDirectory)
        XCTAssertEqual(all[1].kind, .video)
        XCTAssertEqual(all[6].kind, .nfo)
        let page2 = try await h.store.children(sourceID: Harness.sourceID, folder: "/Show", sort: FileSort(), limit: 3, offset: 3)
        XCTAssertEqual(page2.map(\.name), ["Episode 3.mkv", "Episode 10.mkv", "Episode 11.mkv"])
        let bySize = try await h.store.children(sourceID: Harness.sourceID, folder: "/Show", sort: FileSort(key: .size, ascending: false), limit: 3, offset: 0)
        XCTAssertEqual(bySize.map(\.name), ["Extras", "Episode 11.mkv", "Episode 10.mkv"])
        let byDate = try await h.store.children(sourceID: Harness.sourceID, folder: "/Show", sort: FileSort(key: .dateModified, ascending: true), limit: 100, offset: 0)
        XCTAssertEqual(byDate.first?.name, "Extras")
        XCTAssertEqual(byDate.dropFirst().first?.modified, day(1))
        try await expectTrue(try await h.store.children(sourceID: Harness.sourceID, folder: "/Nope", sort: FileSort(), limit: 10, offset: 0).isEmpty)
    }
}
