import Foundation

// HLS playlists for the loopback server: one master playlist, one video media playlist and one media playlist per
// audio rendition, and one WebVTT playlist per text subtitle track (SubtitleRendition.swift). All are VOD playlists; video and audio
// segments are fMP4 (EXT-X-MAP). Picture subtitles (PGS) are not in the playlists.

public enum VideoRange: String, Sendable { case sdr = "SDR", pq = "PQ", hlg = "HLG" }

public struct PlaylistVideo: Sendable {
    public var codecs: String
    public var supplementalCodecs: String?
    public var range: VideoRange
    public var width: Int
    public var height: Int
    public var frameRate: Double?
    public var averageBandwidth: Int
    public var bandwidth: Int
}

public struct PlaylistAudio: Sendable {
    public var trackNumber: Int
    public var name: String
    public var language: String
    public var codecs: String
    public var channels: Int
    public var isDefault: Bool
    public var uri: String
    /// E-AC-3 with Dolby Atmos (Joint Object Coding): CHANNELS becomes "<n>/JOC" (HLS authoring spec for Atmos).
    public var isAtmos = false
}

/// A WebVTT subtitle rendition (text subtitles only; picture subtitles are never listed here, see SubtitleRendition.swift).
public struct PlaylistSubtitle: Sendable {
    public var trackNumber: Int
    public var name: String
    public var language: String
    public var isDefault: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    public var uri: String
    public init(trackNumber: Int, name: String, language: String, isDefault: Bool, isForced: Bool, isHearingImpaired: Bool, uri: String) {
        self.trackNumber = trackNumber; self.name = name; self.language = language; self.isDefault = isDefault
        self.isForced = isForced; self.isHearingImpaired = isHearingImpaired; self.uri = uri
    }
}

public enum PlaylistWriter {
    public static func master(video: PlaylistVideo, audio: [PlaylistAudio], subtitles: [PlaylistSubtitle] = [], videoURI: String = "video.m3u8") -> String {
        var s = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n"
        let group = "audio"
        for a in audio {
            var line = "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"\(group)\",NAME=\"\(escape(a.name))\""
            if let l = bcp47(a.language) { line += ",LANGUAGE=\"\(l)\"" }
            let channels = a.isAtmos ? "\(a.channels)/JOC" : "\(a.channels)"
            line += ",DEFAULT=\(a.isDefault ? "YES" : "NO"),AUTOSELECT=YES,CHANNELS=\"\(channels)\",URI=\"\(a.uri)\""
            s += line + "\n"
        }
        // Subtitles (PROVISIONAL, D1): one WebVTT rendition per text track. A forced track is DEFAULT=YES,AUTOSELECT=YES,FORCED=YES
        // (the player shows it by itself); every other track is DEFAULT=NO, AUTOSELECT=YES, so the app's own track rules (and
        // the user) decide whether subtitles are on. Alternative: DEFAULT=YES for the file's default flag (turns subtitles on by
        // default for everyone who plays the file).
        let subGroup = "subs"
        for t in subtitles {
            var line = "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"\(subGroup)\",NAME=\"\(escape(t.name))\""
            if let l = bcp47(t.language) { line += ",LANGUAGE=\"\(l)\"" }
            line += ",DEFAULT=\(t.isForced ? "YES" : "NO"),AUTOSELECT=YES"
            if t.isForced { line += ",FORCED=YES" }
            if t.isHearingImpaired {
                line += ",CHARACTERISTICS=\"public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound\""
            }
            line += ",URI=\"\(t.uri)\""
            s += line + "\n"
        }
        var codecs = video.codecs
        for a in audio { codecs += "," + a.codecs }
        if !subtitles.isEmpty { codecs += ",wvtt" }
        // One CODECS list for the variant has to name each distinct audio codec once.
        var seen = Set<String>(), list: [String] = []
        for c in codecs.split(separator: ",").map(String.init) where seen.insert(c).inserted { list.append(c) }
        var inf = "#EXT-X-STREAM-INF:BANDWIDTH=\(video.bandwidth),AVERAGE-BANDWIDTH=\(video.averageBandwidth),CODECS=\"\(list.joined(separator: ","))\""
        if let sup = video.supplementalCodecs { inf += ",SUPPLEMENTAL-CODECS=\"\(sup)\"" }
        inf += ",RESOLUTION=\(video.width)x\(video.height)"
        if let f = video.frameRate { inf += ",FRAME-RATE=\(String(format: "%.3f", f))" }
        inf += ",VIDEO-RANGE=\(video.range.rawValue)"
        if !audio.isEmpty { inf += ",AUDIO=\"\(group)\"" }
        if !subtitles.isEmpty { inf += ",SUBTITLES=\"\(subGroup)\"" }
        s += inf + "\n\(videoURI)\n"
        return s
    }

    /// A media playlist. `segments` are (uri, seconds); `initURI` is the EXT-X-MAP.
    public static func media(initURI: String, segments: [(uri: String, seconds: Double)], targetDuration: Int) -> String {
        var s = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(targetDuration)\n#EXT-X-MEDIA-SEQUENCE:0\n"
        s += "#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-INDEPENDENT-SEGMENTS\n#EXT-X-MAP:URI=\"\(initURI)\"\n"
        for seg in segments { s += "#EXTINF:\(String(format: "%.5f", seg.seconds)),\n\(seg.uri)\n" }
        s += "#EXT-X-ENDLIST\n"
        return s
    }

