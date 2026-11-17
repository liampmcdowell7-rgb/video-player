import Foundation
import LibraryIndex
import PlaybackStatus

/// The real names of the formats a file contains, for the detail page's version rows (docs/NAMES.md: always the real
/// format name, never "HDR" or "surround" when the file says more). These describe what the FILE contains, as far as the
/// library index knows it (file-name tags and the probe); they say nothing about how it plays, which is the playback
/// status text's job. Unknown values pass through unchanged rather than being guessed.
public enum FormatNames {
    /// "HEVC", "H.264", "AV1", "VP9", ... from the index's codec text ("hevc", "h264", "x265", "AV1", ...).
    public static func videoCodec(_ raw: String) -> String {
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "hevc", "h265", "x265", "hvc1", "hev1": return "HEVC"
        case "h264", "avc", "avc1", "x264": return "H.264"
        case "av1", "av01": return "AV1"
        case "vp9", "vp09": return "VP9"
        case "vp8": return "VP8"
        case "mpeg2", "mpeg2video", "mp2v": return "MPEG-2"
        case "mpeg4", "mp4v": return "MPEG-4 Part 2"
        case "vc1", "wvc1": return "VC-1"
        case "xvid": return "Xvid"
        case "divx": return "DivX"
        default: return raw
        }
    }

    /// "Dolby Vision Profile 8 / HDR10", "HDR10+ / HDR10", "HLG", or nil for SDR / nothing known. Dolby Vision comes
    /// first, then the layers a display without it gets. The index keeps the profile number only (8, not 8.1), so the
    /// sub-profile is not shown rather than guessed.
    public static func hdr(_ formats: Set<LibraryIndex.HDRFormat>, dolbyVisionProfile: Int?) -> String? {
        var parts: [String] = []
        if formats.contains(.dolbyVision) {
            parts.append(dolbyVisionProfile.map { "Dolby Vision Profile \($0)" } ?? "Dolby Vision")
        }
        if formats.contains(.hdr10Plus) { parts.append("HDR10+") }
        if formats.contains(.hdr10) { parts.append("HDR10") }
        if formats.contains(.hlg) { parts.append("HLG") }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    /// "Dolby TrueHD with Dolby Atmos 7.1", "DTS-HD Master Audio 5.1", "Dolby Digital Plus 5.1", "AAC Stereo", or nil
    /// when nothing is known. `codec` is the index's text: a file-name tag ("TrueHD", "DD+", "DTS-HD", "Atmos") or a probe
    /// name ("eac3", "dts-hd ma", "truehd"). A bare "Atmos" tag means the codec is unknown, so only "Dolby Atmos" is said.
    public static func audio(codec: String?, channels: Int?, atmos: Bool) -> String? {
        let layout = channels.flatMap { $0 > 0 ? StatusText.layout($0) : nil }
        var name: String?
        if let codec, !codec.trimmingCharacters(in: .whitespaces).isEmpty {
            name = audioCodec(codec)
        }
        let atmosOnly = name == "Dolby Atmos"
        if atmos && !atmosOnly {
            switch name {
            case "Dolby TrueHD", "Dolby Digital Plus": name = "\(name!) with Dolby Atmos"
            case nil: name = "Dolby Atmos"
            default: break   // Atmos only travels in TrueHD or Dolby Digital Plus; any other pairing is not claimed
            }
        }
        switch (name, layout) {
        case let (n?, l?): return "\(n) \(l)"
        case let (n?, nil): return n
        case let (nil, l?): return l
        default: return nil
        }
    }

    /// One audio codec's real name. Unknown text passes through unchanged.
    public static func audioCodec(_ raw: String) -> String {
        // "DD+" (the file-name tag) loses its "+" in the key below, so it is matched first.
        if raw.trimmingCharacters(in: .whitespaces).lowercased() == "dd+" { return "Dolby Digital Plus" }
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        switch key {
        case "atmos": return "Dolby Atmos"
        case "truehd", "dolbytruehd", "mlp": return key == "mlp" ? "MLP" : "Dolby TrueHD"
        case "dd", "ac3", "dolbydigital": return "Dolby Digital"
        case "ddp", "eac3", "ec3", "dolbydigitalplus": return "Dolby Digital Plus"
        case "dtshdma", "dtshdmasteraudio", "dtsma": return "DTS-HD Master Audio"
        case "dtshdhra", "dtshdhighresolution", "dtshdhr": return "DTS-HD High Resolution Audio"
        case "dtshd": return "DTS-HD"
        case "dtsx": return "DTS:X"
        case "dts", "dca", "dtses": return key == "dtses" ? "DTS-ES" : "DTS"
        case "aac", "aaclc", "mp4a", "heaac": return key == "heaac" ? "HE-AAC" : "AAC"
        case "flac": return "FLAC"
        case "opus": return "Opus"
        case "vorbis": return "Vorbis"
        case "alac": return "ALAC"
        case "mp3": return "MP3"
        case "pcm", "lpcm", "pcms16le", "pcms24le", "pcms32le", "pcmbluray": return "PCM"
        default: return raw
        }
    }
}
