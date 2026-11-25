import SwiftUI
import Observation
import os
import VideoPlayerCore
import LibraryIndex
import UserData
import AppLogic
import LibraryBackup
import SourcePlex

/// What the player is asked to start (an item, from the beginning or from its saved place).
struct PlayRequest: Identifiable, Equatable {
    let id = UUID()
    let itemID: Int64
    let fromStart: Bool
}

/// #15 8.1: a title that could not be played. The player closes and the page it was started from stays as it was, under a
/// system alert with the reason, "Try Again" (when trying again can help) and "Done".
struct PlayFailurePrompt: Identifiable {
    let id = UUID()
    let failure: PlaybackFailure
    let request: PlayRequest
}

/// The one place the app's long-lived parts are built and held, handed to every screen through the environment.
/// Screens receive plain protocols and view models; none of them builds a database or a network client.
@MainActor
@Observable
final class AppServices {
    let sqlite: SQLiteLibraryStore
    let ledger: UserDataLedger
    let essentials: UDEssentialsStore
    let secrets: MirroredSecrets
    let cloud: any UserDataCloud
    /// The Apple-only parts (iCloud, App Group, Keychain), or their stand-ins in a UI-test mode (launch safety).
    let dependencies: AppDependencies
    let connector: any SourceConnecting
    /// Which sources are refused for a changed certificate or host key (SOURCES, docs/SOURCES_WIRING.md).
    let trust: TrustCenter
    /// Builds the live object for every source kind; the one place that applies the approved fingerprints.
    let sourceFactory: SourceFactory
    /// Online lookups, built only from the keys the user entered (artwork, Fix Match, Discover). ARTWORK.
    let online: OnlineServices
    /// iCloud (CloudKit) sync of the user-data ledger: schedule and honest status (Settings > Storage and iCloud). ARTWORK.
    let sync: CloudSyncHost
    /// The start-up sequence (restore after a cleanup, rebuild a lost ledger, then sync). Run once by `startCloudSync()`.
    let ledgerWasLost: Bool
    let syncEngine: UserDataSyncEngine
    /// True when the library database could not be opened and was created again (shown as "Rebuilding").
    let databaseWasRebuilt: Bool
    /// iCloud backup of the generated data (Settings > Backup, docs/BACKUP.md).
    let backup: BackupHost
    /// Two-way watch state with Plex servers whose source has the switch on (R306 b, R309).
    let watchSync: ServerWatchSync
    /// R471 (16): a rating also goes to Plex while the source's two-way sync switch is on (path UNVERIFIED).
    let ratingSender: ServerRatingSender

    var libraryRevision = 0
    /// R459: Restrictions are on (read from this device's settings; Discover and online suggestions are off meanwhile).
    private(set) var restrictionsOn = ParentalKeys.read().enabled
    /// R471 (17): raised on every change to the user's lists, so the menus and My Lists read the ledger again.
    private(set) var listsRevision = 0
    /// R460: the rating pass is running (the page shows it and the Read Ratings button waits).
    private(set) var isReadingRatings = false
    /// R459: the passcode and its lockout, in this device's Keychain.
    @ObservationIgnored let parental = ParentalPIN(store: KeychainPINStore())
    var pendingLink: DeepLink?
    var playRequest: PlayRequest?
    /// #21 F: a page a long-press menu asked for ("Go to Movie", "Go to Show"). RootView pushes it on the current tab's stack.
    var openRequest: Route?
    var playFailure: PlayFailurePrompt?
    var isScanning = false
    /// Folders done and still queued in the running scan (the one-time re-sort runs inside a scan, addendum #18 F); nil when
    /// no scan runs. Shown with a system ProgressView in Settings > Library and Needs Review.
    var scanProgress: ScanProgress?
    var accountStatus: UDAccountStatus = .unknown
    var secretState: CloudSecretState = .signedOut
    var passwordsNeeded = 0
    /// Set when iCloud cannot be used at all by this copy of the app (no iCloud capability); shown in Settings. Everything
    /// is then kept on this Apple TV only: no sync, no backup, no restore.
    var cloudUnavailable: String?

    var store: any LibraryStore { sqlite }

