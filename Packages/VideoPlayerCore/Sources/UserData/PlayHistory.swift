import Foundation

// R471 (20), PROVISIONAL: Play History. One record per playback of a movie or an episode, record type "playhistory", id
// "<item key>|<device>|<start time>", written from the player's progress saves only (marking a title watched by hand is not a
// playback and is not listed). Fields: itemKey, device, startedAt, lastAt, position, duration, finished. A save less than
// `sessionGap` after the last one of the same item on the same device continues that playback; a later one starts a new
// entry. Synced and backed up like every other record (R456: an unregistered type merges field by field, the later stamp
// wins). Clearing writes deletion stamps; the watch state (watched, progress, play count) is not touched.

public struct UDPlayRecord: Equatable, Hashable, Sendable {
    public var id: String
    public var itemKey: String
    public var device: String
    public var startedAt: Date
    public var lastAt: Date
    public var position: Double
    public var duration: Double?
    public var finished: Bool

    public init(id: String, itemKey: String, device: String, startedAt: Date, lastAt: Date, position: Double, duration: Double?, finished: Bool) {
        self.id = id; self.itemKey = itemKey; self.device = device; self.startedAt = startedAt; self.lastAt = lastAt
        self.position = position; self.duration = duration; self.finished = finished
    }

    static func value(of r: UDRecord) -> UDPlayRecord? {
        guard r.type == UDPlayHistory.type, !r.isDeleted, let key = r["itemKey"]?.asString,
              let started = r["startedAt"]?.asDouble else { return nil }
        return UDPlayRecord(id: r.id, itemKey: key, device: r["device"]?.asString ?? "",
                            startedAt: Date(timeIntervalSince1970: started),
                            lastAt: Date(timeIntervalSince1970: r["lastAt"]?.asDouble ?? started),
                            position: max(0, r["position"]?.asDouble ?? 0), duration: r["duration"]?.asDouble,
                            finished: r["finished"]?.asBool ?? false)
    }
}

public enum UDPlayHistory {
    public static let type = "playhistory"
    /// A pause longer than this starts a new entry. PROVISIONAL.
    public static let sessionGap: TimeInterval = 30 * 60
    /// Entries kept per item; older ones are cleared when a new one starts. PROVISIONAL.
    public static let keptPerItem = 50
}

public extension UserDataLedger {
    /// Records one progress save of the player.
    func recordPlay(itemKey: String, position: Double, duration: Double?, finished: Bool, at date: Date? = nil) {
        let s = stamp(date)
        let now = s.time
        let mine = playHistory(itemKey: itemKey).filter { $0.device == deviceID }
        var r: UDRecord
        if let last = mine.first, now - last.lastAt.timeIntervalSince1970 < UDPlayHistory.sessionGap, now >= last.lastAt.timeIntervalSince1970 {
            r = UDRecord(type: UDPlayHistory.type, id: last.id)
            if finished && !last.finished { r.set("finished", .bool(true), at: s) }
        } else {
            r = UDRecord(type: UDPlayHistory.type, id: "\(itemKey)|\(deviceID)|\(Int64(now * 1000))")
            r.set("itemKey", .string(itemKey), at: s)
            r.set("device", .string(deviceID), at: s)
            r.set("startedAt", .double(now), at: s)
            r.set("finished", .bool(finished), at: s)
            let all = playHistory(itemKey: itemKey)
            if all.count >= UDPlayHistory.keptPerItem {
                for old in all.suffix(all.count - UDPlayHistory.keptPerItem + 1) {
                    apply(UDRecord(type: UDPlayHistory.type, id: old.id, fields: [:], deleted: s))
                }
            }
        }
        r.set("lastAt", .double(now), at: s)
        r.set("position", .double(max(0, position)), at: s)
        r.set("duration", duration.map { .double($0) } ?? .null, at: s)
        apply(r)
    }

    /// The playbacks of an item, newest first.
    func playHistory(itemKey: String) -> [UDPlayRecord] {
        records(ofType: UDPlayHistory.type).compactMap(UDPlayRecord.value).filter { $0.itemKey == itemKey }
            .sorted { $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.id > $1.id }
    }

    /// Clears the item's playbacks (on every device, through the sync). The watch state stays.
    func clearPlayHistory(itemKey: String, at date: Date? = nil) {
        let s = stamp(date)
        for entry in playHistory(itemKey: itemKey) {
            apply(UDRecord(type: UDPlayHistory.type, id: entry.id, fields: [:], deleted: s))
        }
    }
}
