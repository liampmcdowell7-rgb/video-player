import Foundation

// Segment sidecar files: a small file next to the video that says where the intro, recap or credits are.
//
// PROVISIONAL FORMATS. The spec (docs/PLAYBACK_LOGIC.md "Detection tiers", docs/METADATA_LOCAL.md) names no sidecar format for
// segments, only "local sidecar" as a source tier, so these two are my choice (docs/SEGMENTS.md has the alternatives):
//   <video name>.edl            lines of "start end action"
//   <video name>.segments.json  {"version":1,"segments":[{"type":"intro","start":12.5,"end":95}]}
// Parsing never throws and never trusts the file: bad lines and entries are skipped and reported in `warnings`; the
// resolver's limits (intro 10 to 180 s, credits in the last 40 percent, ...) apply afterwards like for every source.

public struct SidecarEntry: Equatable, Sendable {
    public var type: SegmentType
    public var start: TimeInterval
    public var end: TimeInterval
    /// Length of the release the times were made for (JSON only). When present it must match the file (B1).
    public var referenceDuration: TimeInterval?

    public init(type: SegmentType, start: TimeInterval, end: TimeInterval, referenceDuration: TimeInterval? = nil) {
        self.type = type
        self.start = start
        self.end = end
        self.referenceDuration = referenceDuration
    }
}

public struct SidecarParseResult: Equatable, Sendable {
    public var entries: [SidecarEntry]
    /// One line per thing that was skipped, for File Details and tests. Empty for a clean file.
    public var warnings: [String]
    public init(entries: [SidecarEntry] = [], warnings: [String] = []) {
        self.entries = entries
        self.warnings = warnings
    }
}

public enum SidecarFormat: String, Sendable, CaseIterable {
    case edl, json

    /// File name suffixes after the video's stem, lower case. Matching is case-insensitive.
    public var suffix: String {
        switch self {
        case .edl: return ".edl"
        case .json: return ".segments.json"
        }
    }
}

public enum SidecarSegments {
    /// PROVISIONAL: confidence given to a sidecar segment. Below embedded chapters (0.9) because a sidecar is easier to get wrong
    /// (a file for another cut), above the 0.7 threshold. The source priority already puts chapters above sidecars.
    public static let sidecarConfidence = 0.8
    /// A sidecar bigger than this is not read (a segment list is a few hundred bytes).
    public static let maxBytes = 256 * 1024
    /// Lines or entries after this many are ignored.
    public static let maxEntries = 500

    /// Which of `names` (the file names in the video's folder) are segment sidecars of `videoName`, in the order EDL, JSON.
    /// A sidecar is `<stem>.edl` or `<stem>.segments.json`, compared case-insensitively.
    public static func matching(videoName: String, among names: [String]) -> [(name: String, format: SidecarFormat)] {
        let stem = Self.stem(of: videoName).lowercased()
        var out: [(name: String, format: SidecarFormat)] = []
        for format in SidecarFormat.allCases {
            let wanted = stem + format.suffix
            if let hit = names.first(where: { $0.lowercased() == wanted }) { out.append((hit, format)) }
        }
        return out
    }

