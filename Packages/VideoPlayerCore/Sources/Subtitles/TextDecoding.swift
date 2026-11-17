import Foundation

/// The text encodings the decoder can read.
///
/// Decoded by our own code (tables in `EncodingTables.swift`): UTF-8, UTF-16, UTF-32 and every
/// single-byte code page below. Decoded through Foundation: Shift-JIS, EUC-KR, GB 18030 (which covers
/// GBK and GB 2312) and Big5. Foundation decodes those four on Linux (checked) and on Apple platforms.
public enum SubtitleTextEncoding: String, Sendable, CaseIterable, Codable {
    case ascii
    case utf8, utf8BOM
    case utf16LE, utf16BE, utf16LEBOM, utf16BEBOM
    case utf32LE, utf32BE
    case windows1250, windows1251, windows1252, windows1253, windows1254, windows1255, windows1256
    case windows1257, windows1258, windows874
    case iso8859_1, iso8859_2, iso8859_15
    case cp437, cp850
    case shiftJIS, eucKR, gb18030, big5

    /// Foundation's raw value for the four multi-byte encodings.
    var foundationRawValue: UInt? {
        switch self {
        case .shiftJIS: return String.Encoding.shiftJIS.rawValue
        case .eucKR: return 0x8000_0940
        case .gb18030: return 0x8000_0632
        case .big5: return 0x8000_0A03
        default: return nil
        }
    }

    var table: [UInt16]? {
        switch self {
        case .windows1250: return SingleByteTables.windows1250
        case .windows1251: return SingleByteTables.windows1251
        case .windows1252: return SingleByteTables.windows1252
        case .windows1253: return SingleByteTables.windows1253
        case .windows1254: return SingleByteTables.windows1254
        case .windows1255: return SingleByteTables.windows1255
        case .windows1256: return SingleByteTables.windows1256
        case .windows1257: return SingleByteTables.windows1257
        case .windows1258: return SingleByteTables.windows1258
        case .windows874: return SingleByteTables.windows874
        case .iso8859_1: return SingleByteTables.iso8859_1
        case .iso8859_2: return SingleByteTables.iso8859_2
        case .iso8859_15: return SingleByteTables.iso8859_15
        case .cp437: return SingleByteTables.cp437
        case .cp850: return SingleByteTables.cp850
        default: return nil
        }
    }
}

public struct DecodedSubtitleText: Sendable {
    public var text: String
    public var encoding: SubtitleTextEncoding
    /// Short plain-language note when the choice was a guess ("No language hint; assumed Windows-1252").
    public var note: String?
    /// Number of bytes that could not be mapped (shown as U+FFFD).
    public var invalidBytes: Int
}

/// Reads subtitle file bytes as text. Never throws and never returns nil: the worst case is some U+FFFD.
public enum SubtitleTextDecoder {

    /// - Parameters:
    ///   - languageHint: a language tag or name ("fr", "Japanese", "zh-Hant"); decides the legacy code page.
    ///     Without a hint the decoder separates the Unicode forms, ASCII and the CJK family and otherwise
    ///     assumes Windows-1252 (or Windows-1251 when the bytes are overwhelmingly Cyrillic-shaped).
    public static func decode(_ data: Data, languageHint: String? = nil) -> DecodedSubtitleText {
        let bytes = [UInt8](data)
        if bytes.isEmpty { return DecodedSubtitleText(text: "", encoding: .ascii, note: nil, invalidBytes: 0) }

        // 1. Byte order marks.
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0, bytes[3] == 0 {
            return utf32(bytes, from: 4, littleEndian: true)
        }
        if bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0xFE, bytes[3] == 0xFF {
            return utf32(bytes, from: 4, littleEndian: false)
        }
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            let d = decodeUTF8(Array(bytes[3...]))
            return DecodedSubtitleText(text: d.text, encoding: d.invalid == 0 ? .utf8BOM : .utf8BOM, note: d.invalid == 0 ? nil : "Invalid UTF-8 bytes were replaced", invalidBytes: d.invalid)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            let d = utf16(bytes, from: 2, littleEndian: true)
            return DecodedSubtitleText(text: d.text, encoding: .utf16LEBOM, note: nil, invalidBytes: d.invalid)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            let d = utf16(bytes, from: 2, littleEndian: false)
            return DecodedSubtitleText(text: d.text, encoding: .utf16BEBOM, note: nil, invalidBytes: d.invalid)
        }

