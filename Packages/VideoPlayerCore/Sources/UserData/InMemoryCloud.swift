import Foundation

/// An in-memory stand-in for the cloud, with the same limits and with faults you can switch on. It is part of the
/// library (not only of the tests) so the app's own tests and previews can use it.
public final class InMemoryCloud: UserDataCloud, @unchecked Sendable {
    public enum Fault: Equatable, Sendable {
        case fetch(UDCloudError)
        case save(UDCloudError)
    }

    private let lock = NSLock()
    private var store: [String: (record: UDRecord, tag: String, seq: Int)] = [:]
    private var sequence = 0
    private var tagCounter = 0
    private var status: UDAccountStatus = .available
    private var faults: [Fault] = []
    private var onSave: (@Sendable () -> Void)?
    private var minValidToken = 0
    private let limits: UDLimits
    private let pageSize: Int
    public private(set) var saveCalls = 0
    public private(set) var fetchCalls = 0
    public private(set) var largestBatchSeen = 0

    public init(limits: UDLimits = .cloudKit, pageSize: Int = 200) {
        self.limits = limits
        self.pageSize = pageSize
    }

    // MARK: Test controls

    public func setAccount(_ s: UDAccountStatus) { lock.withLock { status = s } }
    /// The next calls fail with these faults, in order (a fault is used up by the first matching call).
    public func inject(_ fault: Fault, times: Int = 1) { lock.withLock { faults += Array(repeating: fault, count: times) } }
    /// Runs inside the next save, before it is checked: another device writing at the same moment.
    public func beforeSave(_ body: (@Sendable () -> Void)?) { lock.withLock { onSave = body } }
    /// Tokens handed out before now stop working (the server forgot that much history).
    public func expireTokens() { lock.withLock { minValidToken = sequence } }

    /// What another device does: write a record straight into the server.
    @discardableResult
    public func serverWrite(_ record: UDRecord) -> String {
        lock.withLock { write(record) }
    }

    public func serverRecord(_ key: String) -> UDRecord? { lock.withLock { store[key]?.record } }
    public var serverRecords: [UDRecord] { lock.withLock { store.values.map(\.record).sorted { $0.key < $1.key } } }
    public var serverCount: Int { lock.withLock { store.count } }
    public func wipe() { lock.withLock { store = [:] } }

    private func write(_ record: UDRecord) -> String {
        sequence += 1
        tagCounter += 1
        let tag = "t\(tagCounter)"
        store[record.key] = (record, tag, sequence)
        return tag
    }

    // MARK: UserDataCloud

    public func accountStatus() async -> UDAccountStatus { lock.withLock { status } }

    public func fetchChanges(since: UDChangeToken?) async throws -> UDChanges {
        try lock.withLock {
            fetchCalls += 1
            if let i = faults.firstIndex(where: { if case .fetch = $0 { return true } else { return false } }) {
                if case let .fetch(e) = faults.remove(at: i) { throw e }
            }
            guard status == .available else { throw UDCloudError.notAuthenticated }
            var after = 0
            if let since {
                guard let text = String(data: since.data, encoding: .utf8), let n = Int(text) else { throw UDCloudError.changeTokenExpired }
                if n < minValidToken { throw UDCloudError.changeTokenExpired }
                after = n
            }
            let newer = store.values.filter { $0.seq > after }.sorted { $0.seq < $1.seq }
            let page = Array(newer.prefix(pageSize))
            let last = page.last?.seq ?? max(after, sequence)
            let more = newer.count > page.count
            return UDChanges(
                records: page.map { UDServerRecord(record: $0.record, tag: $0.tag) },
                newToken: UDChangeToken(data: Data(String(more ? last : max(last, sequence)).utf8)), moreComing: more
            )
        }
    }

    public func save(_ batch: [UDOutgoing]) async throws -> UDSaveOutcome {
        let hook: (@Sendable () -> Void)? = lock.withLock { let h = onSave; onSave = nil; return h }
        hook?()
        return try lock.withLock {
            saveCalls += 1
            largestBatchSeen = max(largestBatchSeen, batch.count)
            if let i = faults.firstIndex(where: { if case .save = $0 { return true } else { return false } }) {
                if case let .save(e) = faults.remove(at: i) { throw e }
            }
            guard status == .available else { throw UDCloudError.notAuthenticated }
            if batch.count > limits.maxItemsPerRequest { throw UDCloudError.limitExceeded }
            var total = 0
            var sizes: [Int] = []
            for o in batch {
                let n = o.record.encodedByteCount
                sizes.append(n)
                total += n
            }
            if total > limits.maxBytesPerRequest { throw UDCloudError.limitExceeded }
            var out = UDSaveOutcome()
            for (o, n) in zip(batch, sizes) {
                let key = o.record.key
                if n > limits.maxRecordBytes { out.failed[key] = .recordTooLarge(key); continue }
                if let current = store[key] {
                    if o.expectedTag != current.tag {
                        out.conflicts[key] = UDServerRecord(record: current.record, tag: current.tag)
                        continue
                    }
                } else if o.expectedTag != nil {
                    // The server lost the record (the user cleared iCloud data): treat as new.
                }
                out.saved[key] = write(o.record)
            }
            return out
        }
    }
}
