import Foundation

// The data model for everything that must survive a system cleanup of Caches (docs/STORAGE_MODEL.md).
//
// A record is a bag of fields. Every field carries the stamp (time + device) of the edit that wrote it, so two
// copies of a record merge field by field: the latest stamp wins. `UDSchema.merge` is commutative, associative and
// idempotent (tested), so the order in which devices and the cloud exchange records never changes the result.

/// When and where an edit was made. Ordered by time, then by device id so a tie still has one winner.
public struct UDStamp: Codable, Hashable, Comparable, Sendable {
    public var time: Double
    public var device: String

    public init(time: Double, device: String) {
        self.time = time
        self.device = device
    }

    public init(_ date: Date, device: String) {
        self.init(time: date.timeIntervalSince1970, device: device)
    }

    public static func < (a: UDStamp, b: UDStamp) -> Bool {
        a.time != b.time ? a.time < b.time : a.device < b.device
    }
}

/// A field value. Encoded as a one-key object so integers and doubles never turn into each other on a round trip.
public enum UDValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)

    public var asBool: Bool? {
        switch self {
        case let .bool(v): return v
        case let .int(v): return v != 0
        default: return nil
        }
    }

    public var asInt: Int64? {
        switch self {
        case let .int(v): return v
        case let .double(v): return v.isFinite && abs(v) < 9e18 ? Int64(v) : nil
        case let .bool(v): return v ? 1 : 0
        default: return nil
        }
    }

    public var asDouble: Double? {
        switch self {
        case let .double(v): return v
        case let .int(v): return Double(v)
        default: return nil
        }
    }

    public var asString: String? {
        if case let .string(v) = self { return v }
        return nil
    }

    /// A string that identifies the value exactly; used to break ties the same way on every device.
    var canonical: String {
        switch self {
        case .null: return "n"
        case let .bool(v): return v ? "b1" : "b0"
        case let .int(v): return "i\(v)"
        case let .double(v): return "d\(v)"
        case let .string(v): return "s" + v
        }
    }
}

extension UDValue: Codable {
    private enum Key: String, CodingKey { case b, i, d, s }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .b) { self = .bool(v) }
        else if let v = try c.decodeIfPresent(Int64.self, forKey: .i) { self = .int(v) }
        else if let v = try c.decodeIfPresent(Double.self, forKey: .d) { self = .double(v) }
        else if let v = try c.decodeIfPresent(String.self, forKey: .s) { self = .string(v) }
        else { self = .null }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .null: break
        case let .bool(v): try c.encode(v, forKey: .b)
        case let .int(v): try c.encode(v, forKey: .i)
        case let .double(v):
            guard v.isFinite else { throw EncodingError.invalidValue(v, .init(codingPath: c.codingPath, debugDescription: "non-finite number")) }
            try c.encode(v, forKey: .d)
        case let .string(v): try c.encode(v, forKey: .s)
        }
    }
}

public struct UDField: Codable, Hashable, Sendable {
    public var value: UDValue
    public var stamp: UDStamp

    public init(_ value: UDValue, _ stamp: UDStamp) {
        self.value = value
        self.stamp = stamp
    }
}

/// One user-data record: a type, an id that is stable across devices, stamped fields and an optional deletion stamp.
public struct UDRecord: Codable, Hashable, Sendable {
    public var type: String
    public var id: String
    public var fields: [String: UDField]
    /// Set when the record was deleted. Fields stamped later than this bring the record back to life.
    public var deleted: UDStamp?

    public init(type: String, id: String, fields: [String: UDField] = [:], deleted: UDStamp? = nil) {
        self.type = type
        self.id = id
        self.fields = fields
        self.deleted = deleted
    }

    /// `type/id`, the key the ledger uses.
    public var key: String { type + "/" + id }

    /// A tombstone that has not been revived: deleted and no field newer than the deletion.
    public var isDeleted: Bool { deleted != nil && liveFields.isEmpty }

    /// The fields that count: all of them, or only those newer than the deletion stamp when there is one. Older fields stay
    /// stored (merge never drops anything, which keeps it order independent) but are not read.
    public var liveFields: [String: UDField] {
        guard let d = deleted else { return fields }
        return fields.filter { $0.value.stamp > d }
    }

    public subscript(name: String) -> UDValue? {
        guard let f = fields[name] else { return nil }
        if let d = deleted, f.stamp <= d { return nil }
        return f.value
    }

    public mutating func set(_ name: String, _ value: UDValue, at stamp: UDStamp) {
        fields[name] = UDField(value, stamp)
    }

    /// Size of the record as it is stored (what the 1 MB CloudKit limit is measured against).
    public var encodedByteCount: Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self).count) ?? Int.max
    }

    /// The name used for the record in the cloud: `type.id` when that is short ASCII, a hash of the id otherwise.
    /// (The 255-character record-name limit is recalled, not verified from an Apple page, so this stays well below it.)
    public var cloudName: String {
        let plain = type + "." + id
        let safe = plain.utf8.count <= 180 && plain.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x21 && $0.value != 0x2F }
        if safe { return plain }
        return type + ".h" + UDHash.hex128(id)
    }
}

/// FNV-1a, twice with different offsets: a stable name for long or unusual ids (not a security feature).
enum UDHash {
    static func fnv(_ s: String, seed: UInt64) -> UInt64 {
        var h = seed
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    static func hex128(_ s: String) -> String {
        let a = fnv(s, seed: 0xcbf29ce484222325), b = fnv(s, seed: 0x84222325cbf29ce4)
        return String(a, radix: 16).leftPadded(16) + String(b, radix: 16).leftPadded(16)
    }
}

extension String {
    func leftPadded(_ n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}
