import Foundation
import VideoPlayerCore

// Subtitles in the HLS stream (docs/PLAYBACK_WIRING.md, decisions D1 and D5).
//
// D1 (PROVISIONAL): text subtitles (SRT, ASS/SSA, WebVTT) are served as WebVTT renditions, so they appear only in the
//   system subtitle menu. Picture subtitles (PGS) are NOT renditions: they are listed in `RemuxMediaInfo.pictureSubtitles`
//   and delivered as `.sup` data (`PGSSupWriter`) to the app's single custom menu. Alternative: draw the text cues in
//   the app too (rejected: two menus for one kind of thing).
// D5 (PROVISIONAL): plain WebVTT, no styling of our own, no regions, no cue settings: the system caption style (Settings
//   > Accessibility > Subtitles and Captioning) applies. ASS is flattened to text; only italic, bold and underline survive.
//
// Time base: a cue is written in the player's media timeline: (file time - first keyframe time) + the video decode delay,
// the same timeline as the fMP4 segments. Every segment says `X-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000`, so a cue
// time of 12.5 s is media time 12.5 s (RFC 8216 section 3.5 and RFC 8216bis: the mapping ties local cue time to the
// 90 kHz MPEG timestamp; the fMP4 timeline here starts at 0, so no offset is needed).

public enum SubtitleTextFormat: Equatable, Sendable { case srt, ass, webVTT }

public enum SubtitleTrackClass: Equatable, Sendable {
    case text(SubtitleTextFormat)
    case picture
    case unsupported(String)
}

public enum SubtitleClassifier {
    public static func classify(codecID: String) -> SubtitleTrackClass {
        switch codecID {
        case "S_TEXT/UTF8", "S_TEXT/ASCII": return .text(.srt)
        case "S_TEXT/ASS", "S_TEXT/SSA", "S_ASS", "S_SSA": return .text(.ass)
        case "S_TEXT/WEBVTT": return .text(.webVTT)
        case "S_HDMV/PGS": return .picture
        case "S_VOBSUB": return .unsupported("VobSub picture subtitles are not supported yet")
        case "S_HDMV/TEXTST": return .unsupported("Blu-ray text subtitles (TextST) are not supported")
        case "S_DVBSUB": return .unsupported("DVB picture subtitles are not supported")
        default: return .unsupported("subtitle format \(codecID) is not supported")
        }
    }
}

public struct SubtitleRenditionInfo: Equatable, Sendable {
    public var trackNumber: Int
    public var name: String
    public var language: String
    public var isDefault: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    public var format: SubtitleTextFormat
}

public struct PictureSubtitleInfo: Equatable, Sendable {
    public var trackNumber: Int
    public var name: String
    public var language: String
    public var isDefault: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
}

public struct SkippedSubtitle: Equatable, Sendable {
    public var trackNumber: Int
    public var codecID: String
    public var reason: String
}

// MARK: Cue text conversion

/// One styled piece of cue text.
struct StyledRun: Equatable {
    var text: String
    var italic = false
    var bold = false
    var underline = false
}

public struct VTTCue: Equatable, Sendable {
    public var start: Double      // seconds in the media timeline
    public var end: Double
    public var text: String       // already WebVTT payload text (escaped, tags i/b/u only, lines joined with \n)
}

public enum WebVTTBuilder {
    /// "00:01:02.345" (hours always written; HLS clients accept it and it keeps sorting simple).
    public static func timestamp(_ seconds: Double) -> String {
        let ms = Int((max(0, seconds) * 1000).rounded())
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        let milli = ms % 1000
        let fraction = milli < 10 ? "00\(milli)" : (milli < 100 ? "0\(milli)" : "\(milli)")
        return "\(two(ms / 3_600_000)):\(two(ms / 60_000 % 60)):\(two(ms / 1000 % 60)).\(fraction)"
    }

