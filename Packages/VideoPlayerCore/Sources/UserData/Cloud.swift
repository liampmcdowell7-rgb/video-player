import Foundation

/// Limits the sync engine respects. Numbers from Apple's CloudKit documentation (docs/STORAGE_MODEL.md has the links):
/// 1 MB of data per record (assets not counted); for a `limitExceeded` error Apple suggests at most 400 items and
/// 2 MB per request, and to split the request in half and retry both halves.
public struct UDLimits: Equatable, Sendable {
    public var maxRecordBytes: Int
    public var maxItemsPerRequest: Int
    public var maxBytesPerRequest: Int

    public init(maxRecordBytes: Int, maxItemsPerRequest: Int, maxBytesPerRequest: Int) {
        self.maxRecordBytes = maxRecordBytes
        self.maxItemsPerRequest = maxItemsPerRequest
        self.maxBytesPerRequest = maxBytesPerRequest
    }

    public static let cloudKit = UDLimits(maxRecordBytes: 1_000_000, maxItemsPerRequest: 400, maxBytesPerRequest: 2_000_000)
}

public enum UDAccountStatus: Equatable, Sendable {
    case available
    /// No iCloud account is signed in on this Apple TV.
    case noAccount
    /// iCloud is restricted (a profile or a setting blocks it).
    case restricted
    /// The state could not be determined (offline, or the system could not say).
    case unknown
}

/// The errors the engine knows how to react to. The CloudKit wrapper maps `CKError` codes onto these.
public enum UDCloudError: Error, Equatable, Sendable {
    /// The request was too big: split it in half and retry both halves.
    case limitExceeded
    /// Too many requests: wait `retryAfter` seconds (nil = engine default back-off) and retry.
    case rateLimited(retryAfter: Double?)
    /// The user's iCloud storage is full.
    case quotaExceeded
    case notAuthenticated
    case networkUnavailable
    /// The change token is too old: fetch everything again.
    case changeTokenExpired
    /// One record is over the size limit (its key).
    case recordTooLarge(String)
    case other(String)
}

public struct UDChangeToken: Codable, Equatable, Sendable {
    public var data: Data
    public init(data: Data) { self.data = data }
}

/// A record as the server holds it, with the server's change tag (an opaque string the engine hands back when saving).
public struct UDServerRecord: Equatable, Sendable {
    public var record: UDRecord
    public var tag: String
    public init(record: UDRecord, tag: String) {
        self.record = record
        self.tag = tag
    }
}

public struct UDChanges: Sendable {
    public var records: [UDServerRecord]
    public var newToken: UDChangeToken
    public var moreComing: Bool
    public init(records: [UDServerRecord], newToken: UDChangeToken, moreComing: Bool) {
        self.records = records
        self.newToken = newToken
        self.moreComing = moreComing
    }
}

public struct UDOutgoing: Sendable {
    public var record: UDRecord
    /// The tag of the server copy this edit was based on; nil for a record the server has never seen.
    public var expectedTag: String?
    public init(record: UDRecord, expectedTag: String?) {
        self.record = record
        self.expectedTag = expectedTag
    }
}

public struct UDSaveOutcome: Sendable {
    /// record key -> new tag
    public var saved: [String: String]
    /// The server had a different version: here is its copy (merge it and save again).
    public var conflicts: [String: UDServerRecord]
    public var failed: [String: UDCloudError]
    public init(saved: [String: String] = [:], conflicts: [String: UDServerRecord] = [:], failed: [String: UDCloudError] = [:]) {
        self.saved = saved
        self.conflicts = conflicts
        self.failed = failed
    }
}

/// The cloud as the sync engine sees it. `CloudKitUserDataCloud` (Apple/, never compiled here) implements it over the
/// private database; `InMemoryCloud` implements it for tests, with fault injection.
public protocol UserDataCloud: Sendable {
    func accountStatus() async -> UDAccountStatus
    /// Records changed since `since` (nil = everything). Pages: while `moreComing`, call again with `newToken`.
    func fetchChanges(since: UDChangeToken?) async throws -> UDChanges
    /// Saves a batch. Whole-request errors are thrown; per-record outcomes come back in the result.
    func save(_ batch: [UDOutgoing]) async throws -> UDSaveOutcome
}
