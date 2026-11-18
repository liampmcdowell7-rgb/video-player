import Foundation
import UserData

/// Backs up and restores the generated library data (docs/BACKUP.md). One actor, so a backup and a restore never run at
/// the same time. Low priority work: the caller runs it in a background task; nothing here blocks the UI or playback.
///
/// Backup of one set:
///  1. account check (signed out: nothing is sent);
///  2. read the current manifest (a newer format is never overwritten);
///  3. for each file (smallest first, so if iCloud fills up it is the largest that are left out): read, refuse if it
///     contains a password, token or API key, cut into 1 MiB chunks, name each by its SHA-256, upload only the chunks
///     the cloud does not have (incremental, and resumable: an interrupted run leaves uploaded chunks behind);
///  4. save the new manifest (generation + 1) only when every chunk it lists is uploaded, so a manifest never points at
///     a missing chunk;
///  5. delete chunks no longer used by this generation, the previous one, or the other set.
/// Restore of one set: read the manifest once; download each chunk into a staging folder (kept across an interruption),
/// check its SHA-256 (download again once on a mismatch), join, check the file's SHA-256, then write. Newer local files
/// are kept (merge rule). The library database is restored only into an empty library, unless the user asked.
public actor BackupEngine {
    private let cloud: any BackupCloud
    private let codec: any BackupCodec
    private let content: any BackupContent
    private let staging: URL
    private let clock: @Sendable () -> Date
    private let forbidden: @Sendable () -> [String]
    private let maxFileBytes: [BackupSet: Int]
    private let onStatus: @Sendable (BackupStatus) -> Void
    private let codecs: [String: any BackupCodec]
    private let sleep: @Sendable (Double) async throws -> Void

    /// - forbidden: the secrets that must never leave the device (source passwords and tokens, API keys). Checked on
    ///   every file before upload; strings shorter than 4 characters are not checked (they would match by chance).
    /// - maxFileBytes: files larger than this are left out and reported (default: no limit for library, 20 MB artwork).
    public init(cloud: any BackupCloud, codec: any BackupCodec = IdentityCodec(), extraCodecs: [any BackupCodec] = [],
                content: any BackupContent, staging: URL, clock: @escaping @Sendable () -> Date = { Date() },
                forbidden: @escaping @Sendable () -> [String],
                maxFileBytes: [BackupSet: Int] = [.artwork: 20_000_000],
                sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                onStatus: @escaping @Sendable (BackupStatus) -> Void = { _ in }) {
        self.sleep = sleep
        self.cloud = cloud
        self.codec = codec
        self.content = content
        self.staging = staging
        self.clock = clock
        self.forbidden = forbidden
        self.maxFileBytes = maxFileBytes
        self.onStatus = onStatus
        var all: [String: any BackupCodec] = [IdentityCodec().id: IdentityCodec()]
        for c in extraCodecs + [codec] { all[c.id] = c }
        self.codecs = all
    }

    // MARK: Status mapping

    /// The status the Backup screen shows for an error (also used by the app for restore errors).
    public static func status(for error: Error) -> BackupStatus {
        switch error {
        case BackupError.cloud(let e), let e as UDCloudError:
            switch e {
            case .notAuthenticated: return .signedOut
            case .quotaExceeded: return .iCloudFull
            case .networkUnavailable: return .offline
            default: return .failed(BackupStatusText.describe(e))
            }
        case BackupError.newerBackup: return .newerBackup
        case let e as BackupError: return .failed(BackupStatusText.describe(e))
        default: return .failed(String(describing: error))
        }
    }

    private func checkAccount() async throws {
        switch await cloud.accountStatus() {
        case .available: return
        case .noAccount, .restricted: throw BackupError.cloud(.notAuthenticated)
        case .unknown: throw BackupError.cloud(.networkUnavailable)
        }
    }

    /// One cloud call. "Too many requests" (`requestRateLimited`, `zoneBusy`) waits the time the server gives (or 2, 4, 6 s)
    /// and tries again, up to 3 times, as Apple's error pages say (docs/BACKUP.md); every other error is passed on.
    private func call<T>(_ body: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do { return try await body() } catch let e as UDCloudError {
                if case .rateLimited(let after) = e, attempt < 3 {
                    attempt += 1
                    try? await sleep(after ?? Double(2 * attempt))
                    continue
                }
                throw BackupError.cloud(e)
            }
        }
    }

    private func manifest(_ set: BackupSet) async throws -> BackupManifest? {
        guard let data = try await call({ try await cloud.fetchManifest(set) }) else { return nil }
        guard let m = try? BackupManifest.decode(data) else { throw BackupError.local("the \(set.rawValue) backup in iCloud could not be read") }
        return m
    }

    // MARK: Backup

    /// Backs up every set the switches include. The report's status is the first problem met, or idle.
    public func backUp(settings: BackupSettings) async -> BackupReport {
        var total = BackupReport()
        for set in BackupSet.allCases where settings.includes(set) {
            do {
                let r = try await backUp(set, settings: settings)
                total.uploadedChunks += r.uploadedChunks
                total.reusedChunks += r.reusedChunks
                total.deletedChunks += r.deletedChunks
                total.skipped += r.skipped
            } catch {
                total.status = Self.status(for: error)
                onStatus(total.status)
                return total
            }
        }
        total.finishedAt = clock()
        onStatus(.idle)
        return total
    }

    public func backUp(_ set: BackupSet, settings: BackupSettings = BackupSettings()) async throws -> BackupReport {
        try await checkAccount()
        let old = try await manifest(set)
        if let old, old.format > BackupFormat.current {
            throw BackupError.newerBackup(format: old.format, librarySchema: old.librarySchema)
        }
        var report = BackupReport()
        let listed = try await content.files(for: set, settings: settings)
        report.skipped = listed.skipped
        var files = listed.files.sorted { ($0.size, $0.name) < ($1.size, $1.name) }
        if let limit = maxFileBytes[set] {
            for f in files where f.size > limit { report.skipped.append(BackupSkip(name: f.name, size: f.size, reason: .tooLarge)) }
            files.removeAll { $0.size > limit }
        }
        let secrets = forbidden().filter { $0.count >= 4 }.map { Data($0.utf8) }
        var known = old?.chunkSet ?? []
        var storedBytes: [String: Int] = [:]
        var entries: [BackupFileEntry] = []
        let totalChunks = files.reduce(0) { $0 + max(1, ($1.size + BackupFormat.chunkSize - 1) / BackupFormat.chunkSize) }
        var done = 0
        var iCloudFull = false
        onStatus(.backingUp(BackupProgress(set: set, done: 0, total: totalChunks)))

        for file in files {
            if iCloudFull {
                report.skipped.append(BackupSkip(name: file.name, size: file.size, reason: .iCloudFull))
                continue
            }
            let data = try await file.load()
            for s in secrets where data.range(of: s) != nil { throw BackupError.secretDetected(file.name) }
            var hashes: [String] = []
            var pieces: [(String, Data)] = []
            var offset = 0
            repeat {
                let end = min(offset + BackupFormat.chunkSize, data.count)
                let piece = data.subdata(in: data.startIndex + offset ..< data.startIndex + end)
                let hash = BackupSHA256.hex(piece)
                hashes.append(hash)
                pieces.append((hash, piece))
                offset = end
            } while offset < data.count
            let unknown = Array(Set(hashes).subtracting(known))
            let present = unknown.isEmpty ? [] : try await call { try await cloud.existingChunks(unknown) }
            do {
                for (hash, piece) in pieces {
                    if known.contains(hash) || present.contains(hash) {
                        if storedBytes[hash] == nil {
                            if let measured = old?.storedBytes[hash] {
                                storedBytes[hash] = measured
                            } else {
                                storedBytes[hash] = try codec.compress(piece).count
                            }
                            report.reusedChunks += 1
                        }
                    } else {
                        let packed = try codec.compress(piece)
                        try await call { try await cloud.uploadChunk(hash, codec: codec.id, data: packed) }
                        storedBytes[hash] = packed.count
                        known.insert(hash)
                        report.uploadedChunks += 1
                    }
                    done += 1
                    onStatus(.backingUp(BackupProgress(set: set, done: done, total: totalChunks)))
                }
            } catch BackupError.cloud(.quotaExceeded) where set == .artwork {
                // Artwork degrades: this file and every larger one is left out and reported; the backup still finishes
                // with what fits. The library set is all-or-nothing.
                iCloudFull = true
                report.skipped.append(BackupSkip(name: file.name, size: file.size, reason: .iCloudFull))
                continue
            }
            known.formUnion(hashes)
            entries.append(BackupFileEntry(name: file.name, size: data.count, modified: file.modified, chunks: hashes, sha256: BackupSHA256.hex(data)))
        }

        let next = BackupManifest(
            set: set, generation: (old?.generation ?? 0) + 1, createdAt: clock(),
            librarySchema: set == .library ? await content.librarySchema() : 0,
            files: entries.sorted { $0.name < $1.name }, storedBytes: storedBytes,
            previousChunks: (old?.chunkSet ?? []).sorted(), skipped: report.skipped.sorted { $0.name < $1.name }
        )
        let encoded = try next.encoded()
        for s in secrets where encoded.range(of: s) != nil { throw BackupError.secretDetected("manifest") }
        try await call { try await cloud.saveManifest(set, generation: next.generation, data: encoded) }

        // Clean-up: never fatal (a leftover chunk costs space, not correctness).
        if let old {
            var keep = next.chunkSet.union(old.chunkSet)
            for other in BackupSet.allCases where other != set {
                if let m = try? await manifest(other) { keep.formUnion(m.chunkSet); keep.formUnion(m.previousChunks) }
            }
            let stale = Set(old.previousChunks).subtracting(keep)
            if !stale.isEmpty, (try? await cloud.deleteChunks(stale.sorted())) != nil { report.deletedChunks = stale.count }
        }
        report.finishedAt = clock()
        return report
    }

    // MARK: Restore

    /// Restores the sets the switches include, library first. `replaceLibrary` is true only when the user chose
    /// "Restore from iCloud" and confirmed; the automatic restore after a purge passes false (it restores the database
    /// only when the library is empty). `priority` orders files (lower first): the app puts the pictures of the Home rows first.
    public func restore(settings: BackupSettings, into target: any BackupRestoreTarget, replaceLibrary: Bool,
                        priority: @escaping @Sendable (BackupSet, String) -> Int = { _, _ in 0 }) async -> BackupReport {
        var total = BackupReport()
        for set in BackupSet.allCases where settings.includes(set) {
            do {
                let r = try await restore(set, into: target, replaceLibrary: replaceLibrary, priority: priority)
                total.downloadedChunks += r.downloadedChunks
                total.resumedChunks += r.resumedChunks
                total.restoredFiles += r.restoredFiles
                total.keptNewerLocal += r.keptNewerLocal
            } catch BackupError.nothingToRestore {
                continue
            } catch {
                total.status = Self.status(for: error)
                onStatus(total.status)
                return total
            }
        }
        total.finishedAt = clock()
        onStatus(.idle)
        return total
    }

    public func restore(_ set: BackupSet, into target: any BackupRestoreTarget, replaceLibrary: Bool,
                        priority: @escaping @Sendable (BackupSet, String) -> Int = { _, _ in 0 }) async throws -> BackupReport {
        try await checkAccount()
        guard let m = try await manifest(set) else { throw BackupError.nothingToRestore }
        if m.format > BackupFormat.current || m.librarySchema > target.supportedLibrarySchema {
            throw BackupError.newerBackup(format: m.format, librarySchema: m.librarySchema)
        }
        var report = BackupReport()
        let restoreDatabase = replaceLibrary ? true : await target.libraryIsEmpty()
        var plan: [BackupFileEntry] = []
        for f in m.files {
            if set == .library && f.name == backupLibraryDatabaseName {
                if restoreDatabase { plan.append(f) } else { report.keptNewerLocal += 1 }
                continue
            }
            // Merge rule: the newest edit wins. A local file newer than the backed-up one is kept.
            if let local = await target.localModified(set, name: f.name), local > f.modified {
                report.keptNewerLocal += 1
                continue
            }
            plan.append(f)
        }
        plan.sort {
            let a = ($0.name == backupLibraryDatabaseName ? -1 : priority(set, $0.name), $0.name)
            let b = ($1.name == backupLibraryDatabaseName ? -1 : priority(set, $1.name), $1.name)
            return a < b
        }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let total = plan.reduce(0) { $0 + $1.chunks.count }
        var done = 0
        onStatus(.restoring(BackupProgress(set: set, done: 0, total: total)))
        for file in plan {
            var joined = Data()
            joined.reserveCapacity(file.size)
            for hash in file.chunks {
                joined.append(try await chunk(hash, report: &report))
                done += 1
                onStatus(.restoring(BackupProgress(set: set, done: done, total: total)))
            }
            guard BackupSHA256.hex(joined) == file.sha256 else { throw BackupError.checksumMismatch(file.name) }
            try await target.write(set, name: file.name, data: joined, modified: file.modified)
            report.restoredFiles += 1
        }
        // Every file is in place: the staged chunks of this set are no longer needed.
        for hash in Set(plan.flatMap(\.chunks)) { try? FileManager.default.removeItem(at: staging.appendingPathComponent(hash)) }
        report.finishedAt = clock()
        return report
    }

    /// A chunk's content, from the staging folder when an earlier (interrupted) restore already fetched and checked it.
    private func chunk(_ hash: String, report: inout BackupReport) async throws -> Data {
        let staged = staging.appendingPathComponent(hash)
        if let data = try? Data(contentsOf: staged), BackupSHA256.hex(data) == hash {
            report.resumedChunks += 1
            return data
        }
        for attempt in 0..<2 {
            let (codecID, packed) = try await call { try await cloud.downloadChunk(hash) }
            guard let c = codecs[codecID] else { throw BackupError.local("unknown compression \(codecID)") }
            let data = (try? c.decompress(packed, expectedSize: BackupFormat.chunkSize)) ?? Data()
            if BackupSHA256.hex(data) == hash {
                try data.write(to: staged, options: .atomic)
                report.downloadedChunks += 1
                return data
            }
            if attempt == 1 { break }
        }
        throw BackupError.checksumMismatch(hash)
    }

    // MARK: Size

    /// The space the backup uses in iCloud, per set, measured: the compressed size of every chunk each manifest lists,
    /// recorded at upload (a chunk shared by both sets is counted once, under library).
    public func usage() async throws -> [BackupSet: Int] {
        var seen = Set<String>()
        var out: [BackupSet: Int] = [:]
        for set in BackupSet.allCases {
            guard let m = try await manifest(set) else { out[set] = 0; continue }
            var bytes = 0
            for (hash, n) in m.storedBytes where !seen.contains(hash) { seen.insert(hash); bytes += n }
            out[set] = bytes
        }
        return out
    }

    /// The manifest of a set as last read from iCloud (for the screen: last backup time, skipped files).
    public func currentManifest(_ set: BackupSet) async throws -> BackupManifest? {
        try await checkAccount()
        return try await manifest(set)
    }
}
