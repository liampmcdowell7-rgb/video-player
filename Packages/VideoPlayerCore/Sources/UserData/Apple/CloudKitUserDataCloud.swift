#if canImport(CloudKit)
import CloudKit
import Foundation

// NEVER COMPILED. This file is only built on Apple platforms and has not been built yet (no Mac in this project; the first
// Codemagic compile check is its first compile). Every API used was checked against Apple's documentation pages, listed in
// docs/STORAGE_MODEL.md, but a compile error or a behaviour difference on a real iCloud account is possible.
//
// The cloud copy of user data: one custom zone in the user's PRIVATE database, one CloudKit record per `UDRecord`.
// The whole record (all stamped fields) is stored as one encrypted JSON `payload`; the merge rules live in Swift
// (UDSchema.merge), not in CloudKit, so the CloudKit schema never has to change when a field is added. Encrypted values can
// not be queried, which is fine: the app only fetches changes by token, never by predicate.

public final class CloudKitUserDataCloud: UserDataCloud, @unchecked Sendable {
    public static let recordType = "UDRecord"
    static let payloadKey = "payload"

    /// Created on first use, never in `init` (launch safety, docs/API_USAGE.md): `CloudKitContainers.make` or the app's guarded maker.
    private let containers: LazyCloudResource<CKContainer>
    private let zoneID: CKRecordZone.ID
    private let lock = NSLock()
    private var zoneReady = false

    public init(containers: LazyCloudResource<CKContainer> = CloudKitContainers.make()) {
        self.containers = containers
        zoneID = CKRecordZone.ID(zoneName: UserDataModule.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: UserDataCloud

    /// The private database, or `UDCloudError.other` with the reason when the container cannot be made.
    private var database: CKDatabase {
        get throws { try containers.value().privateCloudDatabase }
    }

    public func accountStatus() async -> UDAccountStatus {
        // No container (no iCloud capability in this build): reported as "could not determine"; the app shows the reason
        // from the same gate (AppServices.cloudUnavailable) instead of "signed out".
        guard let container = try? containers.value() else { return .unknown }
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            default: return .unknown   // couldNotDetermine, temporarilyUnavailable
            }
        } catch {
            return .unknown
        }
    }

    public func fetchChanges(since: UDChangeToken?) async throws -> UDChanges {
        do {
            try await ensureZone()
            let token = try since.flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0.data) }
            let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, desiredKeys: nil, resultsLimit: 200)
            var records: [UDServerRecord] = []
            for (_, modification) in result.modificationResultsByID {
                switch modification {
                case let .success(m):
                    if let server = Self.decode(m.record) { records.append(server) }
                case let .failure(error):
                    throw Self.map(error)
                }
            }
            let data = try NSKeyedArchiver.archivedData(withRootObject: result.changeToken, requiringSecureCoding: true)
            return UDChanges(records: records, newToken: UDChangeToken(data: data), moreComing: result.moreComing)
        } catch {
            throw Self.map(error)
        }
    }

    public func save(_ batch: [UDOutgoing]) async throws -> UDSaveOutcome {
        do {
            try await ensureZone()
            var records: [CKRecord] = []
            var keyByID: [CKRecord.ID: String] = [:]
            for o in batch {
                let id = CKRecord.ID(recordName: o.record.cloudName, zoneID: zoneID)
                // Saving over an existing record needs the server's system fields (its change tag), which the tag carries.
                let record = o.expectedTag.flatMap { Self.record(fromTag: $0) } ?? CKRecord(recordType: Self.recordType, recordID: id)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                record.encryptedValues[Self.payloadKey] = try encoder.encode(o.record)
                record["schema"] = 1 as Int
                records.append(record)
                keyByID[record.recordID] = o.record.key
            }
            let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            var out = UDSaveOutcome()
            for (id, saveResult) in result.saveResults {
                guard let key = keyByID[id] else { continue }
                switch saveResult {
                case let .success(saved):
                    out.saved[key] = Self.tag(of: saved)
                case let .failure(error):
                    if let ck = error as? CKError, ck.code == .serverRecordChanged,
                       let serverRecord = ck.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord, let server = Self.decode(serverRecord) {
                        out.conflicts[key] = server
                    } else {
                        out.failed[key] = Self.map(error)
                    }
                }
            }
            return out
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Zone

    private func ensureZone() async throws {
        if lock.withLock({ zoneReady }) { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        lock.withLock { zoneReady = true }
    }

    // MARK: Conversions

    static func decode(_ record: CKRecord) -> UDServerRecord? {
        guard let data = record.encryptedValues[payloadKey] as? Data, let udRecord = try? JSONDecoder().decode(UDRecord.self, from: data) else { return nil }
        return UDServerRecord(record: udRecord, tag: tag(of: record))
    }

    /// The server tag the engine hands back on the next save: the record's archived system fields (record id, change tag...).
    static func tag(of record: CKRecord) -> String {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData.base64EncodedString()
    }

    static func record(fromTag tag: String) -> CKRecord? {
        guard let data = Data(base64Encoded: tag), let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    static func map(_ error: Error) -> UDCloudError {
        if let known = error as? UDCloudError { return known }
        if let missing = error as? CloudUnavailable { return .other(missing.reason) }
        guard let ck = error as? CKError else { return .other("\(error)") }
        switch ck.code {
        case .limitExceeded: return .limitExceeded
        case .requestRateLimited, .zoneBusy, .serviceUnavailable: return .rateLimited(retryAfter: ck.retryAfterSeconds)
        case .quotaExceeded: return .quotaExceeded
        case .notAuthenticated: return .notAuthenticated
        case .networkUnavailable, .networkFailure, .serverResponseLost, .accountTemporarilyUnavailable: return .networkUnavailable
        case .changeTokenExpired: return .changeTokenExpired
        default: return .other("CloudKit error \(ck.code.rawValue): \(ck.localizedDescription)")
        }
    }
}
#endif
