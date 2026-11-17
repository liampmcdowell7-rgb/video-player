import Foundation

/// The local copy of all user data: every record, the server tag each one was last synced at, and which ones still
/// have to be uploaded. It lives in Caches like everything else (so a system cleanup can delete it); the cloud is
/// the copy that survives. Synchronous and thread-safe, so the library store can write to it from inside its own actor.
public final class UserDataLedger: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var record: UDRecord
        public var tag: String?
        public var dirty: Bool
    }

    public enum LoadResult: Equatable, Sendable {
        case loaded(records: Int)
        case missing
        case corrupt(String)
    }

    public static let fileFormat = "video-player-ledger"
    public static let fileVersion = 1

    public let deviceID: String
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var token: UDChangeToken?
    private var unsavedChanges = false

    public init(deviceID: String, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.deviceID = deviceID
        self.clock = clock
    }

    public func stamp(_ date: Date? = nil) -> UDStamp { UDStamp(date ?? clock(), device: deviceID) }
    public var now: Date { clock() }

    // MARK: Local edits

    /// Merges a local edit in. Marks the record for upload when it changed anything.
    @discardableResult
    public func apply(_ patch: UDRecord) -> Bool {
        lock.withLock {
            let existing = entries[patch.key]
            let merged = existing.map { UDSchema.merge($0.record, patch) } ?? patch
            if let existing, existing.record == merged { return false }
            entries[patch.key] = Entry(record: merged, tag: existing?.tag, dirty: true)
            unsavedChanges = true
            return true
        }
    }

    // MARK: Reads

    public func record(type: String, id: String) -> UDRecord? { lock.withLock { entries[type + "/" + id]?.record } }
    public func record(key: String) -> UDRecord? { lock.withLock { entries[key]?.record } }

    /// Live (not deleted) records of one type, in a stable order.
    public func records(ofType type: String) -> [UDRecord] {
        lock.withLock { entries.values.map(\.record).filter { $0.type == type && !$0.isDeleted }.sorted { $0.id < $1.id } }
    }

    /// Every record including tombstones (what export and the cloud need).
    public func allRecords() -> [UDRecord] {
        lock.withLock { entries.values.map(\.record).sorted { $0.key < $1.key } }
    }

    public var count: Int { lock.withLock { entries.count } }
    public var isEmpty: Bool { lock.withLock { entries.isEmpty } }
    public var dirtyCount: Int { lock.withLock { entries.values.filter(\.dirty).count } }
    public var needsSave: Bool { lock.withLock { unsavedChanges } }

    public var changeToken: UDChangeToken? {
        get { lock.withLock { token } }
        set { lock.withLock { token = newValue; unsavedChanges = true } }
    }

    // MARK: Sync bookkeeping

    func dirtyEntries() -> [(key: String, entry: Entry)] {
        lock.withLock { entries.filter { $0.value.dirty }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
    }

    func entry(_ key: String) -> Entry? { lock.withLock { entries[key] }  }

    /// Merges a server record in. The result is dirty when it still differs from what the server holds.
    func mergeFromCloud(_ server: UDServerRecord) {
        lock.withLock {
            let key = server.record.key
            if let existing = entries[key] {
                let merged = UDSchema.merge(existing.record, server.record)
                entries[key] = Entry(record: merged, tag: server.tag, dirty: merged != server.record)
            } else {
                entries[key] = Entry(record: server.record, tag: server.tag, dirty: false)
            }
            unsavedChanges = true
        }
    }

    /// The server accepted `sent` and gave it `tag`. If the record changed meanwhile it stays dirty.
    func markSent(key: String, sent: UDRecord, tag: String) {
        lock.withLock {
            guard var e = entries[key] else { return }
            e.tag = tag
            if e.record == sent { e.dirty = false }
            entries[key] = e
            unsavedChanges = true
        }
    }

    // MARK: Persistence (one JSON file, written atomically)

    private struct FileBody: Codable {
        var format: String
        var version: Int
        var token: UDChangeToken?
        var entries: [Entry]
    }

    public func encoded() throws -> Data {
        let body: FileBody = lock.withLock { FileBody(format: Self.fileFormat, version: Self.fileVersion, token: token, entries: entries.sorted { $0.key < $1.key }.map(\.value)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }

    public func save(to url: URL) throws {
        let data = try encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        lock.withLock { unsavedChanges = false }
    }

    /// Replaces the contents with the file's. A missing or damaged file leaves the ledger empty and says which.
    @discardableResult
    public func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return .corrupt("empty or unreadable file") }
        guard let body = try? JSONDecoder().decode(FileBody.self, from: data) else { return .corrupt("not valid ledger JSON") }
        guard body.format == Self.fileFormat else { return .corrupt("wrong format") }
        guard body.version == Self.fileVersion else { return .corrupt("unsupported version \(body.version)") }
        lock.withLock {
            entries = Dictionary(body.entries.map { ($0.record.key, $0) }, uniquingKeysWith: { a, _ in a })
            token = body.token
            unsavedChanges = false
        }
        return .loaded(records: body.entries.count)
    }

    /// Forgets everything (what a cleanup of Caches does to the file). Used by the purge simulator.
    public func reset() {
        lock.withLock {
            entries = [:]
            token = nil
            unsavedChanges = false
        }
    }
}
