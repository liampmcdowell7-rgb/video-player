import Foundation

/// Where a subtitle came from, which also says how it must be shown.
public enum SubtitleFormat: String, Sendable, Codable, CaseIterable {
    case srt, webVTT, ass, ssa
    /// Image subtitles (HDMV Presentation Graphic Stream, .sup).
    case pgs
    /// DVD bitmap subtitles (.idx/.sub). Not built in this batch; only the .idx header is read.
    case vobSub

    public var isText: Bool { self != .pgs && self != .vobSub }
}

/// RGBA colour with components 0...255. Alpha 255 is opaque.
public struct SubtitleColor: Equatable, Hashable, Sendable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = SubtitleColor(red: 255, green: 255, blue: 255)
}

/// A piece of text with one set of attributes. Nil attributes mean "use the player's style".
public struct SubtitleRun: Equatable, Hashable, Sendable, Codable {
    public var text: String
    public var bold = false
    public var italic = false
    public var underline = false
    public var strikeOut = false
    public var color: SubtitleColor?
    public var fontName: String?
    public var fontSize: Double?

    public init(
        _ text: String,
        bold: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        strikeOut: Bool = false,
        color: SubtitleColor? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil
    ) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikeOut = strikeOut
        self.color = color
        self.fontName = fontName
        self.fontSize = fontSize
    }

    /// Same attributes, ignoring the text (used to merge neighbouring runs).
    func hasSameStyle(as other: SubtitleRun) -> Bool {
        bold == other.bold && italic == other.italic && underline == other.underline
            && strikeOut == other.strikeOut && color == other.color
            && fontName == other.fontName && fontSize == other.fontSize
    }
}

/// Alignment on the numeric-keypad grid used by ASS `\an` (1 bottom-left ... 9 top-right).
public struct SubtitleAlignment: Equatable, Hashable, Sendable, Codable {
    public enum Horizontal: Int, Sendable, Codable { case left = 0, center = 1, right = 2 }
    public enum Vertical: Int, Sendable, Codable { case bottom = 0, middle = 1, top = 2 }

    public var horizontal: Horizontal
    public var vertical: Vertical

    public init(horizontal: Horizontal, vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let bottomCenter = SubtitleAlignment(horizontal: .center, vertical: .bottom)

    /// 1...9 as on a numeric keypad. Out-of-range values give nil.
    public init?(numpad: Int) {
        guard (1...9).contains(numpad) else { return nil }
        self.horizontal = Horizontal(rawValue: (numpad - 1) % 3) ?? .center
        self.vertical = Vertical(rawValue: (numpad - 1) / 3) ?? .bottom
    }

    public var numpad: Int { vertical.rawValue * 3 + horizontal.rawValue + 1 }
}

/// An absolute position in the script's coordinate space (ASS `\pos`, PlayResX x PlayResY).
public struct SubtitlePosition: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    /// Size of the coordinate space the numbers are in.
    public var spaceWidth: Double
    public var spaceHeight: Double

    public init(x: Double, y: Double, spaceWidth: Double, spaceHeight: Double) {
        self.x = x
        self.y = y
        self.spaceWidth = spaceWidth
        self.spaceHeight = spaceHeight
    }
}

/// WebVTT cue settings, normalised.
public struct VTTCueSettings: Equatable, Hashable, Sendable, Codable {
    public enum Direction: String, Sendable, Codable { case horizontal, verticalRightToLeft = "rl", verticalLeftToRight = "lr" }
    public enum Align: String, Sendable, Codable { case start, center, end, left, right }

    /// 0...100 percent from the left edge of the video (nil = auto).
    public var positionPercent: Double?
    /// Line: either a line number (negative counts from the bottom) or a percentage.
    public var line: Double?
    public var lineIsPercent = false
    public var sizePercent: Double?
    public var align: Align = .center
    public var direction: Direction = .horizontal
    public var region: String?

    public init() {}
}

