import Foundation
import LibraryIndex
import PlaybackStatus

/// R370 (owner's decision of 21 Nov 2026, replaces the badge part of R350 and R369): the format badges are an ORIGINAL set
/// the app draws, a small rounded badge with the format's name spelled out in the system font, one visual treatment per
/// group so they read as icons at a glance. No image of anyone's logo and no logo shapes or lettering: the names are plain
/// text (docs/NAMES.md). This is the model; App/Shared/ProductPageParts.swift draws it.
public enum FormatBadgeGroup: String, CaseIterable, Sendable {
    case resolution, hdr, audio, channels, videoCodec, container

    /// The Information row (`MediaInfo.rows`) that holds the same fact in full.
    public var informationRow: String {
        switch self {
        case .resolution: return "Resolution"
        case .hdr: return "HDR"
        case .audio, .channels: return "Audio"
        case .videoCodec: return "Video"
        case .container: return "Container"
        }
    }

    /// What VoiceOver says after the name ("4K, resolution").
    public var spokenName: String {
        switch self {
        case .resolution: return "resolution"
        case .hdr: return "high dynamic range"
        case .audio: return "audio format"
        case .channels: return "audio channels"
        case .videoCodec: return "video format"
        case .container: return "file format"
        }
    }
}

/// One badge: its group (the drawing) and its text (the format's name).
public struct FormatBadgeItem: Hashable, Sendable {
    public let group: FormatBadgeGroup
    public let text: String

    public init(_ group: FormatBadgeGroup, _ text: String) {
        self.group = group
        self.text = text
    }

    public var spokenLabel: String { "\(text), \(group.spokenName)" }
}

/// R370: every format the app detects maps to exactly one badge (or, for SDR and an unknown container, to none, as the
/// owner's list says). Test: FormatBadgesTests.
public enum FormatBadges {
    /// The groups on the metadata line of a movie or show page and on an episode row: "the most important few".
    public static let headlineGroups: [FormatBadgeGroup] = [.resolution, .hdr, .audio]

    public static func resolution(_ r: ResolutionClass) -> FormatBadgeItem {
        switch r {
        case .uhd4k: return FormatBadgeItem(.resolution, "4K")
        case .hd1080: return FormatBadgeItem(.resolution, "1080p")
        case .hd720: return FormatBadgeItem(.resolution, "720p")
        case .sd: return FormatBadgeItem(.resolution, "SD")
        }
    }

    /// One HDR format; SDR is shown as nothing.
    public static func hdr(_ f: LibraryIndex.HDRFormat) -> FormatBadgeItem? {
        switch f {
        case .sdr: return nil
        case .dolbyVision: return FormatBadgeItem(.hdr, "Dolby Vision")
        case .hdr10Plus: return FormatBadgeItem(.hdr, "HDR10+")
        case .hdr10: return FormatBadgeItem(.hdr, "HDR10")
        case .hlg: return FormatBadgeItem(.hdr, "HLG")
        }
    }

    /// The best HDR format of a file: Dolby Vision before the layers a display without it gets.
    public static func hdr(_ formats: Set<LibraryIndex.HDRFormat>) -> FormatBadgeItem? {
        for f in [LibraryIndex.HDRFormat.dolbyVision, .hdr10Plus, .hdr10, .hlg] where formats.contains(f) { return hdr(f) }
        return nil
    }

    /// The audio format. Dolby Atmos replaces the codec it travels in. Nil for no codec or a codec name the app does not
    /// know (`FormatNames.audioCodec` passes unknown text through; it is not guessed into a badge).
    public static func audio(codec: String?, atmos: Bool) -> FormatBadgeItem? {
        if atmos { return FormatBadgeItem(.audio, "Dolby Atmos") }
        guard let codec, !codec.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let text: String?
        switch FormatNames.audioCodec(codec) {
        case "Dolby Atmos": text = "Dolby Atmos"
        case "Dolby TrueHD": text = "Dolby TrueHD"
        case "MLP": text = "MLP"
        case "Dolby Digital Plus": text = "Dolby Digital Plus"
        case "Dolby Digital": text = "Dolby Digital"
        case "DTS:X": text = "DTS:X"
        case "DTS-HD Master Audio": text = "DTS-HD MA"
        case "DTS-HD High Resolution Audio": text = "DTS-HD HRA"
        case "DTS-HD": text = "DTS-HD"
        case "DTS", "DTS-ES": text = "DTS"
        case "AAC", "HE-AAC": text = "AAC"
        case "FLAC": text = "FLAC"
        case "PCM": text = "PCM"
        case "ALAC": text = "ALAC"
        case "Opus": text = "Opus"
        case "Vorbis": text = "Vorbis"
        case "MP3": text = "MP3"
        default: text = nil
        }
        return text.map { FormatBadgeItem(.audio, $0) }
    }

