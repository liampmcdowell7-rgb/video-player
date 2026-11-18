import Foundation
import UserData

/// The cloud as the backup engine sees it. `CloudKitBackupCloud` (Sources/LibraryBackup/Apple, CloudKit only) implements it over the user's PRIVATE
/// CloudKit database in its own zone; `InMemoryBackupCloud` implements it for tests. Errors are the same `UDCloudError`
/// cases the user-data sync already maps from `CKError` (quotaExceeded, notAuthenticated, networkUnavailable, …).
///
/// Records (docs/BACKUP.md): one manifest record per set (`BackupManifest` JSON as an asset, plus the generation), and one
/// chunk record per chunk, named by the SHA-256 of its uncompressed content, holding the compressed bytes as an asset.
public protocol BackupCloud: Sendable {
    func accountStatus() async -> UDAccountStatus
    /// The current manifest of a set as stored bytes, or nil when there is none.
    func fetchManifest(_ set: BackupSet) async throws -> Data?
    func saveManifest(_ set: BackupSet, generation: Int, data: Data) async throws
    /// Which of these chunks already exist in the cloud.
    func existingChunks(_ hashes: [String]) async throws -> Set<String>
    func uploadChunk(_ hash: String, codec: String, data: Data) async throws
    /// The stored bytes and the codec they were written with.
    func downloadChunk(_ hash: String) async throws -> (codec: String, data: Data)
    func deleteChunks(_ hashes: [String]) async throws
}

/// Compression of a chunk. The codec's `id` is stored with the chunk so a restore always uses the matching one.
public protocol BackupCodec: Sendable {
    var id: String { get }
    func compress(_ data: Data) throws -> Data
    func decompress(_ data: Data, expectedSize: Int) throws -> Data
}

/// No compression (Linux tests, and the fallback when a codec is unknown).
public struct IdentityCodec: BackupCodec {
    public init() {}
    public var id: String { "none" }
    public func compress(_ data: Data) throws -> Data { data }
    public func decompress(_ data: Data, expectedSize: Int) throws -> Data { data }
}

#if canImport(Darwin)
/// LZFSE through Foundation's `NSData.compressed(using:)` (Apple platforms only; never compiled in WSL).
/// https://developer.apple.com/documentation/foundation/nsdata/compressed(using:)
public struct LZFSECodec: BackupCodec {
    public init() {}
    public var id: String { "lzfse" }
    public func compress(_ data: Data) throws -> Data { try (data as NSData).compressed(using: .lzfse) as Data }
    public func decompress(_ data: Data, expectedSize: Int) throws -> Data { try (data as NSData).decompressed(using: .lzfse) as Data }
}
#endif

/// An in-memory cloud for tests, with the faults the engine must survive. Not Apple code: it proves the protocol only.
public final class InMemoryBackupCloud: BackupCloud, @unchecked Sendable {
    public enum Operation: Equatable, Sendable { case fetchManifest, saveManifest, existing, upload, download, delete }

    private let lock = NSLock()
    private var manifests: [BackupSet: (generation: Int, data: Data)] = [:]
    private var chunks: [String: (codec: String, data: Data)] = [:]
    private var status: UDAccountStatus = .available
    private var faults: [(Operation, UDCloudError, after: Int)] = []
    private var counts: [Operation: Int] = [:]
    /// Total bytes the account may hold (manifests and chunks); nil = no limit. Exceeding it throws quotaExceeded.
    public var quotaBytes: Int?
    private var corrupt: Set<String> = []
    private var corruptTimes: [String: Int] = [:]
    public private(set) var uploads: [String] = []
    public private(set) var uploadedPayloads: [Data] = []
    public private(set) var savedManifests: [Data] = []

    public init() {}

    // MARK: Test controls
    public func setAccount(_ s: UDAccountStatus) { lock.withLock { status = s } }
    /// The `after`+1-th call of `operation` from now fails with `error` (after: 0 = the next one).
    public func inject(_ operation: Operation, _ error: UDCloudError, after: Int = 0) {
        lock.withLock { faults.append((operation, error, after: (counts[operation] ?? 0) + after)) }
    }
    /// The next `times` downloads of this chunk return damaged bytes.
    public func corruptChunk(_ hash: String, times: Int = 1) { lock.withLock { corrupt.insert(hash); corruptTimes[hash] = times } }
    public var chunkCount: Int { lock.withLock { chunks.count } }
    public var chunkHashes: Set<String> { lock.withLock { Set(chunks.keys) } }
    public var storedBytes: Int { lock.withLock { chunks.values.reduce(0) { $0 + $1.data.count } + manifests.values.reduce(0) { $0 + $1.data.count } } }
    public func calls(_ operation: Operation) -> Int { lock.withLock { counts[operation] ?? 0 } }
    public func manifestGeneration(_ set: BackupSet) -> Int? { lock.withLock { manifests[set]?.generation } }
    /// Another device writes a manifest (used to test a backup that changes during a restore).
    public func replaceManifest(_ set: BackupSet, generation: Int, data: Data) { lock.withLock { manifests[set] = (generation, data) } }

    private func enter(_ op: Operation) throws {
        let n = counts[op] ?? 0
        counts[op] = n + 1
        if let i = faults.firstIndex(where: { $0.0 == op && $0.after == n }) {
            let e = faults.remove(at: i).1
            throw e
        }
        guard status == .available else { throw UDCloudError.notAuthenticated }
    }

    private func checkQuota(adding bytes: Int) throws {
        guard let quotaBytes else { return }
        let used = chunks.values.reduce(0) { $0 + $1.data.count } + manifests.values.reduce(0) { $0 + $1.data.count }
        if used + bytes > quotaBytes { throw UDCloudError.quotaExceeded }
    }

    // MARK: BackupCloud
    public func accountStatus() async -> UDAccountStatus { lock.withLock { status } }

    public func fetchManifest(_ set: BackupSet) async throws -> Data? {
        try lock.withLock { try enter(.fetchManifest); return manifests[set]?.data }
    }

    public func saveManifest(_ set: BackupSet, generation: Int, data: Data) async throws {
        try lock.withLock {
            try enter(.saveManifest)
            try checkQuota(adding: data.count - (manifests[set]?.data.count ?? 0))
            manifests[set] = (generation, data)
            savedManifests.append(data)
        }
    }

    public func existingChunks(_ hashes: [String]) async throws -> Set<String> {
        try lock.withLock { try enter(.existing); return Set(hashes.filter { chunks[$0] != nil }) }
    }

    public func uploadChunk(_ hash: String, codec: String, data: Data) async throws {
        try lock.withLock {
            try enter(.upload)
            if chunks[hash] == nil { try checkQuota(adding: data.count) }
            chunks[hash] = (codec, data)
            uploads.append(hash)
            uploadedPayloads.append(data)
        }
    }

    public func downloadChunk(_ hash: String) async throws -> (codec: String, data: Data) {
        try lock.withLock {
            try enter(.download)
            guard let c = chunks[hash] else { throw UDCloudError.other("no chunk \(hash)") }
            if corrupt.contains(hash) {
                let left = (corruptTimes[hash] ?? 1) - 1
                corruptTimes[hash] = left
                if left <= 0 { corrupt.remove(hash) }
                var damaged = c.data
                if damaged.isEmpty { damaged = Data([1]) } else { damaged[damaged.startIndex] ^= 0xFF }
                return (c.codec, damaged)
            }
            return c
        }
    }

    public func deleteChunks(_ hashes: [String]) async throws {
        try lock.withLock {
            try enter(.delete)
            for h in hashes { chunks[h] = nil }
        }
    }
}
