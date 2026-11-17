import Foundation

/// One line of a File Details screen: a label and a value, both plain text.
public struct FileDetailRow: Equatable, Codable, Sendable {
    public var label: String
    public var value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Plain-text descriptions of tracks and a row list for a File Details screen. Everything is derived from the
/// header; nothing is measured from the stream, so for example "HDR10" means "PQ transfer", not "verified HDR10".
extension MatroskaTrack {
    /// "English", or the code itself when it is not in the short table of common languages.
    public var languageName: String {
        MatroskaTrack.languageName(for: languageBCP47 ?? language)
    }

    static func languageName(for code: String) -> String {
        let key = code.lowercased().split(separator: "-").first.map(String.init) ?? code.lowercased()
        let table: [String: String] = [
            "eng": "English", "en": "English", "fre": "French", "fra": "French", "fr": "French",
            "ger": "German", "deu": "German", "de": "German", "spa": "Spanish", "es": "Spanish",
            "ita": "Italian", "it": "Italian", "jpn": "Japanese", "ja": "Japanese", "kor": "Korean", "ko": "Korean",
            "chi": "Chinese", "zho": "Chinese", "zh": "Chinese", "rus": "Russian", "ru": "Russian",
            "por": "Portuguese", "pt": "Portuguese", "dut": "Dutch", "nld": "Dutch", "nl": "Dutch",
            "swe": "Swedish", "sv": "Swedish", "nor": "Norwegian", "dan": "Danish", "da": "Danish",
            "fin": "Finnish", "fi": "Finnish", "pol": "Polish", "pl": "Polish", "tur": "Turkish", "tr": "Turkish",
            "ara": "Arabic", "ar": "Arabic", "heb": "Hebrew", "he": "Hebrew", "hin": "Hindi", "hi": "Hindi",
            "und": "Undetermined", "zxx": "No linguistic content", "mul": "Multiple languages",
        ]
        return table[key] ?? code
    }

    /// "2.0", "5.1", "7.1" for the common layouts, otherwise "N ch".
    public var channelLayoutLabel: String? {
        guard let n = channels, n > 0 else { return nil }
        switch n {
        case 1: return "1.0"
        case 2: return "2.0"
        case 3: return "2.1"
        case 4: return "4.0"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(n) ch"
        }
    }

    /// One line, for example "HEVC 3840×2160 · 23.976 fps · HDR (PQ) · Dolby Vision 8.1".
    public var summary: String {
        var parts: [String] = []
        switch type {
        case .video:
            var head = videoCodecLabel ?? codecID
            if let w = pixelWidth, let h = pixelHeight { head += " \(w)×\(h)" }
            parts.append(head)
            if let fps = frameRate { parts.append(MatroskaTrack.formatNumber(fps) + " fps") }
            if let c = colour {
                switch c.transfer {
                case .pq: parts.append("HDR (PQ)")
                case .hlg: parts.append("HDR (HLG)")
                case .sdr, .unknown: break
                }
                if let bits = c.bitsPerChannel, bits > 8 { parts.append("\(bits)-bit") }
            }
            if let dv = dolbyVision { parts.append("Dolby Vision \(dv.label)") }
            if isInterlaced == true { parts.append("interlaced") }
        case .audio:
            parts.append(languageName)
            parts.append(MatroskaTrack.audioCodecLabel(codecID))
            if let layout = channelLayoutLabel { parts.append(layout) }
            if let rate = samplingFrequency, rate > 0 { parts.append(MatroskaTrack.formatNumber(rate / 1000) + " kHz") }
            if let bits = bitDepth, bits > 0 { parts.append("\(bits)-bit") }
            if atmos == .nameSuggests { parts.append("Atmos (from the track name)") }
        case .subtitle:
            parts.append(languageName)
            switch subtitleFormat ?? .other {
            case .srt: parts.append("SubRip")
            case .ass: parts.append("ASS")
            case .ssa: parts.append("SSA")
            case .webvtt: parts.append("WebVTT")
            case .pgs: parts.append("PGS (image)")
            case .vobsub: parts.append("VobSub (image)")
            case .dvb: parts.append("DVB (image)")
            case .hdmvText: parts.append("HDMV text")
            case .other: parts.append(codecID)
            }
        default:
            parts.append(codecID)
        }
        if let name, !name.isEmpty { parts.append("\u{201C}\(name)\u{201D}") }
        if isForced { parts.append("forced") }
        if isHearingImpaired { parts.append("SDH") }
        if isCommentary { parts.append("commentary") }
        if isDefault && type != .video { parts.append("default") }
        if !isEnabled { parts.append("disabled") }
        return parts.joined(separator: " · ")
    }

