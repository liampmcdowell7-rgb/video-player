import Foundation

// R449 (owner's request of 23 Nov 2026): the user layer of metadata. Every title can be edited at show, season, movie and
// episode level; an edit is one field of one item, stamped like every other user-data field, so it syncs (record type
// "edit"), travels in the export, and is never overwritten by a rescan, Fix Match, an online refresh or a Plex re-index
// (those write other records and caches; the edit is read on top of them: precedence B3, user > embedded chapters >
// local sidecar > online). The edit lives in the ledger's user-data records, NOT in Caches-based generated data, so the
// library backup's purge (R163) never takes it.
//
// Record shape: id = `UDEditKey.recordID`; fields "f.<field>" (one per edited field, each with its own stamp, so the newest
// edit wins per field) and "schema" (the format of the values). A field set to null means "reset: no override". A record
// with a larger "schema" than this app knows is kept untouched and not read (never restore a newer format).

public enum UDEditField: String, CaseIterable, Codable, Sendable {
    // General
    case title, sortTitle, originalTitle, tagline, overview, releaseDate, year, certification, studio, runtime
    case seasonNumber, episodeNumber, episodeTitle, airDate
    // Tags
    case genres, collections, labels
    // Cast and crew
    case cast, crew
    // Artwork
    case poster, backdrop, logo, seasonPoster, episodeStill

    public var storedName: String { "f." + rawValue }

    public enum Group: String, CaseIterable, Sendable { case general, artwork, castAndCrew, tags }

    public var group: Group {
        switch self {
        case .poster, .backdrop, .logo, .seasonPoster, .episodeStill: return .artwork
        case .cast, .crew: return .castAndCrew
        case .genres, .collections, .labels: return .tags
        default: return .general
        }
    }
}

/// A person in the cast or crew: `role` is the character for cast, the job (director, writer) for crew.
public struct UDEditPerson: Codable, Hashable, Sendable {
    public var name: String
    public var role: String
    public init(name: String, role: String = "") {
        self.name = name
        self.role = role
    }
}

/// The picture chosen for an artwork field. Online candidates are kept as the supplier's path; a picture beside the file or
/// from a typed web address becomes a file of the user-artwork folder, named by its content (`UDUserArtwork`), so the same
/// picture is one file on every device and in the backup.
public enum UDEditArtwork: Hashable, Sendable {
    case online(String)
    case file(String)
    case address(String)

    public var stored: String {
        switch self {
        case let .online(p): return "online:" + p
        case let .file(n): return "file:" + n
        case let .address(a): return "address:" + a
        }
    }

    public init?(stored: String) {
        if stored.hasPrefix("online:") { self = .online(String(stored.dropFirst(7))) }
        else if stored.hasPrefix("file:") { self = .file(String(stored.dropFirst(5))) }
        else if stored.hasPrefix("address:") { self = .address(String(stored.dropFirst(8))) }
        else { return nil }
    }
}

/// One edited value.
public enum UDEditValue: Hashable, Sendable {
    case text(String)
    case number(Int64)
    case list([String])
    case people([UDEditPerson])
    case artwork(UDEditArtwork)

    var stored: UDValue {
        switch self {
        case let .text(s): return .string("t" + s)
        case let .number(n): return .int(n)
        case let .list(l): return .string("l" + Self.json(l))
        case let .people(p): return .string("p" + Self.json(p))
        case let .artwork(a): return .string("a" + a.stored)
        }
    }

    init?(stored: UDValue) {
        switch stored {
        case let .int(n): self = .number(n)
        case let .string(s):
            guard let tag = s.first else { return nil }
            let body = String(s.dropFirst())
            switch tag {
            case "t": self = .text(body)
            case "l": guard let l = Self.decode([String].self, body) else { return nil }; self = .list(l)
            case "p": guard let p = Self.decode([UDEditPerson].self, body) else { return nil }; self = .people(p)
            case "a": guard let a = UDEditArtwork(stored: body) else { return nil }; self = .artwork(a)
            default: return nil
            }
        default: return nil
        }
    }

