#if canImport(CloudKit)
import CloudKit
import Foundation

// NEVER COMPILED (same status as CloudKitUserDataCloud.swift). Uses only APIs read on Apple's pages on 2026-11-17:
//  - CKRecord.encryptedValues (tvOS 15.0+): https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues
//  - CKErrorUserDidResetEncryptedDataKey (tvOS 15.0+): https://developer.apple.com/documentation/cloudkit/ckerroruserdidresetencrypteddatakey
//  - CKDatabase.modifyRecordZones(saving:deleting:) (tvOS 15.0+): https://developer.apple.com/documentation/cloudkit/ckdatabase/modifyrecordzones(saving:deleting:)
//  - Encrypting User Data (the reset handling below follows it): https://developer.apple.com/documentation/cloudkit/encrypting-user-data
//
// One zone ("Secrets") in the private database, one record per source, one encrypted field `secret`. Encrypted fields have no
// indexes, so records are read by change fetch (like CloudKitUserDataCloud), never by query.
//
// Setup the person must do once (docs/CODEMAGIC_SETUP.md): run the app against the DEVELOPMENT environment so the encrypted
// field is created in the schema, then promote the schema in the CloudKit console before the first TestFlight build. Apple's
// page: "Promote this schema change to your production environment before deploying any app changes".

public final class CloudKitSecretCloud: SecretCloud, @unchecked Sendable {
    public static let recordType = "SourceSecret"
    static let secretKey = "secret"

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let lock = NSLock()
    private var zoneReady = false

    public init(containerIdentifier: String = UserDataModule.cloudKitContainerIdentifier) {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: "Secrets", ownerName: CKCurrentUserDefaultName)
    }

    private func recordID(_ sourceID: String) -> CKRecord.ID { CKRecord.ID(recordName: "secret-" + sourceID, zoneID: zoneID) }

    public func fetchAll() async throws -> [String: String] {
        do {
            try await ensureZone()
            var out: [String: String] = [:]
            var token: CKServerChangeToken?
            var more = true
            while more {
                let result = try await database.recordZoneChanges(inZoneWith: zoneID, since: token, desiredKeys: nil, resultsLimit: 200)
                for (_, modification) in result.modificationResultsByID {
                    if case let .success(m) = modification,
                       let secret = m.record.encryptedValues[Self.secretKey] as? String,
                       m.record.recordID.recordName.hasPrefix("secret-") {
                        out[String(m.record.recordID.recordName.dropFirst("secret-".count))] = secret
                    }
                }
                token = result.changeToken
                more = result.moreComing
            }
            return out
        } catch {
            throw try await map(error)
        }
    }

    public func save(_ secret: String, for sourceID: String) async throws {
        do {
            try await ensureZone()
            let record = CKRecord(recordType: Self.recordType, recordID: recordID(sourceID))
            record.encryptedValues[Self.secretKey] = secret
            // Replacing an existing record needs no change tag here: the value is overwritten wholesale.
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            for (_, r) in result.saveResults { if case let .failure(e) = r { throw e } }
        } catch {
            throw try await map(error)
        }
    }

    public func delete(sourceID: String) async throws {
        do {
            try await ensureZone()
            let result = try await database.modifyRecords(saving: [], deleting: [recordID(sourceID)])
            for (_, r) in result.deleteResults {
                if case let .failure(e) = r, (e as? CKError)?.code != .unknownItem { throw e }
            }
        } catch {
            throw try await map(error)
        }
    }

    // MARK: Zone and errors

    private func ensureZone() async throws {
        if lock.withLock({ zoneReady }) { return }
        let result = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        for (_, r) in result.saveResults { if case let .failure(e) = r { throw e } }
        lock.withLock { zoneReady = true }
    }

    /// Apple's "Handle a User Keychain Reset": `zoneNotFound` with `CKErrorUserDidResetEncryptedDataKey` means the data is
    /// permanently lost; delete and recreate the zone, then report `keyReset` so the mirror uploads its local copies.
    private func map(_ error: Error) async throws -> SecretCloudError {
        guard let ck = error as? CKError else { return .unavailable(String(describing: error)) }
        switch ck.code {
        case .notAuthenticated, .managedAccountRestricted:
            return .notSignedIn
        case .zoneNotFound:
            lock.withLock { zoneReady = false }
            if (ck.userInfo[CKErrorUserDidResetEncryptedDataKey] as? NSNumber)?.boolValue == true {
                _ = try? await database.modifyRecordZones(saving: [], deleting: [zoneID])
                return .keyReset
            }
            return .unavailable("The secrets zone was removed. It will be created again.")
        default:
            return .unavailable(ck.localizedDescription)
        }
    }
}
#endif