    static func audioCodecLabel(_ id: String) -> String {
        let upper = id.uppercased()
        switch true {
        case upper.hasPrefix("A_EAC3"): return "E-AC-3"
        case upper.hasPrefix("A_AC3"): return "AC-3"
        case upper.hasPrefix("A_TRUEHD"): return "TrueHD"
        case upper.hasPrefix("A_MLP"): return "MLP"
        case upper.hasPrefix("A_DTS/EXPRESS"): return "DTS Express"
        case upper.hasPrefix("A_DTS/LOSSLESS"): return "DTS-HD MA"
        case upper.hasPrefix("A_DTS"): return "DTS"
        case upper.hasPrefix("A_AAC"): return "AAC"
        case upper.hasPrefix("A_FLAC"): return "FLAC"
        case upper.hasPrefix("A_OPUS"): return "Opus"
        case upper.hasPrefix("A_VORBIS"): return "Vorbis"
        case upper.hasPrefix("A_PCM"): return "PCM"
        case upper.hasPrefix("A_MPEG/L3"): return "MP3"
        case upper.hasPrefix("A_MPEG/L2"): return "MP2"
        case upper.hasPrefix("A_ALAC"): return "ALAC"
        default: return id
        }
    }

    static func formatNumber(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}

extension EmbeddedMetadata {
    /// "1:42:07" or "42:07".
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Rows for a File Details screen: container, title, duration, one row per track, chapter count, and
    /// a row per warning count. Empty values are left out.
    public var detailRows: [FileDetailRow] {
        var rows: [FileDetailRow] = []
        rows.append(FileDetailRow(label: "Container", value: docType == "webm" ? "WebM" : "Matroska"))
        if let title = info?.title, !title.isEmpty { rows.append(FileDetailRow(label: "Title", value: title)) }
        if let d = durationSeconds { rows.append(FileDetailRow(label: "Duration", value: EmbeddedMetadata.clock(d))) }
        let videos = videoTracks, audios = audioTracks, subs = subtitleTracks
        for (i, t) in videos.enumerated() {
            rows.append(FileDetailRow(label: videos.count > 1 ? "Video \(i + 1)" : "Video", value: t.summary))
        }
        for (i, t) in audios.enumerated() {
            rows.append(FileDetailRow(label: audios.count > 1 ? "Audio \(i + 1)" : "Audio", value: t.summary))
        }
        for (i, t) in subs.enumerated() {
            rows.append(FileDetailRow(label: subs.count > 1 ? "Subtitle \(i + 1)" : "Subtitle", value: t.summary))
        }
        if let edition = preferredEdition, !edition.flattenedChapters.isEmpty {
            let n = edition.flattenedChapters.count
            var value = n == 1 ? "1 chapter" : "\(n) chapters"
            if editions.count > 1 { value += " (\(editions.count) editions)" }
            rows.append(FileDetailRow(label: "Chapters", value: value))
        }
        if let muxer = info?.muxingApp, !muxer.isEmpty { rows.append(FileDetailRow(label: "Muxed with", value: muxer)) }
        if let writer = info?.writingApp, !writer.isEmpty, writer != info?.muxingApp {
            rows.append(FileDetailRow(label: "Written by", value: writer))
        }
        if !attachments.isEmpty {
            rows.append(FileDetailRow(label: "Attachments", value: attachments.map(\.fileName).joined(separator: ", ")))
        }
        if !warnings.isEmpty {
            rows.append(FileDetailRow(label: "Notes", value: warnings.count == 1 ? "1 problem while reading" : "\(warnings.count) problems while reading"))
        }
        return rows
    }
}
