import Foundation
import UserData

// Starts and schedules the sync of the user-data ledger (docs/STORAGE_MODEL.md section 3, docs/ARTWORK_DISCOVER.md part 4).
// The merge rules and the push/pull protocol already exist and are tested in UserData (`UserDataSyncEngine`); this is only the
// scheduling around them, pure Swift so it runs in tests with `InMemoryCloud` and a fake clock. Nothing here talks to CloudKit.
//
// When it syncs:
//   * at launch: the full start-up sequence (`LibraryBootstrap`: restore after a purge, rebuild a lost ledger, then merge);
//   * when something changed locally (watch state, saved views, sources, settings, watchlist): after a short pause so a burst
//     of edits is one upload (`debounce`);
//   * when the app becomes active again and when the account changes (`request(.becameActive)`, `request(.accountChanged)`);
//   * every `pullInterval` even when nothing changed, to pick up another device's edits;
//   * on "Sync Now" (`request(.manual)`).
// After a failure it waits longer each time (`backoff`); signed-out and full-storage states are not retried on a timer, only on
// an account change, a manual request or the periodic pull, so a signed-out device never hammers the service.
// The ledger file (Caches) is rewritten whenever the ledger has unsaved changes, at every tick.

public enum CloudSyncReason: Equatable, Sendable {
    case launch, becameActive, accountChanged, localChange, manual, periodic
}

public enum CloudSyncStatus: Equatable, Sendable {
    case notStarted
    case syncing
    case synced
    case signedOut
    case offline
    case iCloudFull
    case failed(String)
}

public struct CloudSyncState: Equatable, Sendable {
    public var status: CloudSyncStatus = .notStarted
    public var lastSynced: Date?
    /// Records changed here that are not uploaded yet.
    public var pending = 0
    public var lastReport: UDSyncReport?

    public init() {}
}

public struct CloudSyncPolicy: Equatable, Sendable {
    /// Wait after the first local change before uploading, so many edits go up together. PROVISIONAL: 5 seconds.
    public var debounce: Double = 5
    /// Pull from the cloud this often even with no local change. PROVISIONAL: 15 minutes.
    public var pullInterval: Double = 15 * 60
    /// First retry delay after a failure; doubles each time up to `maxBackoff`. PROVISIONAL.
    public var baseBackoff: Double = 30
    public var maxBackoff: Double = 15 * 60
    public init() {}
}

