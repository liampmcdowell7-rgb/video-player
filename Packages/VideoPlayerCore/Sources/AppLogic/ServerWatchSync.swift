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

/// Sends the app's watch state to the servers that want it (R309). Events are handled one at a time, in the order they
/// were sent, by `run()`; nothing is sent for a source whose switch is off at the moment of sending.
///
/// - A watched or unwatched change goes to every Plex file of the item (each server once per item) whose source has the
///   switch on, whichever source the change was made through.
/// - Playback reports (`/:/timeline`: playing, paused, buffering, stopped; at most every 10 seconds unless the state
///   changes) go to the file being played when it is such a Plex file; when the item is played through another source,
///   to every such Plex file of the item.
/// Stage 2 sends once and forgets a failure (counted in `failures`); stage 3 adds the queue for an unreachable server.
public actor ServerWatchSync {
    public enum Event: Sendable {
        case changed(ServerWatchChange)
        case started(itemID: Int64, file: StoredFile?)
        case progress(state: ServerPlaybackState, position: Double, duration: Double?, at: Date)
        case stopped(position: Double, duration: Double?, at: Date)
    }

    /// One Plex file of an item, on one server.
    struct Target: Sendable {
        var sourceID: String
        var serverKey: String
        var writer: any ServerWatchWriting
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

    private let store: SQLiteLibraryStore
    private let isOn: @Sendable (String) -> Bool
    private let source: @Sendable (String) async -> (any ServerWatchSource)?
    private let makeSessionID: @Sendable () -> String
    private let jobs: AsyncStream<Job>
    private let jobInput: AsyncStream<Job>.Continuation
    private var session: Session?
    private var running = false

    /// Requests that failed (stage 2 does not retry them).
    public private(set) var failures = 0

    /// - Parameters:
    ///   - isOn: whether the switch is on for a source id (read at every send).
    ///   - source: the live source for a source id; only sources that keep server watch state are used.
    public init(store: SQLiteLibraryStore, isOn: @escaping @Sendable (String) -> Bool,
                source: @escaping @Sendable (String) async -> (any ServerWatchSource)?,
                makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
        self.store = store
        self.isOn = isOn
        self.source = source
        self.makeSessionID = makeSessionID
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
            await report(current, state: state, position: position, duration: duration)
        case .stopped(let position, let duration, _):
            guard let current = session else { return }
            session = nil
            await report(current, state: .stopped, position: position, duration: duration, continuing: false)
        }
    }

    private func changed(_ change: ServerWatchChange) async {
        guard let itemID = try? await store.itemID(forKey: change.key) else { return }
        for target in await targets(ofItem: itemID) where isOn(target.sourceID) {
            do {
                if change.watched {
                    try await target.writer.markPlayed(itemKey: target.serverKey)
                } else {
                    try await target.writer.markUnplayed(itemKey: target.serverKey)
                }
            } catch {
                failures += 1
            }
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

    private func report(_ session: Session, state: ServerPlaybackState, position: Double, duration: Double?, continuing: Bool? = nil) async {
        for target in session.targets where isOn(target.sourceID) {
            let report = ServerTimelineReport(itemKey: target.serverKey, state: state, position: max(0, position), duration: duration,
                                              continuing: continuing, sessionIdentifier: session.id)
            do { try await target.writer.report(report) } catch { failures += 1 }
        }
    }

    // MARK: Targets

    /// Every file of the item on a source with the switch on, each server item once.
    private func targets(ofItem itemID: Int64) async -> [Target] {
        guard let files = try? await store.versions(of: itemID) else { return [] }
        var out: [Target] = []
        var seen = Set<String>()
        for file in files {
            guard let target = await target(for: file), seen.insert(target.sourceID + "\n" + target.serverKey).inserted else { continue }
            out.append(target)
        }
        return out
    }

    /// The file as a target, when its source has the switch on and its server lists the file. Nothing is asked of a source
    /// whose switch is off.
    private func target(for file: StoredFile) async -> Target? {
        guard isOn(file.sourceID), let live = await source(file.sourceID),
              let key = try? await live.serverItemKey(at: file.path), !key.isEmpty else { return nil }
        return Target(sourceID: file.sourceID, serverKey: key, writer: live.watchWriter)
    }
}