/// One subtitle shown from `start` to `end` (seconds on the media timeline).
public struct SubtitleCue: Equatable, Hashable, Sendable, Codable {
    public var start: TimeInterval
    public var end: TimeInterval
    /// Text with attributes. Hard line breaks are "\n" inside run text.
    public var runs: [SubtitleRun]
    public var format: SubtitleFormat
    public var alignment: SubtitleAlignment?
    public var position: SubtitlePosition?
    public var layer: Int = 0
    /// ASS style name, WebVTT cue identifier or SRT index, when the file has one.
    public var identifier: String?
    public var styleName: String?
    /// ASS margins (left, right, vertical) in script pixels, when the file gives them.
    public var marginLeft: Double?
    public var marginRight: Double?
    public var marginVertical: Double?
    /// ASS `\fad(in, out)` in seconds.
    public var fadeIn: TimeInterval?
    public var fadeOut: TimeInterval?
    public var vtt: VTTCueSettings?
    /// Speaker from a WebVTT `<v>` tag or an ASS name field.
    public var speaker: String?
    /// True when the cue is in a forced or SDH track (set by the track, not by the cue).
    public var isForced = false
    public var isSDH = false

    public init(
        start: TimeInterval,
        end: TimeInterval,
        runs: [SubtitleRun],
        format: SubtitleFormat,
        alignment: SubtitleAlignment? = nil,
        position: SubtitlePosition? = nil,
        layer: Int = 0,
        identifier: String? = nil,
        styleName: String? = nil
    ) {
        self.start = start
        self.end = end
        self.runs = runs
        self.format = format
        self.alignment = alignment
        self.position = position
        self.layer = layer
        self.identifier = identifier
        self.styleName = styleName
    }

    /// The text without attributes.
    public var plainText: String { runs.map(\.text).joined() }

    public var duration: TimeInterval { end - start }

    /// Equal in everything a viewer sees except the time range.
    func isVisuallyIdentical(to other: SubtitleCue) -> Bool {
        runs == other.runs && alignment == other.alignment && position == other.position
            && layer == other.layer && styleName == other.styleName && vtt == other.vtt
            && marginLeft == other.marginLeft && marginRight == other.marginRight
            && marginVertical == other.marginVertical && speaker == other.speaker
    }
}

/// A parsed set of cues plus things the parser noticed.
public struct ParsedSubtitle: Sendable {
    public var format: SubtitleFormat
    public var cues: [SubtitleCue]
    /// Plain-language notes about what was skipped or repaired. Never contains subtitle text.
    public var warnings: [String]
    /// ASS/SSA script information, when the file had it.
    public var ass: ASSScript?
    /// WebVTT regions and style blocks.
    public var vttStyleBlocks: [String]
    /// WebVTT REGION blocks, keyed by region id, with their raw settings.
    public var vttRegions: [String: [String: String]]

    public init(
        format: SubtitleFormat,
        cues: [SubtitleCue],
        warnings: [String] = [],
        ass: ASSScript? = nil,
        vttStyleBlocks: [String] = [],
        vttRegions: [String: [String: String]] = [:]
    ) {
        self.format = format
        self.cues = cues
        self.warnings = warnings
        self.ass = ass
        self.vttStyleBlocks = vttStyleBlocks
        self.vttRegions = vttRegions
    }
}

/// A sorted list of cues with a fast "what is on screen at time t" query.
///
/// `activeCues(at:)` is O(log n + k) for k active cues, even with heavily overlapping cues,
/// using a balanced interval index over the cues sorted by start time.
public struct SubtitleTrack: Sendable {
    public private(set) var cues: [SubtitleCue]
    public var format: SubtitleFormat
    public var language: String?
    public var isForced: Bool
    public var isSDH: Bool
    private var maxEnd: [TimeInterval]

    public init(cues: [SubtitleCue], format: SubtitleFormat, language: String? = nil, isForced: Bool = false, isSDH: Bool = false) {
        var sorted = cues
        sorted.sort { a, b in
            if a.start != b.start { return a.start < b.start }
            if a.layer != b.layer { return a.layer < b.layer }
            return a.end < b.end
        }
        if isForced || isSDH {
            for i in sorted.indices {
                sorted[i].isForced = isForced
                sorted[i].isSDH = isSDH
            }
        }
        self.cues = sorted
        self.format = format
        self.language = language
        self.isForced = isForced
        self.isSDH = isSDH
        self.maxEnd = [TimeInterval](repeating: 0, count: sorted.count)
        _ = SubtitleTrack.fill(&maxEnd, sorted, 0, sorted.count)
    }