    /// The text of one Matroska subtitle block as a WebVTT cue payload. nil when nothing visible is left (an empty cue,
    /// an ASS drawing, only tags).
    public static func cuePayload(_ block: [UInt8], format: SubtitleTextFormat) -> String? {
        var text = String(decoding: block, as: UTF8.self)
        if text.unicodeScalars.first == "\u{FEFF}" { text.unicodeScalars.removeFirst() }
        if format == .ass {
            // "ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text": the text is everything after the 8th comma.
            var commas = 0
            var idx = text.startIndex
            while idx < text.endIndex, commas < 8 { if text[idx] == "," { commas += 1 }; idx = text.index(after: idx) }
            guard commas == 8 else { return nil }
            text = String(text[idx...])
        }
        let runs = parseRuns(text, format: format)
        guard let runs else { return nil }          // ASS drawing
        let rendered = render(runs)
        return rendered.isEmpty ? nil : rendered
    }

    // Parsing --------------------------------------------------------------------------------------------------

    static func parseRuns(_ input: String, format: SubtitleTextFormat) -> [StyledRun]? {
        // CRLF is one Character in Swift and would slip past every "\n" split below: work on scalars with CR folded away.
        var chars: [Unicode.Scalar] = []
        chars.reserveCapacity(input.unicodeScalars.count)
        var previousWasCR = false
        for s in input.unicodeScalars {
            if s == "\r" { chars.append("\n"); previousWasCR = true; continue }
            if s == "\n", previousWasCR { previousWasCR = false; continue }
            previousWasCR = false
            chars.append(s)
        }
        var runs: [StyledRun] = []
        var buffer = String.UnicodeScalarView()
        var htmlI = 0, htmlB = 0, htmlU = 0           // open HTML-style tags (nesting counters)
        var overrideI = false, overrideB = false, overrideU = false
        var drawing = false

        func state() -> (Bool, Bool, Bool) { (htmlI > 0 || overrideI, htmlB > 0 || overrideB, htmlU > 0 || overrideU) }
        func flush() {
            guard !buffer.isEmpty else { return }
            let s = state()
            let text = String(buffer)
            buffer = String.UnicodeScalarView()
            if var last = runs.last, last.italic == s.0, last.bold == s.1, last.underline == s.2 {
                last.text += text; runs[runs.count - 1] = last
            } else {
                runs.append(StyledRun(text: text, italic: s.0, bold: s.1, underline: s.2))
            }
        }
        var n = 0
        while n < chars.count {
            let c = chars[n]
            if c == "<" {
                // Find the closing ">" on the same line, within a short distance.
                var j = n + 1
                while j < chars.count, chars[j] != ">", chars[j] != "<", chars[j] != "\n", j - n < 80 { j += 1 }
                if j < chars.count, chars[j] == ">" {
                    let inner = String(String.UnicodeScalarView(chars[(n + 1)..<j]))
                    if let action = tagAction(inner) {
                        switch action {
                        case .open(let k): flush(); switch k { case "i": htmlI += 1; case "b": htmlB += 1; default: htmlU += 1 }
                        case .close(let k): flush(); switch k { case "i": htmlI = max(0, htmlI - 1); case "b": htmlB = max(0, htmlB - 1); default: htmlU = max(0, htmlU - 1) }
                        case .lineBreak: buffer.append("\n")
                        case .drop: break
                        }
                        n = j + 1
                        continue
                    }
                }
                buffer.append(c); n += 1
                continue
            }
            if c == "{", n + 1 < chars.count, chars[n + 1] == "\\" {
                var j = n + 2
                while j < chars.count, chars[j] != "}", j - n < 400 { j += 1 }
                if j < chars.count, chars[j] == "}" {
                    let body = String(String.UnicodeScalarView(chars[(n + 1)..<j]))
                    flush()
                    for piece in body.split(separator: "\\", omittingEmptySubsequences: true) {
                        let tag = piece.trimmingCharacters(in: .whitespaces)
                        if tag.hasPrefix("r") {
                            // \r and \rStyleName: back to the style, which D5 does not render (so: no override)
                            overrideI = false; overrideB = false; overrideU = false
                        } else if let v = flagValue(tag, "i") { overrideI = v }
                        else if let v = flagValue(tag, "b") { overrideB = v }
                        else if let v = flagValue(tag, "u") { overrideU = v }
                        else if tag.hasPrefix("p"), let n = Int(tag.dropFirst()) { drawing = n > 0 }
                    }
                    n = j + 1
                    continue
                }
            }
            if c == "\\", format == .ass || format == .srt, n + 1 < chars.count {
                let d = chars[n + 1]
                if d == "N" { buffer.append("\n"); n += 2; continue }
                if d == "n" && format == .ass { buffer.append(" "); n += 2; continue }
                if d == "h" && format == .ass { buffer.append("\u{00A0}"); n += 2; continue }
            }
            if drawing { n += 1; continue }
            buffer.append(c)
            n += 1
        }
        flush()
        // A cue that is only a vector drawing has no visible text.
        if drawing && runs.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return nil }
        return runs
    }

    private enum TagAction { case open(String), close(String), lineBreak, drop }

    /// What an HTML-like tag means: i, b, u are kept, br is a line break, other known tags are dropped; nil means "this is
    /// not a tag, show the < as text".
    private static func tagAction(_ inner: String) -> TagAction? {
        var s = inner.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var closing = false
        if s.hasPrefix("/") { closing = true; s.removeFirst() }
        if let first = s.unicodeScalars.first, first.properties.numericType != nil {
            // WebVTT inline timestamp tag <00:01:02.000>
            return s.contains(":") ? .drop : nil
        }
        let name = String(s.prefix { $0.isLetter || $0.isNumber }).lowercased()
        if name.isEmpty { return nil }
        switch name {
        case "i", "em": return closing ? .close("i") : .open("i")
        case "b", "strong": return closing ? .close("b") : .open("b")
        case "u": return closing ? .close("u") : .open("u")
        case "br": return .lineBreak
        case "font", "span", "c", "v", "lang", "ruby", "rt", "rp", "p", "div", "center", "s", "strike", "del", "sub", "sup", "big", "small":
            return .drop
        default: return nil
        }
    }

    /// `\i1` / `\i0` / `\i` (a bare flag means "back to the style value", treated as off) for the single letter `key`.
    private static func flagValue(_ tag: String, _ key: Character) -> Bool? {
        guard tag.first == key else { return nil }
        let rest = tag.dropFirst()
        if rest.isEmpty { return false }
        guard rest.allSatisfy({ $0.isNumber }), let v = Int(rest) else { return nil }     // \bord, \blur, \be ... are not flags
        return key == "b" ? v >= 1 : v != 0
    }

    // Rendering ------------------------------------------------------------------------------------------------

    static func render(_ runs: [StyledRun]) -> String {
        var out = ""
        for run in runs {
            let t = escape(run.text)
            if t.isEmpty { continue }
            // Style tags wrap each line separately so that a cue never has a blank line inside (a blank line ends a cue).
            let lines = t.split(separator: "\n", omittingEmptySubsequences: false)
            for (n, line) in lines.enumerated() {
                if n > 0 { out += "\n" }
                if line.isEmpty { continue }
                var open = "", close = ""
                if run.bold { open += "<b>"; close = "</b>" + close }
                if run.italic { open += "<i>"; close = "</i>" + close }
                if run.underline { open += "<u>"; close = "</u>" + close }
                out += open + line + close
            }
        }
        // Normalise: trim every line, drop empty lines, join with one newline.
        let lines = out.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // A line holding only tags has nothing to show.
        let visible = lines.filter { !stripTags($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return visible.joined(separator: "\n")
    }

    private static func stripTags(_ s: String) -> String {
        var out = "", inTag = false
        for c in s { if c == "<" { inTag = true } else if c == ">" { inTag = false } else if !inTag { out.append(c) } }
        return out
    }

    /// Escapes `& < >` for WebVTT. An `&` that already starts a valid entity is kept (WebVTT and HTML-ish SRT text often
    /// arrive escaped); NBSP becomes `&nbsp;`; the line separators `-->` cannot appear because `>` is escaped.
    static func escape(_ s: String) -> String {
        var out = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "&":
                if let len = entityLength(chars, i) { out += String(chars[i..<(i + len)]); i += len; continue }
                out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\u{00A0}": out += "&nbsp;"
            case "\r": break
            default: out.append(c)
            }
            i += 1
        }
        return out
    }

    private static func entityLength(_ c: [Character], _ i: Int) -> Int? {
        var j = i + 1
        guard j < c.count else { return nil }
        if c[j] == "#" {
            j += 1
            let hex = j < c.count && (c[j] == "x" || c[j] == "X")
            if hex { j += 1 }
            let digits = j
            while j < c.count, hex ? c[j].isHexDigit : (c[j].isASCII && c[j].isNumber) { j += 1 }
            guard j > digits, j < c.count, c[j] == ";", j - i <= 10 else { return nil }
            return j - i + 1
        }
        let start = j
        while j < c.count, c[j].isASCII, c[j].isLetter, j - start < 8 { j += 1 }
        guard j > start, j < c.count, c[j] == ";" else { return nil }
        let name = String(c[start..<j])
        return ["amp", "lt", "gt", "nbsp", "lrm", "rlm", "quot", "apos"].contains(name) ? j - i + 1 : nil
    }

    // Segments -------------------------------------------------------------------------------------------------

    /// A WebVTT file body for one HLS segment. Cues are written in start order (ties keep their input order).
    public static func segment(cues: [VTTCue]) -> String {
        var s = "WEBVTT\nX-TIMESTAMP-MAP=MPEGTS:0,LOCAL:00:00:00.000\n"
        let ordered = cues.enumerated().sorted { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }
        for (_, cue) in ordered {
            s += "\n\(timestamp(cue.start)) --> \(timestamp(max(cue.end, cue.start + 0.001)))\n\(cue.text)\n"
        }
        return s
    }

    /// Converts the subtitle frames of a window that fall in `[lo, hi)` (file time, ns) into cues on the media timeline.
    static func cues(frames: [MKVFrame], track: MKVTrack, format: SubtitleTextFormat,
                     lo: Int64, hi: Int64, originNs: Int64, delaySeconds: Double) -> [VTTCue] {
        var out: [VTTCue] = []
        for f in frames where f.track == track.number && f.timeNs >= lo && f.timeNs < hi {
            var bytes = Array(f.data)
            if track.zlibCompressed {
                guard let inflated = try? Inflate.zlib(bytes) else { continue }          // a damaged cue is skipped, the rest still plays
                bytes = inflated
            }
            guard let text = cuePayload(bytes, format: format) else { continue }
            let duration = f.durationNs.map { Double($0) / 1e9 }.flatMap { $0 > 0 ? $0 : nil } ?? defaultCueSeconds
            let start = Double(f.timeNs - originNs) / 1e9 + delaySeconds
            let end = start + duration
            if end <= 0 { continue }
            out.append(VTTCue(start: max(0, start), end: end, text: text))
        }
        return out
    }

    /// PROVISIONAL: a cue block without a duration is shown for 3 seconds. Alternative: until the next cue starts.
    static let defaultCueSeconds = 3.0
}