    init(dependencies: AppDependencies? = nil) {
        // The ledger comes first: the library store is opened with its recorder already in place (below), so not one
        // watch-state or saved-view change can happen before it is recorded. (`setRecorder` is actor-isolated and cannot be
        // called from this synchronous main-actor init; first compile, 2026-11-17.)
        #if DEBUG
        // UI-test launches (screenshots) start from a clean state; nothing happens in a normal launch or in Release.
        UITestMode.resetPersistentState()
        #endif
        // Built before anything else and touching nothing Apple-only: the CloudKit container is made on the first iCloud call.
        let dependencies = dependencies ?? AppDependencies.forThisLaunch()
        self.dependencies = dependencies
        let defaults = UserDefaults.standard
        let deviceKey = "vp.deviceID"
        let deviceID = defaults.string(forKey: deviceKey) ?? UUID().uuidString.lowercased()
        defaults.set(deviceID, forKey: deviceKey)
        let ledger = UserDataLedger(deviceID: deviceID)
        let essentials = UDEssentialsStore(store: UserDefaultsKeyValueStore())
        essentials.restore(into: ledger)
        // R309: the recorder also tells the Plex watch sync about watched and unwatched changes (the sync is set up below).
        let recorder = ServerWatchRecorder(wrapping: LedgerRecorder(ledger: ledger))

        let caches = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
        let databaseURL = caches.appendingPathComponent("library.sqlite")
        var rebuilt = false
        var opened: SQLiteLibraryStore?
        do {
            opened = try SQLiteLibraryStore(path: databaseURL.path, recorder: recorder)
        } catch {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databaseURL.path + suffix) }
            rebuilt = true
            opened = try? SQLiteLibraryStore(path: databaseURL.path, recorder: recorder)
        }
        // An in-memory database only fails to open if SQLite itself is broken; there is nothing better to fall back to.
        self.sqlite = opened ?? (try! SQLiteLibraryStore(path: ":memory:", recorder: recorder))
        self.databaseWasRebuilt = rebuilt

        self.ledger = ledger
        self.essentials = essentials
        self.cloud = dependencies.userDataCloud
        let secrets = MirroredSecrets(local: dependencies.credentials, cloud: dependencies.secretCloud)
        let trust = TrustCenter()
        self.secrets = secrets
        self.trust = trust
        self.sourceFactory = SourceFactory(secrets: secrets, ledger: ledger, trust: trust, deviceID: deviceID)
        self.connector = LiveSourceConnector(deviceID: deviceID)
        // ARTWORK: online lookups and the ledger sync. The saved ledger file replaces what the essentials copy restored above
        // (it is newer); when it is missing or damaged the essentials copy stays and the bootstrap rebuilds from the database.
        let sqliteStore = self.sqlite
        let factory = self.sourceFactory
        // `SourceFactory` is main-actor isolated (it reads the secrets and the trust list), and this closure is a plain
        // `@Sendable async` one, so the call hops to the main actor with `await` (first compile, 2026-11-17).
        let sourceFor: @Sendable (String) async -> (any MediaSource)? = { @Sendable [ledger, factory] (sourceID: String) async -> (any MediaSource)? in
            guard let definition = ledger.sourceDefinitions().first(where: { $0.id == sourceID }) else { return nil }
            return await factory.makeSource(definition)
        }
        let reader = SourceSidecarReader(sourceFor: sourceFor)
        self.ratingSender = ServerRatingSender(
            store: sqliteStore,
            isOn: { @Sendable [ledger] sourceID in ledger.sourceDefinitions().first { $0.id == sourceID }.map(PlexWatchSyncOption.isOn) ?? false },
            source: { @Sendable sourceID in await sourceFor(sourceID) as? any ServerWatchSource })
        // R309: watch state goes to a Plex server only while its source's "Sync Watched Status with Plex" switch is on.
        let watchSync = ServerWatchSync(
            store: sqliteStore,
            isOn: { @Sendable [ledger] sourceID in ledger.sourceDefinitions().first { $0.id == sourceID }.map(PlexWatchSyncOption.isOn) ?? false },
            source: { @Sendable sourceID in await sourceFor(sourceID) as? any ServerWatchSource },
            // R310: writes wait here while their server cannot be reached (no token or address in the file; not synced).
            queue: ServerWatchQueue(storage: FileServerWatchQueueStorage(url: Self.watchQueueURL)),
            resetTime: { @Sendable [ledger] key in
                let epoch = UDWatch.epoch(of: ledger.record(type: UDSchema.watch, id: key))
                return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil
            })
        self.watchSync = watchSync
        recorder.setHandler { watchSync.send(.changed($0)) }
        Task { await watchSync.run() }
        // #26 item 2: one app-wide key store, its own Keychain items plus the encrypted iCloud copy; keys an earlier version
        // kept with the source passwords are moved there at start-up (OnlineKeyStore.migrateLegacy).
        let keyStore = OnlineKeyStore(secrets: MirroredSecrets(local: dependencies.keyCredentials, cloud: dependencies.secretCloud),
                                      legacy: dependencies.credentials)
        keyStore.migrateLegacy()
        // R307: Plex's own synopsis and poster come first for Plex files; every other source keeps its order.
        // R381: Fix Match choices also go into the ledger, so the iCloud sync keeps them (CloudMatchStore).
        self.online = OnlineServices(keys: keyStore, store: sqliteStore, reader: reader, server: PlexServerMetadata(sourceFor: sourceFor),
                                     ledger: ledger)
        // The backup refuses any file that holds one of these: every source password or token and every API key, read
        // from protected storage at the time of each backup and never written anywhere (docs/BACKUP.md "Secrets").
        self.backup = BackupHost(store: sqliteStore, cloud: dependencies.backupCloud, matchFile: OnlineServices.matchFileURL, forbidden: { @Sendable [ledger, secrets, keyStore] () -> [String] in
            // #29: typed steps.
            var values: [String] = []
            for definition in ledger.sourceDefinitions() {
                if let secret: String = secrets.secret(for: definition.id) { values.append(secret) }
            }
            let keys: [String] = keyStore.allValues()
            values.append(contentsOf: keys)
            return values
        })
        let engine = UserDataSyncEngine(ledger: ledger, cloud: self.cloud)
        self.syncEngine = engine
        let host = CloudSyncHost(ledger: ledger, engine: engine)
        self.ledgerWasLost = host.loadLedgerFile()
        self.sync = host
        #if DEBUG
        // UI-test modes: iCloud is off, and Settings says so (no CloudKit object exists in these modes).
        if UITestMode.current != .off { applyCloudGate() }
        #endif
    }

    /// Asks the gate whether iCloud can be used (the first call makes the CloudKit container, after the first frame) and,
    /// when it cannot, switches sync and backup off with the reason. True when iCloud can be used.
    @discardableResult
    func applyCloudGate() -> Bool {
        guard let reason = dependencies.cloudUnavailable() else { return true }
        cloudUnavailable = reason.reason
        accountStatus = .unknown
        sync.markCloudUnavailable(reason.reason)
        backup.markCloudUnavailable(reason.reason)
        return false
    }

    // MARK: Sources

    var definitions: [UDSourceDefinition] { ledger.sourceDefinitions() }

    var definitionSaver: any SourceDefinitionSaving { LedgerSourceDefinitions(ledger: ledger, essentials: essentials) }

    func makeSource(_ definition: UDSourceDefinition) -> (any MediaSource)? { sourceFactory.makeSource(definition) }

    func sourceAdded() {
        libraryRevision += 1
        Task { await scanAll() }
    }

    /// Scans every source. A call while a scan runs waits for that scan instead of returning at once, so a caller that needs
    /// the finished index (the start-up rebuild of a lost database, R169) never goes on with a half-scanned one.
    func scanAll() async {
        if let running = scanTask { await running.value; return }
        let task = Task { @MainActor in
            isScanning = true
            await scanSources()
            // Signal d (docs/SORTING.md): with the user's own key, Needs Review files are checked online once per launch;
            // anything it moves is filed by one more scan. Without a TMDB key `sortLookup` is nil and nothing is sent
            // (OnlineSortPass, tested in SortingLogicTests).
            let pass = await OnlineSortPass.run(store: sqlite, lookup: online.sortLookup, writer: ledger, tried: onlineSortTried)
            onlineSortTried.formUnion(pass.checked)
            if !pass.saved.isEmpty { await scanSources() }
            isScanning = false
            scanProgress = nil
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: LastScan.key)
            libraryRevision += 1
            backup.libraryChanged()
            await writeTopShelf()
            // R460: while Restrictions are on, a new title is read for its rating by this scan, so it does not wait hidden
            // for the button (the lists are read again when the reading ends).
            if restrictionsOn { await readRatings() }
        }
        // Stored before the first suspension: this method and the task body both run on the main actor, so the body cannot
        // start before the handle is here, and a later cancel always finds it. The syncer reads `Task.isCancelled` at every
        // folder, which stays set, so even a cancel that came first is not lost (addendum #19 B). The app has no cancel
        // control for a scan today.
        scanTask = task
        await task.value
        scanTask = nil
    }

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Needs Review files already checked online in this launch (not sent again until the next launch).
    @ObservationIgnored private var onlineSortTried: Set<String> = []

    /// One pass over every source. Each file is sorted on its own (docs/SORTING.md): Move choices come from the ledger,
    /// the source's "Sort by filename" setting is applied, and every decision is logged (category "Sorting").
    private func scanSources() async {
        let overrides = LedgerSortOverrides(ledger: ledger)
        let log = Self.sortLogger
        for definition in definitions {
            guard let source = makeSource(definition) else { continue }
            let syncer = LibrarySyncer(store: sqlite, source: source, sourceID: definition.id, overrides: overrides,
                                       preferFilename: SortSourceOption.preferFilename(definition),
                                       sortLog: { path, outcome, signal, note in
                                           log.debug("sorted \(outcome.rawValue, privacy: .public) by \(signal.rawValue, privacy: .public): \(path, privacy: .private) (\(note, privacy: .public))")
                                       })
            // Runs off the main thread (the store is an actor); only the progress numbers come back to the screen.
            // #23 D: weak at the outer closure too, so the progress closure itself never holds AppServices strongly.
            let summary = try? await syncer.sync(progress: { [weak self] p in Task { @MainActor [weak self] in self?.scanProgress = p } })
            guard summary?.status == .completed else { continue }
            if PlexWatchSyncOption.isOn(definition) {
                // R310: with the switch on, the app's and the server's watch state are merged after every complete scan
                // (what waited for the server is sent first); the newer change wins.
                watchSync.send(.merge(sourceID: definition.id))
            } else if PlexWatchSeed.isNeeded(for: definition), let plex = source as? PlexClient {
                await seedPlexWatchState(plex, definition: definition)
            }
        }
    }

    /// R306 (sources with the R309 switch off): after the first complete scan of a Plex source, the server's watched and resume
    /// state is copied once into the app's own watch state, only where the app has none. Nothing is ever sent to the server. The source is marked
    /// seeded only when the copy succeeded, so a failure is tried again after the next scan.
    private func seedPlexWatchState(_ plex: PlexClient, definition: UDSourceDefinition) async {
        guard let items = try? await plex.serverItems() else { return }
        let states = items.mapValues {
            PlexWatchSeed.ServerState(positionSeconds: $0.viewOffsetSeconds, viewCount: $0.viewCount, lastViewedAt: $0.lastViewedAt,
                                      durationSeconds: $0.metadata.runtimeSeconds.map(Double.init))
        }
        // What came from the server is not sent back to it (R309).
        let seed = PlexWatchSeed(store: sqlite, files: sqlite)
        let copied = await ServerWatchEcho.$suppressed.withValue(true) {
            (try? await seed.seed(sourceID: definition.id, statesByPath: states)) != nil
        }
        guard copied else { return }
        try? await definitionSaver.saveDefinition(PlexWatchSeed.markedDone(definition))
    }

    /// R310: the file of writes waiting for a Plex server, next to the library database (Caches: the system may delete it;
    /// the merge after the next scan then still sends the app's newer state).
    nonisolated static var watchQueueURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("plex-watch-queue.json")
    }

    private static let sortLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VideoPlayer", category: "Sorting")

    // MARK: Sorting (docs/SORTING.md)

    var sortMover: SortMover { SortMover(store: sqlite, writer: ledger) }

    /// After a Move choice: the list and counts change at the next scan, which is started here.
    func sortChoiceSaved() {
        libraryRevision += 1
        Task { await rescanAfterSortChange() }
    }

    /// Saves the source's "Sort by Filename" setting and sorts again.
    func setSortByFilename(_ on: Bool, for definition: UDSourceDefinition) async {
        try? await definitionSaver.saveDefinition(SortSourceOption.setting(on, on: definition))
        libraryRevision += 1
        await rescanAfterSortChange()
    }

    /// Saves the Plex source's "Sync Watched Status with Plex" switch (R309). It takes effect at the next change sent.
    func setPlexWatchSync(_ on: Bool, for definition: UDSourceDefinition) async {
        try? await definitionSaver.saveDefinition(PlexWatchSyncOption.setting(on, on: definition))
        libraryRevision += 1
    }

    // MARK: Library page and source page (R458)

    /// The library's one rule of which titles show: hidden sources (R458) and the rating rule of Parental Controls (R459).
    /// Restrictions that are on stay on when the passcode record is gone (the rule fails closed).
    func applyRestrictions() async {
        var settings = ParentalKeys.read()
        if settings.enabled, settings.scaleRegion == nil {
            // R460: Restrictions that were turned on before the rating system was stored keep today's system from now on.
            settings = settings.pinningScale(region: online.region)
            UserDefaults.standard.set(settings.scaleRegion, forKey: ParentalKeys.scale)
        }
        restrictionsOn = settings.enabled
        await sqlite.setRestrictions(LibraryRestrictions(hiddenSourceIDs: HideSourceOption.hiddenIDs(definitions),
                                                         ratings: settings.rule(region: online.region)))
    }

    // MARK: Parental Controls (R459)

    /// Saves the Parental Controls settings on this device only (never the user data) and applies them everywhere at once:
    /// every list, Continue Watching and Next Up, and the Top Shelf are read again.
    func setParental(_ requested: ParentalSettings) async {
        let defaults = UserDefaults.standard
        let wasOn = restrictionsOn
        var settings = requested
        // R460: the rating system is stored when Restrictions are turned on (the lookup region's at that moment) and is
        // forgotten when they are turned off, so the next time starts from the region again.
        if settings.enabled { settings = settings.pinningScale(region: online.region) } else if wasOn { settings.scaleRegion = nil }
        if let region = settings.scaleRegion { defaults.set(region, forKey: ParentalKeys.scale) } else { defaults.removeObject(forKey: ParentalKeys.scale) }
        defaults.set(settings.enabled, forKey: ParentalKeys.enabled)
        defaults.set(settings.allowUnrated, forKey: ParentalKeys.allowUnrated)
        if let tier = settings.movieTier { defaults.set(tier, forKey: ParentalKeys.movieTier) } else { defaults.removeObject(forKey: ParentalKeys.movieTier) }
        if let tier = settings.episodeTier { defaults.set(tier, forKey: ParentalKeys.episodeTier) } else { defaults.removeObject(forKey: ParentalKeys.episodeTier) }
        await applyRestrictions()
        libraryRevision += 1
        await writeTopShelf()
        // R460: turning Restrictions on starts reading the ratings of the titles already there, in the background.
        if settings.enabled, !wasOn { Task { _ = await readRatings() } }
    }

    /// R460: reads the rating of every title that has none kept yet and shows the lists again. One reading at a time; a second
    /// call while one runs returns 0 at once.
    @discardableResult
    func readRatings() async -> Int {
        guard !isReadingRatings else { return 0 }
        isReadingRatings = true
        let found = await online.readRatings()
        isReadingRatings = false
        libraryRevision += 1
        await writeTopShelf()
        return found
    }

    /// R460: the number of titles with no usable rating (the page's "Titles Without a Rating").
    func unratedTitleCount() async -> Int { (try? await sqlite.unratedCount()) ?? 0 }

    func setSourceHidden(_ hidden: Bool, for definition: UDSourceDefinition) async {
        try? await definitionSaver.saveDefinition(HideSourceOption.setting(hidden, on: definition))
        await applyRestrictions()
        libraryRevision += 1
        await writeTopShelf()
    }

    func renameSource(_ text: String, for definition: UDSourceDefinition) async {
        guard SourceRename.cleaned(text) != nil else { return }
        try? await definitionSaver.saveDefinition(SourceRename.setting(text, on: definition))
        libraryRevision += 1
    }

    /// Reads the first 8 MB of one video file of the source and returns the speed as text. Nothing is written.
    func speedTest(_ definition: UDSourceDefinition) async -> String {
        var filter = ItemFilter()
        filter.sourceID = definition.id
        guard let items = try? await sqlite.page(ItemQuery(filter: filter), limit: 1, offset: 0), let item = items.first,
              let files = try? await sqlite.versions(of: item.id), let file = files.first(where: { $0.sourceID == definition.id }),
              let range = SpeedTest.range(fileSize: file.size),
              let reader = try? await sourceFactory.byteReader(for: file) else { return "No video file to read" }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let data = try await reader.read(ByteRange(offset: range.lowerBound, length: range.upperBound - range.lowerBound))
            let seconds = ProcessInfo.processInfo.systemUptime - started
            return SpeedTest.text(SpeedTest.megabitsPerSecond(bytes: Int64(data.count), seconds: seconds))
        } catch {
            return "The file could not be read"
        }
    }

    /// Refresh Metadata for every source (nil) or one. The online answers are fetched again the next time a title is shown.
    func refreshMetadata(sourceID: String?) async {
        await online.refreshMetadata(sourceID: sourceID)
        libraryRevision += 1
    }

    /// A scan already running may have passed the changed file; one more scan then picks the change up.
    private func rescanAfterSortChange() async {
        let wasRunning = isScanning
        await scanAll()
        if wasRunning { await scanAll() }
    }

    // MARK: Launch (time-boxed, OPEN_QUESTIONS R169)

    /// Everything a normal launch does after the first frame. The screens already show the library from the database on this
    /// Apple TV; nothing here holds them up. The iCloud part (account status, the restore of an empty library, the start-up
    /// sync) runs in the background; the launch scan waits for it at most `TimeBox.launchWait` seconds and then starts anyway,
    /// while the iCloud part finishes on its own. One exception: while a restore is writing the (empty) library database, the
    /// scan waits for that part of the restore only, because both would write the same database; the restore banner is on
    /// screen meanwhile. If the restore has not started when the box runs out, it is not started at all (Settings > Restore).
    func launch(scanOnLaunch: Bool) async {
        Task { await refreshCloudStatus() }
        await applyRestrictions()
        // R457: every completed sync reconciles the settings (own edits first, then the newest values).
        sync.onSynced = { [weak self] in self?.reconcileSettings() }
        let cloud = Task { await startCloudSync() }
        let finishedInTime = await TimeBox.wait(atMost: TimeBox.launchWait) { await cloud.value } != nil
        guard scanOnLaunch else { return }
        if !finishedInTime {
            if backup.isRestoringLibraryDatabase {
                // Only the database part is waited for, not the pictures and not the start-up sync after it.
                await backup.libraryDatabaseRestoreFinished()
            } else {
                // The restore has not started: it must not start later under the scan (it would replace the database).
                backup.automaticRestoreAllowed = false
            }
        }
        await scanAll()
    }

    func removeSource(id: String) async {
        try? await store.removeSource(id: id)
        ledger.removeSource(id: id)
        try? essentials.save(from: ledger)
        _ = try? await secrets.remove(sourceID: id)
        trust.clear(sourceID: id)
        libraryRevision += 1
        backup.libraryChanged()
        await writeTopShelf()
    }

    // MARK: Cloud status

    func refreshCloudStatus() async {
        guard applyCloudGate() else {
            passwordsNeeded = CredentialGap.sourcesNeedingPassword(definitions, store: secrets.local).count
            return
        }
        accountStatus = await cloud.accountStatus()
        let report = await secrets.reconcile(sourceIDs: definitions.map(\.id))
        secretState = report.state
        passwordsNeeded = CredentialGap.sourcesNeedingPassword(definitions, store: secrets.local).count
    }

    // MARK: Top Shelf

    /// Writes the snapshot the Top Shelf extension reads, and the picture files it names (ARTWORK). A picture comes from a file
    /// next to the video first, then from the matched online poster when a key is entered; an item with no picture is left out
    /// by the extension. The folder is not durable storage (the system may delete it); it is written again after every scan.
    func writeTopShelf() async {
        // The App Group folder, checked before use; without it (no App Group in this build) there is simply no Top Shelf.
        guard let folder = dependencies.sharedFolder() else { return }
        let days = UserDefaults.standard.integer(forKey: SettingsKey.continueWatchingDays.rawValue)
        let builder = TopShelfBuilder(store: store)
        guard let result = try? await builder.build(retentionDays: days > 0 ? days : SettingsKey.defaultContinueWatchingDays) else { return }
        let shelf = folder.appendingPathComponent("TopShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        var written = Set<String>()
        for art in result.artwork {
            guard let bytes = await online.artworkBytes(key: art.key) else { continue }
            if (try? bytes.write(to: shelf.appendingPathComponent(art.file), options: .atomic)) != nil { written.insert(art.file) }
        }
        // Items whose picture could not be found are left out, so the shelf never names a file that is not there.
        var snapshot = result.snapshot
        snapshot.items = snapshot.items.filter { written.contains($0.imageFile) }
        try? TopShelfSnapshotStore.write(snapshot, to: shelf)
        // Pictures of items no longer on the shelf are removed.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: shelf.path)) ?? []
        for name in names where name.hasSuffix(".jpg") && !written.contains(name) {
            try? FileManager.default.removeItem(at: shelf.appendingPathComponent(name))
        }
    }

    // MARK: Cloud sync of the ledger

    /// Runs the start-up sequence once (restore after a cleanup, rebuild a lost ledger, merge with the cloud), then keeps syncing.
    /// Safe to call on every launch of the root screen; later calls do nothing.
    func startCloudSync() async {
        await online.reconcileKeys()
        // No iCloud in this copy of the app: local only (no restore, no sync, no backup); Settings shows the reason.
        guard applyCloudGate() else { return }
        let target = LibraryRestoreAdapter(store: sqlite, deviceID: ledger.deviceID, scan: { [weak self] in await self?.scanAll() })
        let bootstrap = LibraryBootstrap(ledger: ledger, engine: syncEngine, essentials: essentials, credentials: secrets.local)
        let lost = ledgerWasLost
        var health: UDDatabaseHealth = databaseWasRebuilt ? .missing : .ok
        // An empty index (a cleanup, a reinstall, a new Apple TV) comes back from the iCloud backup BEFORE the user-data
        // merge, so the newest watch state is applied on top of it and no rebuild is needed (docs/BACKUP.md "Merge rule").
        if await backup.restoreIfLibraryIsEmpty() {
            health = .ok
            libraryRevision += 1
        }
        backup.appLaunched()
        // #23 D: the start-up closure is @Sendable; it captures this constant, not the `var` above (which Swift reports as
        // "reference to captured var 'health' in concurrently-executing code").
        let startupHealth = health
        await sync.start(startupSync: {
            if let report = try? await bootstrap.run(health: startupHealth, ledgerWasLost: lost, target: target) { return report }
            var failed = UDSyncReport()
            failed.status = .failed("The start-up sync did not finish.")
            return failed
        })
        // R456: settings another device (or a restore) set arrive with the user data.
        reconcileSettings()
    }

    /// After "Restore from iCloud" replaced the index: merges with iCloud and loads the ledger's watch state and saved views
    /// into the restored index again (the healthy-database path of the bootstrap, which is idempotent), then reloads screens.
    func reapplyUserData() async {
        let target = LibraryRestoreAdapter(store: sqlite, deviceID: ledger.deviceID, scan: { [weak self] in await self?.scanAll() })
        let bootstrap = LibraryBootstrap(ledger: ledger, engine: syncEngine, essentials: essentials, credentials: secrets.local)
        _ = try? await bootstrap.run(health: .ok, ledgerWasLost: false, target: target)
        reconcileSettings()
        await applyRestrictions()
        libraryRevision += 1
    }

    // MARK: Playback

    /// Finds and opens the file for one item. R311: `tracker` follows the steps (the player screen's time limit and the
    /// "Last Playback Problem" row in Settings > Playback say which step a failure happened in).
    func resolvePlayback(itemID: Int64, fromStart: Bool, tracker: PlaybackStartTracker? = nil) async throws -> ResolvedPlayback {
        tracker?.enter(.findFile)
        guard let item = try await store.item(id: itemID) else { throw PlaybackError.noFile }
        let files = try await store.versions(of: itemID)
        // R458: Settings > Playback > Play Version; a version chosen on the page always wins. Ask is asked on the page, so any
        // other place plays Auto.
        let versionMode = PlayVersion(rawValue: UserDefaults.standard.string(forKey: PlayVersion.key) ?? "") ?? .auto
        guard let file = PlayVersion.pick(files, explicit: item.preferredFileID, mode: versionMode) ?? files.first else { throw PlaybackError.noFile }
        // R313: the error's first line names the episode ("Show · S1, E3 · Name"); nil for a film.
        tracker?.itemLine = PlayerEpisodeText.errorLine(for: item)
        let definition = definitions.first(where: { $0.id == file.sourceID })
        tracker?.describe(sourceKind: definition?.kindTitle,
                          container: PlaybackStartTracker.containerName(fileName: file.name),
                          codecs: PlaybackStartTracker.codecText([file.technical?.videoCodec, file.technical?.audioCodec]))
        #if DEBUG
        // #21 E: in fixture mode one sample file plays a generated clip (screenshots of the player). Not in Release.
        tracker?.enter(.prepareSample)
        let clip: URL? = UITestClip.standsIn(for: file) ? try await UITestClip.url() : nil
        #else
        let clip: URL? = nil
        #endif
        // MKV and the other containers the converting player opens go through it (PLAYBACK); the rest is refused with the reason.
        tracker?.enter(.checkFormat)
        let route = PlaybackRoute.route(fileName: file.name)
        if clip == nil, case .unsupported(let failure) = route { throw failure }
        // R305: a Plex file the Apple TV cannot decode is refused here with one sentence; the server never converts.
        tracker?.enter(.checkServer)
        if clip == nil, let format = await plexConversionNeeded(file) {
            throw PlaybackFailures.needsServerConversion(formatName: format)
        }
        let location: URL
        var headers: [String: String] = [:]
        var remux: RemuxPlayback?
        if let clip {
            location = clip
            tracker?.setPath(.sample)
            tracker?.reach(.fileOpened, detail: "Sample clip")
        } else if route == .remux {
            tracker?.enter(.openConverter)
            // R390: converted playback; the file counts as opened once its header is read, the loopback once it serves.
            tracker?.setPath(.converted)
            let opened = try await RemuxPlayback.open(reader: try await sourceFactory.byteReader(for: file),
                                                      fileOpened: { tracker?.reach(.fileOpened, detail: "Header read by the converting player") })
            remux = opened
            location = opened.url
            tracker?.reach(.loopbackReady)
            tracker?.describe(codecs: PlaybackStartTracker.codecText([opened.info.videoCodecString] + opened.info.audio.map(\.codecString)))
        } else {
            tracker?.enter(.getLink)
            guard let definition, let source = makeSource(definition) else {
                throw PlaybackError.sourceUnavailable
            }
            let access = try await source.playbackAccess(for: file.path)
            guard case .url(let url, let accessHeaders) = access else { throw PlaybackError.notReadable }
            location = url
            headers = accessHeaders
            // The header values (a server token) never reach the stored problem text.
            tracker?.describe(secrets: Array(accessHeaders.values))
            // R390: direct playback; the system player opens the link itself, so "opened" here means the link is known.
            tracker?.setPath(.direct)
            tracker?.reach(.fileOpened, detail: "Link from the source")
        }
        tracker?.enter(.readSegments)
        let card = CardBuilder.card(item)
        let content = NowPlayingContent(kind: item.kind == .movie ? .movie : .episode, title: card.title, seriesTitle: item.seriesTitle,
                                        season: item.season, episode: item.episode, year: item.year, artworkKey: card.artworkKey)
        // R458: Settings > Playback > Resume Playback. Off starts at the beginning; Start Over and a watched title do too.
        let resumeOn = UserDefaults.standard.object(forKey: ResumeRule.key) as? Bool ?? true
        let resume = ResumeRule.startPosition(saved: item.watch.position, watched: item.watch.watched, fromStart: fromStart, resume: resumeOn)
        let segments = await segmentService.segments(forItem: itemID)
        // R313: an episode's transport bar (and so its Info tab and Now Playing entry) reads name over "Show · S1, E3".
        let lines = PlayerEpisodeText.lines(for: item, filmTitle: card.title, filmSubtitle: item.seriesTitle)
        var resolved = ResolvedPlayback(url: location, headers: headers, title: lines.title, subtitle: lines.subtitle, startAt: resume,
                                        duration: item.runtime ?? item.watch.duration, content: content)
        resolved.segments = segments
        resolved.remux = remux
        resolved.file = file
        resolved.ratingKey = PlayerRating.detailsKey(for: item)
        // R380: the rating already on hand, no request: Plex's from the listing its client holds, else the library's own.
        resolved.startRating = PlayerRating.atStart(sourceRating: await online.heldSourceRating(for: file),
                                                    storedRating: item.contentRating)
        return resolved
    }

    /// The video format a Plex file would need converted, from what the server said about it (nil for every other source,
    /// and when the server cannot be asked: the player then reports its own error).
    private func plexConversionNeeded(_ file: StoredFile) async -> String? {
        guard let definition = definitions.first(where: { $0.id == file.sourceID }), definition.sourceKind == .plex,
              let plex = makeSource(definition) as? PlexClient else { return nil }
        return (try? await plex.conversionNeeded(at: file.path)) ?? nil
    }
}

