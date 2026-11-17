import Foundation

/// One `Style:` line of an ASS (V4+) or SSA (V4) script.
public struct ASSStyle: Equatable, Sendable {
    public var name: String
    public var fontName = "Arial"
    public var fontSize = 20.0
    public var primaryColor = SubtitleColor.white
    public var secondaryColor = SubtitleColor(red: 255, green: 0, blue: 0)
    public var outlineColor = SubtitleColor(red: 0, green: 0, blue: 0)
    public var backColor = SubtitleColor(red: 0, green: 0, blue: 0)
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikeOut = false
    public var scaleX = 100.0
    public var scaleY = 100.0
    public var spacing = 0.0
    public var angle = 0.0
    public var borderStyle = 1
    public var outline = 2.0
    public var shadow = 0.0
    public var alignment = SubtitleAlignment.bottomCenter
    public var marginL = 10.0
    public var marginR = 10.0
    public var marginV = 10.0
    public var encoding = 1

    public init(name: String) { self.name = name }
}

/// The `[Script Info]` and style data of a script.
public struct ASSScript: Equatable, Sendable {
    /// True for SSA (`[V4 Styles]`, ScriptType v4.00), false for ASS (`[V4+ Styles]`).
    public var isSSA = false
    public var title: String?
    public var scriptType: String?
    /// Coordinate space of `\pos`, margins and font sizes. Missing values follow libass: 384x288, or the
    /// missing side derived at 4:3 from the one given.
    public var playResX = 384.0
    public var playResY = 288.0
    public var playResGiven = false
    /// 0 smart wrap, 1 end-of-line wrap, 2 no wrap (only `\N` breaks), 3 smart wrap with wider bottom line.
    public var wrapStyle = 0
    public var scaledBorderAndShadow = false
    public var info: [String: String] = [:]
    public var styles: [String: ASSStyle] = [:]
    public var styleOrder: [String] = []
    /// True when the file has `[Fonts]` or `[Graphics]` sections. Their UU-encoded data is skipped, never decoded.
    public var hasEmbeddedData = false

    public init() {}
}

/// ASS / SSA parser.
///
/// Handled: Script Info (PlayResX/Y, WrapStyle, ScriptType, Title), V4 and V4+ styles with every field, Events
/// with any `Format:` order, commas inside the text, comments (`Comment:` lines and `;`), layers, margins,
/// SSA numbering of alignments, `\N \n \h`, and the override tags listed below. `[Fonts]` and `[Graphics]` are skipped.
///
/// Override tags: applied: `\b \i \u \s \fn \fs \c \1c \alpha \1a \an \a \r \pos \fad \p`; `\move` uses its start
/// point as the position (fallback: no animation); read and ignored: `\2c \3c \4c \2a \3a \4a \fscx \fscy \fsp \fr*
/// \fax \fay \bord \xbord \ybord \shad \xshad \yshad \be \blur \fe \q \org \clip \iclip \fade \t \k* \pbo`.
/// Drawing mode (`\p1`) text is dropped; a cue with only drawings is dropped.
public enum ASSParser {

    private enum Section { case none, info, styles, events, embedded, other }

