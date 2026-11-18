#if canImport(CloudKit)
import CloudKit
import Foundation
import UserData

// NEVER COMPILED until the next CI run (no Mac here). Kept thin on purpose: every decision is in BackupEngine (tested in
// WSL against InMemoryBackupCloud); this file only moves bytes. The calls are the ones CloudKitUserDataCloud already uses
// and that compiled for tvOS in the first compile (container.accountStatus, privateCloudDatabase, modifyRecordZones,
// modifyRecords), plus `record(for:)`, `records(for:desiredKeys:)` and CKAsset(fileURL:) (docs/BACKUP.md lists the pages).
//
// Records, in the custom zone "LibraryBackup" of the user's PRIVATE database (counts toward the user's iCloud storage):
//   BKManifest  name "manifest.<set>"  fields: generation (Int), payload (CKAsset: the BackupManifest JSON)
//   BKChunk     name "chunk.<sha256>"  fields: codec (String), data (CKAsset: the compressed chunk)
// CKAsset contents are encrypted by default (CKRecord.encryptedValues page). No field is queried, so none is indexed.

public final class CloudKitBackupCloud: BackupCloud, @unchecked Sendable {
    public static let zoneName = "LibraryBackup"
    static let manifestType = "BKManifest"
    static let chunkType = "BKChunk"
    /// Below every per-request count Apple's pages mention (200 in the web-services reference, 250 for CKSyncEngine,
    /// 400 for limitExceeded); a chunk is at most 1 MiB, so 8 chunks stay far under any size limit per request.
    static let idsPerRequest = 200

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let temp: URL
    private let lock = NSLock()
    private var zoneReady = false

    public init(containerIdentifier: String = UserDataModule.cloudKitContainerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("backup-assets", isDirectory: true)
    }

    public func accountStatus() async -> UDAccountStatus {
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    // MARK: Manifests

    public func fetchManifest(_ set: BackupSet) async throws -> Data? {
        try await mapped {
            try await ensureZone()
            guard let record = try await fetch(id("manifest.\(set.rawValue)")) else { return nil }
            return try Self.assetData(record, "payload")
        }
    }

    public func saveManifest(_ set: BackupSet, generation: Int, data: Data) async throws {
        try await mapped {
            try await ensureZone()
            let record = CKRecord(recordType: Self.manifestType, recordID: id("manifest.\(set.rawValue)"))
            record["generation"] = generation as Int
            let file = try writeTemp(data)
            defer { try? FileManager.default.removeItem(at: file) }
            record["payload"] = CKAsset(fileURL: file)
            try await save([record])
        }
    }

    // MARK: Chunks

    public func existingChunks(_ hashes: [String]) async throws -> Set<String> {
        try await mapped {
            try await ensureZone()
            var found = Set<String>()
            for start in stride(from: 0, to: hashes.count, by: Self.idsPerRequest) {
                let slice = Array(hashes[start..<min(start + Self.idsPerRequest, hashes.count)])
                let results = try await database.records(for: slice.map { id("chunk.\($0)") }, desiredKeys: ["codec"])
                for (recordID, result) in results {
                    switch result {
                    case .success: found.insert(String(recordID.recordName.dropFirst("chunk.".count)))
                    case .failure(let error):
                        if (error as? CKError)?.code == .unknownItem { continue }
                        throw error
                    }
                }
            }
            return found
        }
    }

    public func uploadChunk(_ hash: String, codec: String, data: Data) async throws {
        try await mapped {
            try await ensureZone()
            let record = CKRecord(recordType: Self.chunkType, recordID: id("chunk.\(hash)"))
            record["codec"] = codec as String
            let file = try writeTemp(data)
            defer { try? FileManager.default.removeItem(at: file) }
            record["data"] = CKAsset(fileURL: file)
            try await save([record])
        }
    }

    public func downloadChunk(_ hash: String) async throws -> (codec: String, data: Data) {
        try await mapped {
            try await ensureZone()
            guard let record = try await fetch(id("chunk.\(hash)")) else { throw UDCloudError.other("a part of the backup is missing (\(hash))") }
            return ((record["codec"] as? String) ?? "none", try Self.assetData(record, "data"))
        }
    }

    public func deleteChunks(_ hashes: [String]) async throws {
        try await mapped {
            try await ensureZone()
            for start in stride(from: 0, to: hashes.count, by: Self.idsPerRequest) {
                let ids = hashes[start..<min(start + Self.idsPerRequest, hashes.count)].map { id("chunk.\($0)") }
                _ = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys, atomically: false)
            }
        }
    }

    // MARK: Helpers

    private func id(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID) }

    private func ensureZone() async throws {
        if lock.withLock({ zoneReady }) { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        lock.withLock { zoneReady = true }
    }

    /// The record, or nil when it does not exist (CKError.unknownItem).
    private func fetch(_ recordID: CKRecord.ID) async throws -> CKRecord? {
        do { return try await database.record(for: recordID) } catch let error as CKError where error.code == .unknownItem { return nil }
    }

    /// Saves, overwriting (a manifest is replaced whole; a chunk with the same name has the same content).
    private func save(_ records: [CKRecord]) async throws {
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
        for (_, outcome) in result.saveResults {
            if case .failure(let error) = outcome { throw error }
        }
    }

    private func writeTemp(_ data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let file = temp.appendingPathComponent(UUID().uuidString)
        try data.write(to: file, options: .atomic)
        return file
    }

    private static func assetData(_ record: CKRecord, _ key: String) throws -> Data {
        guard let asset = record[key] as? CKAsset, let url = asset.fileURL else { throw UDCloudError.other("a backup record has no data") }
        return try Data(contentsOf: url)
    }

    private func mapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            // The zone is gone (the user deleted the app's data in the iCloud settings): create it again on the next call.
            if let ck = error as? CKError, ck.code == .zoneNotFound || ck.code == .userDeletedZone {
                lock.withLock { zoneReady = false }
            }
            throw Self.map(error)
        }
    }

    /// The same mapping as CloudKitUserDataCloud (docs/STORAGE_MODEL.md, error codes).
    static func map(_ error: Error) -> UDCloudError {
        if let known = error as? UDCloudError { return known }
        guard let ck = error as? CKError else { return .other("\(error)") }
        switch ck.code {
        case .limitExceeded: return .limitExceeded
        case .requestRateLimited, .zoneBusy, .serviceUnavailable: return .rateLimited(retryAfter: ck.retryAfterSeconds)
        case .quotaExceeded: return .quotaExceeded
        case .notAuthenticated: return .notAuthenticated
        case .networkUnavailable, .networkFailure, .serverResponseLost, .accountTemporarilyUnavailable: return .networkUnavailable
        default: return .other("CloudKit error \(ck.code.rawValue): \(ck.localizedDescription)")
        }
    }
}
#endif