// MARK: Library actions used by context menus

extension AppServices {
    func setWatched(_ itemID: Int64, _ watched: Bool) async {
        try? await store.markWatched(itemIDs: [itemID], watched: watched, at: Date())
        libraryRevision += 1
    }

    /// R471 (23): Mark All as Watched or Unwatched from a long press, for a whole show (`season` nil) or one season; the
    /// same store call the show page makes.
    func setSeriesWatched(_ seriesID: Int64, season: Int?, watched: Bool) async {
        try? await store.markSeries(seriesID: seriesID, season: season, watched: watched, at: Date())
        libraryRevision += 1
    }

    /// R471 (23): the online id most of a show's episodes carry (nil before a match), for the show's edit keys from a long
    /// press. The show page reads one episode's id, which is the same whenever the episodes agree.
    func showOnlineID(seriesID: Int64) async -> Int? {
        let ids: [Int] = ((try? await store.episodes(ofSeries: seriesID)) ?? []).compactMap(\.tmdbID)
        return Dictionary(grouping: ids, by: { $0 }).max(by: { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key })?.key
    }

    func setFavorite(_ itemID: Int64, _ favorite: Bool) async {
        try? await store.setFavorite(itemID: itemID, favorite: favorite)
        libraryRevision += 1
    }

    /// R471 (14): Unmatch a movie or a whole show (after the confirmation); the pages reload on the revision.
    func unmatch(_ target: Unmatcher.Target) async {
        _ = try? await Unmatcher(store: store, ledger: ledger, forgetter: online.forgetter).run(target)
        libraryRevision += 1
    }

