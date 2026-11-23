import Foundation

/// How the fields of one record type merge. Three kinds of rule, all semilattices (so merge order never matters):
///  - a plain field: the later stamp wins;
///  - an atomic group: the fields move together, the group with the later stamp wins as a whole (position, duration,
///    watched flag and last-played time must never mix two different plays);
///  - a counter group (`counterGroups`): compared as numbers, first field first, the larger tuple wins as a whole
///    (the play count: `[epoch, count]`; an "unwatch" starts a new epoch with count 0, so it beats older counts,
///    while two devices that played in the same epoch keep the larger count).
///  - `maxFields`: the larger number wins (counters that only grow).
public struct UDRecordSchema: Sendable {
    public var type: String
    public var atomicGroups: [[String]]
    public var counterGroups: [[String]]
    public var maxFields: Set<String>

    public init(type: String, atomicGroups: [[String]] = [], counterGroups: [[String]] = [], maxFields: Set<String> = []) {
        self.type = type
        self.atomicGroups = atomicGroups
        self.counterGroups = counterGroups
        self.maxFields = maxFields
    }
}

public enum UDSchema {
    // Record types. The strings are stored in the cloud; never rename one.
    public static let watch = "watch"
    public static let view = "view"
    public static let fixMatch = "fixmatch"
    public static let segment = "segment"
    public static let learnedSkip = "learnedskip"
    public static let source = "source"
    public static let settings = "settings"
    /// "Move to Movies" / "Move to Shows" for one file (docs/SORTING.md), keyed by `UDSortOverride.recordID`.
    public static let sorting = "sorting"

    public static let schemas: [String: UDRecordSchema] = [
        sorting: UDRecordSchema(type: sorting, atomicGroups: [["kind", "title", "year", "season", "episode", "episodeEnd", "signal"]]),
        watch: UDRecordSchema(
            type: watch,
            atomicGroups: [["position", "duration", "watched", "lastPlayed"]],
            counterGroups: [["playEpoch", "playCount"]]
        ),
        view: UDRecordSchema(type: view, atomicGroups: [["scopeKind", "scopeSource", "scopePath", "query"]]),
        // R381: every field of a Fix Match choice moves together (AppLogic `FixMatchRecords`); nothing wrote this type before.
        fixMatch: UDRecordSchema(type: fixMatch, atomicGroups: [["provider", "providerID", "title", "year", "kind", "scope", "season", "path", "fileSize", "createdAt", "choiceID"]]),
        // "fileDuration" (the length of the file the mark was made on) moves with the range, so a start and an end from two
        // different edits never mix. Records written before it existed simply lack the field (see SegmentMarks.swift).
        segment: UDRecordSchema(type: segment, atomicGroups: [["kind", "start", "end", "fileDuration"]]),
        learnedSkip: UDRecordSchema(type: learnedSkip, atomicGroups: [["start", "end"]], maxFields: ["samples"]),
        source: UDRecordSchema(type: source, atomicGroups: [["host", "port", "path", "username", "auth", "options", "trustedFingerprint"]]),
        settings: UDRecordSchema(type: settings),
        // R449: the chosen audio and subtitle of one item move together (never a language of one edit with the off flag of another).
        UDTrackChoiceRecord.type: UDRecordSchema(type: UDTrackChoiceRecord.type, atomicGroups: [["audio", "subtitle", "subtitlesOff"]]),
        // R449: metadata edits merge field by field (the default rule): the newest edit of each field wins.
        UDEdit.type: UDRecordSchema(type: UDEdit.type),
    ]

    /// A type this version does not know (written by a newer app) merges field by field and is kept as it is.
    public static func schema(for type: String) -> UDRecordSchema {
        schemas[type] ?? UDRecordSchema(type: type)
    }

    // MARK: Merge

