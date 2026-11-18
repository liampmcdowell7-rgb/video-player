import XCTest
import Foundation
import UserData
@testable import LibraryBackup

/// In-memory content and restore target: a dictionary of files per set.
final class MemoryFiles: BackupContent, BackupRestoreTarget, @unchecked Sendable {
    let lock = NSLock()
    var sets: [BackupSet: [String: (data: Data, modified: Date)]] = [.library: [:], .artwork: [:]]
    var schema = 2
    var supportedLibrarySchema = 2
    var notInLibrary: Set<String> = []
    var writes: [String] = []

    func put(_ set: BackupSet, _ name: String, _ data: Data, modified: Date = Date(timeIntervalSince1970: 1_000)) {
        lock.withLock { sets[set]![name] = (data, modified) }
    }
    func get(_ set: BackupSet, _ name: String) -> Data? { lock.withLock { sets[set]![name]?.data } }
    func clear() { lock.withLock { sets = [.library: [:], .artwork: [:]] } }

    func files(for set: BackupSet, settings: BackupSettings) async throws -> (files: [BackupFile], skipped: [BackupSkip]) {
        let entries = lock.withLock { sets[set]! }
        var files: [BackupFile] = []
        var skipped: [BackupSkip] = []
        for (name, v) in entries.sorted(by: { $0.key < $1.key }) {
            if set == .artwork, settings.artworkLibraryOnly, notInLibrary.contains(name) {
                skipped.append(BackupSkip(name: name, size: v.data.count, reason: .notInLibrary)); continue
            }
            let data = v.data
            files.append(BackupFile(name: name, size: data.count, modified: v.modified) { data })
        }
        return (files, skipped)
    }
    func librarySchema() async -> Int { schema }
    func libraryIsEmpty() async -> Bool { lock.withLock { sets[.library]![backupLibraryDatabaseName] == nil } }
    func localModified(_ set: BackupSet, name: String) async -> Date? { lock.withLock { sets[set]![name]?.modified } }
    func write(_ set: BackupSet, name: String, data: Data, modified: Date) async throws {
        lock.withLock { sets[set]![name] = (data, modified); writes.append(name) }
    }
}

/// A tiny run-length codec, so the tests see compressed sizes that differ from the plain ones.
struct RLECodec: BackupCodec {
    var id: String { "rle-test" }
    func compress(_ data: Data) throws -> Data {
        var out = Data(); var i = data.startIndex
        while i < data.endIndex {
            let b = data[i]; var n = 1
            while i + n < data.endIndex, data[i + n] == b, n < 255 { n += 1 }
            out.append(UInt8(n)); out.append(b); i += n
        }
        return out
    }
    func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        var out = Data(); var i = data.startIndex
        while i + 1 < data.endIndex { out.append(contentsOf: repeatElement(data[i + 1], count: Int(data[i]))); i += 2 }
        return out
    }
}

func bytes(_ n: Int, seed: UInt8) -> Data {
    var x = UInt32(seed) &* 2_654_435_761 | 1
    return Data((0..<n).map { _ in x ^= x << 13; x ^= x >> 17; x ^= x << 5; return UInt8(truncatingIfNeeded: x) })
}

