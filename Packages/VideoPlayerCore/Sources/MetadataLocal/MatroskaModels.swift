import Foundation

// What the header of a Matroska/WebM file says. Everything here comes from the file's own
// header elements; nothing is guessed. Where the container cannot tell (for example whether an
// E-AC-3 track carries Dolby Atmos) the model says `unknown` instead of guessing.

public enum MatroskaTrackType: Int, Codable, Sendable {
    case video = 1, audio = 2, complex = 3, logo = 0x10, subtitle = 0x11, buttons = 0x12, control = 0x20, unknown = 0
}

public enum HDRTransfer: String, Codable, Sendable {
    /// SMPTE ST 2084 (transfer characteristics 16): HDR10 or HDR10+ or Dolby Vision base; the header cannot tell which.
    case pq
    /// ARIB STD-B67 (18).
    case hlg
    case sdr
    /// No colour information in the header.
    case unknown
}

public struct MasteringDisplay: Equatable, Codable, Sendable {
    public var redX, redY, greenX, greenY, blueX, blueY, whiteX, whiteY: Double?
    /// cd/m².
    public var luminanceMax: Double?
    public var luminanceMin: Double?
    public init() {}
}

public struct ColourInfo: Equatable, Codable, Sendable {
    public var matrixCoefficients: Int?
    public var transferCharacteristics: Int?
    public var primaries: Int?
    /// 0 unspecified, 1 broadcast (limited), 2 full, 3 defined by matrix/transfer.
    public var range: Int?
    public var bitsPerChannel: Int?
    public var maxCLL: Int?
    public var maxFALL: Int?
    public var mastering: MasteringDisplay?
    public init() {}

    public var transfer: HDRTransfer {
        switch transferCharacteristics {
        case 16?: return .pq
        case 18?: return .hlg
        case nil: return .unknown
        default: return .sdr
        }
    }
}

/// The Dolby Vision decoder configuration record (`dvcC` or `dvvC`), as stored in a BlockAdditionMapping.
public struct DolbyVisionConfig: Equatable, Codable, Sendable {
    public var versionMajor: Int
    public var versionMinor: Int
    public var profile: Int
    public var level: Int
    public var rpuPresent: Bool
    public var elPresent: Bool
    public var blPresent: Bool
    /// dv_bl_signal_compatibility_id: 0 none, 1 HDR10, 2 SDR, 4 HLG, 6 HDR10 (v2)...
    public var baseLayerCompatibilityID: Int
    /// "dvcC" or "dvvC".
    public var boxType: String

    public init(versionMajor: Int, versionMinor: Int, profile: Int, level: Int, rpuPresent: Bool,
                elPresent: Bool, blPresent: Bool, baseLayerCompatibilityID: Int, boxType: String) {
        self.versionMajor = versionMajor
        self.versionMinor = versionMinor
        self.profile = profile
        self.level = level
        self.rpuPresent = rpuPresent
        self.elPresent = elPresent
        self.blPresent = blPresent
        self.baseLayerCompatibilityID = baseLayerCompatibilityID
        self.boxType = boxType
    }

    /// Parses the 5 meaningful bytes of a DOVIDecoderConfigurationRecord.
    public init?(record: [UInt8], boxType: String) {
        guard record.count >= 5 else { return nil }
        let profile = Int(record[2] >> 1)
        let level = (Int(record[2] & 1) << 5) | Int(record[3] >> 3)
        self.init(
            versionMajor: Int(record[0]), versionMinor: Int(record[1]), profile: profile, level: level,
            rpuPresent: record[3] & 0b100 != 0, elPresent: record[3] & 0b010 != 0, blPresent: record[3] & 0b001 != 0,
            baseLayerCompatibilityID: Int(record[4] >> 4), boxType: boxType)
    }

    /// "5", "7.6" style label: profile plus compatibility id, as people write "profile 8.1".
    public var label: String {
        switch profile {
        case 8: return "8.\(baseLayerCompatibilityID)"
        default: return "\(profile)"
        }
    }
}

public enum AudioCodecKind: String, Codable, Sendable {
    case ac3, eac3, truehd, dts, aac, flac, opus, vorbis, pcm, mp3, alac, mlp, other
}

/// Whether the container says the track carries Dolby Atmos. Matroska has no flag for it.
public enum AtmosEvidence: String, Codable, Sendable {
    /// The header cannot say. (Almost always the case.)
    case unknown
    /// Only the track name mentions Atmos. A hint, not proof.
    case nameSuggests
}

