import Foundation
import MetadataOnline
import UserData

// R381 (audit docs/AUDIT_AGAINST_REFERENCE_PACK.md #14, section 5; owner 21 Nov 2026, PROVISIONAL): Fix Match choices are
// kept in iCloud through the mechanism the app already uses for the person's own data, the user-data ledger that
// `CloudKitUserDataCloud` syncs to the private CloudKit database of iCloud.com.liamp.videoplayer. Its schema has had a
// "fixmatch" record type since the ledger was written (UserData/Schema.swift); nothing wrote it until now. matches.json in
// Application Support stays as the local cache that Fix Match reads, rebuilt from the ledger when it is missing.
// Apple's archived App Programming Guide for tvOS: data that must last goes in iCloud; whether Application Support is
// purgeable on tvOS is on no Apple page (UNVERIFIED). That iCloud sync works can only be checked on a device.

/// One Fix Match choice as a ledger record, and back.
public enum FixMatchRecords {
    public static let type: String = UDSchema.fixMatch

    /// One record per scope and path, the key `JSONFileMatchStore` replaces by: a new choice for the same file, season or
    /// folder replaces the old one on every device.
    public static func id(scope: MatchScope, path: String) -> String {
        switch scope {
        case .file: return "file:" + path
        case .season(let number): return "season\(number):" + path
        case .folder: return "folder:" + path
        }
    }

    public static func id(_ match: StoredMatch) -> String { id(scope: match.scope, path: match.path) }

    public static func record(_ match: StoredMatch, stamp: UDStamp) -> UDRecord {
        let values: [String: UDValue] = [
            "provider": .string("tmdb"),
            "providerID": .int(Int64(match.tmdbID)),
            "title": .string(match.title),
            "year": match.year.map { .int(Int64($0)) } ?? .null,
            "kind": .string(match.kind.rawValue),
            "scope": .string(scopeName(match.scope)),
            "season": seasonNumber(match.scope).map { .int(Int64($0)) } ?? .null,
            "path": .string(match.path),
            "fileSize": match.fileSize.map { .int($0) } ?? .null,
            // Whole seconds, as matches.json stores the date (ISO 8601), so the two copies compare equal.
            "createdAt": .int(Int64(match.createdAt.timeIntervalSince1970.rounded(.down))),
            "choiceID": .string(match.id.uuidString),
        ]
        return UDRecord(type: type, id: id(match), fields: values.mapValues { UDField($0, stamp) })
    }

    /// The record that removes a choice on every device.
    public static func tombstone(scope: MatchScope, path: String, stamp: UDStamp) -> UDRecord {
        UDRecord(type: type, id: id(scope: scope, path: path), deleted: stamp)
    }

    /// The choice a live record holds; nil for a tombstone or a record this version cannot read.
    public static func match(_ record: UDRecord) -> StoredMatch? {
        guard record.type == type, !record.isDeleted else { return nil }
        let f: [String: UDField] = record.liveFields
        guard f["provider"]?.value.asString == "tmdb",
              let tmdbID = f["providerID"]?.value.asInt,
              let title = f["title"]?.value.asString,
              let kind = f["kind"]?.value.asString.flatMap(TitleKind.init(rawValue:)),
              let path = f["path"]?.value.asString,
              let scope = scope(name: f["scope"]?.value.asString, season: f["season"]?.value.asInt),
              let created = f["createdAt"]?.value.asInt else { return nil }
        let choiceID: UUID = f["choiceID"]?.value.asString.flatMap(UUID.init(uuidString:)) ?? UUID()
        return StoredMatch(id: choiceID, scope: scope, path: path, fileSize: f["fileSize"]?.value.asInt, tmdbID: Int(tmdbID),
                           kind: kind, title: title, year: f["year"]?.value.asInt.map { Int($0) },
                           createdAt: Date(timeIntervalSince1970: Double(created)))
    }

    static func scopeName(_ scope: MatchScope) -> String {
        switch scope {
        case .file: return "file"
        case .season: return "season"
        case .folder: return "folder"
        }
    }

    static func seasonNumber(_ scope: MatchScope) -> Int? {
        if case .season(let number) = scope { return number }
        return nil
    }

    static func scope(name: String?, season: Int64?) -> MatchScope? {
        switch name {
        case "file": return .file
        case "folder": return .folder
        case "season": return season.map { .season(Int($0)) }
        default: return nil
        }
    }
}

/// R381: which copy wins when the local cache (matches.json) and the iCloud copy (the ledger's "fixmatch" records) differ.
/// PROVISIONAL rules:
///  1. No cache file (never written, or removed by the system): the choices are the iCloud copy, and the file is rebuilt.
///  2. A choice in both: the iCloud copy wins. Every save and removal on this device writes both, so a difference means
///     another device changed it (the ledger has already merged the devices by time).
///  3. A choice only in the cache: kept and sent to iCloud (a choice saved before R381, or a restored backup), unless
///     iCloud holds a removal of the same file, season or folder that is later than the choice; then it is dropped.
public enum FixMatchCopies {
    public struct Outcome: Equatable, Sendable {
        /// The choices Fix Match uses.
        public var matches: [StoredMatch]
        /// Cache-only choices to write into the ledger.
        public var upload: [StoredMatch]
        /// True when matches.json must be written again.
        public var rewriteCache: Bool
    }

