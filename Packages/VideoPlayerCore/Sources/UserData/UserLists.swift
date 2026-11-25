import Foundation

// R471 (17), PROVISIONAL: the user's own lists, playlists and collections of library titles (movies, shows, episodes).
// User data (docs/STORAGE_MODEL.md section 2), synced and backed up like every other record (R456): two plain record
// types with no special merge rule (an unregistered type merges field by field, the later stamp wins):
//   "userlist"       one per list: name, kind ("list", "playlist", "collection"), createdAt. Deleting writes a deletion stamp.
//   "userlistentry"  one per title in a list, id "<list id>|<title ref>": the title's stable library key and its name at the
//                    time it was added (shown when the title is not in this device's library). Removing writes a deletion stamp.
// A title is named by its stable key (`items.key` for a movie or an episode, `series.key` for a show), which is derived from
// the file names and is the same on every device. Entries whose list was deleted are not shown.

public struct UDTitleRef: Hashable, Sendable, Comparable {
    public enum Kind: String, Sendable, CaseIterable { case movie, episode, show }
    public var kind: Kind
    public var key: String

    public init(kind: Kind, key: String) { self.kind = kind; self.key = key }

    /// "movie:<key>", "episode:<key>", "show:<key>".
    public var id: String { kind.rawValue + ":" + key }

    public init?(id: String) {
        guard let colon = id.firstIndex(of: ":"), let kind = Kind(rawValue: String(id[..<colon])) else { return nil }
        self.init(kind: kind, key: String(id[id.index(after: colon)...]))
    }

    public static func < (a: UDTitleRef, b: UDTitleRef) -> Bool { a.id < b.id }
}

public struct UDUserList: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case list, playlist, collection }
    public var id: String
    public var name: String
    public var kind: Kind
    public var createdAt: Date

    public init(id: String, name: String, kind: Kind, createdAt: Date) {
        self.id = id; self.name = name; self.kind = kind; self.createdAt = createdAt
    }

    public static let type = "userlist"

    static func value(of r: UDRecord) -> UDUserList? {
        guard r.type == type, !r.isDeleted, let name = r["name"]?.asString,
              let kind = r["kind"]?.asString.flatMap(Kind.init(rawValue:)) else { return nil }
        return UDUserList(id: r.id, name: name, kind: kind, createdAt: Date(timeIntervalSince1970: r["createdAt"]?.asDouble ?? 0))
    }
}

public struct UDUserListEntry: Hashable, Sendable {
    public var listID: String
    public var ref: UDTitleRef
    public var title: String
    public var addedAt: Date

    public init(listID: String, ref: UDTitleRef, title: String, addedAt: Date) {
        self.listID = listID; self.ref = ref; self.title = title; self.addedAt = addedAt
    }

    public static let type = "userlistentry"

    static func recordID(listID: String, ref: UDTitleRef) -> String { listID + "|" + ref.id }

    static func value(of r: UDRecord) -> UDUserListEntry? {
        guard r.type == type, !r.isDeleted, let listID = r["listID"]?.asString,
              let ref = r["ref"]?.asString.flatMap(UDTitleRef.init(id:)) else { return nil }
        return UDUserListEntry(listID: listID, ref: ref, title: r["title"]?.asString ?? "",
                               addedAt: Date(timeIntervalSince1970: r["addedAt"]?.asDouble ?? 0))
    }
}

public extension UserDataLedger {
    /// Creates a list; the name is trimmed and may not be empty. The id is new and random, so two devices never collide.
    @discardableResult
    func createList(name: String, kind: UDUserList.Kind, id: String = UUID().uuidString, at date: Date? = nil) -> UDUserList? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let s = stamp(date)
        var r = UDRecord(type: UDUserList.type, id: id)
        r.set("name", .string(name), at: s)
        r.set("kind", .string(kind.rawValue), at: s)
        r.set("createdAt", .double(s.time), at: s)
        apply(r)
        return userList(id: id)
    }

    /// Renames a list; an empty name changes nothing.
    func renameList(id: String, to name: String, at date: Date? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, userList(id: id) != nil else { return }
        var r = UDRecord(type: UDUserList.type, id: id)
        r.set("name", .string(name), at: stamp(date))
        apply(r)
    }

    /// Deletes a list and its entries (the titles stay in the library).
    func deleteList(id: String, at date: Date? = nil) {
        let s = stamp(date)
        for entry in listEntries(id) {
            apply(UDRecord(type: UDUserListEntry.type, id: UDUserListEntry.recordID(listID: id, ref: entry.ref), fields: [:], deleted: s))
        }
        apply(UDRecord(type: UDUserList.type, id: id, fields: [:], deleted: s))
    }

    func userList(id: String) -> UDUserList? {
        record(type: UDUserList.type, id: id).flatMap(UDUserList.value)
    }

    /// The lists of the given kinds, by name (case and accents ignored), then by id.
    func userLists(kinds: Set<UDUserList.Kind> = Set(UDUserList.Kind.allCases)) -> [UDUserList] {
        records(ofType: UDUserList.type).compactMap(UDUserList.value).filter { kinds.contains($0.kind) }.sorted {
            let order = $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive])
            return order != .orderedSame ? order == .orderedAscending : $0.id < $1.id
        }
    }

    func addToList(_ listID: String, ref: UDTitleRef, title: String, at date: Date? = nil) {
        guard userList(id: listID) != nil else { return }
        let s = stamp(date)
        var r = UDRecord(type: UDUserListEntry.type, id: UDUserListEntry.recordID(listID: listID, ref: ref))
        r.set("listID", .string(listID), at: s)
        r.set("ref", .string(ref.id), at: s)
        r.set("title", .string(title), at: s)
        r.set("addedAt", .double(s.time), at: s)
        apply(r)
    }

    func removeFromList(_ listID: String, ref: UDTitleRef, at date: Date? = nil) {
        apply(UDRecord(type: UDUserListEntry.type, id: UDUserListEntry.recordID(listID: listID, ref: ref), fields: [:], deleted: stamp(date)))
    }

    /// The titles of a list in the order they were added (oldest first); none when the list was deleted.
    func listEntries(_ listID: String) -> [UDUserListEntry] {
        guard userList(id: listID) != nil else { return [] }
        return records(ofType: UDUserListEntry.type).compactMap(UDUserListEntry.value).filter { $0.listID == listID }
            .sorted { $0.addedAt != $1.addedAt ? $0.addedAt < $1.addedAt : $0.ref < $1.ref }
    }

    /// The ids of the live lists that hold a title.
    func listIDs(containing ref: UDTitleRef) -> Set<String> {
        let live = Set(userLists().map(\.id))
        return Set(records(ofType: UDUserListEntry.type).compactMap(UDUserListEntry.value)
            .filter { $0.ref == ref && live.contains($0.listID) }.map(\.listID))
    }
}