final class BackupHashTests: XCTestCase {
    func testSHA256MatchesTheFIPSTestVectors() {
        XCTAssertEqual(BackupSHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(BackupSHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(BackupSHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(BackupSHA256.hex(Data(repeating: 0x61, count: 1_000_000)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}

final class BackupEngineTests: XCTestCase {
    var dir: URL!
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func engine(_ cloud: InMemoryBackupCloud, _ files: MemoryFiles, codec: any BackupCodec = IdentityCodec(), forbidden: [String] = [],
                staging: String = "staging", statuses: Locked<[BackupStatus]>? = nil) -> BackupEngine {
        BackupEngine(cloud: cloud, codec: codec, content: files, staging: dir.appendingPathComponent(staging),
                     clock: { Date(timeIntervalSince1970: 2_000_000_000) }, forbidden: { forbidden },
                     sleep: { _ in }, onStatus: { s in statuses?.with { $0.append(s) } })
    }

    func testTooManyRequestsWaitsAndTriesAgainUpToThreeTimes() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(100, seed: 1))
        cloud.inject(.upload, .rateLimited(retryAfter: 1))
        cloud.inject(.upload, .rateLimited(retryAfter: nil), after: 1)
        let e = engine(cloud, files)
        let r = try await e.backUp(.library)
        XCTAssertEqual(r.uploadedChunks, 1)
        XCTAssertEqual(cloud.calls(.upload), 3)
        for n in 0..<4 { cloud.inject(.upload, .rateLimited(retryAfter: nil), after: n) }
        files.put(.library, backupLibraryDatabaseName, bytes(100, seed: 2))
        let r2 = await e.backUp(settings: BackupSettings(library: true, artwork: false))
        guard case .failed = r2.status else { return XCTFail("gives up after 3 retries, got \(r2.status)") }
    }

    func testChunkingUsesOneMiBPiecesAndARestoreRebuildsTheFilesExactly() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        let db = bytes(BackupFormat.chunkSize * 3 + 12_345, seed: 1)
        files.put(.library, backupLibraryDatabaseName, db)
        files.put(.library, "metadata/a.json", Data("{\"a\":1}".utf8))
        files.put(.artwork, "artwork/p.png", bytes(5_000, seed: 2))
        let e = engine(cloud, files, codec: RLECodec())
        let r = await e.backUp(settings: BackupSettings())
        XCTAssertEqual(r.status, .idle)
        XCTAssertEqual(r.uploadedChunks, 4 + 1 + 1)
        let mFound = try await e.currentManifest(.library)
        let m = try XCTUnwrap(mFound)
        XCTAssertEqual(m.generation, 1)
        XCTAssertEqual(m.files.first { $0.name == backupLibraryDatabaseName }?.chunks.count, 4)
        XCTAssertEqual(m.format, BackupFormat.current)
        XCTAssertEqual(m.librarySchema, 2)

        let target = MemoryFiles()
        let back = await e.restore(settings: BackupSettings(), into: target, replaceLibrary: false)
        XCTAssertEqual(back.status, .idle)
        XCTAssertEqual(target.get(.library, backupLibraryDatabaseName), db)
        XCTAssertEqual(target.get(.library, "metadata/a.json"), Data("{\"a\":1}".utf8))
        XCTAssertEqual(target.get(.artwork, "artwork/p.png"), bytes(5_000, seed: 2))
        XCTAssertEqual(target.writes.first, backupLibraryDatabaseName, "the index is restored first")
    }

    func testTheSecondBackupUploadsOnlyTheChangedChunksAndTheSizeIsMeasured() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        var db = bytes(BackupFormat.chunkSize * 4, seed: 3)
        files.put(.library, backupLibraryDatabaseName, db)
        let e = engine(cloud, files, codec: RLECodec())
        _ = try await e.backUp(.library)
        db[BackupFormat.chunkSize * 2 + 7] ^= 0x55          // one page in the third chunk changes
        files.put(.library, backupLibraryDatabaseName, db)
        let r = try await e.backUp(.library)
        XCTAssertEqual(r.uploadedChunks, 1, "only the changed chunk is uploaded")
        XCTAssertEqual(r.reusedChunks, 3)
        XCTAssertEqual(cloud.manifestGeneration(.library), 2)
        let usage = try await e.usage()
        let mFound = try await e.currentManifest(.library)
        let m = try XCTUnwrap(mFound)
        XCTAssertEqual(usage[.library], m.totalStoredBytes)
        XCTAssertEqual(m.totalStoredBytes, m.storedBytes.values.reduce(0, +))
        XCTAssertGreaterThan(m.totalStoredBytes, 0)
        // Generation 1's replaced chunk is kept for one more generation, then removed.
        db[7] ^= 0x55
        files.put(.library, backupLibraryDatabaseName, db)
        let r3 = try await e.backUp(.library)
        XCTAssertEqual(r3.deletedChunks, 1)
        XCTAssertEqual(cloud.chunkCount, 5, "the 4 current chunks + generation 2's replaced first chunk; generation 1's old third chunk is gone")
    }

    func testAnInterruptedBackupResumesWithoutUploadingTheSameChunksAgainAndNeverSavesAHalfManifest() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(BackupFormat.chunkSize * 5, seed: 4))
        cloud.inject(.upload, .networkUnavailable, after: 3)
        let e = engine(cloud, files)
        let r = await e.backUp(settings: BackupSettings(library: true, artwork: false))
        XCTAssertEqual(r.status, .offline)
        XCTAssertNil(cloud.manifestGeneration(.library), "no manifest points at missing chunks")
        XCTAssertEqual(cloud.chunkCount, 3)
        let again = try await e.backUp(.library)
        XCTAssertEqual(again.uploadedChunks, 2)
        XCTAssertEqual(again.reusedChunks, 3)
        XCTAssertEqual(cloud.manifestGeneration(.library), 1)
    }

