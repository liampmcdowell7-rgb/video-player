import Foundation

// Playback Stats overlay (FEATURE_BACKLOG Tier A item 11).
// Every stat is shown at once, no collapsed sections, most important first. Missing values show "—".
// The file path is NOT in the overlay (it is long and private on a shared screen); File Details has it.

public enum DecodePath: String, Sendable, CaseIterable {
    /// Remuxed to fragmented MP4 and played by Apple's player.
    case remux
    /// Played by Apple's player without remuxing (MP4 / MOV / HLS).
    case direct
    /// Played by the fallback player.
    case fallback

    public var text: String {
        switch self {
        case .remux: return "Remux (Apple player)"
        case .direct: return "Direct (Apple player)"
        case .fallback: return "Fallback player"
        }
    }
}

/// One moment of playback numbers. Everything optional: the app fills what it knows.
public struct PlaybackStatsSnapshot: Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var videoCodec: String?
    public var videoProfile: String?
    public var videoLevel: String?
    public var hdr: HDRFormat?
    /// Bits per second over the last few seconds.
    public var liveBitrate: Double?
    /// Bits per second over the whole file so far.
    public var averageBitrate: Double?
    public var audio: AudioTrackContent?
    /// Bits per second the network is delivering.
    public var throughput: Double?
    public var bufferSeconds: Double?
    public var droppedFrames: Int?
    public var totalFrames: Int?
    public var decodePath: DecodePath?
    public var container: String?
    public var pixelFormat: String?
    public var colorPrimaries: String?
    public var transferFunction: String?
    public var engine: PlaybackEngine

    public init(width: Int? = nil, height: Int? = nil, frameRate: Double? = nil, videoCodec: String? = nil,
                videoProfile: String? = nil, videoLevel: String? = nil, hdr: HDRFormat? = nil,
                liveBitrate: Double? = nil, averageBitrate: Double? = nil, audio: AudioTrackContent? = nil,
                throughput: Double? = nil, bufferSeconds: Double? = nil, droppedFrames: Int? = nil, totalFrames: Int? = nil,
                decodePath: DecodePath? = nil, container: String? = nil, pixelFormat: String? = nil,
                colorPrimaries: String? = nil, transferFunction: String? = nil, engine: PlaybackEngine = .primary) {
        self.width = width; self.height = height; self.frameRate = frameRate; self.videoCodec = videoCodec
        self.videoProfile = videoProfile; self.videoLevel = videoLevel; self.hdr = hdr
        self.liveBitrate = liveBitrate; self.averageBitrate = averageBitrate; self.audio = audio
        self.throughput = throughput; self.bufferSeconds = bufferSeconds; self.droppedFrames = droppedFrames
        self.totalFrames = totalFrames; self.decodePath = decodePath; self.container = container
        self.pixelFormat = pixelFormat; self.colorPrimaries = colorPrimaries; self.transferFunction = transferFunction
        self.engine = engine
    }
}

public enum StatTone: String, Sendable {
    case normal
    /// Something the viewer may need to look at (slow network, low buffer, dropped frames).
    case warning
    /// The value is not known.
    case unavailable
}

public struct StatRow: Equatable, Sendable {
    public var label: String
    public var value: String
    public var tone: StatTone
}

public enum StatsOverlay {
    public static let missing = "—"

    /// Thresholds for the warning tone. PROVISIONAL: the user has not given numbers.
    public static let lowBufferSeconds = 5.0
    public static let droppedFrameWarningPercent = 0.5

    // MARK: Formatting (no NumberFormatter, so output never depends on the device language)

    /// `x` with exactly `places` decimals, "." as separator, no grouping.
    static func fixed(_ x: Double, places: Int) -> String {
        let scale = Int(pow(10.0, Double(places)))
        let scaled = Int((abs(x) * Double(scale)).rounded())
        let whole = scaled / scale
        let frac = scaled % scale
        let sign = x < 0 && scaled != 0 ? "-" : ""
        if places == 0 { return sign + String(whole) }
        var f = String(frac)
        while f.count < places { f = "0" + f }
        return sign + String(whole) + "." + f
    }

    /// Up to 3 decimals, trailing zeros removed: 23.976, 24, 29.97, 59.94, 119.88.
    public static func frameRateText(_ fps: Double) -> String {
        var s = fixed(fps, places: 3)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + " fps"
    }

