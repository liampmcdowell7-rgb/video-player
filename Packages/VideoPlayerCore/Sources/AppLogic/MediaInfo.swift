import Foundation
import LibraryIndex
import MetadataLocal
import MetadataOnline

/// One line of the detail page's "Media Info" section (#15 6.2): a label and its value.
public struct MediaInfoRow: Equatable, Sendable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String
}

/// The "Media Info" section of a movie or episode page (#15 6.2, #21 C): what the preferred file contains, most important
/// first (resolution, HDR, video codec, frame rate, bitrate, each audio track, subtitles, container, size, source, path),
/// always fully shown. The library index gives the first part (file-name tags and the scan); the frame rate, every audio
/// track and the subtitles inside the file come from the file's header, read when the page opens (`MediaTrackProbe`,
/// OPEN_QUESTIONS R192). Until then, and for containers that are not read, those rows say "Not checked yet" (#25 B6: one
/// wording everywhere for "the file has not been probed"); a fact the probe or the scan read and found missing says "Not
/// known". Nothing is guessed.
public enum MediaInfo {
    /// The value of a row the file's facts have no answer for.
    public static let notKnown = "Not known"
    /// #25 B6: the value of a row that only the file's header can answer, while the header has not been read (OPEN_QUESTIONS R198).
    public static let notChecked = "Not checked yet"

    public static func rows(file: StoredFile, sidecars: [StoredFile], sourceName: String?, tracks: FileTrackDetails? = nil) -> [MediaInfoRow] {
        rows(technical: file.technical, size: file.size, path: file.path,
             subtitleNames: sidecars.filter { $0.kind == .subtitle }.map(\.name), sourceName: sourceName, tracks: tracks)
    }

    public static func rows(technical t: FileTechnicalInfo?, size: Int64?, path: String, subtitleNames: [String], sourceName: String?,
                            tracks: FileTrackDetails? = nil) -> [MediaInfoRow] {
        var rows: [MediaInfoRow] = []
        func add(_ label: String, _ value: String?) { rows.append(MediaInfoRow(label: label, value: value ?? notKnown)) }

        add("Resolution", resolution(width: t?.width, height: t?.height))
        // An SDR file has no HDR format; it is said only when the probe or a tag gave the video's facts.
        let hdr = t.flatMap { FormatNames.hdr($0.hdrFormats, dolbyVisionProfile: $0.dolbyVisionProfile) }
        add("HDR", hdr ?? ((t?.height != nil || t?.videoCodec != nil) ? "None (SDR)" : nil))
        add("Video", t?.videoCodec.map(FormatNames.videoCodec))
        rows.append(MediaInfoRow(label: "Frame Rate", value: tracks == nil ? notChecked : (tracks?.frameRate.flatMap(frameRate) ?? notKnown)))
        add("Bitrate", t?.bitrate.flatMap(bitrate))
        // Every audio track when the header was read ("Audio 1", "Audio 2", ...); before that the index's one line.
        if let audio = tracks?.audio, !audio.isEmpty {
            for (i, track) in audio.enumerated() {
                rows.append(MediaInfoRow(label: audio.count == 1 ? "Audio" : "Audio \(i + 1)", value: audioLine(track)))
            }
            // R369: the header's track lines never claim Atmos, so the Dolby Atmos badge (from the library scan: a file-name
            // tag or the probe) keeps its own row here.
            if t?.hasAtmos == true { rows.append(MediaInfoRow(label: "Audio Format", value: "Dolby Atmos (from the library scan)")) }
        } else {
            let line = t.flatMap { FormatNames.audio(codec: $0.audioCodec, channels: $0.audioChannels, atmos: $0.hasAtmos) }
            rows.append(MediaInfoRow(label: "Audio", value: line ?? (tracks == nil ? notChecked : notKnown)))
        }
        add("Subtitles", subtitlesLine(embedded: tracks?.subtitles, files: subtitleNames))
        add("Container", t?.container.map(containerName))
        add("File Size", size.map(DisplayText.fileSize))
        add("Source", sourceName)
        add("Path", path)
        return rows
    }

    /// "23.976 fps", "25 fps".
    public static func frameRate(_ fps: Double) -> String? {
        guard fps > 0, fps.isFinite else { return nil }
        let rounded = (fps * 1000).rounded() / 1000
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.3f", rounded)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return text + " fps"
    }

    /// "Dolby TrueHD 7.1 · English · default", plus the track's own name when it says more ("Director's commentary").
    /// Atmos is never claimed from the header (Matroska has no flag for it); a name that mentions it is shown as the name.
    public static func audioLine(_ a: FileTrackDetails.Audio) -> String {
        var parts = [FormatNames.audio(codec: a.codec, channels: a.channels, atmos: false) ?? a.codec]
        if let lang = a.language, !lang.isEmpty { parts.append(MatroskaTrack.languageName(for: lang)) }
        if a.isDefault { parts.append("default") }
        if a.isCommentary { parts.append("commentary") }
        if let name = a.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty { parts.append("“\(name)”") }
        return parts.joined(separator: " · ")
    }

    /// Embedded tracks ("In the file: English (PGS), French (SRT, forced)") and the files next to the video. When the header
    /// was not read, the embedded part says "not checked yet" (#25 B6).
    public static func subtitlesLine(embedded: [FileTrackDetails.Subtitle]?, files: [String]) -> String {
        let inFile: String
        if let embedded {
            inFile = embedded.isEmpty ? "none in the file" : "in the file: " + embedded.map { s in
                var notes = [s.codec]
                if s.isForced { notes.append("forced") }
                if s.isHearingImpaired { notes.append("SDH") }
                let lang = s.language.map { MatroskaTrack.languageName(for: $0) } ?? "Unknown language"
                return "\(lang) (\(notes.joined(separator: ", ")))"
            }.joined(separator: ", ")
        } else {
            inFile = "in the file: not checked yet"
        }
        let names = files.sorted()
        let side = names.isEmpty ? "no subtitle files next to the video" : "files: " + names.joined(separator: ", ")
        let text = inFile + "; " + side
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "3840 × 2160 (4K)", "1920 × 1080 (1080p)", or "1080p" when only the height is known.
    public static func resolution(width: Int?, height: Int?) -> String? {
        guard let name = resolutionName(height: height), let height else { return nil }
        guard let width, width > 0 else { return name }
        return "\(width) × \(height) (\(name))"
    }

    /// "4K", "1080p", "720p" or "<height>p": the name in the Resolution row, and the resolution badge (R369).
    public static func resolutionName(height: Int?) -> String? {
        guard let height, height > 0 else { return nil }
        switch height {
        case 2000...: return "4K"
        case 1000..<2000: return "1080p"
        case 700..<1000: return "720p"
        default: return "\(height)p"
        }
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
        /// #25 B7 (OPEN_QUESTIONS R201): a photo to show in the cast shelf. Only the sample library's generated test photos
        /// fill it today; the online lookup leaves it empty (no photo is requested), and the shelf shows the system person
        /// symbol instead.
        public var photo: URL? = nil
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
