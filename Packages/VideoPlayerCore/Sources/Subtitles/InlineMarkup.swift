import Foundation

struct InlineParseResult {
    var runs: [SubtitleRun]
    var alignment: SubtitleAlignment?
    var speaker: String?
}

/// Reads the HTML-like markup of SRT and WebVTT cue text, plus the `{\an8}` / `{\i1}` blocks that
/// SRT files copy from ASS. Unknown tags are kept as text; known tags are applied or dropped.
enum InlineMarkup {

    private struct Open {
        var name: String
        var color: SubtitleColor?
        var face: String?
    }

    private static let srtTags: Set<String> = [
        "b", "i", "u", "s", "strike", "del", "em", "strong", "font", "br", "span", "p", "div", "center", "sub", "sup", "big", "small",
    ]
    private static let vttTags: Set<String> = ["c", "v", "lang", "ruby", "rt", "rp", "b", "i", "u", "br"]

    private static let vttClassColors: [String: SubtitleColor] = [
        "white": SubtitleColor(red: 255, green: 255, blue: 255),
        "lime": SubtitleColor(red: 0, green: 255, blue: 0),
        "cyan": SubtitleColor(red: 0, green: 255, blue: 255),
        "red": SubtitleColor(red: 255, green: 0, blue: 0),
        "yellow": SubtitleColor(red: 255, green: 255, blue: 0),
        "magenta": SubtitleColor(red: 255, green: 0, blue: 255),
        "blue": SubtitleColor(red: 0, green: 0, blue: 255),
        "black": SubtitleColor(red: 0, green: 0, blue: 0),
    ]

    static func parse(_ input: String, webVTT: Bool) -> InlineParseResult {
        let chars = Array(input.unicodeScalars)
        let known = webVTT ? vttTags : srtTags
        var stack: [Open] = []
        var runs: [SubtitleRun] = []
        var buffer = String.UnicodeScalarView()
        var alignment: SubtitleAlignment?
        var speaker: String?

        func currentRun(_ text: String) -> SubtitleRun {
            var run = SubtitleRun(text)
            for o in stack {
                switch o.name {
                case "b", "strong": run.bold = true
                case "i", "em": run.italic = true
                case "u": run.underline = true
                case "s", "strike", "del": run.strikeOut = true
                default: break
                }
                if let c = o.color { run.color = c }
                if let f = o.face { run.fontName = f }
            }
            return run
        }

        func flush() {
            if buffer.isEmpty { return }
            let text = SubtitleText.decodeEntities(String(buffer))
            buffer = String.UnicodeScalarView()
            if text.isEmpty { return }
            let run = currentRun(text)
            if var last = runs.last, last.hasSameStyle(as: run) {
                last.text += run.text
                runs[runs.count - 1] = last
            } else {
                runs.append(run)
            }
        }

        func close(_ name: String) {
            let canonical = canonicalName(name)
            if let idx = stack.lastIndex(where: { canonicalName($0.name) == canonical }) {
                flush()
                stack.remove(at: idx)
            }
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "<" {
                var j = i + 1
                var found = false
                while j < chars.count, j - i <= 240 {
                    if chars[j] == ">" { found = true; break }
                    if chars[j] == "<" || chars[j] == "\n" { break }
                    j += 1
                }
                if found, let tag = handleTag(Array(chars[(i + 1)..<j]), known: known, webVTT: webVTT) {
                    switch tag {
                    case .lineBreak:
                        buffer.append("\n")
                    case .closing(let name):
                        close(name)
                    case .opening(let open, let who):
                        flush()
                        // A real cue nests a handful of tags; capping the depth stops "<i>a<i>a<i>a..." from
                        // costing quadratic time in `currentRun`.
                        if stack.count < 32 { stack.append(open) }
                        if let who, speaker == nil { speaker = who }
                    case .ignore:
                        break
                    }
                    i = j + 1
                    continue
                }
                buffer.append(c)
                i += 1
                continue
            }
            if c == "{", i + 1 < chars.count, chars[i + 1] == "\\" {
                var j = i + 2
                while j < chars.count, chars[j] != "}", j - i <= 240 { j += 1 }
                if j < chars.count, chars[j] == "}" {
                    let body = String(String.UnicodeScalarView(chars[(i + 1)..<j]))
                    for piece in body.split(separator: "\\") {
                        let p = piece.lowercased()
                        if p.hasPrefix("an"), let n = Int(p.dropFirst(2)), let a = SubtitleAlignment(numpad: n) {
                            if alignment == nil { alignment = a }
                        } else if let first = p.first, "ibus".contains(first), p.count == 2 {
                            let name = first == "b" ? "b" : first == "i" ? "i" : first == "u" ? "u" : "s"
                            if p.hasSuffix("1") { flush(); if stack.count < 32 { stack.append(Open(name: name)) } }
                            else if p.hasSuffix("0") { close(name) }
                        }
                    }
                    i = j + 1
                    continue
                }
            }
            buffer.append(c)
            i += 1
        }
        flush()

        // Trim blank space at both ends of the cue.
        while let first = runs.first, first.text.allSatisfy({ $0.isWhitespace }) {
            runs.removeFirst()
        }
        while let last = runs.last, last.text.allSatisfy({ $0.isWhitespace }) {
            runs.removeLast()
        }
        if var first = runs.first {
            first.text = String(first.text.drop(while: { $0.isWhitespace }))
            runs[0] = first
        }
        if var last = runs.last {
            while let ch = last.text.last, ch.isWhitespace { last.text.removeLast() }
            runs[runs.count - 1] = last
        }
        runs.removeAll { $0.text.isEmpty }
        return InlineParseResult(runs: runs, alignment: alignment, speaker: speaker)
    }