public actor CloudSyncCoordinator {
    public private(set) var state = CloudSyncState()

    private let ledger: UserDataLedger
    private let engine: UserDataSyncEngine
    private let ledgerFile: URL?
    private let policy: CloudSyncPolicy
    private let now: @Sendable () -> Date
    private let onState: @Sendable (CloudSyncState) -> Void
    private var dirtySince: Date?
    private var lastAttempt: Date?
    private var failures = 0
    private var blockedUntil: Date?
    private var wantsSync: CloudSyncReason?
    private var running = false
    private var loop: Task<Void, Never>?

    public init(ledger: UserDataLedger, engine: UserDataSyncEngine, ledgerFile: URL?, policy: CloudSyncPolicy = CloudSyncPolicy(),
                now: @escaping @Sendable () -> Date = { Date() }, onState: @escaping @Sendable (CloudSyncState) -> Void = { _ in }) {
        self.ledger = ledger
        self.engine = engine
        self.ledgerFile = ledgerFile
        self.policy = policy
        self.now = now
        self.onState = onState
    }

    // MARK: Launch

    /// Reads the saved ledger file. Returns whether the ledger had been lost (no file, or a damaged one), which the start-up
    /// sequence needs to know (it then rebuilds the ledger from the database before syncing).
    public nonisolated func loadLedgerFile() -> Bool {
        guard let ledgerFile else { return true }
        switch ledger.load(from: ledgerFile) {
        case .loaded: return false
        case .missing, .corrupt: return true
        }
    }

    /// The start-up sequence, then the periodic loop. `startupSync` is `LibraryBootstrap.run` in the app (so a restore after a
    /// system cleanup happens first); tests pass a closure that just syncs.
    public func start(startupSync: @Sendable () async -> UDSyncReport) async {
        setStatus(.syncing)
        let report = await startupSync()
        finish(report, at: now())
        persist()
    }

    /// Runs `tick()` every `interval` seconds until `stop()`. The sleep is injected so tests do not wait.
    public func startLoop(every interval: Double = 5, sleep: @escaping @Sendable (Double) async -> Void = { s in try? await Task.sleep(nanoseconds: UInt64(max(0.1, s) * 1_000_000_000)) }) {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await sleep(interval)
                if Task.isCancelled { break }
                await self?.tick()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        persist()
    }

    // MARK: Requests

    /// Something asks for a sync. It runs at the next tick (immediately for everything except `.localChange`, which waits `debounce`).
    public func request(_ reason: CloudSyncReason) {
        switch reason {
        case .localChange:
            if dirtySince == nil { dirtySince = now() }
        default:
            wantsSync = reason
            blockedUntil = nil   // an explicit reason (account change, manual, active) overrides the back-off
        }
    }

    /// One scheduling step: save the ledger file when it changed, decide whether to sync, and sync. Returns true when a sync ran.
    @discardableResult
    public func tick() async -> Bool {
        persist()
        let t = now()
        let pendingBefore = state.pending
        state.pending = ledger.dirtyCount
        if ledger.dirtyCount > 0, dirtySince == nil { dirtySince = t }
        guard !running else { return false }

        var reason = wantsSync
        if reason == nil, let since = dirtySince, t.timeIntervalSince(since) >= policy.debounce, ledger.dirtyCount > 0, !isBlocked(t) {
            reason = .localChange
        }
        if reason == nil, shouldPull(t) { reason = .periodic }
        guard let reason else { if state.pending != pendingBefore { onState(state) }; return false }
        if let blockedUntil, t < blockedUntil, reason == .periodic || reason == .localChange { return false }

        wantsSync = nil
        dirtySince = nil
        running = true
        setStatus(.syncing)
        lastAttempt = t
        let report = await engine.sync()
        running = false
        finish(report, at: now())
        persist()
        return true
    }

    // MARK: Internals

    private func isBlocked(_ t: Date) -> Bool {
        if let blockedUntil, t < blockedUntil { return true }
        switch state.status {
        case .signedOut, .iCloudFull: return true   // not retried because of local edits alone
        default: return false
        }
    }

    private func shouldPull(_ t: Date) -> Bool {
        guard let lastAttempt else { return false }   // the launch sync sets it
        return t.timeIntervalSince(lastAttempt) >= policy.pullInterval
    }

    private func finish(_ report: UDSyncReport, at t: Date) {
        lastAttempt = lastAttempt ?? t
        state.lastReport = report
        state.pending = report.remainingDirty
        switch report.status {
        case .synced:
            failures = 0
            blockedUntil = nil
            state.lastSynced = t
            state.status = .synced
        case .signedOut:
            state.status = .signedOut
        case .iCloudFull:
            state.status = .iCloudFull
        case .offline:
            noteFailure(t)
            state.status = .offline
        case .failed(let message):
            noteFailure(t)
            state.status = .failed(message)
        }
        onState(state)
    }

    private func noteFailure(_ t: Date) {
        failures += 1
        let delay = min(policy.maxBackoff, policy.baseBackoff * pow(2, Double(failures - 1)))
        blockedUntil = t.addingTimeInterval(delay)
    }

    private func setStatus(_ s: CloudSyncStatus) {
        state.status = s
        onState(state)
    }

    /// Writes the ledger file when the ledger has changes not saved yet. A failure to write is not fatal (the cloud copy and the
    /// essentials copy remain); it is tried again at the next tick.
    func persist() {
        guard let ledgerFile, ledger.needsSave else { return }
        try? ledger.save(to: ledgerFile)
    }
}

/// The sentences Settings shows for the ledger sync, next to the account line. Final user-facing text.
public enum CloudSyncText {
    public static func line(_ s: CloudSyncState, now: Date = Date()) -> String {
        switch s.status {
        case .notStarted: return "iCloud sync has not started yet."
        case .syncing: return "Syncing now."
        case .synced:
            let pending = s.pending > 0 ? " \(s.pending) newer changes will go up shortly." : ""
            if let last = s.lastSynced { return "Last synced \(ago(last, now: now))." + pending }
            return "Synced." + pending
        case .signedOut: return "Not signed in to iCloud, so nothing is synced. \(pendingText(s))"
        case .offline: return "iCloud could not be reached. \(pendingText(s)) It tries again automatically."
        case .iCloudFull: return "Your iCloud storage is full, so recent changes are not backed up. \(pendingText(s))"
        case .failed: return "The last sync did not finish. \(pendingText(s)) It tries again automatically."
        }
    }

    private static func pendingText(_ s: CloudSyncState) -> String {
        s.pending == 0 ? "Nothing is waiting to be uploaded." : (s.pending == 1 ? "1 change is waiting to be uploaded." : "\(s.pending) changes are waiting to be uploaded.")
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 48 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        return "\(hours / 24) days ago"
    }
}