    func testAChunkThatArrivesDamagedIsFetchedAgainAndADamagedChunkTwiceStopsTheRestoreWithoutWritingAnything() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        let db = bytes(BackupFormat.chunkSize * 2, seed: 5)
        files.put(.library, backupLibraryDatabaseName, db)
        let e = engine(cloud, files)
        _ = try await e.backUp(.library)
        let hashFound = try await e.currentManifest(.library)?.files.first?.chunks.last
        let hash = try XCTUnwrap(hashFound)

        cloud.corruptChunk(hash, times: 1)
        let ok = MemoryFiles()
        _ = try await e.restore(.library, into: ok, replaceLibrary: false)
        XCTAssertEqual(ok.get(.library, backupLibraryDatabaseName), db)

        cloud.corruptChunk(hash, times: 2)
        let bad = MemoryFiles()
        let e2 = engine(cloud, files, staging: "staging2")
        do { _ = try await e2.restore(.library, into: bad, replaceLibrary: false); XCTFail("must fail") }
        catch { XCTAssertEqual(error as? BackupError, .checksumMismatch(hash)) }
        XCTAssertNil(bad.get(.library, backupLibraryDatabaseName), "nothing half-restored is written")
    }

    func testAFullICloudStopsTheLibraryBackupButArtworkLeavesOutTheLargestPicturesAndSaysSo() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.artwork, "artwork/small.png", bytes(1_000, seed: 6))
        files.put(.artwork, "artwork/medium.png", bytes(5_000, seed: 7))
        files.put(.artwork, "artwork/large.png", bytes(50_000, seed: 8))
        cloud.quotaBytes = 20_000
        let e = engine(cloud, files)
        let art = try await e.backUp(.artwork)
        XCTAssertEqual(Set(art.skipped.map(\.name)), ["artwork/large.png"])
        XCTAssertEqual(art.skipped.first?.reason, .iCloudFull)
        let mFound = try await e.currentManifest(.artwork)
        let m = try XCTUnwrap(mFound)
        XCTAssertEqual(m.files.map(\.name), ["artwork/medium.png", "artwork/small.png"])
        XCTAssertEqual(m.skipped.count, 1)
        XCTAssertNotNil(BackupStatusText.skippedLine(m.skipped))

        files.put(.library, backupLibraryDatabaseName, bytes(100_000, seed: 9))
        let r = await e.backUp(settings: BackupSettings(library: true, artwork: false))
        XCTAssertEqual(r.status, .iCloudFull)
        XCTAssertNil(cloud.manifestGeneration(.library))
        XCTAssertEqual(BackupStatusText.line(.iCloudFull).contains("iCloud storage is full"), true)
    }

    func testSignedOutSendsNothingAndSaysSo() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(10, seed: 1))
        cloud.setAccount(.noAccount)
        let e = engine(cloud, files)
        let r = await e.backUp(settings: BackupSettings())
        XCTAssertEqual(r.status, .signedOut)
        XCTAssertEqual(cloud.calls(.upload), 0)
        XCTAssertEqual(cloud.calls(.fetchManifest), 0)
        let back = await e.restore(settings: BackupSettings(), into: MemoryFiles(), replaceLibrary: true)
        XCTAssertEqual(back.status, .signedOut)
    }

    func testABackupFromANewerAppVersionIsNeitherRestoredNorOverwritten() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(10, seed: 1))
        let newer = BackupManifest(format: BackupFormat.current + 1, set: .library, generation: 9, createdAt: Date(), librarySchema: 2,
                                   files: [], storedBytes: [:], previousChunks: [], skipped: [])
        cloud.replaceManifest(.library, generation: 9, data: try newer.encoded())
        let e = engine(cloud, files)
        let r = await e.backUp(settings: BackupSettings(library: true, artwork: false))
        XCTAssertEqual(r.status, .newerBackup)
        XCTAssertEqual(cloud.manifestGeneration(.library), 9)
        let back = await e.restore(settings: BackupSettings(), into: MemoryFiles(), replaceLibrary: true)
        XCTAssertEqual(back.status, .newerBackup)

        // Same for a newer library database schema with the current format.
        let schemaNewer = BackupManifest(set: .library, generation: 10, createdAt: Date(), librarySchema: 3, files: [], storedBytes: [:], previousChunks: [], skipped: [])
        cloud.replaceManifest(.library, generation: 10, data: try schemaNewer.encoded())
        let target = MemoryFiles()
        let back2 = await e.restore(settings: BackupSettings(), into: target, replaceLibrary: true)
        XCTAssertEqual(back2.status, .newerBackup)
        XCTAssertTrue(target.writes.isEmpty)
    }

    func testAnInterruptedRestoreResumesFromTheChunksItAlreadyCheckedAndAppliesNothingUntilComplete() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        let db = bytes(BackupFormat.chunkSize * 6, seed: 10)
        files.put(.library, backupLibraryDatabaseName, db)
        let e = engine(cloud, files)
        _ = try await e.backUp(.library)
        cloud.inject(.download, .networkUnavailable, after: 4)
        let target = MemoryFiles()
        let first = await e.restore(settings: BackupSettings(library: true, artwork: false), into: target, replaceLibrary: false)
        XCTAssertEqual(first.status, .offline)
        XCTAssertNil(target.get(.library, backupLibraryDatabaseName))
        let second = try await e.restore(.library, into: target, replaceLibrary: false)
        XCTAssertEqual(second.resumedChunks, 4)
        XCTAssertEqual(second.downloadedChunks, 2)
        XCTAssertEqual(target.get(.library, backupLibraryDatabaseName), db)
        // Idempotent: restoring again changes nothing (the library is no longer empty, so the index is kept).
        let third = try await e.restore(.library, into: target, replaceLibrary: false)
        XCTAssertEqual(third.restoredFiles, 0)
        XCTAssertEqual(third.keptNewerLocal, 1)
    }

    func testNewerLocalFilesAreKeptAndOlderOnesAreReplaced() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, "matches.json", Data("backup".utf8), modified: Date(timeIntervalSince1970: 1_000))
        files.put(.library, "metadata/x.json", Data("backup-x".utf8), modified: Date(timeIntervalSince1970: 1_000))
        let e = engine(cloud, files)
        _ = try await e.backUp(.library)
        let target = MemoryFiles()
        target.put(.library, "matches.json", Data("edited later here".utf8), modified: Date(timeIntervalSince1970: 5_000))
        target.put(.library, "metadata/x.json", Data("older".utf8), modified: Date(timeIntervalSince1970: 10))
        let r = try await e.restore(.library, into: target, replaceLibrary: true)
        XCTAssertEqual(r.keptNewerLocal, 1)
        XCTAssertEqual(target.get(.library, "matches.json"), Data("edited later here".utf8), "the newest edit wins")
        XCTAssertEqual(target.get(.library, "metadata/x.json"), Data("backup-x".utf8))
    }

    func testTheSwitchesDecideWhatIsUploadedAndWhatIsRestored() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(100, seed: 1))
        files.put(.artwork, "artwork/a.png", bytes(100, seed: 2))
        files.put(.artwork, "artwork/orphan.png", bytes(100, seed: 3))
        files.notInLibrary = ["artwork/orphan.png"]
        let e = engine(cloud, files)

        _ = await e.backUp(settings: BackupSettings(library: true, artwork: false))
        XCTAssertNotNil(cloud.manifestGeneration(.library))
        XCTAssertNil(cloud.manifestGeneration(.artwork), "nothing from a switched-off set is uploaded")
        XCTAssertEqual(cloud.uploads.count, 1)

        let cloud2 = InMemoryBackupCloud()
        let e2 = engine(cloud2, files)
        _ = await e2.backUp(settings: BackupSettings(library: false, artwork: true, artworkLibraryOnly: true))
        XCTAssertNil(cloud2.manifestGeneration(.library))
        let mFound = try await e2.currentManifest(.artwork)
        let m = try XCTUnwrap(mFound)
        XCTAssertEqual(m.files.map(\.name), ["artwork/a.png"])
        XCTAssertEqual(m.skipped.map(\.reason), [.notInLibrary])
        XCTAssertEqual(cloud2.uploads.count, 1)

        let target = MemoryFiles()
        _ = await e.restore(settings: BackupSettings(library: false, artwork: true), into: target, replaceLibrary: true)
        XCTAssertTrue(target.writes.isEmpty, "the library switch is off, and there is no artwork backup in this cloud")
    }

    func testIdenticalPicturesAreStoredOnce() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        let picture = bytes(3_000, seed: 4)
        files.put(.artwork, "artwork/one/poster.png", picture)
        files.put(.artwork, "artwork/two/poster.png", picture)
        let e = engine(cloud, files)
        let r = try await e.backUp(.artwork)
        XCTAssertEqual(r.uploadedChunks, 1)
        XCTAssertEqual(cloud.chunkCount, 1)
    }

    func testNoPasswordTokenOrAPIKeyCanBeUploaded() async throws {
        let password = "hunter2-source-password", token = "tok_9f8e7d6c5b4a", apiKey = "0123456789abcdef0123456789abcdef"
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, Data("ordinary library pages".utf8))
        files.put(.library, "metadata/answer.json", Data("{\"overview\":\"a film\"}".utf8))
        let e = engine(cloud, files, forbidden: [password, token, apiKey])
        let ok = await e.backUp(settings: BackupSettings())
        XCTAssertEqual(ok.status, .idle)
        for payload in cloud.uploadedPayloads + cloud.savedManifests {
            for secret in [password, token, apiKey] { XCTAssertNil(payload.range(of: Data(secret.utf8)), "a secret reached iCloud") }
        }

        // A file that somehow holds a secret stops the whole backup before anything of it is sent.
        let leaky = MemoryFiles()
        leaky.put(.library, backupLibraryDatabaseName, Data("pages ... \(token) ...".utf8))
        let cloud2 = InMemoryBackupCloud()
        let e2 = engine(cloud2, leaky, forbidden: [password, token, apiKey])
        let r = await e2.backUp(settings: BackupSettings())
        guard case .failed = r.status else { return XCTFail("expected failed, got \(r.status)") }
        XCTAssertEqual(cloud2.uploads.count, 0)
        XCTAssertNil(cloud2.manifestGeneration(.library))
    }

    func testProgressIsReportedAndTheTextsUseTheRealNames() async throws {
        let cloud = InMemoryBackupCloud(), files = MemoryFiles()
        files.put(.library, backupLibraryDatabaseName, bytes(BackupFormat.chunkSize * 2, seed: 1))
        let statuses = Locked<[BackupStatus]>([])
        let e = engine(cloud, files, statuses: statuses)
        _ = await e.backUp(settings: BackupSettings(library: true, artwork: false))
        let seen = statuses.with { $0 }
        XCTAssertTrue(seen.contains(.backingUp(BackupProgress(set: .library, done: 2, total: 2))))
        XCTAssertEqual(seen.last, .idle)
        XCTAssertTrue(BackupStatusText.storageNote.contains("iCloud"))
        XCTAssertTrue(BackupStatusText.line(.signedOut).contains("iCloud"))
        XCTAssertEqual(BackupStatusText.size(1_500_000), "1.5 MB")
        XCTAssertEqual(BackupStatusText.size(999), "999 bytes")
    }
}

final class BackupSchedulerTests: XCTestCase {
    func testManyLibraryChangesSettleIntoOneBackupAndALaunchBacksUpOnlyWhenTheLastOneIsOld() async throws {
        let count = Locked(0)
        let s = BackupScheduler(sleep: { _ in try await Task.sleep(nanoseconds: 20_000_000) }, run: { count.with { $0 += 1 } })
        for _ in 0..<50 { await s.libraryChanged() }
        await s.waitForPending()
        XCTAssertEqual(count.with { $0 }, 1)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        await s.appLaunched(lastSuccess: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(count.with { $0 }, 1, "a recent backup is not repeated at launch")
        await s.appLaunched(lastSuccess: now.addingTimeInterval(-2 * 86_400), now: now)
        XCTAssertEqual(count.with { $0 }, 2)
        await s.appLaunched(lastSuccess: nil, now: now)
        await s.backUpNow()
        XCTAssertEqual(count.with { $0 }, 4)
    }
}

final class Locked<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ v: T) { value = v }
    func with<R>(_ body: (inout T) -> R) -> R { lock.withLock { body(&value) } }
}