public struct MatroskaTrack: Equatable, Codable, Sendable {
    public var number: Int
    public var uid: UInt64?
    public var type: MatroskaTrackType
    public var codecID: String
    public var codecName: String?
    public var codecPrivate: Data?
    public var name: String?
    /// ISO 639-2 code from `Language` (default "eng" when the file omits it, as the spec says).
    public var language: String
    public var languageBCP47: String?
    public var isEnabled: Bool
    public var isDefault: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    public var isVisualImpaired: Bool
    public var isTextDescriptions: Bool
    public var isOriginalLanguage: Bool
    public var isCommentary: Bool
    /// Nanoseconds per frame.
    public var defaultDurationNanos: UInt64?
    /// True when the track uses ContentEncodings (compression or encryption), so sizes and codec data may be transformed.
    public var hasContentEncoding: Bool

    // Video
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var displayWidth: Int?
    public var displayHeight: Int?
    public var isInterlaced: Bool?
    public var colour: ColourInfo?
    public var dolbyVision: DolbyVisionConfig?

    // Audio
    public var samplingFrequency: Double?
    public var channels: Int?
    public var bitDepth: Int?

    public init(number: Int, type: MatroskaTrackType, codecID: String) {
        self.number = number
        self.type = type
        self.codecID = codecID
        self.language = "eng"
        self.isEnabled = true
        self.isDefault = true
        self.isForced = false
        self.isHearingImpaired = false
        self.isVisualImpaired = false
        self.isTextDescriptions = false
        self.isOriginalLanguage = false
        self.isCommentary = false
        self.hasContentEncoding = false
    }

    /// Frames per second from `DefaultDuration`, rounded to 3 decimals (23.976, 25, 29.97 ...).
    public var frameRate: Double? {
        guard let d = defaultDurationNanos, d > 0 else { return nil }
        return (1_000_000_000.0 / Double(d) * 1000).rounded() / 1000
    }

    public var audioCodec: AudioCodecKind? {
        guard type == .audio else { return nil }
        let id = codecID.uppercased()
        if id.hasPrefix("A_AC3") { return .ac3 }
        if id.hasPrefix("A_EAC3") { return .eac3 }
        if id.hasPrefix("A_TRUEHD") { return .truehd }
        if id.hasPrefix("A_MLP") { return .mlp }
        if id.hasPrefix("A_DTS") { return .dts }
        if id.hasPrefix("A_AAC") { return .aac }
        if id.hasPrefix("A_FLAC") { return .flac }
        if id.hasPrefix("A_OPUS") { return .opus }
        if id.hasPrefix("A_VORBIS") { return .vorbis }
        if id.hasPrefix("A_PCM") { return .pcm }
        if id.hasPrefix("A_MPEG/L3") || id.hasPrefix("A_MPEG/L2") || id.hasPrefix("A_MPEG/L1") { return .mp3 }
        if id.hasPrefix("A_ALAC") { return .alac }
        return .other
    }

    /// Only a hint from the track name; the container has no Atmos flag. Never claim more than this.
    public var atmos: AtmosEvidence {
        guard let kind = audioCodec, kind == .eac3 || kind == .truehd else { return .unknown }
        if let n = name?.lowercased(), n.contains("atmos") { return .nameSuggests }
        return .unknown
    }

    public var videoCodecLabel: String? {
        guard type == .video else { return nil }
        let id = codecID.uppercased()
        if id == "V_MPEGH/ISO/HEVC" { return "HEVC" }
        if id == "V_MPEG4/ISO/AVC" { return "H.264" }
        if id == "V_AV1" { return "AV1" }
        if id == "V_VP9" { return "VP9" }
        if id == "V_VP8" { return "VP8" }
        if id.hasPrefix("V_MPEG2") { return "MPEG-2" }
        if id == "V_MS/VFW/FOURCC" { return "VfW (legacy)" }
        if id.hasPrefix("V_MPEG4/ISO/ASP") || id.hasPrefix("V_MPEG4/ISO/SP") { return "MPEG-4 Part 2" }
        return codecID
    }

    public var subtitleFormat: SubtitleFormat? {
        guard type == .subtitle else { return nil }
        let id = codecID.uppercased()
        if id == "S_TEXT/UTF8" || id == "S_TEXT/ASCII" { return .srt }
        if id == "S_TEXT/ASS" { return .ass }
        if id == "S_TEXT/SSA" { return .ssa }
        if id == "S_TEXT/WEBVTT" { return .webvtt }
        if id == "S_HDMV/PGS" { return .pgs }
        if id == "S_VOBSUB" { return .vobsub }
        if id == "S_HDMV/TEXTST" { return .hdmvText }
        if id.hasPrefix("S_DVBSUB") { return .dvb }
        return .other
    }
}

public enum SubtitleFormat: String, Codable, Sendable {
    case srt, ass, ssa, webvtt, pgs, vobsub, hdmvText, dvb, other

    /// Bitmap formats the app must draw itself.
    public var isImageBased: Bool { self == .pgs || self == .vobsub || self == .dvb }
}

public struct ChapterDisplay: Equatable, Codable, Sendable {
    public var title: String
    /// `ChapLanguage` values (ISO 639-2). The spec allows several per display; "eng" when absent.
    public var languages: [String]
    public var languagesBCP47: [String]
    public var countries: [String]
}