    /// R471 (16): Rate. The stars go into the user layer under the title's first key; a movie's or an episode's files also
    /// send it to Plex where the source's sync switch is on (`itemIDs` empty for a show or a season: the app only).
    func rate(keys: [UDEditKey], itemIDs: [Int64], stars: Int?) async {
        guard let key = keys.first else { return }
        ledger.setRating(key, stars: stars)
        if !itemIDs.isEmpty { await ratingSender.send(itemIDs: itemIDs, stars: stars) }
    }

    /// R471 (15): Delete from Library (after the confirmation); the files stay on the source. Off while Restrictions are on.
    func removeFromLibrary(_ target: LibraryRemover.Target) async {
        guard !restrictionsOn else { return }
        _ = try? await LibraryRemover(store: store, ledger: ledger).run(target)
        libraryRevision += 1
    }

    /// R471 (15): Settings > Library > Removed from Library: the record goes, and the next scan adds the file again.
    func restoreToLibrary(_ removal: UDLibraryRemoval) async {
        ledger.restoreToLibrary(sourceID: removal.sourceID, path: removal.path)
        libraryRevision += 1
        await scanAll()
    }

    // MARK: R471 (17): the user's own lists

    func userLists(kinds: Set<UDUserList.Kind>) -> [UDUserList] {
        _ = listsRevision
        return ledger.userLists(kinds: kinds)
    }