    /// - cache: the choices in matches.json; nil when the file does not exist.
    /// - cloud: the live "fixmatch" records of the ledger, as choices.
    /// - cloudRemoved: the ledger's removals, by record id (`FixMatchRecords.id`), with their time.
    public static func resolve(cache: [StoredMatch]?, cloud: [StoredMatch], cloudRemoved: [String: Date]) -> Outcome {
        let cloudSorted: [StoredMatch] = sorted(cloud)
        guard let cache else {
            return Outcome(matches: cloudSorted, upload: [], rewriteCache: !cloudSorted.isEmpty)
        }
        let cloudIDs: Set<String> = Set(cloud.map(FixMatchRecords.id))
        var upload: [StoredMatch] = []
        var kept: [StoredMatch] = cloud
        for match in cache where !cloudIDs.contains(FixMatchRecords.id(match)) {
            if let removed = cloudRemoved[FixMatchRecords.id(match)], removed >= match.createdAt { continue }
            kept.append(match)
            upload.append(match)
        }
        let matches: [StoredMatch] = sorted(kept)
        return Outcome(matches: matches, upload: sorted(upload), rewriteCache: Set(matches) != Set(cache))
    }

    /// Oldest choice first; ties by record id, so the order never depends on where a choice came from.
    static func sorted(_ matches: [StoredMatch]) -> [StoredMatch] {
        matches.sorted { ($0.createdAt, FixMatchRecords.id($0)) < ($1.createdAt, FixMatchRecords.id($1)) }
    }
}

/// R381: the store Fix Match uses. matches.json (`JSONFileMatchStore`) is the cache it reads; every save and removal is
/// also written into the user-data ledger, which the app's iCloud sync uploads. Every read first reconciles the two
/// (`FixMatchCopies`), so a missing file is rebuilt and choices made on another device reach the cache. A scan asks for the
/// choices once per file, so between saves the full reconcile runs at most once per `refreshInterval` (and always when the
/// file is missing); the rest of the time the cache answers.
public actor CloudMatchStore: MatchStore {
    /// PROVISIONAL: how long a reconciled list is trusted before the ledger is read again.
    public static let refreshInterval: TimeInterval = 30

    private let url: URL
    private let cache: JSONFileMatchStore
    private let ledger: UserDataLedger
    private let clock: @Sendable () -> Date
    private var lastReconcile: Date?

    public init(url: URL, ledger: UserDataLedger, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.cache = JSONFileMatchStore(url: url)
        self.ledger = ledger
        self.clock = clock
    }

    @discardableResult public func save(_ match: StoredMatch) async throws -> StoredMatch? {
        _ = await reconciled()
        let replaced: StoredMatch? = try await cache.save(match)
        ledger.apply(FixMatchRecords.record(match, stamp: ledger.stamp()))
        return replaced
    }

    @discardableResult public func remove(id: UUID) async throws -> StoredMatch? {
        _ = await reconciled()
        guard let removed = try await cache.remove(id: id) else { return nil }
        ledger.apply(FixMatchRecords.tombstone(scope: removed.scope, path: removed.path, stamp: ledger.stamp()))
        return removed
    }

    public func all() async -> [StoredMatch] {
        let exists: Bool = FileManager.default.fileExists(atPath: url.path)
        if exists, let last = lastReconcile, clock().timeIntervalSince(last) < Self.refreshInterval {
            return await cache.all()
        }
        return await reconciled()
    }

    private func reconciled() async -> [StoredMatch] {
        lastReconcile = clock()
        let exists: Bool = FileManager.default.fileExists(atPath: url.path)
        let cached: [StoredMatch]? = exists ? await cache.all() : nil
        let records: [UDRecord] = ledger.allRecords().filter { $0.type == FixMatchRecords.type }
        var removed: [String: Date] = [:]
        for record in records where record.isDeleted {
            if let stamp = record.deleted { removed[record.id] = Date(timeIntervalSince1970: stamp.time) }
        }
        let outcome = FixMatchCopies.resolve(cache: cached, cloud: records.compactMap(FixMatchRecords.match), cloudRemoved: removed)
        for match in outcome.upload {
            // Stamped with the time the choice was made, so a later removal on another device still wins.
            ledger.apply(FixMatchRecords.record(match, stamp: ledger.stamp(match.createdAt)))
        }
        if outcome.rewriteCache {
            // A failed write keeps the old file; the next read tries again. Fix Match still gets the reconciled list.
            try? await cache.replaceAll(outcome.matches)
        }
        return outcome.matches
    }
}
