import Foundation
import Observation
import UserData
import LibraryIndex
import LibraryBackup
import AppLogic

/// Connects the iCloud backup of generated data (docs/BACKUP.md) to the app: the three switches, the schedule, the status
/// the Backup screen shows, and the automatic restore before the start-up sync. Every decision is in `BackupEngine` and
/// `BackupScheduler` (tested in WSL against an in-memory fake); this class only stores choices and passes calls on.
@MainActor
@Observable
final class BackupHost {
    private(set) var status: BackupStatus = .idle
    private(set) var lastSuccess: Date?
    private(set) var lastProblem: String?
    private(set) var skippedLine: String?
    private(set) var usage: [BackupSet: Int] = [:]
    /// True while the automatic restore after a cleanup runs (the "Restoring your library from iCloud" banner).
    private(set) var isAutoRestoring = false
    private(set) var isWorking = false
    /// Set when iCloud cannot be used at all by this copy of the app; the screen shows it and nothing is backed up or restored.
    private(set) var unavailableReason: String?
    /// False once the launch scan has started without waiting for iCloud (launch time-box, OPEN_QUESTIONS R169): from then
    /// on the automatic restore of an empty library is not started, so it never writes the database under a running scan.
    /// "Restore from iCloud" in Settings still works.
    @ObservationIgnored var automaticRestoreAllowed = true
    /// The automatic restore of the library DATABASE while it runs (the pictures that follow are not part of it).
    @ObservationIgnored private var libraryRestore: Task<Bool, Never>?

    /// True while the automatic restore is writing the library database.
    var isRestoringLibraryDatabase: Bool { libraryRestore != nil }

    /// Returns when the automatic restore of the library database has finished (at once when none runs). The pictures may
    /// still be arriving; they do not touch the database.
    func libraryDatabaseRestoreFinished() async {
        _ = await libraryRestore?.value
    }

    var settings: BackupSettings {
        didSet { Self.save(settings) }
    }

    @ObservationIgnored private let store: SQLiteLibraryStore
    @ObservationIgnored private let files: LibraryBackupFiles
    @ObservationIgnored private let engine: BackupEngine
    @ObservationIgnored private var scheduler: BackupScheduler!

    private static let lastSuccessKey = "vp.backup.lastSuccess"
    /// Set while a picture restore has not finished, so the next launch resumes it.
    private static let artworkPendingKey = "vp.backup.artworkRestorePending"

    /// - forbidden: every source password or token and every API key, read at the time of each backup (never stored).
    /// - matchFile: the Fix Match choices (Application Support).
    /// - cloud: the CloudKit adapter (container made on first use), or the in-memory one in a UI-test mode.
    init(store: SQLiteLibraryStore, cloud: any BackupCloud, matchFile: URL, forbidden: @escaping @Sendable () -> [String]) {
        self.store = store
        self.settings = Self.loadSettings()
        self.lastSuccess = UserDefaults.standard.object(forKey: Self.lastSuccessKey) as? Date
        let caches = ArtworkFolders.caches
        let files = LibraryBackupFiles(
            store: store,
            workDir: caches.appendingPathComponent("backup-work", isDirectory: true),
            libraryFolders: [FolderBackupStore(root: ArtworkFolders.metadata, prefix: "metadata")],
            libraryFiles: ["matches.json": matchFile],
            artwork: FolderBackupStore(root: ArtworkFolders.sidecars, prefix: "artwork"),
            artworkNamesInLibrary: { [store] in
                // A cached picture belongs to the library when it is the cached copy of a picture file the index still holds
                // (same key function as the artwork engine), so old copies and pictures of removed sources are left out.
                guard let images = try? await store.indexedImageFiles() else { return nil }
                return Set(images.map { Self.backupName(of: $0) })
            })
        self.files = files
        let box = BackupStatusBox()
        self.engine = BackupEngine(cloud: cloud, codec: LZFSECodec(), content: files,
                                   staging: caches.appendingPathComponent("backup-staging", isDirectory: true),
                                   forbidden: forbidden, onStatus: { box.deliver($0) })
        box.onMain = { [weak self] new in self?.status = new }
        self.scheduler = BackupScheduler(run: { [weak self] in await self?.runBackup() })
    }