    func userList(id: String) -> UDUserList? {
        _ = listsRevision
        return ledger.userList(id: id)
    }

    func listEntries(_ listID: String) -> [UDUserListEntry] {
        _ = listsRevision
        return ledger.listEntries(listID)
    }

    @discardableResult
    func createList(name: String, kind: UDUserList.Kind) -> UDUserList? {
        defer { listsRevision += 1 }
        return ledger.createList(name: name, kind: kind)
    }

    func renameList(_ list: UDUserList, to name: String) {
        ledger.renameList(id: list.id, to: name)
        listsRevision += 1
    }

    func deleteList(_ list: UDUserList) {
        ledger.deleteList(id: list.id)
        listsRevision += 1
    }

    func addToList(_ list: UDUserList, ref: UDTitleRef, title: String) {
        ledger.addToList(list.id, ref: ref, title: title)
        listsRevision += 1
    }

    func removeFromList(_ list: UDUserList, ref: UDTitleRef) {
        ledger.removeFromList(list.id, ref: ref)
        listsRevision += 1
    }

    /// A page's menu: adds the title, or removes it when the list holds it already.
    func toggleList(_ list: UDUserList, ref: UDTitleRef, title: String) {
        if ledger.listIDs(containing: ref).contains(list.id) { removeFromList(list, ref: ref) } else { addToList(list, ref: ref, title: title) }
    }

    func titleRef(itemID: Int64, kind: ItemKind) async -> UDTitleRef? { await sqlite.titleRef(itemID: itemID, kind: kind) }
    func titleRef(seriesID: Int64) async -> UDTitleRef? { await sqlite.titleRef(seriesID: seriesID) }
    func listTarget(_ ref: UDTitleRef) async -> UserListTarget? { await sqlite.target(of: ref) }

    func hideFromContinue(_ itemID: Int64) async {
        try? await store.hideFromContinue(itemID: itemID, hidden: true)
        libraryRevision += 1
    }
}

// MARK: Playback progress

extension AppServices {
    func saveProgress(itemID: Int64, position: Double, duration: Double?) async {
        try? await store.updateProgress(itemID: itemID, position: position, duration: duration, at: Date())
        // R471 (20): the same save is one step of the title's Play History (the player's saves only; marking watched by hand
        // is not a playback). Finished: at or past the point where the library counts the title as watched.
        if let key = try? await sqlite.userDataKey(forItem: itemID) {
            let finished = duration.map { $0 > 0 && position >= $0 * SQLiteLibraryStore.watchedFraction } ?? false
            ledger.recordPlay(itemKey: key, position: position, duration: duration, finished: finished)
        }
    }
}