        // 2. BOM-less UTF-32 / UTF-16 (mostly-ASCII text shows as many zero bytes).
        if let le = guessWideEndianness(bytes) {
            switch le.width {
            case 4:
                let r = utf32(bytes, from: 0, littleEndian: le.littleEndian)
                return DecodedSubtitleText(text: r.text, encoding: r.encoding, note: "No byte order mark; guessed UTF-32 from the zero bytes", invalidBytes: r.invalidBytes)
            default:
                let d = utf16(bytes, from: 0, littleEndian: le.littleEndian)
                return DecodedSubtitleText(text: d.text, encoding: le.littleEndian ? .utf16LE : .utf16BE, note: "No byte order mark; guessed UTF-16 from the zero bytes", invalidBytes: d.invalid)
            }
        }

        // 3. ASCII / strict UTF-8.
        if bytes.allSatisfy({ $0 < 0x80 }) {
            return DecodedSubtitleText(text: String(decoding: bytes, as: UTF8.self), encoding: .ascii, note: nil, invalidBytes: 0)
        }
        if isValidUTF8(bytes) {
            return DecodedSubtitleText(text: String(decoding: bytes, as: UTF8.self), encoding: .utf8, note: nil, invalidBytes: 0)
        }

        // 4. Legacy encodings: the language hint first.
        var tried: [SubtitleTextEncoding] = []
        if let hint = languageHint, let tag = LanguageTag(hint) {
            for enc in candidates(for: tag) {
                tried.append(enc)
                if let r = decodeLegacy(bytes, as: enc), r.invalidBytes == 0 {
                    return DecodedSubtitleText(text: r.text, encoding: enc, note: "Read as \(label(enc)) because the language is \(tag)", invalidBytes: 0)
                }
            }
        }

