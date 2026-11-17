import Foundation

/// A forgiving reader over parsed JSON. Missing keys, nulls and wrong types give nil or empty values,
/// never an error, so a provider changing or omitting a field cannot break decoding of the rest.
struct JSON {
    let raw: Any?

    init(raw: Any?) { self.raw = raw }

    init(data: Data) throws {
        do {
            self.raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw MetadataError.decoding("response is not valid JSON")
        }
    }

    subscript(_ key: String) -> JSON { JSON(raw: (raw as? [String: Any])?[key]) }

    var isObject: Bool { raw is [String: Any] }
    var array: [JSON] { (raw as? [Any])?.map { JSON(raw: $0) } ?? [] }

    /// A string with surrounding whitespace removed; nil when missing, not a string, or blank.
    var text: String? {
        guard let s = raw as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var int: Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double, d == d.rounded(), abs(d) < 1e15 { return Int(d) }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    var double: Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    var bool: Bool? {
        if let b = raw as? Bool { return b }
        if let s = raw as? String { return ["true", "1"].contains(s.lowercased()) ? true : (["false", "0"].contains(s.lowercased()) ? false : nil) }
        return nil
    }
}
