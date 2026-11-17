import Foundation

/// SubRip (.srt) parser that accepts the many ways real files are broken.
///
/// Rules (all covered by tests):
/// - A cue is a line with `start --> end`; the number line before it is optional and may be wrong.
/// - Commas or dots before the milliseconds; hours optional ("01:02,500" is 1 min 2.5 s).
/// - The text runs to the next blank line, or to the next cue when the blank line is missing. A line made only
///   of digits right before a timing line is taken as that cue's number, not as text.
/// - Lines that belong to no cue are skipped and counted in a warning.
/// - Cues whose end is not after their start are dropped; a negative start is clamped to 0 (both counted).
/// - Cues may overlap and may be out of order; the result is sorted by start (file order for ties).
public enum SRTParser {

    public static func parse(_ text: String) -> ParsedSubtitle {
        let lines = SubtitleText.lines(SubtitleText.strippingBOM(text))
        var cues: [SubtitleCue] = []
        var skippedLines = 0
        var droppedEmpty = 0
        var droppedDuration = 0
        var clampedStart = 0
        let n = lines.count
        var i = 0
        var coveredUpTo = 0   // lines before this index have been consumed or skipped

        while i < n {
            guard let (start, end) = timing(lines[i]) else { i += 1; continue }
            // Lines between the last cue and this timing line: the cue number may be the last of them.
            var identifier: String?
            var gapEnd = i
            if i > coveredUpTo {
                let prev = SubtitleText.trimmed(lines[i - 1])
                if SubtitleText.isDigits(Substring(prev)) { identifier = prev; gapEnd = i - 1 }
            }
            if gapEnd > coveredUpTo {
                for k in coveredUpTo..<gapEnd where !SubtitleText.isBlank(lines[k]) { skippedLines += 1 }
            }

            var j = i + 1
            var textLines: [String] = []
            while j < n {
                let line = lines[j]
                if SubtitleText.isBlank(line) { break }
                if timing(line) != nil { break }
                if j + 1 < n, SubtitleText.isDigits(Substring(SubtitleText.trimmed(line))), timing(lines[j + 1]) != nil { break }
                textLines.append(line)
                j += 1
            }
            coveredUpTo = j
            i = j

            let parsed = InlineMarkup.parse(textLines.joined(separator: "\n"), webVTT: false)
            if parsed.runs.isEmpty { droppedEmpty += 1; continue }
            var s = start
            if s < 0 { s = 0; clampedStart += 1 }
            if end <= s { droppedDuration += 1; continue }
            var cue = SubtitleCue(start: s, end: end, runs: parsed.runs, format: .srt, alignment: parsed.alignment, identifier: identifier)
            cue.speaker = parsed.speaker
            cues.append(cue)
        }
        if coveredUpTo < n {
            for k in coveredUpTo..<n where !SubtitleText.isBlank(lines[k]) { skippedLines += 1 }
        }

        var warnings: [String] = []
        if skippedLines > 0 { warnings.append("Skipped \(skippedLines) line(s) that were not part of a cue") }
        if droppedEmpty > 0 { warnings.append("Dropped \(droppedEmpty) cue(s) with no text") }
        if droppedDuration > 0 { warnings.append("Dropped \(droppedDuration) cue(s) whose end was not after their start") }
        if clampedStart > 0 { warnings.append("Moved \(clampedStart) negative start time(s) to 0") }
        return ParsedSubtitle(format: .srt, cues: SubtitleText.sortedStable(cues), warnings: warnings)
    }

    /// `start --> end [coordinates]`, or nil when the line is not a timing line.
    static func timing(_ line: String) -> (TimeInterval, TimeInterval)? {
        guard let arrow = line.range(of: "-->") else { return nil }
        let left = line[line.startIndex..<arrow.lowerBound]
        let rightFull = line[arrow.upperBound...].drop(while: { $0 == " " || $0 == "\t" })
        let right = rightFull.prefix(while: { $0 != " " && $0 != "\t" })
        guard let a = SubtitleText.timestamp(left), let b = SubtitleText.timestamp(right) else { return nil }
        return (a, b)
    }
}
