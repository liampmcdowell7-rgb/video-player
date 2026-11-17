import Foundation

/// WebVTT parser.
///
/// Handled: the header (and header lines), NOTE / STYLE / REGION blocks, cue identifiers, timestamps with or
/// without hours, cue settings (position, line, align, size, vertical, region), `<v>` voice tags, `<c>` colour
/// classes, `<b><i><u>`, and inline timestamps (ignored). Ignored on purpose: CSS from STYLE blocks (kept as
/// text in `vttStyleBlocks`), the HLS `X-TIMESTAMP-MAP` header, karaoke timing.
public enum WebVTTParser {

    public static func parse(_ text: String) -> ParsedSubtitle {
        let lines = SubtitleText.lines(SubtitleText.strippingBOM(text))
        let n = lines.count
        var warnings: [String] = []
        var cues: [SubtitleCue] = []
        var styleBlocks: [String] = []
        var regions: [String: [String: String]] = [:]
        var droppedDuration = 0
        var skippedBlocks = 0

        var i = 0
        if let first = lines.first, first.hasPrefix("WEBVTT"), first.count == 6 || first.dropFirst(6).first.map({ $0 == " " || $0 == "\t" }) == true {
            i = 1
            // Header lines run to the first blank line (or to the first cue when the blank line is missing).
            while i < n, !SubtitleText.isBlank(lines[i]), timing(lines[i]) == nil, !(i + 1 < n && timing(lines[i + 1]) != nil && !SubtitleText.isBlank(lines[i + 1])) {
                i += 1
            }
        } else {
            warnings.append("Missing WEBVTT header; read as WebVTT anyway")
        }

        while i < n {
            let line = lines[i]
            if SubtitleText.isBlank(line) { i += 1; continue }
            let head = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
            let blockKeyword = head.split(separator: "\t").first.map(String.init) ?? head
            if timing(line) == nil, blockKeyword == "NOTE" || blockKeyword == "STYLE" || blockKeyword == "REGION", !(i + 1 < n && timing(lines[i + 1]) != nil) {
                var block: [String] = []
                var j = i + 1
                let firstRest = line.dropFirst(blockKeyword.count)
                if !SubtitleText.isBlank(String(firstRest)) { block.append(SubtitleText.trimmed(String(firstRest))) }
                while j < n, !SubtitleText.isBlank(lines[j]) { block.append(lines[j]); j += 1 }
                if blockKeyword == "STYLE" { styleBlocks.append(block.joined(separator: "\n")) }
                if blockKeyword == "REGION" {
                    var settings: [String: String] = [:]
                    for token in block.joined(separator: " ").split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                        let kv = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                        if kv.count == 2 { settings[String(kv[0])] = String(kv[1]) }
                    }
                    if let id = settings["id"], !id.isEmpty { regions[id] = settings }
                }
                i = j
                continue
            }

            var timingIndex: Int?
            var identifier: String?
            if timing(line) != nil { timingIndex = i }
            else if i + 1 < n, timing(lines[i + 1]) != nil { timingIndex = i + 1; identifier = SubtitleText.trimmed(line) }
            guard let t = timingIndex, let parsedTiming = timing(lines[t]) else {
                skippedBlocks += 1
                var j = i
                while j < n, !SubtitleText.isBlank(lines[j]) { j += 1 }
                i = max(j, i + 1)
                continue
            }

            var j = t + 1
            var textLines: [String] = []
            while j < n {
                let l = lines[j]
                if SubtitleText.isBlank(l) { break }
                if timing(l) != nil { break }
                // A one-word line right before the next timing line, after some text, is that cue's identifier
                // (the blank line between the cues is missing).
                if !textLines.isEmpty, j + 1 < n, timing(lines[j + 1]) != nil, !l.contains(where: { $0 == " " || $0 == "\t" }) { break }
                textLines.append(l)
                j += 1
            }
            i = j

            let parsed = InlineMarkup.parse(textLines.joined(separator: "\n"), webVTT: true)
            if parsed.runs.isEmpty { continue }
            var start = parsedTiming.start
            if start < 0 { start = 0 }
            if parsedTiming.end <= start { droppedDuration += 1; continue }
            var cue = SubtitleCue(start: start, end: parsedTiming.end, runs: parsed.runs, format: .webVTT, identifier: (identifier?.isEmpty ?? true) ? nil : identifier)
            cue.speaker = parsed.speaker
            let settings = parseSettings(parsedTiming.settings)
            cue.vtt = settings
            cue.alignment = alignment(for: settings)
            cues.append(cue)
        }