        // 5. No usable hint: the CJK family by structure, else Cyrillic-shaped, else Windows-1252.
        let cyrillic = looksCyrillic(bytes)
        if !cyrillic, let cjk = guessCJK(bytes) {
            return DecodedSubtitleText(text: cjk.text, encoding: cjk.enc, note: "No language hint; guessed \(label(cjk.enc)) from the byte pattern", invalidBytes: 0)
        }
        let enc: SubtitleTextEncoding = cyrillic ? .windows1251 : .windows1252
        if let r = decodeLegacy(bytes, as: enc) {
            return DecodedSubtitleText(text: r.text, encoding: enc, note: "No language hint; assumed \(label(enc))", invalidBytes: r.invalidBytes)
        }
        // Unreachable for single-byte tables, kept so the function can never return nothing.
        return DecodedSubtitleText(text: String(decoding: bytes, as: UTF8.self), encoding: .utf8, note: "Could not detect the encoding", invalidBytes: bytes.count)
    }

    /// Reads bytes as one specific encoding (used by tests and by callers that already know).
    public static func decode(_ data: Data, as encoding: SubtitleTextEncoding) -> DecodedSubtitleText {
        let bytes = [UInt8](data)
        switch encoding {
        case .ascii, .utf8:
            let d = decodeUTF8(bytes)
            return DecodedSubtitleText(text: d.text, encoding: encoding, note: nil, invalidBytes: d.invalid)
        case .utf8BOM:
            let body = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(bytes.dropFirst(3)) : bytes
            let d = decodeUTF8(body)
            return DecodedSubtitleText(text: d.text, encoding: encoding, note: nil, invalidBytes: d.invalid)
        case .utf16LE, .utf16LEBOM:
            let d = utf16(bytes, from: bytes.starts(with: [0xFF, 0xFE]) ? 2 : 0, littleEndian: true)
            return DecodedSubtitleText(text: d.text, encoding: encoding, note: nil, invalidBytes: d.invalid)
        case .utf16BE, .utf16BEBOM:
            let d = utf16(bytes, from: bytes.starts(with: [0xFE, 0xFF]) ? 2 : 0, littleEndian: false)
            return DecodedSubtitleText(text: d.text, encoding: encoding, note: nil, invalidBytes: d.invalid)
        case .utf32LE: return utf32(bytes, from: bytes.starts(with: [0xFF, 0xFE, 0, 0]) ? 4 : 0, littleEndian: true)
        case .utf32BE: return utf32(bytes, from: bytes.starts(with: [0, 0, 0xFE, 0xFF]) ? 4 : 0, littleEndian: false)
        default:
            if let r = decodeLegacy(bytes, as: encoding) { return r }
            return DecodedSubtitleText(text: String(decoding: bytes, as: UTF8.self), encoding: encoding, note: "Not valid \(label(encoding))", invalidBytes: bytes.count)
        }
    }

    // MARK: Language to encoding

    static func candidates(for tag: LanguageTag) -> [SubtitleTextEncoding] {
        switch tag.language {
        case "ja": return [.shiftJIS]
        case "ko": return [.eucKR]
        case "zh":
            if tag.script == "Hant" || tag.region == "TW" || tag.region == "HK" { return [.big5, .gb18030] }
            return [.gb18030, .big5]
        case "cs", "sk", "pl", "hu", "ro", "sl", "hr", "bs", "sq": return [.windows1250, .iso8859_2]
        case "ru", "uk", "bg", "sr", "mk", "be", "kk", "mn", "uz", "az": return tag.language == "az" ? [.windows1254] : [.windows1251]
        case "el": return [.windows1253]
        case "tr": return [.windows1254]
        case "he": return [.windows1255]
        case "ar", "fa", "ur": return [.windows1256]
        case "lt", "lv", "et": return [.windows1257]
        case "vi": return [.windows1258]
        case "th": return [.windows874]
        default: return [.windows1252]
        }
    }

    static func label(_ e: SubtitleTextEncoding) -> String {
        switch e {
        case .windows1250: return "Windows-1250"
        case .windows1251: return "Windows-1251"
        case .windows1252: return "Windows-1252"
        case .windows1253: return "Windows-1253"
        case .windows1254: return "Windows-1254"
        case .windows1255: return "Windows-1255"
        case .windows1256: return "Windows-1256"
        case .windows1257: return "Windows-1257"
        case .windows1258: return "Windows-1258"
        case .windows874: return "Windows-874"
        case .iso8859_1: return "ISO-8859-1"
        case .iso8859_2: return "ISO-8859-2"
        case .iso8859_15: return "ISO-8859-15"
        case .cp437: return "CP437"
        case .cp850: return "CP850"
        case .shiftJIS: return "Shift-JIS"
        case .eucKR: return "EUC-KR"
        case .gb18030: return "GB 18030"
        case .big5: return "Big5"
        default: return e.rawValue
        }
    }

    // MARK: UTF-8 / 16 / 32

    static func isValidUTF8(_ b: [UInt8]) -> Bool {
        var i = 0
        let n = b.count
        while i < n {
            let c = b[i]
            if c < 0x80 { i += 1; continue }
            var need = 0
            var minimum: UInt32 = 0
            var cp: UInt32 = 0
            if c >= 0xC2 && c <= 0xDF { need = 1; cp = UInt32(c & 0x1F); minimum = 0x80 }
            else if c >= 0xE0 && c <= 0xEF { need = 2; cp = UInt32(c & 0x0F); minimum = 0x800 }
            else if c >= 0xF0 && c <= 0xF4 { need = 3; cp = UInt32(c & 0x07); minimum = 0x10000 }
            else { return false }
            if i + need >= n { return false }
            for k in 1...need {
                let cc = b[i + k]
                if cc & 0xC0 != 0x80 { return false }
                cp = (cp << 6) | UInt32(cc & 0x3F)
            }
            if cp < minimum || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF) { return false }
            i += need + 1
        }
        return true
    }

    static func decodeUTF8(_ b: [UInt8]) -> (text: String, invalid: Int) {
        if isValidUTF8(b) { return (String(decoding: b, as: UTF8.self), 0) }
        let s = String(decoding: b, as: UTF8.self)   // replaces bad sequences with U+FFFD
        let bad = s.unicodeScalars.filter { $0 == "\u{FFFD}" }.count
        return (s, max(bad, 1))
    }

    static func utf16(_ b: [UInt8], from start: Int, littleEndian: Bool) -> (text: String, invalid: Int) {
        var units: [UInt16] = []
        units.reserveCapacity((b.count - start) / 2)
        var i = start
        while i + 1 < b.count {
            let u = littleEndian ? UInt16(b[i]) | (UInt16(b[i + 1]) << 8) : (UInt16(b[i]) << 8) | UInt16(b[i + 1])
            units.append(u)
            i += 2
        }
        var invalid = (b.count - start) % 2 == 1 ? 1 : 0
        var scalars = String.UnicodeScalarView()
        var j = 0
        while j < units.count {
            let u = units[j]
            if u >= 0xD800 && u <= 0xDBFF, j + 1 < units.count, units[j + 1] >= 0xDC00 && units[j + 1] <= 0xDFFF {
                let v = 0x10000 + ((UInt32(u) - 0xD800) << 10) + (UInt32(units[j + 1]) - 0xDC00)
                if let sc = Unicode.Scalar(v) { scalars.append(sc) }
                j += 2
            } else if u >= 0xD800 && u <= 0xDFFF {
                scalars.append("\u{FFFD}")
                invalid += 1
                j += 1
            } else {
                if let sc = Unicode.Scalar(UInt32(u)) { scalars.append(sc) }
                j += 1
            }
        }
        return (String(scalars), invalid)
    }

    static func utf32(_ b: [UInt8], from start: Int, littleEndian: Bool) -> DecodedSubtitleText {
        var scalars = String.UnicodeScalarView()
        var invalid = (b.count - start) % 4 == 0 ? 0 : 1
        var i = start
        while i + 3 < b.count {
            let v: UInt32 = littleEndian
                ? UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
                : UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
            if let sc = Unicode.Scalar(v) { scalars.append(sc) } else { scalars.append("\u{FFFD}"); invalid += 1 }
            i += 4
        }
        return DecodedSubtitleText(text: String(scalars), encoding: littleEndian ? .utf32LE : .utf32BE, note: nil, invalidBytes: invalid)
    }

    /// BOM-less wide text: ASCII-heavy subtitles in UTF-16 have a zero byte in every other position;
    /// in UTF-32 three of every four bytes are zero. Needs at least 8 bytes and a clear pattern.
    static func guessWideEndianness(_ b: [UInt8]) -> (width: Int, littleEndian: Bool)? {
        let n = min(b.count, 4096) / 4 * 4
        if n < 8 { return nil }
        var z = [Int](repeating: 0, count: 4)
        for i in 0..<n where b[i] == 0 { z[i % 4] += 1 }
        let per = n / 4
        let strong = Int(Double(per) * 0.8)
        // UTF-32 LE: bytes 1, 2, 3 are zero; BE: bytes 0, 1, 2 are zero.
        if z[1] >= strong, z[2] >= strong, z[3] >= strong, z[0] < per / 4 { return (4, true) }
        if z[0] >= strong, z[1] >= strong, z[2] >= strong, z[3] < per / 4 { return (4, false) }
        // UTF-16: odd bytes zero (LE) or even bytes zero (BE).
        let evenZero = z[0] + z[2]
        let oddZero = z[1] + z[3]
        let half = per * 2
        let threshold = Int(Double(half) * 0.6)
        if oddZero >= threshold, evenZero < half / 5 { return (2, true) }
        if evenZero >= threshold, oddZero < half / 5 { return (2, false) }
        return nil
    }

    // MARK: Legacy

    static func decodeLegacy(_ b: [UInt8], as enc: SubtitleTextEncoding) -> DecodedSubtitleText? {
        if let table = enc.table {
            var scalars = String.UnicodeScalarView()
            var invalid = 0
            scalars.reserveCapacity(b.count)
            for byte in b {
                if byte < 0x80 { scalars.append(Unicode.Scalar(byte)) } else {
                    let v = table[Int(byte) - 0x80]
                    if v == 0xFFFD { invalid += 1 }
                    scalars.append(Unicode.Scalar(UInt32(v)) ?? "\u{FFFD}")
                }
            }
            return DecodedSubtitleText(text: String(scalars), encoding: enc, note: nil, invalidBytes: invalid)
        }
        if let raw = enc.foundationRawValue {
            guard let s = String(data: Data(b), encoding: String.Encoding(rawValue: raw)) else { return nil }
            let bad = s.unicodeScalars.filter { $0 == "\u{FFFD}" }.count
            return DecodedSubtitleText(text: s, encoding: enc, note: nil, invalidBytes: bad)
        }
        return nil
    }

    /// Picks among Shift-JIS, EUC-KR, GB 18030 and Big5 by decoding and scoring. A file is CJK when most
    /// letters after decoding are kana, hangul or ideographs.
    static func guessCJK(_ b: [UInt8]) -> (text: String, enc: SubtitleTextEncoding)? {
        let high = b.filter { $0 >= 0x80 }.count
        if high < 4 { return nil }
        // Western text has a few accented letters per line; CJK lines are mostly high bytes. Without this gate
        // "déjà vu" would decode as valid (but wrong) double-byte text.
        var highInLines = 0
        var lengthOfLines = 0
        var lineStart = 0
        for i in 0...b.count {
            if i == b.count || b[i] == 0x0A || b[i] == 0x0D {
                let slice = b[lineStart..<i]
                let h = slice.filter { $0 >= 0x80 }.count
                if h > 0 { highInLines += h; lengthOfLines += slice.count }
                lineStart = i + 1
            }
        }
        if lengthOfLines == 0 || Double(highInLines) / Double(lengthOfLines) < 0.5 { return nil }
        var best: (score: Double, text: String, enc: SubtitleTextEncoding)?
        for enc in [SubtitleTextEncoding.shiftJIS, .eucKR, .gb18030, .big5] {
            guard let r = decodeLegacy(b, as: enc), r.invalidBytes == 0 else { continue }
            var cjk = 0
            var kana = 0
            var hangul = 0
            var other = 0
            for sc in r.text.unicodeScalars where sc.value >= 0x80 {
                switch sc.value {
                case 0x3040...0x30FF: kana += 1; cjk += 1
                case 0xAC00...0xD7A3: hangul += 1; cjk += 1
                case 0x4E00...0x9FFF, 0x3400...0x4DBF: cjk += 1
                case 0xFF00...0xFFEF, 0x3000...0x303F: cjk += 1
                default: other += 1
                }
            }
            let total = cjk + other
            if total == 0 { continue }
            var score = Double(cjk) / Double(total)
            if enc == .shiftJIS { score += Double(kana) / Double(total) }       // kana is a strong Japanese sign
            if enc == .eucKR { score += Double(hangul) / Double(total) }
            if score >= 0.8, best == nil || score > best?.score ?? 0 { best = (score, r.text, enc) }
        }
        return best.map { ($0.text, $0.enc) }
    }

    /// True when the high bytes are overwhelmingly in the Cyrillic letter range 0xC0...0xFF of Windows-1251
    /// and the text has no Latin accent pattern. A Western text with the odd accent stays Windows-1252.
    static func looksCyrillic(_ b: [UInt8]) -> Bool {
        let high = b.filter { $0 >= 0x80 }
        if high.count < 16 { return false }
        let letters = b.filter { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 >= 0xC0 }.count
        let cyr = high.filter { $0 >= 0xC0 }.count
        return Double(cyr) / Double(max(letters, 1)) > 0.5 && Double(cyr) / Double(high.count) > 0.85
    }

    /// Language hint from a subtitle file name: "Movie.fr.forced.srt" gives "fr".
    public static func languageHint(fromFileName name: String) -> String? {
        let base = name.split(separator: "/").last.map(String.init) ?? name
        let all = base.split(whereSeparator: { ".-_ []()".contains($0) }).map(String.init).dropLast()
        // The first word is the title ("It.srt" is a film, not Italian); "en.srt" alone is a language.
        // A lone word counts only when it is written like a code ("en") or a long name ("English"): "It.srt" is a film.
        let tokens: [String]
        if all.count == 1, let only = all.first {
            tokens = (only == only.lowercased() || only.count > 3) ? [only] : []
        } else {
            tokens = Array(all.dropFirst())
        }
        // A language followed by a script or region ("zh-Hant", "pt_BR") is kept whole.
        if tokens.count >= 2 {
            for j in stride(from: tokens.count - 2, through: 0, by: -1) {
                let joined = tokens[j] + "-" + tokens[j + 1]
                if let tag = LanguageTag(joined), tag.script != nil || tag.region != nil { return joined }
            }
        }
        // "hi" means hearing impaired next to a language and Hindi on its own.
        for t in tokens.reversed() where t.count >= 2 && t.lowercased() != "hi" {
            if LanguageTag(t) != nil { return t }
        }
        if tokens.contains(where: { $0.lowercased() == "hi" }) { return "hi" }
        return nil
    }
}