    private static func canonicalName(_ n: String) -> String {
        switch n {
        case "strong": return "b"
        case "em": return "i"
        case "strike", "del": return "s"
        default: return n
        }
    }

    private enum TagAction {
        case lineBreak
        case closing(String)
        case opening(Open, String?)
        case ignore
    }

    private static func handleTag(_ content: [Unicode.Scalar], known: Set<String>, webVTT: Bool) -> TagAction? {
        if content.isEmpty { return nil }
        var idx = 0
        let isClosing = content[0] == "/"
        if isClosing { idx = 1 }
        // WebVTT inline timestamp: <00:01:02.000>
        if webVTT, !isClosing, let f = content.first, f.value >= 0x30, f.value <= 0x39 {
            let text = String(String.UnicodeScalarView(content))
            if SubtitleText.timestamp(Substring(text)) != nil { return .ignore }
            return nil
        }
        var name = ""
        while idx < content.count {
            let c = content[idx]
            let isAlnum = (c.value >= 0x30 && c.value <= 0x39) || (c.value >= 0x41 && c.value <= 0x5A) || (c.value >= 0x61 && c.value <= 0x7A)
            if !isAlnum { break }
            name.unicodeScalars.append(c)
            idx += 1
        }
        name = name.lowercased()
        if name.isEmpty || !known.contains(name) { return nil }
        if idx < content.count, !(content[idx] == " " || content[idx] == "\t" || content[idx] == "." || content[idx] == "/") { return nil }
        let rest = String(String.UnicodeScalarView(content[idx...]))
        if isClosing { return .closing(name) }
        if name == "br" { return .lineBreak }
        var open = Open(name: name)
        var who: String?
        switch name {
        case "font":
            let attrs = attributes(rest)
            if let c = attrs["color"], let col = SubtitleText.cssColor(c) { open.color = col }
            if let f = attrs["face"], !f.isEmpty { open.face = f }
        case "c":
            // <c.yellow.bg_blue>: dot-separated classes; colour classes are applied.
            for cls in rest.split(separator: ".").map({ $0.split(separator: " ").first.map(String.init) ?? "" }) {
                if let col = vttClassColors[cls.lowercased()] { open.color = col }
            }
        case "v":
            let afterClasses = rest.drop(while: { $0 != " " && $0 != "\t" })
            let nameText = SubtitleText.trimmed(String(afterClasses))
            if !nameText.isEmpty { who = SubtitleText.decodeEntities(nameText) }
        default:
            break
        }
        if rest.hasSuffix("/") && name != "v" { return .ignore }   // <b/> style self-closing: nothing to apply
        return .opening(open, who)
    }

    /// key="value", key='value' or key=value pairs, keys lowercased.
    private static func attributes(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            var key = ""
            while i < chars.count, chars[i] != "=", !chars[i].isWhitespace { key.append(chars[i]); i += 1 }
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            if i < chars.count, chars[i] == "=" {
                i += 1
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                var value = ""
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let quote = chars[i]
                    i += 1
                    while i < chars.count, chars[i] != quote { value.append(chars[i]); i += 1 }
                    i += 1
                } else {
                    while i < chars.count, !chars[i].isWhitespace { value.append(chars[i]); i += 1 }
                }
                if !key.isEmpty { out[key.lowercased()] = value }
            } else if key.isEmpty {
                i += 1
            }
        }
        return out
    }
}
