import Foundation

/// What the text header of a VobSub `.idx` file says. VobSub bitmaps themselves (`.sub`) are NOT decoded in this
/// batch; this only lets the track list show language names and the colour palette.
public struct VobSubIndexHeader: Equatable, Sendable {
    public struct Track: Equatable, Sendable {
        /// Language as written in the file (usually a two-letter code such as "en").
        public var language: String
        public var index: Int
    }

    public var width: Int?
    public var height: Int?
    /// Up to 16 colours from the `palette:` line.
    public var palette: [SubtitleColor]
    public var tracks: [Track]
    /// Number of `timestamp:` lines (cues) in the file, across all tracks.
    public var timestampCount: Int

    /// Reads the header. Always succeeds; missing parts stay nil or empty.
    public static func parse(_ text: String) -> VobSubIndexHeader {
        var header = VobSubIndexHeader(width: nil, height: nil, palette: [], tracks: [], timestampCount: 0)
        for raw in SubtitleText.lines(SubtitleText.strippingBOM(text)) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("timestamp:") { header.timestampCount += 1; continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "size":
                let parts = value.lowercased().split(separator: "x")
                if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 { header.width = w; header.height = h }
            case "palette":
                for token in value.split(separator: ",") {
                    if let c = SubtitleText.cssColor(token.trimmingCharacters(in: .whitespaces)), token.trimmingCharacters(in: .whitespaces).count == 6 {
                        header.palette.append(c)
                    }
                }
                if header.palette.count > 16 { header.palette.removeLast(header.palette.count - 16) }
            case "id":
                // "id: en, index: 0"
                let pieces = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var language = ""
                var index = header.tracks.count
                for piece in pieces {
                    if piece.lowercased().hasPrefix("index:"), let n = Int(piece.dropFirst(6).trimmingCharacters(in: .whitespaces)) { index = n }
                    else if language.isEmpty, !piece.contains(":") { language = piece }
                }
                header.tracks.append(Track(language: language, index: index))
            default:
                break
            }
        }
        return header
    }
}