    /// The channel layout ("7.1", "5.1", "Stereo", "Mono", ...), the playback status text's names.
    public static func channels(_ n: Int?) -> FormatBadgeItem? {
        guard let n, n > 0 else { return nil }
        return FormatBadgeItem(.channels, StatusText.layout(n))
    }

    /// The video codec. Nil for a codec name the app does not know.
    public static func videoCodec(_ raw: String?) -> FormatBadgeItem? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let text: String?
        switch FormatNames.videoCodec(raw) {
        case "HEVC": text = "HEVC"
        case "H.264": text = "H.264"
        case "AV1": text = "AV1"
        case "VP9": text = "VP9"
        case "VP8": text = "VP8"
        case "MPEG-2": text = "MPEG-2"
        case "MPEG-4 Part 2": text = "MPEG-4"
        case "VC-1": text = "VC-1"
        case "Xvid": text = "Xvid"
        case "DivX": text = "DivX"
        default: text = nil
        }
        return text.map { FormatBadgeItem(.videoCodec, $0) }
    }

    /// The container. One index value holds MPEG transport streams of every extension; the file's own extension tells a
    /// Blu-ray stream ("M2TS", ".m2ts" or ".mts") from a broadcast one ("MPEG-TS").
    public static func container(_ c: ContainerFormat?, fileExtension: String? = nil) -> FormatBadgeItem? {
        guard let c else { return nil }
        switch c {
        case .mkv: return FormatBadgeItem(.container, "MKV")
        case .mp4: return FormatBadgeItem(.container, "MP4")
        case .m4v: return FormatBadgeItem(.container, "M4V")
        case .mov: return FormatBadgeItem(.container, "MOV")
        case .ts:
            let ext = (fileExtension ?? "").lowercased()
            return FormatBadgeItem(.container, ext == "m2ts" || ext == "mts" ? "M2TS" : "MPEG-TS")
        case .avi: return FormatBadgeItem(.container, "AVI")
        case .wmv: return FormatBadgeItem(.container, "WMV")
        case .webm: return FormatBadgeItem(.container, "WebM")
        case .other: return nil
        }
    }

    /// The full set for one file, most important first (the Information section): resolution, HDR, audio format, channels,
    /// video codec, container. `maxChannels` is the item's best audio when the file does not say.
    public static func all(technical t: FileTechnicalInfo, fileExtension: String? = nil, maxChannels: Int? = nil) -> [FormatBadgeItem] {
        var out: [FormatBadgeItem] = []
        if let r = ResolutionClass.classify(width: t.width, height: t.height) { out.append(resolution(r)) }
        if let h = hdr(t.hdrFormats) { out.append(h) }
        if let a = audio(codec: t.audioCodec, atmos: t.hasAtmos) { out.append(a) }
        if let c = channels(t.audioChannels ?? maxChannels) { out.append(c) }
        if let v = videoCodec(t.videoCodec) { out.append(v) }
        if let k = container(t.container, fileExtension: fileExtension) { out.append(k) }
        return out
    }

    /// The headline badges: resolution, HDR and audio format only.
    public static func headline(_ all: [FormatBadgeItem]) -> [FormatBadgeItem] {
        all.filter { headlineGroups.contains($0.group) }
    }

    /// What the library item itself knows (its best file): resolution, HDR, Dolby Atmos. For cards and episode rows,
    /// where no single file has been chosen.
    public static func item(_ item: LibraryItem) -> [FormatBadgeItem] {
        var out: [FormatBadgeItem] = []
        if let r = item.maxResolution { out.append(resolution(r)) }
        if let h = hdr(item.hdrFormats) { out.append(h) }
        if item.hasAtmos { out.append(FormatBadgeItem(.audio, "Dolby Atmos")) }
        return out
    }

    /// The group of a badge text the cards carry (`ItemCard.badges`); nil for a text that is no format badge.
    public static func parse(cardText text: String) -> FormatBadgeItem? {
        switch text {
        case "4K", "1080p", "720p", "SD": return FormatBadgeItem(.resolution, text)
        case "Dolby Vision", "HDR10+", "HDR10", "HLG": return FormatBadgeItem(.hdr, text)
        case "Dolby Atmos": return FormatBadgeItem(.audio, text)
        default: return nil
        }
    }
}

public extension ItemCard {
    /// R370: the card's badges as drawn badges (4K, the HDR format, Dolby Atmos).
    var formatBadges: [FormatBadgeItem] { badges.compactMap(FormatBadges.parse(cardText:)) }
}