    private static let v4plusStyleFormat = [
        "name", "fontname", "fontsize", "primarycolour", "secondarycolour", "outlinecolour", "backcolour", "bold", "italic",
        "underline", "strikeout", "scalex", "scaley", "spacing", "angle", "borderstyle", "outline", "shadow", "alignment",
        "marginl", "marginr", "marginv", "encoding",
    ]
    private static let v4StyleFormat = [
        "name", "fontname", "fontsize", "primarycolour", "secondarycolour", "tertiarycolour", "backcolour", "bold", "italic",
        "borderstyle", "outline", "shadow", "alignment", "marginl", "marginr", "marginv", "alphalevel", "encoding",
    ]
    private static let v4plusEventFormat = ["layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]
    private static let v4EventFormat = ["marked", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"]

    public static func parse(_ text: String) -> ParsedSubtitle {
        let lines = SubtitleText.lines(SubtitleText.strippingBOM(text))
        var script = ASSScript()
        var section = Section.none
        var sawV4Styles = false
        var sawV4PlusStyles = false
        var styleFormat: [String]?
        var eventFormat: [String]?
        var resXGiven = false
        var resYGiven = false
        var pendingDialogue: [String] = []   // dialogue lines are read after the whole script (styles may follow)
        var warnings: [String] = []
        var badLines = 0

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("!:") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let name = line.dropFirst().dropLast().lowercased().trimmingCharacters(in: .whitespaces)
                switch name {
                case "script info": section = .info
                case "v4 styles": section = .styles; sawV4Styles = true
                case "v4+ styles", "v4++ styles": section = .styles; sawV4PlusStyles = true
                case "events": section = .events
                case "fonts", "graphics": section = .embedded; script.hasEmbeddedData = true
                default: section = .other
                }
                continue
            }
            switch section {
            case .embedded, .other:
                continue
            case .info:
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                script.info[key] = value
                switch key.lowercased() {
                case "title": script.title = value
                case "scripttype": script.scriptType = value
                case "playresx": if let v = Double(value), v > 0, v.isFinite { script.playResX = v; resXGiven = true }
                case "playresy": if let v = Double(value), v > 0, v.isFinite { script.playResY = v; resYGiven = true }
                case "wrapstyle": if let v = Int(value), (0...3).contains(v) { script.wrapStyle = v }
                case "scaledborderandshadow": script.scaledBorderAndShadow = value.lowercased() == "yes"
                default: break
                }
            case .styles:
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[line.startIndex..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if key == "format" {
                    styleFormat = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                } else if key == "style" {
                    let format = styleFormat ?? (sawV4PlusStyles && !sawV4Styles ? v4plusStyleFormat : (sawV4Styles && !sawV4PlusStyles ? v4StyleFormat : v4plusStyleFormat))
                    let fields = value.split(separator: ",", maxSplits: format.count - 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                    if fields.count < format.count { badLines += 1; continue }
                    let ssaNumbering = sawV4Styles && !sawV4PlusStyles
                    if let style = makeStyle(format: format, fields: fields, ssaNumbering: ssaNumbering) {
                        if script.styles[style.name] == nil { script.styleOrder.append(style.name) }
                        script.styles[style.name] = style
                    } else {
                        badLines += 1
                    }
                }
            case .events, .none:
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[line.startIndex..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).drop(while: { $0 == " " })
                if key == "format", section == .events {
                    eventFormat = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                } else if key == "dialogue" {
                    pendingDialogue.append(String(value))
                }
            }
        }

        // SSA versus ASS: the style section header decides; ScriptType breaks ties.
        let typeLower = script.scriptType?.lowercased() ?? ""
        if sawV4Styles && !sawV4PlusStyles { script.isSSA = true }
        else if sawV4PlusStyles { script.isSSA = false }
        else { script.isSSA = typeLower == "v4.00" }
        script.playResGiven = resXGiven || resYGiven
        if resXGiven && !resYGiven { script.playResY = script.playResX * 3 / 4 }
        if resYGiven && !resXGiven { script.playResX = script.playResY * 4 / 3 }

        let format = eventFormat ?? (script.isSSA ? v4EventFormat : v4plusEventFormat)
        guard let textIndex = format.firstIndex(of: "text") else {
            warnings.append("Events Format line has no Text field; no cues read")
            return ParsedSubtitle(format: script.isSSA ? .ssa : .ass, cues: [], warnings: warnings, ass: script)
        }
        let fieldIndex = Dictionary(format.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var lowerStyles: [String: ASSStyle] = [:]
        for (name, style) in script.styles { lowerStyles[name.lowercased()] = style }
        let fallbackStyle = lowerStyles["default"] ?? ASSStyle(name: "Default")

        var cues: [SubtitleCue] = []
        var missingStyleWarned = false
        var droppedTiming = 0
        var droppedEmpty = 0
        for value in pendingDialogue {
            let fields = value.split(separator: ",", maxSplits: format.count - 1, omittingEmptySubsequences: false)
            if fields.count < format.count { badLines += 1; continue }
            func field(_ name: String) -> String {
                guard let idx = fieldIndex[name], idx < fields.count else { return "" }
                return String(fields[idx]).trimmingCharacters(in: .whitespaces)
            }
            guard let start = SubtitleText.timestamp(Substring(field("start"))), let end = SubtitleText.timestamp(Substring(field("end"))) else {
                droppedTiming += 1
                continue
            }
            let s = max(0, start)
            if end <= s { droppedTiming += 1; continue }
            var styleName = field("style")
            if styleName.hasPrefix("*") { styleName.removeFirst() }
            var style = lowerStyles[styleName.lowercased()]
            if style == nil {
                if !missingStyleWarned { warnings.append("A cue names a style that is not defined; the Default style was used"); missingStyleWarned = true }
                style = fallbackStyle
            }
            let resolvedStyle = style ?? fallbackStyle
            let body = String(fields[textIndex])
            let parsed = parseText(body, style: resolvedStyle, script: script, styles: lowerStyles)
            if parsed.runs.isEmpty { droppedEmpty += 1; continue }

            let layer = Int(field("layer")) ?? 0
            var cue = SubtitleCue(start: s, end: end, runs: parsed.runs, format: script.isSSA ? .ssa : .ass, alignment: parsed.alignment ?? resolvedStyle.alignment, position: parsed.position, layer: layer, styleName: resolvedStyle.name)
            let ml = Double(field("marginl")) ?? 0, mr = Double(field("marginr")) ?? 0, mv = Double(field("marginv")) ?? 0
            cue.marginLeft = ml != 0 ? ml : resolvedStyle.marginL
            cue.marginRight = mr != 0 ? mr : resolvedStyle.marginR
            cue.marginVertical = mv != 0 ? mv : resolvedStyle.marginV
            cue.fadeIn = parsed.fadeIn
            cue.fadeOut = parsed.fadeOut
            let name = field("name")
            if !name.isEmpty { cue.speaker = name }
            cues.append(cue)
        }
        if droppedTiming > 0 { warnings.append("Dropped \(droppedTiming) dialogue line(s) with unreadable or empty time ranges") }
        if droppedEmpty > 0 { warnings.append("Dropped \(droppedEmpty) dialogue line(s) with no visible text (empty or drawings only)") }
        if badLines > 0 { warnings.append("Skipped \(badLines) line(s) with too few fields") }
        return ParsedSubtitle(format: script.isSSA ? .ssa : .ass, cues: SubtitleText.sortedStable(cues), warnings: warnings, ass: script)
    }

    // MARK: Styles

    static func ssaAlignment(_ v: Int) -> SubtitleAlignment? {
        let h = (v - 1) % 4
        guard v >= 1, v <= 11, h >= 0, h <= 2 else { return nil }
        let vertical: SubtitleAlignment.Vertical
        switch v {
        case 1...3: vertical = .bottom
        case 5...7: vertical = .top
        case 9...11: vertical = .middle
        default: return nil
        }
        guard let horizontal = SubtitleAlignment.Horizontal(rawValue: h) else { return nil }
        return SubtitleAlignment(horizontal: horizontal, vertical: vertical)
    }

    private static func makeStyle(format: [String], fields: [String], ssaNumbering: Bool) -> ASSStyle? {
        var style = ASSStyle(name: "")
        var haveName = false
        func flag(_ s: String) -> Bool {
            if let i = Int(s) { return i != 0 }
            if let d = Double(s) { return d != 0 }
            return false
        }
        for (name, value) in zip(format, fields) {
            switch name {
            case "name": style.name = value.hasPrefix("*") ? String(value.dropFirst()) : value; haveName = !style.name.isEmpty
            case "fontname": if !value.isEmpty { style.fontName = value }
            case "fontsize": if let d = Double(value), d > 0, d.isFinite { style.fontSize = d }
            case "primarycolour": if let c = SubtitleText.assColor(value) { style.primaryColor = c }
            case "secondarycolour": if let c = SubtitleText.assColor(value) { style.secondaryColor = c }
            case "outlinecolour", "tertiarycolour": if let c = SubtitleText.assColor(value) { style.outlineColor = c }
            case "backcolour": if let c = SubtitleText.assColor(value) { style.backColor = c }
            case "bold": style.bold = flag(value)
            case "italic": style.italic = flag(value)
            case "underline": style.underline = flag(value)
            case "strikeout": style.strikeOut = flag(value)
            case "scalex": style.scaleX = Double(value) ?? 100
            case "scaley": style.scaleY = Double(value) ?? 100
            case "spacing": style.spacing = Double(value) ?? 0
            case "angle": style.angle = Double(value) ?? 0
            case "borderstyle": style.borderStyle = Int(value) ?? 1
            case "outline": style.outline = Double(value) ?? 2
            case "shadow": style.shadow = Double(value) ?? 0
            case "alignment":
                if let v = Int(value) {
                    if ssaNumbering { if let a = ssaAlignment(v) { style.alignment = a } }
                    else if let a = SubtitleAlignment(numpad: v) { style.alignment = a }
                }
            case "marginl": style.marginL = Double(value) ?? 10
            case "marginr": style.marginR = Double(value) ?? 10
            case "marginv": style.marginV = Double(value) ?? 10
            case "encoding": style.encoding = Int(value) ?? 1
            default: break
            }
        }
        return haveName ? style : nil
    }

    // MARK: Dialogue text

    struct ParsedText {
        var runs: [SubtitleRun] = []
        var alignment: SubtitleAlignment?
        var position: SubtitlePosition?
        var fadeIn: TimeInterval?
        var fadeOut: TimeInterval?
    }

    private struct State {
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var strike: Bool
        var color: SubtitleColor?
        var alpha: UInt8?
        var fontName: String?
        var fontSize: Double?

        init(style: ASSStyle) {
            bold = style.bold
            italic = style.italic
            underline = style.underline
            strike = style.strikeOut
        }
    }

    static func parseText(_ raw: String, style: ASSStyle, script: ASSScript, styles: [String: ASSStyle]) -> ParsedText {
        let chars = Array(raw.unicodeScalars)
        var out = ParsedText()
        var state = State(style: style)
        var buffer = String.UnicodeScalarView()
        var drawing = false

        func flush() {
            defer { buffer = String.UnicodeScalarView() }
            if buffer.isEmpty || drawing { return }
            var run = SubtitleRun(String(buffer), bold: state.bold, italic: state.italic, underline: state.underline, strikeOut: state.strike, fontName: state.fontName, fontSize: state.fontSize)
            if state.color != nil || state.alpha != nil {
                var c = state.color ?? style.primaryColor
                if let a = state.alpha { c.alpha = 255 - a }
                run.color = c
            }
            if var last = out.runs.last, last.hasSameStyle(as: run) {
                last.text += run.text
                out.runs[out.runs.count - 1] = last
            } else {
                out.runs.append(run)
            }
        }

        var i = 0
        // Once a scan for "}" reaches the end, no later "{" can find one either; remembering that keeps a line
        // of many unclosed "{" from costing quadratic time.
        var noMoreClosingBraces = false
        while i < chars.count {
            let c = chars[i]
            if c == "{" && !noMoreClosingBraces {
                var j = i + 1
                while j < chars.count, chars[j] != "}" { j += 1 }
                if j >= chars.count { noMoreClosingBraces = true }
                if j < chars.count {
                    flush()
                    applyBlock(Array(chars[(i + 1)..<j]), style: style, script: script, styles: styles, state: &state, drawing: &drawing, out: &out)
                    i = j + 1
                    continue
                }
            }
            if c == "\\", i + 1 < chars.count {
                let d = chars[i + 1]
                if d == "N" { if !drawing { buffer.append("\n") }; i += 2; continue }
                if d == "n" { if !drawing { buffer.append(script.wrapStyle == 2 ? "\n" : " ") }; i += 2; continue }
                if d == "h" { if !drawing { buffer.append("\u{00A0}") }; i += 2; continue }
            }
            if !drawing { buffer.append(c) }
            i += 1
        }
        flush()
        while let first = out.runs.first, first.text.allSatisfy({ $0 == "\n" || $0 == " " }) { out.runs.removeFirst() }
        while let last = out.runs.last, last.text.allSatisfy({ $0 == "\n" || $0 == " " }) { out.runs.removeLast() }
        if var last = out.runs.last {
            while last.text.last == "\n" { last.text.removeLast() }
            out.runs[out.runs.count - 1] = last
        }
        return out
    }

    /// Splits `\a\b(1,2,\c)` style content into tags at top-level backslashes.
    static func splitTags(_ block: [Unicode.Scalar]) -> [String] {
        var tags: [String] = []
        var current: String.UnicodeScalarView?
        var depth = 0
        for c in block {
            if c == "(" { depth += 1 }
            else if c == ")" { depth = max(0, depth - 1) }
            if c == "\\" && depth == 0 {
                if let cur = current { tags.append(String(cur)) }
                current = String.UnicodeScalarView()
                continue
            }
            current?.append(c)
        }
        if let cur = current { tags.append(String(cur)) }
        return tags
    }

    private static func applyBlock(
        _ block: [Unicode.Scalar],
        style: ASSStyle,
        script: ASSScript,
        styles: [String: ASSStyle],
        state: inout State,
        drawing: inout Bool,
        out: inout ParsedText
    ) {
        for tag in splitTags(block) {
            applyTag(tag.trimmingCharacters(in: .whitespaces), style: style, script: script, styles: styles, state: &state, drawing: &drawing, out: &out)
        }
    }

    private static let ignoredPrefixes = [
        "fscx", "fscy", "fsp", "frx", "fry", "frz", "fr", "fax", "fay", "fe", "xbord", "ybord", "bord", "xshad", "yshad", "shad",
        "be", "blur", "org", "clip", "iclip", "fade", "pbo", "2c", "3c", "4c", "2a", "3a", "4a",
    ]

    /// The alpha byte of `\alpha&H80&` (00 opaque ... FF transparent).
    private static func alphaByte(_ raw: String) -> UInt8? {
        var s = raw.lowercased()
        if s.hasPrefix("&h") || s.hasPrefix("h") {
            s = String(s.drop(while: { $0 == "&" || $0 == "h" }))
            while s.hasSuffix("&") { s.removeLast() }
            guard !s.isEmpty, s.utf8.count <= 8, let v = UInt64(s, radix: 16) else { return nil }
            return UInt8(truncatingIfNeeded: v)
        }
        guard let v = Int64(s) else { return nil }
        return UInt8(truncatingIfNeeded: v)
    }

    private static func arguments(_ s: Substring) -> [Double] {
        var body = s.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("(") { body.removeFirst() }
        if body.hasSuffix(")") { body.removeLast() }
        return body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter { $0.isFinite }
    }

    private static func toggle(_ arg: String, default value: Bool) -> Bool {
        if arg.isEmpty { return value }
        guard let v = Int(arg) else { return value }
        return v == 1 || v >= 600 || (v < 0)
    }

    private static func applyTag(
        _ tag: String,
        style: ASSStyle,
        script: ASSScript,
        styles: [String: ASSStyle],
        state: inout State,
        drawing: inout Bool,
        out: inout ParsedText
    ) {
        if tag.isEmpty { return }
        // No other tag starts with t (transform), q (wrap style), k or K (karaoke).
        if let f = tag.first, "tqkK".contains(f) { return }
        for p in ignoredPrefixes where tag.hasPrefix(p) { return }
        if tag.hasPrefix("fad") {
            let a = arguments(tag.dropFirst(3))
            if a.count == 2 { out.fadeIn = max(0, a[0]) / 1000; out.fadeOut = max(0, a[1]) / 1000 }
            return
        }
        if tag.hasPrefix("pos") {
            let a = arguments(tag.dropFirst(3))
            if a.count == 2, out.position == nil { out.position = SubtitlePosition(x: a[0], y: a[1], spaceWidth: script.playResX, spaceHeight: script.playResY) }
            return
        }
        if tag.hasPrefix("move") {
            let a = arguments(tag.dropFirst(4))
            if a.count >= 4, out.position == nil { out.position = SubtitlePosition(x: a[0], y: a[1], spaceWidth: script.playResX, spaceHeight: script.playResY) }
            return
        }
        if tag.hasPrefix("alpha") || tag.hasPrefix("1a") {
            let rest = tag.hasPrefix("alpha") ? tag.dropFirst(5) : tag.dropFirst(2)
            let t = rest.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { state.alpha = nil; return }
            if let a = alphaByte(t) { state.alpha = a }
            return
        }
        if tag.hasPrefix("an") {
            if let n = Int(tag.dropFirst(2).trimmingCharacters(in: .whitespaces)), let a = SubtitleAlignment(numpad: n), out.alignment == nil { out.alignment = a }
            return
        }
        if tag.hasPrefix("a"), let n = Int(tag.dropFirst(1).trimmingCharacters(in: .whitespaces)) {
            if let a = ssaAlignment(n), out.alignment == nil { out.alignment = a }
            return
        }
        if tag.hasPrefix("fn") {
            let name = String(tag.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            state.fontName = name.isEmpty ? nil : name
            return
        }
        if tag.hasPrefix("fs") {
            let t = tag.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if t.isEmpty { state.fontSize = nil } else if let v = Double(t), v > 0, v.isFinite { state.fontSize = v }
            return
        }
        if tag.hasPrefix("1c") || (tag.hasPrefix("c") && !tag.hasPrefix("clip")) {
            let rest = tag.hasPrefix("1c") ? tag.dropFirst(2) : tag.dropFirst(1)
            let t = rest.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { state.color = nil } else if let c = SubtitleText.assColor(t) { state.color = SubtitleColor(red: c.red, green: c.green, blue: c.blue) }
            return
        }
        if tag.hasPrefix("r") {
            let name = String(tag.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            let target = name.isEmpty ? style : (styles[name.lowercased()] ?? style)
            state = State(style: target)
            return
        }
        if tag.hasPrefix("p"), let n = Int(tag.dropFirst(1).trimmingCharacters(in: .whitespaces)) {
            drawing = n > 0
            return
        }
        guard let first = tag.first else { return }
        let arg = String(tag.dropFirst(1)).trimmingCharacters(in: .whitespaces)
        switch first {
        case "b": state.bold = toggle(arg, default: style.bold)
        case "i": state.italic = toggle(arg, default: style.italic)
        case "u": state.underline = toggle(arg, default: style.underline)
        case "s": state.strike = toggle(arg, default: style.strikeOut)
        default: break
        }
    }
}
