import Foundation
import Observation
import VideoPlayerCore
import LibraryIndex
import UserData
import AppLogic

/// Starts the iCloud (CloudKit) sync of the user-data ledger and keeps its status for Settings (docs/ARTWORK_DISCOVER.md part 4).
/// Scheduling lives in `CloudSyncCoordinator` (tested in WSL against a fake cloud); this class only connects it to the app.
@MainActor
@Observable
final class CloudSyncHost {
    private(set) var state = CloudSyncState()
    @ObservationIgnored private let coordinator: CloudSyncCoordinator
    @ObservationIgnored private let ledger: UserDataLedger
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private var started = false

    static var ledgerFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("user-data-ledger.json")
    }

    /// Builds the coordinator around the sync engine. The saved ledger file is read by `loadLedgerFile()`.
    init(ledger: UserDataLedger, engine: UserDataSyncEngine) {
        self.ledger = ledger
        let box = StateBox()
        self.coordinator = CloudSyncCoordinator(ledger: ledger, engine: engine, ledgerFile: Self.ledgerFile, onState: { box.deliver($0) })
        box.onMain = { [weak self] new in self?.state = new }
    }

    /// Reads the saved ledger file now (call before anything records into the ledger). True when the ledger was lost.
    func loadLedgerFile() -> Bool { coordinator.loadLedgerFile() }

    /// Start-up sequence, then the loop and the account-change watcher. Safe to call once; later calls do nothing.
    func start(startupSync: @escaping @Sendable () async -> UDSyncReport) async {
        guard !started else { return }
        started = true
        observer = Task { [weak self] in
            // PROVISIONAL / NOT CHECKED: the notification's Swift spelling is unverified, so the documented name is used as text.
            for await _ in NotificationCenter.default.notifications(named: Notification.Name("CKAccountChangedNotification")).map({ _ in () }) {
                await self?.coordinator.request(.accountChanged)
            }
        }
        await coordinator.start(startupSync: startupSync)
        await coordinator.startLoop()
    }

    func request(_ reason: CloudSyncReason) { Task { await coordinator.request(reason) } }

    /// "Sync now" in Settings.
    func syncNow() { request(.manual) }

    var line: String { CloudSyncText.line(state) }
}

/// Carries a state from the coordinator's actor to the main actor without capturing `self` across isolation.
private final class StateBox: @unchecked Sendable {
    var onMain: (@MainActor (CloudSyncState) -> Void)?
    func deliver(_ state: CloudSyncState) {
        let callback = onMain
        Task { @MainActor in callback?(state) }
    }
}
