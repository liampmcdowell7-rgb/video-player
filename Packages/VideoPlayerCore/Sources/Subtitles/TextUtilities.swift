import Foundation

/// Small helpers shared by the text parsers.
enum SubtitleText {

    /// Removes a leading U+FEFF (a byte order mark that survived decoding).
    static func strippingBOM(_ text: String) -> String {
        if text.unicodeScalars.first == "\u{FEFF}" { return String(text.unicodeScalars.dropFirst()) }
        return text
    }

    /// Splits on CRLF, LF or a lone CR. Empty lines are kept. Never returns an empty array.
    static func lines(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        var previousWasCR = false
        for sc in text.unicodeScalars {
            if sc == "\r" {
                out.append(String(current))
                current = String.UnicodeScalarView()
                previousWasCR = true
            } else if sc == "\n" {
                if previousWasCR { previousWasCR = false; continue }
                out.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                previousWasCR = false
                current.append(sc)
            }
        }
        out.append(String(current))
        return out
    }

    static func isBlank(_ line: String) -> Bool {
        for sc in line.unicodeScalars where !(sc == " " || sc == "\t" || sc == "\u{00A0}" || sc == "\u{3000}" || sc == "\u{FEFF}") { return false }
        return true
    }

    static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func isDigits(_ s: Substring) -> Bool {
        if s.isEmpty { return false }
        for u in s.utf8 where u < 0x30 || u > 0x39 { return false }
        return true
    }

    /// Reads "1:02:03,456", "02:03.456", "00:00:01.5" or "12.5" as seconds. The number of fraction digits
    /// decides the scale, so ",5" is half a second and ",50" too. Returns nil for anything else.
    static func timestamp(_ raw: Substring) -> TimeInterval? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s.utf8.count > 30 { return nil }
        var body = Substring(s)
        var negative = false
        if body.hasPrefix("-") { negative = true; body = body.dropFirst() }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        if parts.isEmpty || parts.count > 3 { return nil }
        var total = 0.0
        for part in parts.dropLast() {
            guard isDigits(part), part.utf8.count <= 9, let v = Double(part) else { return nil }
            total = total * 60 + v
        }
        guard let last = parts.last else { return nil }
        let secondParts = last.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "." })
        if secondParts.isEmpty || secondParts.count > 2 { return nil }
        guard isDigits(secondParts[0]), secondParts[0].utf8.count <= 9, let seconds = Double(secondParts[0]) else { return nil }
        total = total * 60 + seconds
        if secondParts.count == 2 {
            let f = secondParts[1]
            if !f.isEmpty {
                guard isDigits(f), f.utf8.count <= 9, let fv = Double(f) else { return nil }
                total += fv / pow(10, Double(f.utf8.count))
            }
        }
        return negative ? -total : total
    }

    /// Sorts by start, keeping file order for equal starts.
    static func sortedStable(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        let order = cues.indices.sorted { a, b in
            if cues[a].start != cues[b].start { return cues[a].start < cues[b].start }
            return a < b
        }
        return order.map { cues[$0] }
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let scalars = Array(s.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if c == "&" {
                var j = i + 1
                var name = String.UnicodeScalarView()
                while j < scalars.count, j - i <= 10, scalars[j] != ";", scalars[j] != "&", scalars[j] != " " {
                    name.append(scalars[j])
                    j += 1
                }
                if j < scalars.count, scalars[j] == ";", let r = entity(String(name)) {
                    out.append(r)
                    i = j + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    private static func entity(_ name: String) -> Unicode.Scalar? {
        switch name {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        case "lrm": return "\u{200E}"
        case "rlm": return "\u{200F}"
        default:
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                guard let v = UInt32(name.dropFirst(2), radix: 16) else { return nil }
                return Unicode.Scalar(v)
            }
            if name.hasPrefix("#") {
                guard let v = UInt32(name.dropFirst()) else { return nil }
                return Unicode.Scalar(v)
            }
            return nil
        }
    }

    // MARK: Colours

    private static let namedColors: [String: (UInt8, UInt8, UInt8)] = [
        "white": (255, 255, 255), "black": (0, 0, 0), "red": (255, 0, 0), "green": (0, 128, 0),
        "blue": (0, 0, 255), "yellow": (255, 255, 0), "cyan": (0, 255, 255), "aqua": (0, 255, 255),
        "magenta": (255, 0, 255), "fuchsia": (255, 0, 255), "gray": (128, 128, 128), "grey": (128, 128, 128),
        "orange": (255, 165, 0), "lime": (0, 255, 0), "silver": (192, 192, 192), "maroon": (128, 0, 0),
        "navy": (0, 0, 128), "olive": (128, 128, 0), "purple": (128, 0, 128), "teal": (0, 128, 128),
        "pink": (255, 192, 203), "brown": (165, 42, 42),
    ]

    /// CSS-like colour: "#RRGGBB", "#RGB", "RRGGBB" (six hex digits) or a basic colour name.
    static func cssColor(_ raw: String) -> SubtitleColor? {
        let s = trimmed(raw).lowercased()
        if s.isEmpty { return nil }
        if let n = namedColors[s] { return SubtitleColor(red: n.0, green: n.1, blue: n.2) }
        var hex = Substring(s)
        if hex.hasPrefix("#") { hex = hex.dropFirst() }
        let digits = hex.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
        guard digits else { return nil }
        if hex.count == 6, let v = UInt32(hex, radix: 16) {
            return SubtitleColor(red: UInt8((v >> 16) & 0xFF), green: UInt8((v >> 8) & 0xFF), blue: UInt8(v & 0xFF))
        }
        if hex.count == 3, let v = UInt32(hex, radix: 16) {
            let r = UInt8((v >> 8) & 0xF), g = UInt8((v >> 4) & 0xF), b = UInt8(v & 0xF)
            return SubtitleColor(red: r * 17, green: g * 17, blue: b * 17)
        }
        return nil
    }

    /// ASS colour: "&HAABBGGRR", "&HBBGGRR&", "H0000FF" or a decimal number (SSA, may be negative).
    /// The ASS alpha byte is inverted (00 = opaque); the result uses 255 = opaque.
    static func assColor(_ raw: String) -> SubtitleColor? {
        var s = trimmed(raw)
        if s.isEmpty { return nil }
        var value: UInt32
        let lower = s.lowercased()
        if lower.hasPrefix("&h") || lower.hasPrefix("$") || lower.hasPrefix("h") {
            s = String(lower.drop(while: { $0 == "&" || $0 == "h" || $0 == "$" }))
            while s.hasSuffix("&") { s.removeLast() }
            guard !s.isEmpty, s.utf8.count <= 16, let v = UInt64(s, radix: 16) else { return nil }
            value = UInt32(truncatingIfNeeded: v)
        } else if let v = Int64(s) {
            value = UInt32(truncatingIfNeeded: v)
        } else {
            return nil
        }
        let a = UInt8((value >> 24) & 0xFF)
        return SubtitleColor(
            red: UInt8(value & 0xFF),
            green: UInt8((value >> 8) & 0xFF),
            blue: UInt8((value >> 16) & 0xFF),
            alpha: 255 - a
        )
    }
}