    /// iCloud cannot be used (no iCloud capability in this copy of the app): no backup, no restore, the reason on the screen.
    func markCloudUnavailable(_ reason: String) {
        unavailableReason = reason
        lastProblem = reason
        isAutoRestoring = false
    }

    // MARK: Triggers (never background sync, decision D8)

    /// After a scan or another library change: backs up 2 minutes after the last change.
    func libraryChanged() {
        Task(priority: .background) { await scheduler.libraryChanged() }
    }

    /// At launch: backs up when the last successful backup is more than a day old.
    func appLaunched() {
        let last = lastSuccess
        Task(priority: .background) { await scheduler.appLaunched(lastSuccess: last, now: Date()) }
    }

    /// "Back Up Now".
    func backUpNow() {
        Task(priority: .utility) { await scheduler.backUpNow() }
    }

    private func runBackup() async {
        let chosen = settings
        // Never while a restore is filling the folders (the backup would record a half-restored set); the next trigger runs it.
        guard unavailableReason == nil, chosen.library || chosen.artwork, !isAutoRestoring, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let report = await engine.backUp(settings: chosen)
        skippedLine = BackupStatusText.skippedLine(report.skipped)
        if report.status == .idle, let finished = report.finishedAt {
            lastSuccess = finished
            lastProblem = nil
            UserDefaults.standard.set(finished, forKey: Self.lastSuccessKey)
        } else {
            lastProblem = BackupStatusText.line(report.status)
        }
        status = report.status
        await refreshUsage()
    }

    // MARK: Restore

    /// Before the start-up sync. When the library switch is on and the index is empty (a cleanup, a reinstall, a new Apple
    /// TV), brings the library back from iCloud instead of rescanning. True when the index now holds the library.
    /// The pictures follow in the background, the Home-row posters first.
    func restoreIfLibraryIsEmpty() async -> Bool {
        guard unavailableReason == nil else { return false }
        guard settings.library, (try? await store.isEmptyLibrary()) ?? false else {
            // The index came back on an earlier launch but the pictures did not finish (the app was quit): resume them.
            // Verified pieces are still staged, so only what is missing is downloaded.
            if settings.artwork, UserDefaults.standard.bool(forKey: Self.artworkPendingKey) {
                isAutoRestoring = true
                Task(priority: .utility) {
                    await restoreArtwork()
                    isAutoRestoring = false
                }
            }
            return false
        }
        // Checked after the await above and set by the launch on the main actor too, so the two cannot interleave.
        guard automaticRestoreAllowed else { return false }
        isAutoRestoring = true
        let databaseRestore = Task { await restoreLibrary(replace: false) }
        libraryRestore = databaseRestore
        let restored = await databaseRestore.value
        libraryRestore = nil
        if restored, settings.artwork {
            Task(priority: .utility) {
                await restoreArtwork()
                isAutoRestoring = false
            }
        } else {
            isAutoRestoring = false
        }
        return restored
    }

    /// "Restore from iCloud", after the user confirmed. Replaces the library index on this Apple TV; newer local files are
    /// kept, and `afterLibrary` puts the newest watch state and saved views from the user-data ledger back on top of the
    /// restored index (newest edit wins) before the pictures follow.
    func restoreNow(afterLibrary: @escaping @MainActor () async -> Void) {
        guard unavailableReason == nil else { return }
        Task(priority: .utility) {
            isWorking = true
            defer { isWorking = false }
            if settings.library, await restoreLibrary(replace: true) { await afterLibrary() }
            if settings.artwork { await restoreArtwork() }
        }
    }