    public static func merge(_ a: UDRecord, _ b: UDRecord) -> UDRecord {
        guard a.type == b.type, a.id == b.id else { return a }
        let schema = schema(for: a.type)
        var out: [String: UDField] = [:]
        var handled = Set<String>()

        for group in schema.atomicGroups {
            handled.formUnion(group)
            if let winner = groupWinner(group, a, b, counter: false) { for f in group { if let v = winner.fields[f] { out[f] = v } } }
        }
        for group in schema.counterGroups {
            handled.formUnion(group)
            if let winner = groupWinner(group, a, b, counter: true) { for f in group { if let v = winner.fields[f] { out[f] = v } } }
        }
        for name in Set(a.fields.keys).union(b.fields.keys) where !handled.contains(name) {
            switch (a.fields[name], b.fields[name]) {
            case let (x?, nil): out[name] = x
            case let (nil, y?): out[name] = y
            case let (x?, y?):
                if schema.maxFields.contains(name) {
                    let keepX = (x.value.asDouble ?? -Double.infinity) != (y.value.asDouble ?? -Double.infinity)
                        ? (x.value.asDouble ?? -Double.infinity) > (y.value.asDouble ?? -Double.infinity)
                        : x.value.canonical >= y.value.canonical
                    var best = keepX ? x : y
                    best.stamp = max(x.stamp, y.stamp)
                    out[name] = best
                } else if x.stamp != y.stamp {
                    out[name] = x.stamp > y.stamp ? x : y
                } else {
                    out[name] = x.value.canonical >= y.value.canonical ? x : y
                }
            case (nil, nil): break
            }
        }
        // A pure join: nothing is dropped here. Pruning inside a chain of merges breaks associativity, so fields that are
        // not newer than the deletion stamp stay stored and are simply not read (`UDRecord.liveFields`, `subscript`).
        let deleted = [a.deleted, b.deleted].compactMap { $0 }.max()
        return UDRecord(type: a.type, id: a.id, fields: out, deleted: deleted)
    }

    /// Which side supplies the whole group, or nil when neither has any of its fields.
    private static func groupWinner(_ group: [String], _ a: UDRecord, _ b: UDRecord, counter: Bool) -> UDRecord? {
        let hasA = group.contains { a.fields[$0] != nil }, hasB = group.contains { b.fields[$0] != nil }
        if !hasA && !hasB { return nil }
        if hasA && !hasB { return a }
        if hasB && !hasA { return b }
        if counter {
            let ta = group.map { a.fields[$0]?.value.asDouble ?? 0 }, tb = group.map { b.fields[$0]?.value.asDouble ?? 0 }
            for (x, y) in zip(ta, tb) where x != y { return x > y ? a : b }
        } else {
            let sa = group.compactMap { a.fields[$0]?.stamp }.max(), sb = group.compactMap { b.fields[$0]?.stamp }.max()
            if let sa, let sb, sa != sb { return sa > sb ? a : b }
        }
        // Equal on the rule: pick by the complete content (values and stamps), a total order, so every device picks the same side.
        func content(_ r: UDRecord) -> String {
            group.map { name in r.fields[name].map { "\($0.value.canonical)@\($0.stamp.time)#\($0.stamp.device)" } ?? "-" }.joined(separator: "|")
        }
        return content(a) >= content(b) ? a : b
    }
}

// MARK: Typed views of the records

/// Watch state of one item, keyed by the library item's stable `key`.
public struct UDWatchValue: Equatable, Sendable {
    public var position: Double
    public var duration: Double?
    public var watched: Bool
    public var playCount: Int
    public var lastPlayed: Date?
    public var favorite: Bool
    public var hidden: Bool

    public init(position: Double = 0, duration: Double? = nil, watched: Bool = false, playCount: Int = 0,
                lastPlayed: Date? = nil, favorite: Bool = false, hidden: Bool = false) {
        self.position = position
        self.duration = duration
        self.watched = watched
        self.playCount = playCount
        self.lastPlayed = lastPlayed
        self.favorite = favorite
        self.hidden = hidden
    }
}

public enum UDWatch {
    /// Builds the patch for a play, a stop or an unwatch. `epoch` is the play-count epoch to write (a reset passes the
    /// time of the reset, anything else the record's current epoch).
    public static func progressPatch(key: String, _ v: UDWatchValue, epoch: Double, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.watch, id: key)
        r.set("position", .double(v.position), at: stamp)
        r.set("duration", v.duration.map { .double($0) } ?? .null, at: stamp)
        r.set("watched", .bool(v.watched), at: stamp)
        r.set("lastPlayed", v.lastPlayed.map { .double($0.timeIntervalSince1970) } ?? .null, at: stamp)
        r.set("playEpoch", .double(epoch), at: stamp)
        r.set("playCount", .int(Int64(v.playCount)), at: stamp)
        r.set("hidden", .bool(v.hidden), at: stamp)
        return r
    }

    public static func favoritePatch(key: String, favorite: Bool, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.watch, id: key)
        r.set("favorite", .bool(favorite), at: stamp)
        return r
    }

    public static func hiddenPatch(key: String, hidden: Bool, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.watch, id: key)
        r.set("hidden", .bool(hidden), at: stamp)
        return r
    }

    public static func epoch(of record: UDRecord?) -> Double { record?["playEpoch"]?.asDouble ?? 0 }

    /// nil for a deleted record. Reads defensively: a missing or odd field falls back to the default.
    public static func value(of record: UDRecord) -> UDWatchValue? {
        guard !record.isDeleted, record.type == UDSchema.watch else { return nil }
        let watched = record["watched"]?.asBool ?? false
        let count = Int(clamping: record["playCount"]?.asInt ?? 0)
        return UDWatchValue(
            position: max(0, record["position"]?.asDouble ?? 0), duration: record["duration"]?.asDouble,
            watched: watched, playCount: max(count, watched ? 1 : 0),
            lastPlayed: record["lastPlayed"]?.asDouble.map { Date(timeIntervalSince1970: $0) },
            favorite: record["favorite"]?.asBool ?? false, hidden: record["hidden"]?.asBool ?? false
        )
    }
}

