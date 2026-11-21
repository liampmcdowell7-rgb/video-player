import Foundation
import VideoPlayerCore
import LibraryIndex
import UserData

// Two-way watch state with a Plex server, stage 2: the wiring (docs/PLEX_SOURCE.md section 6; OPEN_QUESTIONS R306 b, R309).
//
// - The per-source switch `PlexWatchSyncOption` ("Sync Watched Status with Plex"), off by default. While it is off for a
//   source, nothing at all is sent to that source's server.
// - `ServerWatchRecorder` sits in front of the ledger recorder and notices the app's own watched and unwatched changes
//   (the 95 % rule, Mark as Watched, Mark as Unwatched), whichever source the item was played or marked through.
// - `ServerWatchSync` turns those changes and the player's events into writes, for every Plex file of the same item whose
//   source has the switch on (one item key = one film, owner's decision 21 Nov 2026).
// Stage 3 (R310): a write the server could not be reached for waits in `ServerWatchQueue` and is replayed later; after
// each scan of a source with the switch on, the app's and the server's watch state are merged, the newer change winning
// (`PlexWatchMerge`).

/// The per-source switch (R309). Plex sources only; off unless the option is "1".
public enum PlexWatchSyncOption {
    public static let key = "watchSync"
    public static let title = "Sync Watched Status with Plex"
    public static let footer = "When on, what you watch here is also marked on the Plex server, so other Plex apps show it. When off, nothing is sent."

    public static func applies(toKind kind: String) -> Bool { kind == SourceKind.plex.rawValue }

    public static func isOn(_ definition: UDSourceDefinition) -> Bool {
        applies(toKind: definition.kind) && SourceOptions.parse(definition.options)[key] == "1"
    }

    public static func setting(_ on: Bool, on definition: UDSourceDefinition) -> UDSourceDefinition {
        var options = SourceOptions.parse(definition.options)
        options[key] = on ? "1" : nil
        var d = definition
        d.options = SourceOptions.format(options)
        return d
    }
}

/// Changes that must not travel back to a server: set around copying the server's own state into the app (the R306
/// seed), so what came from Plex is not sent to Plex again. A task-local value, so only that task's changes are quiet.
public enum ServerWatchEcho {
    @TaskLocal public static var suppressed = false
}

/// One watched or unwatched change the app made to an item.
public struct ServerWatchChange: Equatable, Sendable {
    public var key: String
    public var watched: Bool
    public var at: Date
    public init(key: String, watched: Bool, at: Date) {
        self.key = key
        self.watched = watched
        self.at = at
    }
}

/// Records everything into the ledger exactly as before and, for a change of the watched flag, tells the handler.
/// "Watched" is told only when the item was not watched before (so the 95 % rule and the end of the film, which both mark
/// it, are told once); "unwatched" is told for every Mark as Unwatched. A progress save that is not watched is never told.
public final class ServerWatchRecorder: UserDataRecording, @unchecked Sendable {
    public let wrapped: LedgerRecorder
    private let lock = NSLock()
    private var handler: (@Sendable (ServerWatchChange) -> Void)?

    public init(wrapping wrapped: LedgerRecorder) {
        self.wrapped = wrapped
    }

    /// Set once the sync exists (the store is built before it, with this recorder already in place).
    public func setHandler(_ handler: (@Sendable (ServerWatchChange) -> Void)?) {
        lock.withLock { self.handler = handler }
    }

    private func tell(_ change: ServerWatchChange) {
        guard !ServerWatchEcho.suppressed, let handler = lock.withLock({ self.handler }) else { return }
        handler(change)
    }

    /// The last watched flag this recorder saw per key in this launch. The ledger alone cannot say: two changes stamped
    /// with the same second keep the first one there.
    private var seen: [String: Bool] = [:]

    private func wasWatched(_ key: String) -> Bool {
        if let known = lock.withLock({ seen[key] }) { return known }
        return wrapped.ledger.record(type: UDSchema.watch, id: key).flatMap(UDWatch.value(of:))?.watched ?? false
    }

    private func remember(_ key: String, _ watched: Bool) { lock.withLock { seen[key] = watched } }

    public func recordProgress(key: String, _ value: UDWatchValue, at date: Date) {
        let before = wasWatched(key)
        wrapped.recordProgress(key: key, value, at: date)
        remember(key, value.watched)
        if value.watched && !before { tell(ServerWatchChange(key: key, watched: true, at: date)) }
    }

