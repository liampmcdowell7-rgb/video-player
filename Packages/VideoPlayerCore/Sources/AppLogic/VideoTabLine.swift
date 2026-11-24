import Foundation

/// R454 (owner's photo of the reference player's info panel, 23 Nov 2026; PROVISIONAL): the player's own "Video" tab is ONE
/// plain-text line of the file's facts, in this order: runtime, year, file size, codec with resolution, audio format with
/// channels, bitrate, frame rate, genre, content rating. A part with no data is left out; the line is never cut (the view
/// shrinks it to fit). Numbers use the system formatters (`ByteCountFormatter` in decimal units, `NumberFormatter`).
public struct VideoTabFacts: Equatable, Sendable {
    public var runtimeSeconds: Double?
    public var year: Int?
    public var fileSizeBytes: Int64?
    /// "HEVC", "H.264" (`FormatNames.videoCodec`).
    public var videoCodec: String?
    /// "4K", "1080p" (`MediaInfo.resolutionName`).
    public var resolution: String?
    /// "Dolby Digital Plus 5.1" (`FormatNames.audio`).
    public var audioFormat: String?
    /// Bits per second as READ from the file or the player's track; nil when only an estimate is possible.
    public var bitrateBitsPerSecond: Double?
    public var frameRate: Double?
    public var genre: String?
    public var contentRating: String?

    public init(runtimeSeconds: Double? = nil, year: Int? = nil, fileSizeBytes: Int64? = nil, videoCodec: String? = nil,
                resolution: String? = nil, audioFormat: String? = nil, bitrateBitsPerSecond: Double? = nil, frameRate: Double? = nil,
                genre: String? = nil, contentRating: String? = nil) {
        self.runtimeSeconds = runtimeSeconds
        self.year = year
        self.fileSizeBytes = fileSizeBytes
        self.videoCodec = videoCodec
        self.resolution = resolution
        self.audioFormat = audioFormat
        self.bitrateBitsPerSecond = bitrateBitsPerSecond
        self.frameRate = frameRate
        self.genre = genre
        self.contentRating = contentRating
    }
}

public enum VideoTabLine {
    /// The bitrate to show: the one read, else the ESTIMATE file size over runtime (the whole file, so audio and
    /// subtitles are included); nil when neither is known.
    public static func bitrate(_ facts: VideoTabFacts) -> Double? {
        if let read = facts.bitrateBitsPerSecond, read > 0 { return read }
        guard let size = facts.fileSizeBytes, size > 0, let seconds = facts.runtimeSeconds, seconds > 0 else { return nil }
        return Double(size) * 8 / seconds
    }

    /// The parts, in order; each only with data.
    public static func parts(_ facts: VideoTabFacts, locale: Locale = .current) -> [String] {
        var out: [String] = []
        if let s = facts.runtimeSeconds, s > 0 { out.append(DisplayText.runtime(s)) }
        if let year = facts.year, (1800...2200).contains(year) { out.append(String(year)) }
        if let size = facts.fileSizeBytes, size > 0 { out.append(fileSize(size)) }
        let video = [facts.videoCodec, facts.resolution].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !video.isEmpty { out.append(video) }
        if let audio = facts.audioFormat, !audio.isEmpty { out.append(audio) }
        if let bits = bitrate(facts) { out.append(megabitsPerSecond(bits, locale: locale)) }
        if let fps = facts.frameRate, fps > 0, fps.isFinite { out.append(framesPerSecond(fps, locale: locale)) }
        if let genre = facts.genre, !genre.isEmpty { out.append(genre) }
        if let rating = facts.contentRating, !rating.isEmpty { out.append(rating) }
        return out
    }

    public static func line(_ facts: VideoTabFacts, locale: Locale = .current) -> String {
        parts(facts, locale: locale).joined(separator: " · ")
    }

    /// Decimal units (1 GB = 1,000,000,000 bytes), as the system's own storage readouts.
    public static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }

    /// "18.4 Mbps": one decimal (the system's number format style, in the user's region).
    public static func megabitsPerSecond(_ bitsPerSecond: Double, locale: Locale = .current) -> String {
        (bitsPerSecond / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(locale)) + " Mbps"
    }

    /// "23.976 fps", "24 fps": up to three decimals, none when whole.
    public static func framesPerSecond(_ fps: Double, locale: Locale = .current) -> String {
        fps.formatted(.number.precision(.fractionLength(0...3)).locale(locale)) + " fps"
    }
}