public struct MatroskaChapter: Equatable, Codable, Sendable {
    public var uid: UInt64?
    public var stringUID: String?
    public var startNanos: Int64
    public var endNanos: Int64?
    public var isHidden: Bool
    public var isEnabled: Bool
    /// Every language of the title, in file order.
    public var displays: [ChapterDisplay]
    public var children: [MatroskaChapter]

    public var startSeconds: Double { Double(startNanos) / 1e9 }
    public var endSeconds: Double? { endNanos.map { Double($0) / 1e9 } }

    /// Title for a language (ISO 639-2 or BCP 47 prefix), else the first title, else nil.
    public func title(language: String? = nil) -> String? {
        if let language {
            let wanted = language.lowercased()
            if let hit = displays.first(where: { d in
                d.languages.contains { $0.lowercased() == wanted } || d.languagesBCP47.contains { $0.lowercased().hasPrefix(wanted) }
            }) { return hit.title }
        }
        return displays.first?.title
    }
}

public struct MatroskaEdition: Equatable, Codable, Sendable {
    public var uid: UInt64?
    public var isHidden: Bool
    public var isDefault: Bool
    public var isOrdered: Bool
    public var chapters: [MatroskaChapter]

    /// The chapters with children flattened into start order.
    public var flattenedChapters: [MatroskaChapter] {
        func walk(_ list: [MatroskaChapter]) -> [MatroskaChapter] {
            list.flatMap { [$0] + walk($0.children) }
        }
        return walk(chapters).sorted { $0.startNanos < $1.startNanos }
    }
}

public struct MatroskaSimpleTag: Equatable, Codable, Sendable {
    public var name: String
    public var language: String?
    public var languageBCP47: String?
    public var isDefault: Bool
    public var string: String?
    /// Binary tag values are not kept; only their size.
    public var binarySize: Int?
    public var children: [MatroskaSimpleTag]
}

public struct MatroskaTag: Equatable, Codable, Sendable {
    /// TargetTypeValue: 50 is "movie/episode" level, 70 collection, 30 track, ... nil = 50 by spec default.
    public var targetTypeValue: Int?
    public var targetType: String?
    public var trackUIDs: [UInt64]
    public var editionUIDs: [UInt64]
    public var chapterUIDs: [UInt64]
    public var attachmentUIDs: [UInt64]
    public var simpleTags: [MatroskaSimpleTag]

    /// True when the tag applies to the whole file (no UID targets).
    public var isGlobal: Bool {
        trackUIDs.isEmpty && editionUIDs.isEmpty && chapterUIDs.isEmpty && attachmentUIDs.isEmpty
    }
}

public struct MatroskaAttachment: Equatable, Codable, Sendable {
    public var fileName: String
    public var mediaType: String?
    public var description: String?
    public var uid: UInt64?
    /// Size of the file data in bytes when the header says it; the data itself is never read.
    public var dataSize: Int64?
}

public struct MatroskaInfo: Equatable, Codable, Sendable {
    public var timecodeScale: UInt64
    public var durationSeconds: Double?
    public var title: String?
    public var muxingApp: String?
    public var writingApp: String?
    public var segmentUID: Data?
    public var dateUTC: Date?
}

public struct EmbeddedMetadata: Equatable, Codable, Sendable {
    /// "matroska" or "webm" (the EBML DocType).
    public var docType: String
    public var info: MatroskaInfo?
    public var tracks: [MatroskaTrack]
    public var editions: [MatroskaEdition]
    public var tags: [MatroskaTag]
    public var attachments: [MatroskaAttachment]
    /// Anything that was missing, cut off or damaged. Empty for a clean file.
    public var warnings: [String]
    /// File offsets of the parts that were found (for a later seek or re-read).
    public var layout: MatroskaLayout

    public var durationSeconds: Double? { info?.durationSeconds }
    public var videoTracks: [MatroskaTrack] { tracks.filter { $0.type == .video } }
    public var audioTracks: [MatroskaTrack] { tracks.filter { $0.type == .audio } }
    public var subtitleTracks: [MatroskaTrack] { tracks.filter { $0.type == .subtitle } }

    /// The edition a player should use: default and visible first, then the first visible, then the first.
    public var preferredEdition: MatroskaEdition? {
        editions.first { $0.isDefault && !$0.isHidden } ?? editions.first { !$0.isHidden } ?? editions.first
    }

    /// Global tags flattened to "NAME" -> value (the first value wins, names uppercased).
    public var globalTagValues: [String: String] {
        var out: [String: String] = [:]
        func walk(_ tags: [MatroskaSimpleTag]) {
            for t in tags {
                if let s = t.string, out[t.name.uppercased()] == nil { out[t.name.uppercased()] = s }
                walk(t.children)
            }
        }
        for tag in tags where tag.isGlobal { walk(tag.simpleTags) }
        return out
    }
}