    public func recordReset(key: String, duration: Double?, at date: Date) {
        wrapped.recordReset(key: key, duration: duration, at: date)
        remember(key, false)
        tell(ServerWatchChange(key: key, watched: false, at: date))
    }

    public func recordFavorite(key: String, favorite: Bool, at date: Date) { wrapped.recordFavorite(key: key, favorite: favorite, at: date) }
    public func recordHidden(key: String, hidden: Bool, at date: Date) { wrapped.recordHidden(key: key, hidden: hidden, at: date) }
    public func recordView(_ value: UDViewValue, at date: Date) { wrapped.recordView(value, at: date) }
    public func recordViewDeleted(uid: String, at date: Date) { wrapped.recordViewDeleted(uid: uid, at: date) }
}


/// Sends the app's watch state to the servers that want it (R309, R310). Events are handled one at a time, in the order
/// they were sent, by `run()`; nothing is sent for a source whose switch is off at the moment of sending.
///
/// - A watched or unwatched change goes to every Plex file of the item (each server item once) whose source has the switch
///   on, whichever source the change was made through.
/// - Playback reports (`/:/timeline`: playing, paused, buffering, stopped; at most every 10 seconds unless the state
///   changes) go to the file being played when it is such a Plex file; when the item is played through another source, to
///   every such Plex file of the item.
/// - A write whose server cannot be reached is kept (`ServerWatchQueue`, newest per file and kind) and replayed after the
///   next write that reaches that server, and after each scan of the source: the resume point as a stopped timeline with
///   `offline=1` and `updated`, the watched flag as scrobble or unscrobble. A kept write older than the server's own last
///   view of the file is dropped (the newer change wins). A write the server refused is counted in `failures`, not kept.
/// - `.merge` (after a complete scan of a source with the switch on) replaces R306's one-time copy: per item, the app's
///   and the server's state are compared and the newer one wins (`PlexWatchMerge`).
public actor ServerWatchSync {
    public enum Event: Sendable {
        case changed(ServerWatchChange)
        case started(itemID: Int64, file: StoredFile?)
        case progress(state: ServerPlaybackState, position: Double, duration: Double?, at: Date)
        case stopped(position: Double, duration: Double?, at: Date)
        /// Sends what waits for this source (the app calls it after a complete scan; the server answered then).
        case replay(sourceID: String)
        /// Replays, then merges the app's and the server's watch state for every file of the source (R310).
        case merge(sourceID: String)
    }

    /// One Plex file of an item. `serverKey` and `writer` are nil when the server could not be reached to look the file up:
    /// every write to such a target waits in the queue.
    struct Target: Sendable {
        var sourceID: String
        var path: String
        var serverKey: String?
        var writer: (any ServerWatchWriting)?
    }

    private struct Session {
        var id: String
        var targets: [Target]
        var rhythm = ServerTimelineRhythm()
    }

    private enum Job: Sendable {
        case event(Event)
        case flush(CheckedContinuation<Void, Never>)
    }

    private enum Write {
        case played, unplayed
        case report(ServerPlaybackState, position: Double, duration: Double?, continuing: Bool?, session: String?, offline: Date?)
    }

    private let store: SQLiteLibraryStore
    private let isOn: @Sendable (String) -> Bool
    private let source: @Sendable (String) async -> (any ServerWatchSource)?
    private let resetTime: @Sendable (String) -> Date?
    private let makeSessionID: @Sendable () -> String
    private let now: @Sendable () -> Date
    private let queue: ServerWatchQueue
    private let jobs: AsyncStream<Job>
    private let jobInput: AsyncStream<Job>.Continuation
    private var session: Session?
    private var running = false
    private var replaying: Set<String> = []

    /// Requests the server refused (they are not kept).
    public private(set) var failures = 0

    /// - Parameters:
    ///   - isOn: whether the switch is on for a source id (read at every send).
    ///   - source: the live source for a source id; only sources that keep server watch state are used.
    ///   - queue: where writes wait while their server cannot be reached (kept across launches by the app).
    ///   - resetTime: when the item with this key was last marked unwatched in the app (the ledger's play-count epoch), for
    ///     the merge; nil when never.
    public init(store: SQLiteLibraryStore, isOn: @escaping @Sendable (String) -> Bool,
                source: @escaping @Sendable (String) async -> (any ServerWatchSource)?,
                queue: ServerWatchQueue = ServerWatchQueue(storage: MemoryServerWatchQueueStorage()),
                resetTime: @escaping @Sendable (String) -> Date? = { _ in nil },
                makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.isOn = isOn
        self.source = source
        self.queue = queue
        self.resetTime = resetTime
        self.makeSessionID = makeSessionID
        self.now = now
        (jobs, jobInput) = AsyncStream.makeStream(of: Job.self)
    }

    /// Queues an event. Safe from any thread, including from inside the library store.
    public nonisolated func send(_ event: Event) {
        jobInput.yield(.event(event))
    }

    /// Handles events until `finish()`. Started once by the app (and by tests).
    public func run() async {
        guard !running else { return }
        running = true
        for await job in jobs {
            switch job {
            case .event(let event): await handle(event)
            case .flush(let done): done.resume()
            }
        }
    }

    /// Returns once every event sent before it has been handled (needs `run()` to be running).
    public nonisolated func flush() async {
        await withCheckedContinuation { done in jobInput.yield(.flush(done)) }
    }

    public nonisolated func finish() { jobInput.finish() }

    /// What waits for a server that could not be reached.
    public var waiting: [ServerWatchPending] { queue.entries }

    /// True when the error means the server was not reached (no answer at all). A server that answered (refused, not
    /// found, unauthorized) is a `SourceError` other than `.transport`; anything else is treated as not reached.
    public static func notReached(_ error: Error) -> Bool {
        guard let error = error as? SourceError else { return !(error is CancellationError) }
        if case .transport = error { return true }
        return false
    }

    // MARK: Handling

    private func handle(_ event: Event) async {
        switch event {
        case .changed(let change):
            await changed(change)
        case .started(let itemID, let file):
            await started(itemID: itemID, file: file)
        case .progress(let state, let position, let duration, let at):
            guard var current = session, current.rhythm.isDue(state, at: at) else { return }
            session = current
            await report(current, state: state, position: position, duration: duration, at: at)
        case .stopped(let position, let duration, let at):
            guard let current = session else { return }
            session = nil
            await report(current, state: .stopped, position: position, duration: duration, at: at, continuing: false)
        case .replay(let sourceID):
            _ = await replay(sourceID)
        case .merge(let sourceID):
            await merge(sourceID)
        }
    }

    private func changed(_ change: ServerWatchChange) async {
        guard let itemID = try? await store.itemID(forKey: change.key) else { return }
        for target in await targets(ofItem: itemID) {
            await perform(change.watched ? .played : .unplayed, on: target, at: change.at)
        }
    }

    private func started(itemID: Int64, file: StoredFile?) async {
        let chosen: [Target]
        if let file, let own = await target(for: file) {
            chosen = [own]
        } else {
            chosen = await targets(ofItem: itemID)
        }
        session = chosen.isEmpty ? nil : Session(id: makeSessionID(), targets: chosen)
    }

    private func report(_ session: Session, state: ServerPlaybackState, position: Double, duration: Double?, at: Date,
                        continuing: Bool? = nil) async {
        for target in session.targets {
            await perform(.report(state, position: max(0, position), duration: duration, continuing: continuing,
                                  session: session.id, offline: nil), on: target, at: at)
        }
    }

    // MARK: Sending, keeping, replaying

    /// Sends one write, or keeps it when the server cannot be reached. Nothing at all while the source's switch is off.
    private func perform(_ write: Write, on target: Target, at: Date) async {
        guard isOn(target.sourceID) else { return }
        guard let key = target.serverKey, let writer = target.writer else {
            keep(write, for: target, at: at)
            return
        }
        do {
            try await send(write, key: key, writer: writer)
        } catch {
            if Self.notReached(error) { keep(write, for: target, at: at) } else { failures += 1 }
            return
        }
        if queue.entries.contains(where: { $0.sourceID == target.sourceID }) { _ = await replay(target.sourceID) }
    }

    private func send(_ write: Write, key: String, writer: any ServerWatchWriting) async throws {
        switch write {
        case .played:
            try await writer.markPlayed(itemKey: key)
        case .unplayed:
            try await writer.markUnplayed(itemKey: key)
        case .report(let state, let position, let duration, let continuing, let session, let offline):
            try await writer.report(ServerTimelineReport(itemKey: key, state: state, position: position, duration: duration,
                                                         continuing: continuing, sessionIdentifier: session, offlineUpdated: offline))
        }
    }

    /// A report becomes the file's resume point (replayed as a stopped timeline); a flag stays a flag.
    private func keep(_ write: Write, for target: Target, at: Date) {
        let entry: ServerWatchPending
        switch write {
        case .played: entry = ServerWatchPending(sourceID: target.sourceID, path: target.path, kind: .played, at: at)
        case .unplayed: entry = ServerWatchPending(sourceID: target.sourceID, path: target.path, kind: .unplayed, at: at)
        case .report(_, let position, let duration, _, _, _):
            entry = ServerWatchPending(sourceID: target.sourceID, path: target.path, kind: .position, position: position,
                                       duration: duration, at: at)
        }
        queue.add(entry)
    }

    /// Sends what waits for the source, oldest first. Stops (keeping the rest) when the server cannot be reached. A switch
    /// that is now off drops what waits: nothing is ever sent while it is off. Returns the paths sent.
    private func replay(_ sourceID: String) async -> Set<String> {
        guard !replaying.contains(sourceID) else { return [] }
        let waiting = queue.entries.filter { $0.sourceID == sourceID }.sorted { $0.at < $1.at }
        guard !waiting.isEmpty else { return [] }
        guard isOn(sourceID) else {
            queue.remove { $0.sourceID == sourceID }
            return []
        }
        guard let live = await source(sourceID) else { return [] }
        replaying.insert(sourceID)
        defer { replaying.remove(sourceID) }
        var sent: Set<String> = []
        for entry in waiting {
            let state: ServerWatchState?
            do {
                state = try await live.serverWatchState(at: entry.path)
            } catch {
                if Self.notReached(error) { return sent }
                queue.remove(entry)
                failures += 1
                continue
            }
            // The server no longer lists the file, or saw a newer view of it than this change: the change is dropped.
            guard let state, (state.lastViewedAt ?? .distantPast) <= entry.at else {
                queue.remove(entry)
                continue
            }
            let write: Write
            switch entry.kind {
            case .played: write = .played
            case .unplayed: write = .unplayed
            case .position:
                write = .report(.stopped, position: entry.position, duration: entry.duration, continuing: false,
                                session: makeSessionID(), offline: entry.at)
            }
            do {
                try await send(write, key: state.itemKey, writer: live.watchWriter)
                queue.remove(entry)
                sent.insert(entry.path)
            } catch {
                if Self.notReached(error) { return sent }
                queue.remove(entry)
                failures += 1
            }
        }
        return sent
    }

    // MARK: Merge (R310)

    /// After a complete scan of a source with the switch on: what waits is replayed, then every item of the source is
    /// compared with what the server knows, and the newer change wins. What comes from the server is not sent back.
    private func merge(_ sourceID: String) async {
        guard isOn(sourceID), let live = await source(sourceID) else { return }
        let replayed = await replay(sourceID)
        guard let states = try? await live.serverWatchStates() else { return }
        // The files of the source, grouped by item (two versions of one film on one server: the newest view decides).
        var byItem: [Int64: (state: ServerWatchState, files: [StoredFile])] = [:]
        let folders = Dictionary(grouping: states.keys.filter { !replayed.contains($0) }, by: PlexWatchSeed.folder(of:))
        for (folder, paths) in folders.sorted(by: { $0.key < $1.key }) {
            guard let stored = try? await store.storedFiles(sourceID: sourceID, folder: folder) else { continue }
            let wanted = Set(paths)
            for file in stored where wanted.contains(file.path) {
                guard let itemID = file.itemID, let state = states[file.path] else { continue }
                if var known = byItem[itemID] {
                    known.files.append(file)
                    if (state.lastViewedAt ?? .distantPast) > (known.state.lastViewedAt ?? .distantPast) { known.state = state }
                    byItem[itemID] = known
                } else {
                    byItem[itemID] = (state, [file])
                }
            }
        }
        for (itemID, entry) in byItem.sorted(by: { $0.key < $1.key }) {
            guard let item = try? await store.item(id: itemID) else { continue }
            let key = (try? await store.itemKey(itemID)) ?? nil
            let app = PlexWatchMerge.Side(app: item.watch, resetAt: key.flatMap(resetTime))
            let server = PlexWatchMerge.Side(server: entry.state)
            switch PlexWatchMerge.decide(app: app, server: server) {
            case .same:
                continue
            case .takeServer:
                await ServerWatchEcho.$suppressed.withValue(true) {
                    await self.take(server, itemID: itemID, duration: entry.state.duration ?? item.watch.duration)
                }
            case .sendApp:
                let at = app.at ?? now()
                for file in entry.files {
                    let target = Target(sourceID: sourceID, path: file.path, serverKey: states[file.path]?.itemKey, writer: live.watchWriter)
                    if app.watched {
                        await perform(.played, on: target, at: at)
                    } else if app.position >= PlexWatchSeed.minimumResume {
                        await perform(.report(.stopped, position: app.position, duration: item.watch.duration, continuing: false,
                                              session: makeSessionID(), offline: at), on: target, at: at)
                    } else {
                        await perform(.unplayed, on: target, at: at)
                    }
                }
            }
        }
    }

    /// The server's state into the app (the caller keeps it from being sent back).
    private func take(_ server: PlexWatchMerge.Side, itemID: Int64, duration: Double?) async {
        let at = server.at ?? now()
        if server.watched {
            try? await store.markWatched(itemIDs: [itemID], watched: true, at: at)
        } else if server.position >= PlexWatchSeed.minimumResume {
            try? await store.updateProgress(itemID: itemID, position: server.position, duration: duration, at: at)
        } else {
            try? await store.markWatched(itemIDs: [itemID], watched: false, at: at)
        }
    }

    // MARK: Targets

    /// Every file of the item on a source with the switch on, each server item once.
    private func targets(ofItem itemID: Int64) async -> [Target] {
        guard let files = try? await store.versions(of: itemID) else { return [] }
        var out: [Target] = []
        var seen = Set<String>()
        for file in files {
            guard let target = await target(for: file),
                  seen.insert(target.sourceID + "\n" + (target.serverKey ?? "path:" + target.path)).inserted else { continue }
            out.append(target)
        }
        return out
    }

    /// The file as a target, when its source has the switch on and its server lists the file (or cannot be reached to say:
    /// then writes to it wait in the queue). Nothing is asked of a source whose switch is off.
    private func target(for file: StoredFile) async -> Target? {
        guard isOn(file.sourceID), let live = await source(file.sourceID) else { return nil }
        do {
            guard let key = try await live.serverItemKey(at: file.path), !key.isEmpty else { return nil }
            return Target(sourceID: file.sourceID, path: file.path, serverKey: key, writer: live.watchWriter)
        } catch {
            return Self.notReached(error) ? Target(sourceID: file.sourceID, path: file.path, serverKey: nil, writer: nil) : nil
        }
    }
}

