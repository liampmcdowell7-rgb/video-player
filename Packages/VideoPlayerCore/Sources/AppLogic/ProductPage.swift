import Foundation
import LibraryIndex

/// R350 (owner's device test of build 5, 21 Nov 2026, item D; PROVISIONAL): the movie and show pages follow the product
/// pages of Apple's TV app (docs/DESIGN_SYSTEM.md "Reference screens"): full-bleed artwork behind everything, the title
/// logo or name, ONE metadata line (year, runtime, rating) followed by format badges, the description, Play (or Resume) and
/// More; for a show the season tabs and episodes; then Cast & Crew; then "Information" at the bottom with every technical
/// row of the file, none collapsed, most important first (`MediaInfo.rows`).
public enum ProductPage {
    /// The section names, as the TV app names them.
    public static let castHeading = "Cast & Crew"
    public static let informationHeading = "Information"

    /// The format badges of a title, in the owner's order: resolution, HDR format, Dolby Atmos, then the channel layout of
    /// the best audio ("5.1", "7.1"). `cardBadges` are the card's (`CardBuilder.badges`: 4K, the HDR format, Dolby Atmos);
    /// stereo and mono get no badge (nothing special to show, as the TV app shows none).
    public static func formatBadges(cardBadges: [String], maxChannels: Int?) -> [String] {
        var badges: [String] = cardBadges
        if let layout = channelLayout(maxChannels) { badges.append(layout) }
        return badges
    }

    /// R369 (owner's scan of ec27d52, 21 Nov 2026, finding 4): one format badge and the Information row that says the same
    /// thing in full. Every badge has its row, so a badge dropped from the line (rule S1) is never lost.
    public struct Badge: Equatable, Sendable {
        public let text: String
        /// The label of the Information row (`MediaInfo.rows`) that holds this fact: "Resolution", "HDR", "Audio", "Video",
        /// "Container". An "Audio" badge's row may be "Audio 1", "Audio 2", ... when the header was read.
        public let row: String
        public init(text: String, row: String) { self.text = text; self.row = row }
    }

    /// R369: every technology badge of a file, text only, most important first: resolution ("4K", "1080p", "720p"), the HDR
    /// format ("Dolby Vision", "HDR10+", "HDR10", "HLG"), the audio format ("Dolby Atmos", "TrueHD", "DTS-HD MA", "DTS:X",
    /// "Dolby Digital Plus", "Dolby Digital", "DTS"), the channel layout ("7.1", "5.1"), the video codec ("HEVC", "H.264",
    /// "AV1") and the container ("MKV", "MP4", "AVI", ...). The line drops them from the end (`ProductMetadataLine`), so the
    /// container goes first and the resolution last. Nothing for what is not known, stereo, mono, SD or an "Other" container.
    /// `maxChannels` is the item's best audio when the file does not say.
    public static func badges(technical t: FileTechnicalInfo, maxChannels: Int?) -> [Badge] {
        var out: [Badge] = []
        if let name = MediaInfo.resolutionName(height: t.height), name == "4K" || name == "1080p" || name == "720p" {
            out.append(Badge(text: name, row: "Resolution"))
        }
        if let hdr = hdrBadge(t.hdrFormats) { out.append(Badge(text: hdr, row: "HDR")) }
        if let audio = audioBadge(codec: t.audioCodec, atmos: t.hasAtmos) { out.append(Badge(text: audio, row: "Audio")) }
        if let layout = channelLayout(t.audioChannels ?? maxChannels) { out.append(Badge(text: layout, row: "Audio")) }
        if let codec = t.videoCodec.map(FormatNames.videoCodec), ["HEVC", "H.264", "AV1"].contains(codec) {
            out.append(Badge(text: codec, row: "Video"))
        }
        if let container = t.container, container != .other { out.append(Badge(text: MediaInfo.containerName(container), row: "Container")) }
        return out
    }

    /// The one HDR badge: Dolby Vision before the base layers.
    static func hdrBadge(_ formats: Set<HDRFormat>) -> String? {
        if formats.contains(.dolbyVision) { return "Dolby Vision" }
        if formats.contains(.hdr10Plus) { return "HDR10+" }
        if formats.contains(.hdr10) { return "HDR10" }
        if formats.contains(.hlg) { return "HLG" }
        return nil
    }

    /// The audio format badge, in the short form the owner's scan names ("TrueHD", "DTS-HD MA"); Dolby Atmos replaces the
    /// codec it travels in. AAC, PCM and the other plain formats get none.
    static func audioBadge(codec: String?, atmos: Bool) -> String? {
        if atmos { return "Dolby Atmos" }
        guard let codec, !codec.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch FormatNames.audioCodec(codec) {
        case "Dolby Atmos": return "Dolby Atmos"
        case "Dolby TrueHD": return "TrueHD"
        case "DTS-HD Master Audio": return "DTS-HD MA"
        case "DTS:X": return "DTS:X"
        case "Dolby Digital Plus": return "Dolby Digital Plus"
        case "Dolby Digital": return "Dolby Digital"
        case "DTS", "DTS-ES", "DTS-HD", "DTS-HD High Resolution Audio": return "DTS"
        default: return nil
        }
    }

    /// The show page's metadata line: the number of seasons ("1 Season", "3 Seasons"); the library index holds no year,
    /// runtime or rating for a show. Empty for none.
    public static func showFacts(seasonCount: Int) -> String {
        if seasonCount <= 0 { return "" }
        return seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons"
    }

    /// "7.1" for eight channels or more, "5.1" for six or seven, nil below.
    public static func channelLayout(_ channels: Int?) -> String? {
        guard let channels else { return nil }
        if channels >= 8 { return "7.1" }
        if channels >= 6 { return "5.1" }
        return nil
    }
}