/// A saved view (a filter and sort the user saved), keyed by a uid that is the same on every device.
public struct UDViewValue: Equatable, Sendable {
    public var uid: String
    public var name: String
    public var scopeKind: Int
    public var scopeSource: String
    public var scopePath: String
    public var query: String
    public var pinned: Bool
    public var position: Int
    public var createdAt: Date

    public init(uid: String, name: String, scopeKind: Int, scopeSource: String, scopePath: String, query: String, pinned: Bool, position: Int, createdAt: Date) {
        self.uid = uid
        self.name = name
        self.scopeKind = scopeKind
        self.scopeSource = scopeSource
        self.scopePath = scopePath
        self.query = query
        self.pinned = pinned
        self.position = position
        self.createdAt = createdAt
    }
}

public enum UDView {
    public static func patch(_ v: UDViewValue, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.view, id: v.uid)
        r.set("name", .string(v.name), at: stamp)
        r.set("scopeKind", .int(Int64(v.scopeKind)), at: stamp)
        r.set("scopeSource", .string(v.scopeSource), at: stamp)
        r.set("scopePath", .string(v.scopePath), at: stamp)
        r.set("query", .string(v.query), at: stamp)
        r.set("pinned", .bool(v.pinned), at: stamp)
        r.set("position", .int(Int64(v.position)), at: stamp)
        r.set("createdAt", .double(v.createdAt.timeIntervalSince1970), at: stamp)
        return r
    }

    public static func tombstone(uid: String, at stamp: UDStamp) -> UDRecord {
        UDRecord(type: UDSchema.view, id: uid, fields: [:], deleted: stamp)
    }

    public static func value(of r: UDRecord) -> UDViewValue? {
        guard !r.isDeleted, r.type == UDSchema.view, let name = r["name"]?.asString, let query = r["query"]?.asString else { return nil }
        return UDViewValue(
            uid: r.id, name: name, scopeKind: Int(clamping: r["scopeKind"]?.asInt ?? 0), scopeSource: r["scopeSource"]?.asString ?? "",
            scopePath: r["scopePath"]?.asString ?? "", query: query, pinned: r["pinned"]?.asBool ?? false,
            position: Int(clamping: r["position"]?.asInt ?? 0), createdAt: Date(timeIntervalSince1970: r["createdAt"]?.asDouble ?? 0)
        )
    }
}

/// A source the user added: everything needed to reconnect except the secret (the password is never in a record).
public struct UDSourceDefinition: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var name: String
    public var host: String
    public var port: Int?
    public var path: String
    public var username: String
    public var auth: String
    public var addedAt: Date
    /// Per-kind settings as "key=value" pairs joined by "&" (for example FTP "security=explicit"). Empty when none. Records written before this field existed read as empty.
    public var options: String
    /// The fingerprint of the TLS certificate or SSH host key the user approved, "" when none. Never a secret; it identifies a public key. Enforced on every later connection (docs/SOURCES_WIRING.md). Old records read as "".
    public var trustedFingerprint: String

    public init(id: String, kind: String, name: String, host: String = "", port: Int? = nil, path: String = "", username: String = "", auth: String = "none", addedAt: Date = Date(timeIntervalSince1970: 0), options: String = "", trustedFingerprint: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
        self.host = host
        self.port = port
        self.path = path
        self.username = username
        self.auth = auth
        self.addedAt = addedAt
        self.options = options
        self.trustedFingerprint = trustedFingerprint
    }
}