// MARK: - Newer change wins (R310)

/// Which side's watch state wins for one item (R310; owner's decision 21 Nov 2026: newer change wins, the server's
/// `lastViewedAt` against the app's own change time). Pure; tested on its own.
public enum PlexWatchMerge {
    public enum Decision: Equatable, Sendable {
        /// Both say the same (or neither knows which is newer): nothing changes.
        case same
        /// The server's change is newer: the app takes it.
        case takeServer
        /// The app's change is newer: the server is told.
        case sendApp
    }

    /// One side's state: watched, the resume point, and when it last changed.
    public struct Side: Equatable, Sendable {
        public var watched: Bool
        public var position: Double
        public var at: Date?
        /// False when this side has never recorded anything for the item.
        public var known: Bool

        public init(watched: Bool, position: Double, at: Date?, known: Bool) {
            self.watched = watched
            self.position = position
            self.at = at
            self.known = known
        }

        /// The app's side: its change time is the later of the last play and the last Mark as Unwatched.
        public init(app watch: WatchState, resetAt: Date?) {
            let times = [watch.lastPlayed, resetAt].compactMap { $0 }
            self.init(watched: watch.watched, position: watch.watched ? 0 : watch.position, at: times.max(),
                      known: watch.watched || watch.position > 0 || watch.lastPlayed != nil || resetAt != nil)
        }