    private func restoreLibrary(replace: Bool) async -> Bool {
        do {
            _ = try await engine.restore(.library, into: files, replaceLibrary: replace)
            lastProblem = nil
        } catch BackupError.nothingToRestore {
            return false
        } catch {
            status = BackupEngine.status(for: error)
            lastProblem = BackupStatusText.line(status)
            return false
        }
        status = .idle
        return !((try? await store.isEmptyLibrary()) ?? true)
    }

    private func restoreArtwork() async {
        // The posters of the Home rows first, so the first screen fills in before the rest of the pictures arrive.
        let home = await homeArtworkNames()
        UserDefaults.standard.set(true, forKey: Self.artworkPendingKey)
        do {
            _ = try await engine.restore(.artwork, into: files, replaceLibrary: false, priority: { _, name in home.contains(name) ? 0 : 1 })
            status = .idle
            UserDefaults.standard.removeObject(forKey: Self.artworkPendingKey)
        } catch BackupError.nothingToRestore {
            status = .idle
            UserDefaults.standard.removeObject(forKey: Self.artworkPendingKey)
        } catch {
            status = BackupEngine.status(for: error)
            lastProblem = BackupStatusText.line(status)
        }
    }

    /// The cached pictures of the folders that hold the Home rows' videos (and the show folder above a season folder),
    /// which is where the artwork engine finds their posters.
    private func homeArtworkNames() async -> Set<String> {
        let now = Date()
        var items: [LibraryItem] = []
        items += (try? await store.continueWatching(limit: 30, now: now, retentionDays: SettingsKey.defaultContinueWatchingDays)) ?? []
        items += (try? await store.recentlyAdded(limit: 30, kind: nil)) ?? []
        var folders = Set<String>()
        for item in items {
            for file in (try? await store.versions(of: item.id)) ?? [] {
                folders.insert(file.sourceID + "|" + file.parentPath)
                let up = file.parentPath.split(separator: "/").dropLast()
                folders.insert(file.sourceID + "|" + (up.isEmpty ? "/" : "/" + up.joined(separator: "/")))
            }
        }
        let images = (try? await store.indexedImageFiles()) ?? []
        return Set(images.filter { folders.contains($0.sourceID + "|" + $0.parent) }.map { Self.backupName(of: $0) })
    }

    /// The name of a picture's cached copy inside the backup's artwork set.
    nonisolated static func backupName(of image: IndexedImageFile) -> String {
        "artwork/" + ArtworkDiskCache.name(forKey: ArtworkEngine.sidecarCacheKey(sourceID: image.sourceID, path: image.path,
                                                                                size: image.size, modified: image.modified, etag: nil))
    }

    // MARK: Screen

    func refreshUsage() async {
        guard unavailableReason == nil else { return }
        if let measured = try? await engine.usage() { usage = measured }
    }

    var totalSize: Int { usage.values.reduce(0, +) }

    // MARK: Settings (this Apple TV only)

    private static func loadSettings() -> BackupSettings {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }
        return BackupSettings(library: flag("vp.backup.library", true), artwork: flag("vp.backup.artwork", true),
                              artworkLibraryOnly: flag("vp.backup.artworkLibraryOnly", false), userData: true)
    }

    private static func save(_ s: BackupSettings) {
        let d = UserDefaults.standard
        d.set(s.library, forKey: "vp.backup.library")
        d.set(s.artwork, forKey: "vp.backup.artwork")
        d.set(s.artworkLibraryOnly, forKey: "vp.backup.artworkLibraryOnly")
    }
}

/// Carries a status from the engine's actor to the main actor without capturing `self` across isolation.
private final class BackupStatusBox: @unchecked Sendable {
    var onMain: (@MainActor (BackupStatus) -> Void)?
    func deliver(_ status: BackupStatus) {
        let callback = onMain
        Task { @MainActor in callback?(status) }
    }
}