    /// A WebVTT media playlist: the same segment times as the video playlist, no EXT-X-MAP (WebVTT segments have no init data).
    public static func subtitleMedia(segments: [(uri: String, seconds: Double)], targetDuration: Int) -> String {
        var s = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:\(targetDuration)\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:VOD\n"
        for seg in segments { s += "#EXTINF:\(String(format: "%.5f", seg.seconds)),\n\(seg.uri)\n" }
        s += "#EXT-X-ENDLIST\n"
        return s
    }

    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ") }

    /// HLS LANGUAGE wants an RFC 5646 tag; Matroska gives ISO 639-2. Common three-letter codes are mapped; "und" is omitted.
    static func bcp47(_ l: String) -> String? {
        let lower = l.lowercased()
        if lower.isEmpty || lower == "und" { return nil }
        let map = ["eng": "en", "fre": "fr", "fra": "fr", "ger": "de", "deu": "de", "spa": "es", "ita": "it", "jpn": "ja", "kor": "ko",
                   "chi": "zh", "zho": "zh", "por": "pt", "rus": "ru", "dut": "nl", "nld": "nl", "swe": "sv", "pol": "pl", "tur": "tr"]
        return map[lower] ?? lower
    }
}

// MARK: Extension points the app (or a later engine step) fills in

/// Decoded-audio path for codecs that AVPlayer cannot play (DTS, DTS-HD, TrueHD...). The implementation is the AudioDecode
/// target (`DecodedAudioTranscoder`, docs/AUDIO_PIPELINE.md). Contract: take the original frames of one segment, return frames of the target codec (FLAC) whose
/// total duration equals the input's, plus the config used for the init segment. Channel order must be the FLAC order.
public protocol AudioTranscoding: Sendable {
    /// Source Matroska codec IDs this transcoder accepts ("A_DTS", "A_DTS/EXPRESS", "A_TRUEHD"...).
    var supportedCodecIDs: Set<String> { get }
    /// The configuration (FLAC) for a track, derived from the track and its first frame.
    func outputConfig(for track: MKVTrack, firstFrame: [UInt8]) async throws -> AudioTrackConfig
    /// Transcodes the frames of one segment. Frames are in decode order and continuous with the previous segment of
    /// the same track only when the previous segment was transcoded just before (the session does not guarantee it:
    /// seeks restart the decoder, so implementations must handle a cold start and may emit priming samples).
    func transcode(frames: [MKVFrame], track: MKVTrack, config: AudioTrackConfig) async throws -> [MKVFrame]
    // Requirements added for the decoding transcoder (AudioDecode target). Each has a default in AudioTranscodeSupport.swift
    // that falls back to the three above, so a simple transcoder needs none of them.
    /// The configuration from several first frames (a TrueHD stream can only be decoded from its next major sync).
    func outputConfig(for track: MKVTrack, firstFrames: [MKVFrame]) async throws -> AudioTrackConfig
    /// One segment with its boundaries, the frames before it (decoder warm-up) and after it (the last output block).
    func transcode(_ input: AudioTranscodeInput, track: MKVTrack, config: AudioTrackConfig) async throws -> [MKVFrame]
    /// What the decoded track really is (format, channels, rate, depth, reductions).
    func sourceInfo(for track: MKVTrack) async -> TranscodedAudioSource?
    /// Running counters (concealed frames, layout and rate changes...).
    func diagnostics(for trackNumber: Int) async -> AudioTranscodeDiagnostics?
}

/// Dolby Vision profile 7 to 8.1 on the samples of the base layer (implemented by the DolbyVisionRPU target; see
/// docs/DOLBY_VISION.md). Every access unit is converted on its own (no state between samples), so seeking and read-ahead
/// in any order give the same bytes.
public protocol DolbyVisionConverting: Sendable {
    /// The profile 8.1 configuration record (`dvvC`) that replaces the file's profile 7 record.
    func outputRecord(for source: MKVDolbyVisionMapping) -> MKVDolbyVisionMapping
    /// Rewrites one length-prefixed HEVC access unit: drops the enhancement-layer NAL units, converts the RPU NAL unit.
    /// A sample without enhancement layer or RPU is returned unchanged.
    func convert(sample: [UInt8], lengthSize: Int) throws -> [UInt8]
    /// What the RPU of this access unit says (profile, FEL or MEL). nil when the sample has no readable RPU.
    func inspect(sample: [UInt8], lengthSize: Int) -> DolbyVisionSampleInfo?
}

/// The Dolby Vision facts of one access unit, read from its RPU.
public struct DolbyVisionSampleInfo: Equatable, Sendable {
    public enum EnhancementLayer: String, Sendable {
        /// Full enhancement layer: carries residual picture detail (12-bit reconstruction).
        case full = "FEL"
        /// Minimal enhancement layer: no picture detail, only the composer metadata.
        case minimal = "MEL"
    }
    /// Profile the RPU describes (5, 7, 8...).
    public var profile: Int
    /// Profile 7 only.
    public var enhancementLayer: EnhancementLayer?
    /// The access unit carries enhancement-layer NAL units (type 63 or nuh_layer_id > 0).
    public var hasEnhancementLayerNALs: Bool
    public init(profile: Int, enhancementLayer: EnhancementLayer?, hasEnhancementLayerNALs: Bool) {
        self.profile = profile; self.enhancementLayer = enhancementLayer; self.hasEnhancementLayerNALs = hasEnhancementLayerNALs
    }
}