        /// The server's side. Played with a resume point is a rewatch in progress: the resume point is what counts
        /// (as in the R306 seed).
        public init(server state: ServerWatchState) {
            let position = state.position ?? 0
            let watched = state.played && position < PlexWatchSeed.minimumResume
            self.init(watched: watched, position: watched ? 0 : position, at: state.lastViewedAt,
                      known: state.played || position > 0 || state.lastViewedAt != nil)
        }
    }

    /// Two changes less than this far apart count as made at the same time.
    public static let tolerance: TimeInterval = 1

    public static func decide(app: Side, server: Side) -> Decision {
        if sameState(app, server) { return .same }
        if !server.known { return app.known ? .sendApp : .same }
        if !app.known { return .takeServer }
        switch (app.at, server.at) {
        case (nil, nil): return .same
        case (nil, .some): return .takeServer
        case (.some, nil): return .sendApp
        case (.some(let a), .some(let s)):
            if s.timeIntervalSince(a) > tolerance { return .takeServer }
            if a.timeIntervalSince(s) > tolerance { return .sendApp }
            return .same
        }
    }

    /// Watched on both, or unwatched on both with resume points less than `PlexWatchSeed.minimumResume` apart (or neither
    /// worth resuming).
    static func sameState(_ a: Side, _ b: Side) -> Bool {
        guard a.watched == b.watched else { return false }
        if a.watched { return true }
        let resumeA = a.position >= PlexWatchSeed.minimumResume, resumeB = b.position >= PlexWatchSeed.minimumResume
        if !resumeA && !resumeB { return true }
        return resumeA && resumeB && abs(a.position - b.position) < PlexWatchSeed.minimumResume
    }
}