public enum UDSource {
    public static func patch(_ s: UDSourceDefinition, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.source, id: s.id)
        r.set("kind", .string(s.kind), at: stamp)
        r.set("name", .string(s.name), at: stamp)
        r.set("host", .string(s.host), at: stamp)
        r.set("port", s.port.map { .int(Int64($0)) } ?? .null, at: stamp)
        r.set("path", .string(s.path), at: stamp)
        r.set("username", .string(s.username), at: stamp)
        r.set("auth", .string(s.auth), at: stamp)
        r.set("addedAt", .double(s.addedAt.timeIntervalSince1970), at: stamp)
        r.set("options", .string(s.options), at: stamp)
        r.set("trustedFingerprint", .string(s.trustedFingerprint), at: stamp)
        return r
    }

    public static func tombstone(id: String, at stamp: UDStamp) -> UDRecord {
        UDRecord(type: UDSchema.source, id: id, fields: [:], deleted: stamp)
    }

    public static func value(of r: UDRecord) -> UDSourceDefinition? {
        guard !r.isDeleted, r.type == UDSchema.source, let kind = r["kind"]?.asString, let name = r["name"]?.asString else { return nil }
        return UDSourceDefinition(
            id: r.id, kind: kind, name: name, host: r["host"]?.asString ?? "", port: r["port"]?.asInt.map { Int($0) },
            path: r["path"]?.asString ?? "", username: r["username"]?.asString ?? "", auth: r["auth"]?.asString ?? "none",
            addedAt: Date(timeIntervalSince1970: r["addedAt"]?.asDouble ?? 0),
            options: r["options"]?.asString ?? "", trustedFingerprint: r["trustedFingerprint"]?.asString ?? ""
        )
    }
}

/// A file the user (or the online lookup) put in Movies or Shows by hand. It replaces what the file name says and is
/// read on every scan, so it survives a rescan and a rebuilt index; it syncs like every other record.
public struct UDSortOverrideValue: Equatable, Sendable {
    public enum Kind: String, Sendable { case movie, episode }
    public var sourceID: String
    public var path: String
    public var kind: Kind
    /// The movie title, or the show name for an episode.
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var episodeEnd: Int?
    /// "manual" (the user) or "onlineLookup" (the TMDB check in Needs Review).
    public var signal: String

    public init(sourceID: String, path: String, kind: Kind, title: String, year: Int? = nil, season: Int? = nil,
                episode: Int? = nil, episodeEnd: Int? = nil, signal: String = "manual") {
        self.sourceID = sourceID
        self.path = path
        self.kind = kind
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
        self.episodeEnd = episodeEnd
        self.signal = signal
    }
}

public enum UDSortOverride {
    /// The source id and the path, joined by a newline (which neither can contain).
    public static func recordID(sourceID: String, path: String) -> String { sourceID + "\n" + path }

    public static func patch(_ v: UDSortOverrideValue, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.sorting, id: recordID(sourceID: v.sourceID, path: v.path))
        r.set("kind", .string(v.kind.rawValue), at: stamp)
        r.set("title", .string(v.title), at: stamp)
        r.set("year", v.year.map { .int(Int64($0)) } ?? .null, at: stamp)
        r.set("season", v.season.map { .int(Int64($0)) } ?? .null, at: stamp)
        r.set("episode", v.episode.map { .int(Int64($0)) } ?? .null, at: stamp)
        r.set("episodeEnd", v.episodeEnd.map { .int(Int64($0)) } ?? .null, at: stamp)
        r.set("signal", .string(v.signal), at: stamp)
        return r
    }

    /// Removes the override: the file is sorted by its name again.
    public static func tombstone(sourceID: String, path: String, at stamp: UDStamp) -> UDRecord {
        UDRecord(type: UDSchema.sorting, id: recordID(sourceID: sourceID, path: path), fields: [:], deleted: stamp)
    }

    public static func value(of r: UDRecord) -> UDSortOverrideValue? {
        guard !r.isDeleted, r.type == UDSchema.sorting, let kindText = r["kind"]?.asString, let kind = UDSortOverrideValue.Kind(rawValue: kindText),
              let title = r["title"]?.asString, let newline = r.id.firstIndex(of: "\n") else { return nil }
        func int(_ name: String) -> Int? { r[name]?.asInt.map { Int(clamping: $0) } }
        return UDSortOverrideValue(
            sourceID: String(r.id[r.id.startIndex..<newline]), path: String(r.id[r.id.index(after: newline)...]), kind: kind, title: title,
            year: int("year"), season: int("season"), episode: int("episode"), episodeEnd: int("episodeEnd"),
            signal: r["signal"]?.asString ?? "manual"
        )
    }
}

/// Settings: one record, one field per setting key, so two devices changing different settings both win.
public enum UDSettings {
    public static let recordID = "settings"

    public static func patch(_ key: String, _ value: UDValue, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: UDSchema.settings, id: recordID)
        r.set(key, value, at: stamp)
        return r
    }

    public static func values(of r: UDRecord?) -> [String: UDValue] {
        guard let r, r.type == UDSchema.settings else { return [:] }
        return r.liveFields.mapValues(\.value)
    }
}
