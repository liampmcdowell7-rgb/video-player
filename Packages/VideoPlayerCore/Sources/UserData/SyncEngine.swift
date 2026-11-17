import Foundation

public enum UDSyncStatus: Equatable, Sendable {
    /// Everything pulled and pushed.
    case synced
    /// No iCloud account (or iCloud restricted): nothing was synced, local data is kept.
    case signedOut
    /// The network or iCloud could not be reached; edits stay queued.
    case offline
    /// The user's iCloud storage is full; edits stay queued.
    case iCloudFull
    /// Gave up after the retry budget (message for the log); edits stay queued.
    case failed(String)
}

public struct UDSyncReport: Equatable, Sendable {
    public var status: UDSyncStatus = .synced
    public var pulled = 0
    public var pushed = 0
    public var conflictsMerged = 0
    public var splits = 0
    public var rateLimitWaits = 0
    public var fullRefetches = 0
    /// Records that could not be uploaded because they are over the size limit (their keys).
    public var oversize: [String] = []
    public var remainingDirty = 0
}

/// Pulls changes, merges them into the ledger, pushes what is dirty. One `sync()` at a time (it is an actor).
/// Rules, from Apple's CloudKit guidance (docs/STORAGE_MODEL.md): batches of at most 400 records and 2 MB; on
/// `limitExceeded` split the batch in half and retry both halves; on a rate limit wait the time the server says;
/// on a conflict merge the server's copy into ours and save again; on a full iCloud keep the edits queued.
public actor UserDataSyncEngine {
    private let ledger: UserDataLedger
    private let cloud: any UserDataCloud
    private let limits: UDLimits
    private let sleep: @Sendable (Double) async -> Void
    private let maxAttempts: Int
    private let defaultBackoff: Double

    public init(
        ledger: UserDataLedger, cloud: any UserDataCloud, limits: UDLimits = .cloudKit,
        maxAttempts: Int = 5, defaultBackoff: Double = 2,
        sleep: @escaping @Sendable (Double) async -> Void = { seconds in try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) }
    ) {
        self.ledger = ledger
        self.cloud = cloud
        self.limits = limits
        self.maxAttempts = max(1, maxAttempts)
        self.defaultBackoff = defaultBackoff
        self.sleep = sleep
    }

    public func sync() async -> UDSyncReport {
        var report = UDSyncReport()
        switch await cloud.accountStatus() {
        case .available: break
        case .noAccount, .restricted:
            report.status = .signedOut
            report.remainingDirty = ledger.dirtyCount
            return report
        case .unknown:
            report.status = .offline
            report.remainingDirty = ledger.dirtyCount
            return report
        }
        do {
            try await pull(&report)
            try await push(&report)
            report.status = .synced
        } catch let e as UDCloudError {
            report.status = Self.status(for: e)
        } catch {
            report.status = .failed("\(error)")
        }
        report.remainingDirty = ledger.dirtyCount
        return report
    }

    static func status(for e: UDCloudError) -> UDSyncStatus {
        switch e {
        case .quotaExceeded: return .iCloudFull
        case .notAuthenticated: return .signedOut
        case .networkUnavailable: return .offline
        case let .other(m): return .failed(m)
        case .limitExceeded: return .failed("request too large even for one record")
        case .rateLimited: return .failed("rate limited, retry budget used up")
        case .changeTokenExpired: return .failed("change token expired twice")
        case let .recordTooLarge(k): return .failed("record too large: \(k)")
        }
    }

    // MARK: Pull

    private func pull(_ report: inout UDSyncReport) async throws {
        var refetched = false
        var attempts = 0
        while true {
            do {
                let changes = try await cloud.fetchChanges(since: ledger.changeToken)
                for s in changes.records { ledger.mergeFromCloud(s); report.pulled += 1 }
                ledger.changeToken = changes.newToken
                if !changes.moreComing { return }
                attempts = 0
            } catch UDCloudError.changeTokenExpired {
                guard !refetched else { throw UDCloudError.changeTokenExpired }
                refetched = true
                report.fullRefetches += 1
                ledger.changeToken = nil
            } catch let UDCloudError.rateLimited(retryAfter) {
                attempts += 1
                guard attempts < maxAttempts else { throw UDCloudError.rateLimited(retryAfter: retryAfter) }
                report.rateLimitWaits += 1
                await sleep(retryAfter ?? defaultBackoff * Double(attempts))
            }
        }
    }

    // MARK: Push

    private func push(_ report: inout UDSyncReport) async throws {
        var rounds = 0
        while true {
            var dirty = ledger.dirtyEntries()
            // A record over the size limit can never be uploaded: report it, do not loop on it.
            let tooBig = dirty.filter { $0.entry.record.encodedByteCount > limits.maxRecordBytes }.map(\.key)
            if !tooBig.isEmpty {
                for k in tooBig where !report.oversize.contains(k) { report.oversize.append(k) }
                dirty.removeAll { tooBig.contains($0.key) }
            }
            if dirty.isEmpty { return }
            rounds += 1
            guard rounds <= maxAttempts + 3 else { throw UDCloudError.other("conflicts did not settle") }
            var madeProgress = false
            for batch in Self.batches(dirty.map { UDOutgoing(record: $0.entry.record, expectedTag: $0.entry.tag) }, limits: limits) {
                if try await pushBatch(batch, &report) { madeProgress = true }
            }
            if !madeProgress && ledger.dirtyEntries().allSatisfy({ e in report.oversize.contains(e.key) }) { return }
        }
    }

    /// Splits `records` into requests of at most `maxItemsPerRequest` records and `maxBytesPerRequest` bytes.
    static func batches(_ records: [UDOutgoing], limits: UDLimits) -> [[UDOutgoing]] {
        var out: [[UDOutgoing]] = []
        var current: [UDOutgoing] = []
        var bytes = 0
        for r in records {
            let n = r.record.encodedByteCount
            if !current.isEmpty && (current.count >= limits.maxItemsPerRequest || bytes + n > limits.maxBytesPerRequest) {
                out.append(current)
                current = []
                bytes = 0
            }
            current.append(r)
            bytes += n
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Returns true when at least one record was saved or merged.
    private func pushBatch(_ batch: [UDOutgoing], _ report: inout UDSyncReport) async throws -> Bool {
        var attempts = 0
        while true {
            do {
                let outcome = try await cloud.save(batch)
                var progressed = false
                for o in batch {
                    let key = o.record.key
                    if let tag = outcome.saved[key] {
                        ledger.markSent(key: key, sent: o.record, tag: tag)
                        report.pushed += 1
                        progressed = true
                    } else if let server = outcome.conflicts[key] {
                        ledger.mergeFromCloud(server)
                        report.conflictsMerged += 1
                        progressed = true
                    } else if let failure = outcome.failed[key] {
                        if case .recordTooLarge = failure { if !report.oversize.contains(key) { report.oversize.append(key) } }
                        else { throw failure }
                    }
                }
                return progressed
            } catch UDCloudError.limitExceeded {
                guard batch.count > 1 else { throw UDCloudError.limitExceeded }
                report.splits += 1
                let mid = batch.count / 2
                let a = try await pushBatch(Array(batch[..<mid]), &report)
                let b = try await pushBatch(Array(batch[mid...]), &report)
                return a || b
            } catch let UDCloudError.rateLimited(retryAfter) {
                attempts += 1
                guard attempts < maxAttempts else { throw UDCloudError.rateLimited(retryAfter: retryAfter) }
                report.rateLimitWaits += 1
                await sleep(retryAfter ?? defaultBackoff * Double(attempts))
            }
        }
    }
}