// MARK: - Writes that wait for a server (R310)

/// One write that could not reach its server. Newest per file and kind; replayed oldest first.
public struct ServerWatchPending: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case played, unplayed, position }
    public var sourceID: String
    public var path: String
    public var kind: Kind
    /// Seconds, for `.position`.
    public var position: Double
    public var duration: Double?
    /// When the change was made in the app (sent as `updated` with a replayed timeline).
    public var at: Date

    public init(sourceID: String, path: String, kind: Kind, position: Double = 0, duration: Double? = nil, at: Date) {
        self.sourceID = sourceID
        self.path = path
        self.kind = kind
        self.position = position
        self.duration = duration
        self.at = at
    }

    /// A watched flag replaces the other flag; a resume point replaces the older resume point.
    func replaces(_ other: ServerWatchPending) -> Bool {
        guard sourceID == other.sourceID, path == other.path else { return false }
        return (kind == .position) == (other.kind == .position)
    }
}

/// Where the waiting writes are kept between launches. They hold no token and no address, only the source id, the file's
/// path on the server, the kind, a position and a time.
public protocol ServerWatchQueueStorage: Sendable {
    func load() -> [ServerWatchPending]
    func save(_ entries: [ServerWatchPending])
}

/// The waiting writes, saved after every change.
public final class ServerWatchQueue: @unchecked Sendable {
    private let storage: any ServerWatchQueueStorage
    private let lock = NSLock()
    private var items: [ServerWatchPending]

