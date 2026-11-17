import Foundation

/// What the app found when it opened the library database.
public enum UDDatabaseHealth: Equatable, Sendable {
    case ok
    case missing
    /// The file exists but holds no library (for example the system deleted part of it).
    case empty
    case corrupt(String)

    public var needsRebuild: Bool { self != .ok }
}

/// What the Library screen shows while the bootstrap runs. Texts are English placeholders until localisation.
public enum LibraryBootstrapState: Equatable, Sendable {
    case idle
    case checking
    case restoringUserData
    case rescanning
    /// Finished. `note` is set when the user should be told something (for example that watch history is not backed up).
    case ready(note: LibraryBootstrapNote?)
}

public enum LibraryBootstrapNote: Equatable, Sendable {
    /// Signed out of iCloud and the local copy was gone: watch history could not be restored.
    case historyNotRestored
    /// iCloud was unreachable; the restore used the last local copy and will merge with iCloud later.
    case restoredOffline
    /// iCloud storage is full; recent changes are not backed up.
    case iCloudFull
    /// Some sources lost their passwords (tvOS does not sync Keychain items): enter them again.
    case passwordsNeeded(sourceIDs: [String])
}

/// What the bootstrap needs from the library store and the app. The library store implements the first block.
public protocol LibraryRestoreTarget: Sendable {
    /// Hide watch state (every item reads as unwatched, no Continue Watching, no Next Up) until `openWatchGate`.
    func closeWatchGate() async
    func openWatchGate() async
    /// Load saved watch state and views; items scanned later pick their state up as they appear.
    func restore(watch: [(key: String, value: UDWatchValue)], views: [UDViewValue], deletedViewUIDs: [String]) async throws
    /// What the store holds now, as patches (used when the ledger was lost but the database survived).
    func currentUserData() async throws -> [UDRecord]
    /// Scan the sources again (incrementally: the index is empty, so everything is "new").
    func rescan() async throws
}

/// The startup sequence (docs/STORAGE_MODEL.md, "Startup"):
///  1. database fine, ledger fine -> ready now, sync in the background;
///  2. database missing/empty/corrupt -> close the watch gate, show "Rebuilding", restore from the local copy of the
///     essentials and the cloud, load the restored state into the store, open the gate, rescan;
///  3. database fine but ledger lost -> rebuild the ledger from the database, then merge with the cloud.
/// Watch state is never shown while the gate is closed, so a half-restored library cannot show wrong "watched" marks.
public actor LibraryBootstrap {
    public private(set) var state: LibraryBootstrapState = .idle
    private let ledger: UserDataLedger
    private let engine: UserDataSyncEngine
    private let essentials: UDEssentialsStore
    private let credentials: any CredentialStore
    private let onState: @Sendable (LibraryBootstrapState) -> Void

    public init(
        ledger: UserDataLedger, engine: UserDataSyncEngine, essentials: UDEssentialsStore, credentials: any CredentialStore,
        onState: @escaping @Sendable (LibraryBootstrapState) -> Void = { _ in }
    ) {
        self.ledger = ledger
        self.engine = engine
        self.essentials = essentials
        self.credentials = credentials
        self.onState = onState
    }

    private func set(_ s: LibraryBootstrapState) {
        state = s
        onState(s)
    }

    /// Runs the whole sequence. Returns the sync report of the restore sync.
    @discardableResult
    public func run(health: UDDatabaseHealth, ledgerWasLost: Bool, target: any LibraryRestoreTarget) async throws -> UDSyncReport {
        set(.checking)
        var note: LibraryBootstrapNote?
        var report = UDSyncReport()

        // The essentials copy (UserDefaults) is the first thing back: sources and settings with their stamps.
        essentials.restore(into: ledger)

        if health.needsRebuild {
            await target.closeWatchGate()
            set(.restoringUserData)
            report = await engine.sync()
            if ledger.isEmpty || (ledger.records(ofType: UDSchema.watch).isEmpty && ledger.records(ofType: UDSchema.view).isEmpty) {
                if report.status == .signedOut { note = .historyNotRestored }
            }
            if report.status == .offline { note = note ?? .restoredOffline }
            try await target.restore(watch: ledger.watchEntries(), views: ledger.viewValues(), deletedViewUIDs: ledger.deletedViewUIDs())
            await target.openWatchGate()
            set(.rescanning)
            try await target.rescan()
        } else {
            if ledgerWasLost {
                // The database is intact but the local copy of user data is gone: rebuild it from the database first, so
                // nothing recorded only there is lost, then merge with the cloud.
                for patch in try await target.currentUserData() { ledger.apply(patch) }
            }
            report = await engine.sync()
            if report.status == .offline { note = .restoredOffline }
            if !ledger.isEmpty {
                // Cloud state may be newer than the database (another device): load it too. Idempotent.
                await target.closeWatchGate()
                try await target.restore(watch: ledger.watchEntries(), views: ledger.viewValues(), deletedViewUIDs: ledger.deletedViewUIDs())
                await target.openWatchGate()
            }
        }
        if report.status == .iCloudFull { note = .iCloudFull }
        let missing = CredentialGap.sourcesNeedingPassword(ledger.sourceDefinitions(), store: credentials)
        if !missing.isEmpty { note = .passwordsNeeded(sourceIDs: missing.map(\.id).sorted()) }
        try? essentials.save(from: ledger)
        set(.ready(note: note))
        return report
    }
}

/// The sentence Settings shows under "iCloud". English placeholders (to be localised).
public enum UDStatusText {
    public static func text(for status: UDSyncStatus) -> String {
        switch status {
        case .synced: return "Your watch history, saved views and sources are backed up to iCloud."
        case .signedOut: return "iCloud is off for this Apple TV. Your watch history will not survive a system cleanup. You can export a backup in Settings."
        case .offline: return "iCloud could not be reached. Changes are kept and will be backed up later."
        case .iCloudFull: return "Your iCloud storage is full, so recent changes are not backed up."
        case .failed: return "Backing up to iCloud did not finish. It will try again."
        }
    }
}