    static func stem(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[name.startIndex..<dot])
    }

    /// Parses by format.
    public static func parse(_ data: Data, format: SidecarFormat) -> SidecarParseResult {
        guard data.count <= maxBytes else {
            return SidecarParseResult(warnings: ["The file is larger than \(maxBytes) bytes and was not read"])
        }
        switch format {
        case .edl: return EDLSegmentParser.parse(data)
        case .json: return SegmentsJSONParser.parse(data)
        }
    }

    /// Entries to candidates for `file`, source `.localSidecar`, confidence `sidecarConfidence`.
    public static func candidates(from entries: [SidecarEntry], file: FileIdentity) -> [SkipSegment] {
        entries.map {
            SkipSegment(type: $0.type, start: $0.start, end: $0.end, source: .localSidecar, confidence: sidecarConfidence,
                        file: file, referenceDuration: $0.referenceDuration)
        }
    }

    /// "12.5", "75", "1:15", "0:01:15.250" to seconds. Nil for anything else (negative, infinite, empty, more than 3 parts).
    public static func parseTime(_ text: String) -> TimeInterval? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }
        var total = 0.0
        for (i, part) in parts.enumerated() {
            guard let v = Double(part), v.isFinite, v >= 0 else { return nil }
            // Only the last part may have a fraction; minutes and hours are whole numbers.
            if i < parts.count - 1, v != v.rounded(.towardZero) { return nil }
            total = total * 60 + v
        }
        return total.isFinite ? total : nil
    }

    static func type(named text: String) -> SegmentType? {
        SegmentType(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// `start end action` per line, the layout of an EDL file (times in seconds, or h:mm:ss.fff).
///
/// The classic action numbers (0 cut, 1 mute, 2 scene marker, 3 commercial break) are ignored with a warning: this player never
/// cuts or mutes content. The action may also be one of the words `recap`, `intro` or `credits` (any case), which is the
/// PROVISIONAL extension that makes the format useful here. Text after the action is a comment. Lines starting with `#` and
/// blank lines are ignored.
public enum EDLSegmentParser {
    public static func parse(_ data: Data) -> SidecarParseResult {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return parse(text)
    }

    public static func parse(_ text: String) -> SidecarParseResult {
        var entries: [SidecarEntry] = []
        var warnings: [String] = []
        var number = 0
        // "\r\n" is ONE Character in Swift, so it becomes "\n" first; a lone "\r" still ends a line.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            number += 1
            if number > SidecarSegments.maxEntries {
                warnings.append("More than \(SidecarSegments.maxEntries) lines: the rest was ignored")
                break
            }
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard tokens.count >= 3 else {
                warnings.append("Line \(number): expected \"start end action\", found \"\(shortened(line))\"")
                continue
            }
            guard let start = SidecarSegments.parseTime(tokens[0]), let end = SidecarSegments.parseTime(tokens[1]) else {
                warnings.append("Line \(number): the times \"\(shortened(tokens[0]))\" and \"\(shortened(tokens[1]))\" are not both valid")
                continue
            }
            guard end > start else {
                warnings.append("Line \(number): the end is not after the start")
                continue
            }
            if let type = SidecarSegments.type(named: tokens[2]) {
                entries.append(SidecarEntry(type: type, start: start, end: end))
            } else if Int(tokens[2]) != nil {
                warnings.append("Line \(number): action \(tokens[2]) is a cut, mute or marker, not a skip segment; ignored")
            } else {
                warnings.append("Line \(number): unknown action \"\(shortened(tokens[2]))\"; use recap, intro or credits")
            }
        }
        return SidecarParseResult(entries: entries, warnings: warnings)
    }

    private static func shortened(_ s: String) -> String { s.count > 40 ? String(s.prefix(40)) + "..." : s }
}

/// `{"version":1,"referenceDuration":2610.4,"segments":[{"type":"intro","start":12.5,"end":95}]}`
///
/// `type` is `recap`, `intro` or `credits`; `start` and `end` are seconds (a number) or h:mm:ss text. `referenceDuration` (file level or per
/// entry) is the length of the release the times were made for. Unknown keys are ignored, so a newer file still reads. A
/// `version` above 1 reads with a warning.
public enum SegmentsJSONParser {
    public static let knownVersion = 1

    public static func parse(_ data: Data) -> SidecarParseResult {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return SidecarParseResult(warnings: ["Not valid JSON"])
        }
        guard let object = root as? [String: Any] else {
            return SidecarParseResult(warnings: ["The top level must be an object with a \"segments\" list"])
        }
        var warnings: [String] = []
        if let version = number(object["version"]), version > Double(knownVersion) {
            warnings.append("Format version \(Int(version)) is newer than this app knows (\(knownVersion)); read what it understands")
        }
        guard let list = object["segments"] as? [Any] else {
            return SidecarParseResult(warnings: warnings + ["There is no \"segments\" list"])
        }
        let fileReference = positive(object["referenceDuration"])
        var entries: [SidecarEntry] = []
        for (index, any) in list.enumerated() {
            if index >= SidecarSegments.maxEntries {
                warnings.append("More than \(SidecarSegments.maxEntries) entries: the rest was ignored")
                break
            }
            let label = "Entry \(index + 1)"
            guard let item = any as? [String: Any] else {
                warnings.append("\(label): not an object")
                continue
            }
            guard let typeText = item["type"] as? String, let type = SidecarSegments.type(named: typeText) else {
                warnings.append("\(label): \"type\" must be recap, intro or credits")
                continue
            }
            guard let start = time(item["start"]), let end = time(item["end"]) else {
                warnings.append("\(label): \"start\" and \"end\" must be seconds or h:mm:ss")
                continue
            }
            guard end > start else {
                warnings.append("\(label): the end is not after the start")
                continue
            }
            entries.append(SidecarEntry(type: type, start: start, end: end, referenceDuration: positive(item["referenceDuration"]) ?? fileReference))
        }
        return SidecarParseResult(entries: entries, warnings: warnings)
    }

    private static func number(_ value: Any?) -> Double? {
        // A JSON true or false also arrives as a number (1 or 0); the limits reject such a time later, so it is not special-cased.
        guard let value else { return nil }
        if let n = value as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let d = value as? Double { return d.isFinite ? d : nil }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private static func positive(_ value: Any?) -> Double? {
        number(value).flatMap { $0 > 0 ? $0 : nil }
    }

    private static func time(_ value: Any?) -> TimeInterval? {
        if let n = number(value) { return n >= 0 ? n : nil }
        if let s = value as? String { return SidecarSegments.parseTime(s) }
        return nil
    }
}