// MARK: Picture subtitles (PGS) as `.sup` data

/// Blu-ray `.sup` framing for the blocks of a PGS track: Matroska stores the bare segments, `.sup` adds a 13 byte header
/// ("PG", 90 kHz PTS, DTS 0) to each. The PTS is the media timeline time, so the app can show a cue when the player
/// time reaches it. `PGSParser` (Subtitles target) reads the result.
public enum PGSSupWriter {
    static func sup(frames: [MKVFrame], track: MKVTrack, lo: Int64, hi: Int64, originNs: Int64, delaySeconds: Double) -> [UInt8] {
        var w = ByteWriter()
        for f in frames where f.track == track.number && f.timeNs >= lo && f.timeNs < hi {
            var bytes = Array(f.data)
            if track.zlibCompressed { guard let inflated = try? Inflate.zlib(bytes) else { continue }; bytes = inflated }
            let seconds = Double(f.timeNs - originNs) / 1e9 + delaySeconds
            let pts = UInt32(truncatingIfNeeded: Int64((max(0, seconds) * 90000).rounded()))
            // A block holds one or more segments: type (1), size (2), payload.
            var p = 0
            while p + 3 <= bytes.count {
                let type = bytes[p]
                let size = Int(bytes[p + 1]) << 8 | Int(bytes[p + 2])
                guard p + 3 + size <= bytes.count else { break }
                w.append([0x50, 0x47]); w.u32(pts); w.u32(0)
                w.u8(type); w.u16(UInt16(size))
                w.append(Array(bytes[(p + 3)..<(p + 3 + size)]))
                p += 3 + size
            }
        }
        return w.bytes
    }
}