    private static func json<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? String(data: e.encode(v), encoding: .utf8)) ?? "[]"
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ s: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    public var text: String? { if case let .text(s) = self { return s } else { return nil } }
    public var number: Int64? { if case let .number(n) = self { return n } else { return nil } }
    public var list: [String]? { if case let .list(l) = self { return l } else { return nil } }
    public var people: [UDEditPerson]? { if case let .people(p) = self { return p } else { return nil } }
    public var artwork: UDEditArtwork? { if case let .artwork(a) = self { return a } else { return nil } }
}

/// The stable identity of an edited item (R449, PROVISIONAL). Never a database row number.
///  - a title with an online id: "movie-<tmdb>" / "show-<tmdb>" (survives a moved or renamed file and a re-index);
///  - otherwise the file: "file-<source id>-<path>" (source plus normalised path);
///  - a season or episode: the show's key plus "s<season>" / "s<season>e<episode>".
/// A title edited before it is matched has a file key; once matched it also has an online key. `UDEditKey.candidates` lists
/// both, newest knowledge first, and reads merge them per field. A file that is moved or renamed and has no online id
/// loses its file key: `rekeyEdits(from:to:)` carries the edits over when the scan knows it is the same file.
public struct UDEditKey: Hashable, Sendable {
    public var recordID: String
    public init(recordID: String) { self.recordID = recordID }

    public static func movie(tmdbID: Int) -> UDEditKey { UDEditKey(recordID: "movie-\(tmdbID)") }
    public static func show(tmdbID: Int) -> UDEditKey { UDEditKey(recordID: "show-\(tmdbID)") }

    public static func file(sourceID: String, path: String) -> UDEditKey {
        UDEditKey(recordID: "file-\(sourceID)-\(normalised(path))")
    }

    public func season(_ number: Int) -> UDEditKey { UDEditKey(recordID: recordID + "-s\(number)") }
    public func episode(season: Int, episode: Int) -> UDEditKey { UDEditKey(recordID: recordID + "-s\(season)e\(episode)") }

    /// Case-preserving, one slash between parts, no leading or trailing slash, Unicode normalised (NFC).
    static func normalised(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.split(separator: "/").joined(separator: "/")
    }
}

/// What the user changed on one item: the fields with their values, and when each was set (for "edited" markers).
public struct UDEditValues: Equatable, Sendable {
    public var values: [UDEditField: UDEditValue] = [:]
    public var stamps: [UDEditField: UDStamp] = [:]
    public init() {}

    public var isEmpty: Bool { values.isEmpty }
    public func isEdited(_ field: UDEditField) -> Bool { values[field] != nil }
    public subscript(field: UDEditField) -> UDEditValue? { values[field] }
}

public enum UDEdit {
    public static let type = "edit"
    /// The format of the values. A record with a larger number is kept and not read.
    public static let schemaVersion = 1

    public static func patch(key: UDEditKey, field: UDEditField, value: UDEditValue?, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: type, id: key.recordID)
        r.set("schema", .int(Int64(schemaVersion)), at: stamp)
        r.set(field.storedName, value?.stored ?? .null, at: stamp)
        return r
    }

    /// The edits of one record, or nil for a deleted one or one written by a newer app.
    public static func values(of r: UDRecord) -> UDEditValues? {
        guard r.type == type, !r.isDeleted, (r["schema"]?.asInt ?? 1) <= Int64(schemaVersion) else { return nil }
        var out = UDEditValues()
        for field in UDEditField.allCases {
            guard let f = r.liveFields[field.storedName], let v = UDEditValue(stored: f.value) else { continue }
            out.values[field] = v
            out.stamps[field] = f.stamp
        }
        return out
    }
}

public extension UserDataLedger {
    /// Sets one field. Never touches the other fields of the item.
    func setEdit(_ key: UDEditKey, _ field: UDEditField, _ value: UDEditValue, at date: Date? = nil) {
        apply(UDEdit.patch(key: key, field: field, value: value, at: stamp(date)))
    }

    /// Resets one field to what the sources say.
    func resetEdit(_ key: UDEditKey, _ field: UDEditField, at date: Date? = nil) {
        apply(UDEdit.patch(key: key, field: field, value: nil, at: stamp(date)))
    }