        if skippedBlocks > 0 { warnings.append("Skipped \(skippedBlocks) block(s) that were not cues") }
        if droppedDuration > 0 { warnings.append("Dropped \(droppedDuration) cue(s) whose end was not after their start") }
        return ParsedSubtitle(format: .webVTT, cues: SubtitleText.sortedStable(cues), warnings: warnings, vttStyleBlocks: styleBlocks, vttRegions: regions)
    }

    struct Timing {
        var start: TimeInterval
        var end: TimeInterval
        var settings: String
    }

    static func timing(_ line: String) -> Timing? {
        guard let arrow = line.range(of: "-->") else { return nil }
        let left = line[line.startIndex..<arrow.lowerBound]
        let afterArrow = line[arrow.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
        let endToken = afterArrow.prefix(while: { $0 != " " && $0 != "\t" })
        let settings = afterArrow.dropFirst(endToken.count)
        guard let a = SubtitleText.timestamp(left), let b = SubtitleText.timestamp(endToken) else { return nil }
        return Timing(start: a, end: b, settings: String(settings))
    }

    static func parseSettings(_ text: String) -> VTTCueSettings {
        var s = VTTCueSettings()
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let kv = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let value = String(kv[1])
            switch kv[0] {
            case "position":
                let first = value.split(separator: ",").first.map(String.init) ?? value
                if let p = percent(first) { s.positionPercent = p }
            case "line":
                let first = value.split(separator: ",").first.map(String.init) ?? value
                if first.hasSuffix("%") {
                    if let p = percent(first) { s.line = p; s.lineIsPercent = true }
                } else if let v = Double(first), v.isFinite {
                    s.line = v
                    s.lineIsPercent = false
                }
            case "size":
                if let p = percent(value) { s.sizePercent = p }
            case "align":
                if let a = VTTCueSettings.Align(rawValue: value) { s.align = a }
            case "vertical":
                if let d = VTTCueSettings.Direction(rawValue: value) { s.direction = d }
            case "region":
                if !value.isEmpty { s.region = value }
            default:
                break
            }
        }
        return s
    }

    private static func percent(_ text: String) -> Double? {
        let body = text.hasSuffix("%") ? String(text.dropLast()) : text
        guard let v = Double(body), v.isFinite, v >= 0, v <= 100 else { return nil }
        return v
    }

    /// Alignment hint from cue settings (Interpretation, PROVISIONAL): horizontal from `align`; vertical is top for
    /// `line:` percentages below 33 or line numbers 0...4, middle for 33...66 %, bottom otherwise (including no `line`).
    static func alignment(for s: VTTCueSettings) -> SubtitleAlignment {
        let horizontal: SubtitleAlignment.Horizontal
        switch s.align {
        case .left, .start: horizontal = .left
        case .right, .end: horizontal = .right
        case .center: horizontal = .center
        }
        var vertical = SubtitleAlignment.Vertical.bottom
        if let line = s.line {
            if s.lineIsPercent {
                vertical = line < 33 ? .top : (line <= 66 ? .middle : .bottom)
            } else if line >= 0, line <= 4 {
                vertical = .top
            }
        }
        return SubtitleAlignment(horizontal: horizontal, vertical: vertical)
    }
}