    public init(storage: any ServerWatchQueueStorage) {
        self.storage = storage
        self.items = storage.load()
    }

    public var entries: [ServerWatchPending] { lock.withLock { items } }

    func add(_ entry: ServerWatchPending) {
        let snapshot: [ServerWatchPending] = lock.withLock {
            items.removeAll { entry.replaces($0) }
            items.append(entry)
            return items
        }
        storage.save(snapshot)
    }

    func remove(_ entry: ServerWatchPending) { remove { $0 == entry } }

    func remove(where match: (ServerWatchPending) -> Bool) {
        let snapshot: [ServerWatchPending] = lock.withLock {
            items.removeAll(where: match)
            return items
        }
        storage.save(snapshot)
    }
}

/// Kept in memory only (tests, and the fallback when no file can be written).
public final class MemoryServerWatchQueueStorage: ServerWatchQueueStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: [ServerWatchPending]
    public init(_ entries: [ServerWatchPending] = []) { saved = entries }
    public func load() -> [ServerWatchPending] { lock.withLock { saved } }
    public func save(_ entries: [ServerWatchPending]) { lock.withLock { saved = entries } }
}

/// A JSON file (the app keeps it in Application Support: not synced, not a secret).
public struct FileServerWatchQueueStorage: ServerWatchQueueStorage {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> [ServerWatchPending] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([ServerWatchPending].self, from: data)) ?? []
    }

    public func save(_ entries: [ServerWatchPending]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
