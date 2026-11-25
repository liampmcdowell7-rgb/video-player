import Foundation

// R471 (16), PROVISIONAL: the user's own star rating of a movie, show, season or episode (1 to 5 whole stars). One record
// per title, record type "rating", keyed like the title's edits (`UDEditKey`: the online id when known, else the file or the
// show's name), so it follows the title through a Fix Match like an edit does. Field "stars": the number, or null when the
// rating was cleared. Synced and backed up like every other user record (R456: an unregistered type merges field by field,
// the later stamp wins). Written reviews are NOT built (OPEN_QUESTIONS R471 (16)).

public enum UDRating {
    public static let type = "rating"
    public static let range = 1...5
}

public extension UserDataLedger {
    /// Sets the rating (1 to 5) or clears it (nil).
    func setRating(_ key: UDEditKey, stars: Int?, at date: Date? = nil) {
        var r = UDRecord(type: UDRating.type, id: key.recordID)
        let value: UDValue = stars.map { .int(Int64(min(max($0, UDRating.range.lowerBound), UDRating.range.upperBound))) } ?? .null
        r.set("stars", value, at: stamp(date))
        apply(r)
    }

    /// The rating of a title known under several keys: the newest stamp across the keys wins; a newer clear wins too.
    func rating(for keys: [UDEditKey]) -> Int? {
        var best: UDField?
        for key in keys {
            guard let r = record(type: UDRating.type, id: key.recordID), let f = r.liveFields["stars"] else { continue }
            if let b = best, b.stamp >= f.stamp { continue }
            best = f
        }
        guard let stars = best?.value.asInt, UDRating.range.contains(Int(stars)) else { return nil }
        return Int(stars)
    }
}
