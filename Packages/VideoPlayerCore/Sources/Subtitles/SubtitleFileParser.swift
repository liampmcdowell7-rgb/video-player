import Foundation

public enum SubtitleParseError: Error, Equatable, Sendable {
    /// The text is not SRT, WebVTT, ASS or SSA.
    case unrecognizedFormat
    /// An image or not-yet-built format; use the dedicated parser (PGS) or nothing (VobSub).
    case unsupportedFormat(SubtitleFormat)
}

/// Decodes bytes and picks the right text parser.
public enum SubtitleFileParser {

    /// Names the format from the content (first 64 KiB), using the file extension to break ties.
    public static func detectFormat(text: String, fileExtension: String? = nil) -> SubtitleFormat? {
        let head = String(text.unicodeScalars.prefix(65_536))
        let trimmedHead = head.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" })
        if trimmedHead.hasPrefix("WEBVTT") { return .webVTT }
        let lower = head.lowercased()
        if lower.contains("[script info]") || lower.contains("[v4+ styles]") || lower.contains("[v4 styles]") || lower.contains("[events]") {
            return lower.contains("[v4 styles]") && !lower.contains("[v4+ styles]") ? .ssa : .ass
        }
        if SubtitleText.lines(head).contains(where: { $0.lowercased().hasPrefix("dialogue:") }) { return .ass }
        if head.contains("-->") {
            if fileExtension?.lowercased() == "vtt" { return .webVTT }
            return .srt
        }
        return nil
    }

    /// Parses already-decoded text. `format` nil means detect.
    public static func parse(text: String, format: SubtitleFormat? = nil, fileExtension: String? = nil) throws -> ParsedSubtitle {
        let chosen: SubtitleFormat
        if let format { chosen = format }
        else if let detected = detectFormat(text: text, fileExtension: fileExtension) { chosen = detected }
        else { throw SubtitleParseError.unrecognizedFormat }
        switch chosen {
        case .srt: return SRTParser.parse(text)
        case .webVTT: return WebVTTParser.parse(text)
        case .ass, .ssa: return ASSParser.parse(text)
        case .pgs, .vobSub: throw SubtitleParseError.unsupportedFormat(chosen)
        }
    }

    /// Decodes a subtitle file and parses it. The language hint comes from the file name when not given.
    public static func parse(_ data: Data, fileName: String? = nil, languageHint: String? = nil) throws -> (parsed: ParsedSubtitle, decoding: DecodedSubtitleText) {
        let ext = fileName.map { ($0 as NSString).pathExtension.lowercased() }
        if ext == "sup" || data.starts(with: [0x50, 0x47]) { throw SubtitleParseError.unsupportedFormat(.pgs) }
        if ext == "sub" || ext == "idx" { throw SubtitleParseError.unsupportedFormat(.vobSub) }
        let hint = languageHint ?? fileName.flatMap { SubtitleTextDecoder.languageHint(fromFileName: $0) }
        let decoded = SubtitleTextDecoder.decode(data, languageHint: hint)
        let parsed = try parse(text: decoded.text, format: nil, fileExtension: ext)
        return (parsed, decoded)
    }
}