    public static func bitrateText(_ bps: Double) -> String {
        if bps >= 1_000_000 { return fixed(bps / 1_000_000, places: 1) + " Mbps" }
        if bps >= 1_000 { return fixed(bps / 1_000, places: 0) + " kbps" }
        return fixed(bps, places: 0) + " bps"
    }

    public static func resolutionText(width: Int, height: Int) -> String { "\(width) × \(height)" }

    public static func bufferText(_ seconds: Double) -> String { fixed(seconds, places: 1) + " s" }

    public static func droppedText(dropped: Int, total: Int?) -> String {
        guard let total = total, total > 0 else { return "\(dropped) frames" }
        let pct = Double(dropped) / Double(total) * 100
        return "\(dropped) of \(total) frames (\(fixed(pct, places: 2))%)"
    }

    private static func ok(_ x: Double?) -> Double? {
        guard let x = x, x.isFinite, x >= 0 else { return nil }
        return x
    }

    // MARK: Rows

    /// All rows, in the fixed order. The count never changes: unknown values show "—".
    public static func rows(_ s: PlaybackStatsSnapshot, status: PlaybackStatus? = nil) -> [StatRow] {
        func row(_ label: String, _ value: String?, _ tone: StatTone = .normal) -> StatRow {
            if let v = value, !v.isEmpty { return StatRow(label: label, value: v, tone: tone) }
            return StatRow(label: label, value: missing, tone: .unavailable)
        }

        var resolution: String?
        if let w = s.width, let h = s.height, w > 0, h > 0 { resolution = resolutionText(width: w, height: h) }

        var profileLevel: String?
        switch (s.videoProfile, s.videoLevel) {
        case let (p?, l?): profileLevel = "\(p), level \(l)"
        case let (p?, nil): profileLevel = p
        case let (nil, l?): profileLevel = "Level \(l)"
        default: profileLevel = nil
        }

        let live = ok(s.liveBitrate), avg = ok(s.averageBitrate), thr = ok(s.throughput), buf = ok(s.bufferSeconds)

        var throughputTone = StatTone.normal
        if let t = thr, let l = live, t < l { throughputTone = .warning }
        var bufferTone = StatTone.normal
        if let b = buf, b < lowBufferSeconds { bufferTone = .warning }

        var dropped: String?
        var droppedTone = StatTone.normal
        if let d = s.droppedFrames, d >= 0 {
            dropped = droppedText(dropped: d, total: s.totalFrames)
            if let t = s.totalFrames, t > 0, Double(d) / Double(t) * 100 >= droppedFrameWarningPercent { droppedTone = .warning }
        }

        let audioOutput = status?.audio.output
        let audioChannels = s.audio.map { StatusText.layout($0.channels) }
        let audioCodec = s.audio.map { StatusRules.audioContains($0) }

        return [
            row("Resolution", resolution),
            row("Frame rate", ok(s.frameRate).flatMap { $0 > 0 ? frameRateText($0) : nil }),
            row("Video codec", s.videoCodec),
            row("Profile and level", profileLevel),
            row("HDR format", s.hdr?.containsText),
            row("Bitrate (live)", live.map(bitrateText)),
            row("Bitrate (average)", avg.map(bitrateText)),
            row("Audio codec", audioCodec),
            row("Audio channels", audioChannels),
            row("Audio output", audioOutput),
            row("Network throughput", thr.map(bitrateText), throughputTone),
            row("Buffer health", buf.map(bufferText), bufferTone),
            row("Dropped frames", dropped, droppedTone),
            row("Decode path", s.decodePath?.text),
            row("Container", s.container),
            row("Pixel format", s.pixelFormat),
            row("Color primaries", s.colorPrimaries),
            row("Transfer function", s.transferFunction),
            row("Player", s.engine.label)
        ]
    }

    /// The honest status lines shown above the table: audio line, video line, notes, fallback notice.
    public static func statusLines(_ status: PlaybackStatus) -> [String] {
        var lines = ["Audio: " + status.audio.output]
        if let n = status.audio.note { lines.append(n) }
        lines.append("Video: " + status.video.output)
        if let n = status.video.note { lines.append(n) }
        if let n = status.engineNotice { lines.append(n) }
        return lines
    }
}