    public init(parsed: ParsedSubtitle, language: String? = nil, isForced: Bool = false, isSDH: Bool = false) {
        self.init(cues: parsed.cues, format: parsed.format, language: language, isForced: isForced, isSDH: isSDH)
    }

    /// Fills `maxEnd[mid]` with the largest end time in the subtree [lo, hi) rooted at its midpoint.
    @discardableResult
    private static func fill(_ maxEnd: inout [TimeInterval], _ cues: [SubtitleCue], _ lo: Int, _ hi: Int) -> TimeInterval {
        if lo >= hi { return -.infinity }
        let mid = (lo + hi) / 2
        let left = fill(&maxEnd, cues, lo, mid)
        let right = fill(&maxEnd, cues, mid + 1, hi)
        let value = max(cues[mid].end, left, right)
        maxEnd[mid] = value
        return value
    }

    public var isEmpty: Bool { cues.isEmpty }
    public var count: Int { cues.count }

    /// Cues with `start <= time < end`, in start order.
    public func activeCues(at time: TimeInterval) -> [SubtitleCue] {
        var result: [SubtitleCue] = []
        collect(time, 0, cues.count, &result)
        return result
    }

    private func collect(_ t: TimeInterval, _ lo: Int, _ hi: Int, _ out: inout [SubtitleCue]) {
        if lo >= hi { return }
        let mid = (lo + hi) / 2
        if maxEnd[mid] <= t { return }
        collect(t, lo, mid, &out)
        let cue = cues[mid]
        if cue.start <= t {
            if cue.end > t { out.append(cue) }
            collect(t, mid + 1, hi, &out)
        }
    }

    /// The first start time strictly after `time` (to schedule the next change), if any.
    public func nextChange(after time: TimeInterval) -> TimeInterval? {
        var lo = 0
        var hi = cues.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if cues[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        var best: TimeInterval? = lo < cues.count ? cues[lo].start : nil
        // An end time after `time` can come earlier than the next start.
        for cue in activeCues(at: time) where cue.end > time {
            if best == nil || cue.end < best ?? .infinity { best = cue.end }
        }
        return best
    }

    /// Moves every cue by `offset` seconds (negative = earlier). A cue that ends at or before 0 after the
    /// shift is dropped; a cue that would start before 0 starts at 0 (so a start is never negative).
    public func shifted(by offset: TimeInterval) -> SubtitleTrack {
        var out: [SubtitleCue] = []
        out.reserveCapacity(cues.count)
        for var cue in cues {
            let newEnd = cue.end + offset
            if newEnd <= 0 { continue }
            cue.start = max(0, cue.start + offset)
            cue.end = newEnd
            out.append(cue)
        }
        return SubtitleTrack(cues: out, format: format, language: language, isForced: isForced, isSDH: isSDH)
    }

    /// Joins cues that look the same and touch or overlap (gap <= `maxGap` seconds). Overlapping
    /// duplicates (the same line twice at once, common in broken files) collapse to one.
    public func mergingIdenticalNeighbours(maxGap: TimeInterval = 0.001) -> SubtitleTrack {
        var out: [SubtitleCue] = []
        out.reserveCapacity(cues.count)
        // Output indices per text signature; only the newest few are compared, which keeps repeated lines
        // (a thousand "♪" cues) from costing quadratic time.
        var indicesBySignature: [Int: [Int]] = [:]
        for cue in cues {
            let key = SubtitleTrack.signature(cue)
            var merged = false
            for idx in (indicesBySignature[key] ?? []).suffix(8).reversed() where out[idx].isVisuallyIdentical(to: cue) && cue.start <= out[idx].end + maxGap {
                out[idx].end = max(out[idx].end, cue.end)
                merged = true
                break
            }
            if !merged {
                indicesBySignature[key, default: []].append(out.count)
                out.append(cue)
            }
        }
        return SubtitleTrack(cues: out, format: format, language: language, isForced: isForced, isSDH: isSDH)
    }

    private static func signature(_ cue: SubtitleCue) -> Int {
        var h = Hasher()
        h.combine(cue.plainText)
        h.combine(cue.layer)
        h.combine(cue.styleName)
        return h.finalize()
    }
}
