import Foundation

/// A tiny key-value store. `UserDefaultsKeyValueStore` is the real one; `InMemoryKeyValueStore` is for tests.
public protocol KeyValueStoring: Sendable {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public final class InMemoryKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { lock.withLock { values[key] } }
    public func set(_ data: Data?, forKey key: String) { lock.withLock { values[key] = data } }
    public var totalBytes: Int { lock.withLock { values.values.reduce(0) { $0 + $1.count } } }
}

public final class UserDefaultsKeyValueStore: KeyValueStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func set(_ data: Data?, forKey key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

public enum UDEssentialsError: Error, Equatable, Sendable {
    /// The essentials would exceed our own budget (200 KB). Apple's ceiling for everything in UserDefaults is 500 KB.
    case overBudget(bytes: Int, budget: Int)
}

/// The small copy of what is needed to start usefully with nothing else on disk: the source list (no secrets) and the
/// settings. It lives in UserDefaults, the one place tvOS keeps (up to 500 KB, per Apple's App Programming Guide for tvOS).
/// It holds the same records the cloud holds (with their stamps), so putting it back into the ledger loses nothing.
public final class UDEssentialsStore: @unchecked Sendable {
    /// Our budget for this copy. The hard ceiling is 500 KB for all of UserDefaults; we keep far below it.
    public static let budgetBytes = 200_000
    public static let ceilingBytes = 500_000
    public static let storageKey = "vp.essentials.v1"
    static let types: Set<String> = [UDSchema.source, UDSchema.settings]

    private struct Body: Codable {
        var format: String
        var version: Int
        var records: [UDRecord]
    }

    private let store: any KeyValueStoring

    public init(store: any KeyValueStoring) {
        self.store = store
    }

    /// Writes the source and settings records of `ledger`. Throws (and writes nothing) when they would not fit the budget.
    public func save(from ledger: UserDataLedger) throws {
        let records = ledger.allRecords().filter { Self.types.contains($0.type) }
        let body = Body(format: "video-player-essentials", version: 1, records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(body)
        guard data.count <= Self.budgetBytes else { throw UDEssentialsError.overBudget(bytes: data.count, budget: Self.budgetBytes) }
        store.set(data, forKey: Self.storageKey)
    }

    public var storedBytes: Int { store.data(forKey: Self.storageKey)?.count ?? 0 }

    /// Reads the saved records. A missing or damaged copy gives an empty list (never an error): the cloud and a
    /// re-entry of the sources are the ways back.
    public func load() -> [UDRecord] {
        guard let data = store.data(forKey: Self.storageKey), let body = try? JSONDecoder().decode(Body.self, from: data),
              body.format == "video-player-essentials", body.version == 1 else { return [] }
        return body.records
    }

    /// Merges the saved records into `ledger` (stamps decide; nothing newer is overwritten). Returns how many changed it.
    @discardableResult
    public func restore(into ledger: UserDataLedger) -> Int {
        load().reduce(0) { $0 + (ledger.apply($1) ? 1 : 0) }
    }
}
