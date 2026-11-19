import Foundation
import LibraryIndex
import MetadataOnline

/// One line of the detail page's "Media Info" section (#15 6.2): a label and its value.
public struct MediaInfoRow: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
}

/// The "Media Info" section of a movie or episode page (#15 6.2): what the preferred file contains, most important first,
/// always fully shown. Everything comes from the library index (file-name tags and the probe); a value the index does not
/// hold says so instead of being guessed. The index keeps one audio track and no frame rate or embedded subtitle list, so
/// those rows say what is and is not known (OPEN_QUESTIONS R182).
public enum MediaInfo {
    /// The value of a row the index has no answer for.
    public static let notKnown = "Not known"
    /// Frame rate: the index does not record it.
    public static let frameRateNotRead = "Not read from the file"

    public static func rows(file: StoredFile, sidecars: [StoredFile], sourceName: String?) -> [MediaInfoRow] {
        rows(technical: file.technical, size: file.size, path: file.path,
             subtitleNames: sidecars.filter { $0.kind == .subtitle }.map(\.name), sourceName: sourceName)
    }

    public static func rows(technical t: FileTechnicalInfo?, size: Int64?, path: String, subtitleNames: [String], sourceName: String?) -> [MediaInfoRow] {
        var rows: [MediaInfoRow] = []
        func add(_ label: String, _ value: String?) { rows.append(MediaInfoRow(label: label, value: value ?? notKnown)) }

        add("Resolution", resolution(width: t?.width, height: t?.height))
        // An SDR file has no HDR format; it is said only when the probe or a tag gave the video's facts.
        let hdr = t.flatMap { FormatNames.hdr($0.hdrFormats, dolbyVisionProfile: $0.dolbyVisionProfile) }
        add("HDR", hdr ?? ((t?.height != nil || t?.videoCodec != nil) ? "None (SDR)" : nil))
        add("Video", t?.videoCodec.map(FormatNames.videoCodec))
        add("Frame Rate", frameRateNotRead)
        add("Bitrate", t?.bitrate.flatMap(bitrate))
        add("Audio", t.flatMap { FormatNames.audio(codec: $0.audioCodec, channels: $0.audioChannels, atmos: $0.hasAtmos) })
        let subtitles = subtitleNames.sorted()
        add("Subtitles", subtitles.isEmpty ? "No subtitle files next to the video" : subtitles.joined(separator: ", "))
        add("Container", t?.container.map(containerName))
        add("File Size", size.map(DisplayText.fileSize))
        add("Source", sourceName)
        add("Path", path)
        return rows
    }

    /// "3840 × 2160 (4K)", "1920 × 1080 (1080p)", or "1080p" when only the height is known.
    public static func resolution(width: Int?, height: Int?) -> String? {
        guard let height, height > 0 else { return nil }
        let name: String
        switch height {
        case 2000...: name = "4K"
        case 1000..<2000: name = "1080p"
        case 700..<1000: name = "720p"
        default: name = "\(height)p"
        }
        guard let width, width > 0 else { return name }
        return "\(width) × \(height) (\(name))"
    }

    /// "57.6 Mbit/s", "800 kbit/s". The index keeps bits per second.
    public static func bitrate(_ bitsPerSecond: Int64) -> String? {
        guard bitsPerSecond > 0 else { return nil }
        if bitsPerSecond >= 1_000_000 { return String(format: "%.1f Mbit/s", Double(bitsPerSecond) / 1_000_000) }
        return "\(bitsPerSecond / 1000) kbit/s"
    }

    public static func containerName(_ c: ContainerFormat) -> String {
        switch c {
        case .mkv: return "MKV"
        case .mp4: return "MP4"
        case .m4v: return "M4V"
        case .mov: return "MOV"
        case .ts: return "MPEG-TS"
        case .avi: return "AVI"
        case .wmv: return "WMV"
        case .webm: return "WebM"
        case .other: return "Other"
        }
    }
}

/// A title's synopsis and cast from the online details (#15 6.2). They come with the title details the poster lookup already
/// requested (TMDB `append_to_response=credits`), so showing them sends nothing new; without a key there are none.
public struct TitleDetails: Equatable, Sendable {
    public struct CastMember: Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var role: String?
    }
    public var overview: String?
    public var cast: [CastMember]

    /// The longest cast shelf. PROVISIONAL (OPEN_QUESTIONS R182).
    public static let castLimit = 15

    public init(overview: String?, cast: [CastMember]) {
        self.overview = overview
        self.cast = cast
    }

    /// From the online cast list: billing order, at most `castLimit`, empty names left out, blank overview dropped.
    public init(overview: String?, people: [Person]) {
        let text = overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.overview = (text?.isEmpty ?? true) ? nil : text
        let ordered = people.enumerated().sorted { ($0.element.order ?? $0.offset) < ($1.element.order ?? $1.offset) }.map(\.element)
        self.cast = ordered.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(Self.castLimit).map {
            let role = $0.character?.trimmingCharacters(in: .whitespaces)
            return CastMember(id: $0.id, name: $0.name, role: (role?.isEmpty ?? true) ? nil : role)
        }
    }

    public var isEmpty: Bool { overview == nil && cast.isEmpty }
}