    /// Resets every field of the item (a deletion stamp: a later edit brings the record back).
    func resetAllEdits(_ key: UDEditKey, at date: Date? = nil) {
        apply(UDRecord(type: UDEdit.type, id: key.recordID, fields: [:], deleted: stamp(date)))
    }

    /// The edits for an item known under several keys: per field, the newest stamp wins across the keys.
    func edits(for keys: [UDEditKey]) -> UDEditValues {
        var out = UDEditValues()
        for key in keys {
            guard let r = record(type: UDEdit.type, id: key.recordID), let v = UDEdit.values(of: r) else { continue }
            for (field, value) in v.values {
                guard let s = v.stamps[field] else { continue }
                if let old = out.stamps[field], old >= s { continue }
                out.values[field] = value
                out.stamps[field] = s
            }
        }
        // A reset (null) is newer than an older edit under another key: it wins and the field reads as not edited.
        for key in keys {
            guard let r = record(type: UDEdit.type, id: key.recordID), (r["schema"]?.asInt ?? 1) <= Int64(UDEdit.schemaVersion) else { continue }
            for field in UDEditField.allCases {
                guard let f = r.liveFields[field.storedName], f.value == .null, let s = out.stamps[field], f.stamp > s else { continue }
                out.values[field] = nil
                out.stamps[field] = nil
            }
        }
        return out
    }

    /// A file that moved or was renamed: the edits follow it. The old record is deleted, the new one gets every field with
    /// its original stamp, so the newest-edit-wins rule is unchanged.
    func rekeyEdits(from old: UDEditKey, to new: UDEditKey, at date: Date? = nil) {
        guard old != new, let r = record(type: UDEdit.type, id: old.recordID), !r.isDeleted else { return }
        var moved = UDRecord(type: UDEdit.type, id: new.recordID, fields: r.liveFields)
        moved.deleted = nil
        apply(moved)
        apply(UDRecord(type: UDEdit.type, id: old.recordID, fields: [:], deleted: stamp(date)))
    }
}

// MARK: Chosen audio and subtitle per item (playback data)

/// The audio and subtitle choice the user made for one item (R449 part B 2). Record type "trackchoice", keyed by the item's
/// stable key like the watch record. The system player owns the selection UI, so nothing in the app writes this yet; the
/// record, its merge rule and its place in sync and export are in, ready for the day the choice can be observed.
public struct UDTrackChoice: Equatable, Sendable {
    public var audio: String?
    public var subtitle: String?
    public var subtitlesOff: Bool
    public init(audio: String? = nil, subtitle: String? = nil, subtitlesOff: Bool = false) {
        self.audio = audio
        self.subtitle = subtitle
        self.subtitlesOff = subtitlesOff
    }
}

public enum UDTrackChoiceRecord {
    public static let type = "trackchoice"

    public static func patch(key: String, _ c: UDTrackChoice, at stamp: UDStamp) -> UDRecord {
        var r = UDRecord(type: type, id: key)
        r.set("audio", c.audio.map { .string($0) } ?? .null, at: stamp)
        r.set("subtitle", c.subtitle.map { .string($0) } ?? .null, at: stamp)
        r.set("subtitlesOff", .bool(c.subtitlesOff), at: stamp)
        return r
    }

    public static func value(of r: UDRecord) -> UDTrackChoice? {
        guard r.type == type, !r.isDeleted else { return nil }
        return UDTrackChoice(audio: r["audio"]?.asString, subtitle: r["subtitle"]?.asString, subtitlesOff: r["subtitlesOff"]?.asBool ?? false)
    }
}

public extension UserDataLedger {
    func setTrackChoice(itemKey: String, _ choice: UDTrackChoice, at date: Date? = nil) {
        apply(UDTrackChoiceRecord.patch(key: itemKey, choice, at: stamp(date)))
    }

    func trackChoice(itemKey: String) -> UDTrackChoice? {
        record(type: UDTrackChoiceRecord.type, id: itemKey).flatMap { UDTrackChoiceRecord.value(of: $0) }
    }
}
