import Foundation

/// The rules that turn "what the file contains" + "what the audio output can do" + "which player"
/// into the exact status text. Pure functions. The complete table is in docs/PLAYBACK_STATUS.md and
/// is generated from this code (see StatusTable.swift), so the two cannot drift apart.
///
/// Words used in the text:
/// - "passthrough": the app hands the stream to Apple's player unchanged. Apple TV does not tell us
///   whether it then sends a bitstream to the sink, so "passthrough" is only shown when the route
///   reports it takes Dolby bitstreams (or is unknown, with a note).
/// - "decoded": the audio was turned into PCM (by the app, by Apple TV, or by the fallback player).
public enum StatusRules {

    // MARK: Text pieces

    static func codecName(_ kind: AudioCodecKind) -> String {
        switch kind {
        case .ac3: return "Dolby Digital"
        case .eac3: return "Dolby Digital Plus"
        case .trueHD: return "Dolby TrueHD"
        case .dts: return "DTS"
        case .dtsHDMA: return "DTS-HD Master Audio"
        case .dtsX: return "DTS:X"
        case .aac: return "AAC"
        case .flac: return "FLAC"
        case .pcm: return "PCM"
        case .opus: return "Opus"
        case .dtsHDHRA: return "DTS-HD High Resolution"
        case .vorbis: return "Vorbis"
        }
    }

    /// "96 kHz", "88.2 kHz".
    static func rateText(_ hz: Int) -> String {
        hz % 1000 == 0 ? "\(hz / 1000) kHz" : String(format: "%.1f kHz", Double(hz) / 1000)
    }

    /// Above 48 kHz the platform documents no output rate (docs/QUALITY_CEILINGS.md, Audio): said, not guessed.
    static func highRateClause(_ t: AudioTrackContent) -> String? {
        guard let r = t.sampleRate, r > 48000 else { return nil }
        return "the system does not report whether this output receives the full \(rateText(r))"
    }

    /// What the file holds, e.g. "Dolby TrueHD with Atmos 7.1 (with Dolby Digital core)".
    public static func audioContains(_ t: AudioTrackContent) -> String {
        var s = codecName(t.kind)
        if t.hasAtmos && (t.kind == .eac3 || t.kind == .trueHD) { s += " with Atmos" }
        s += " " + StatusText.layout(t.channels)
        if t.kind == .trueHD && t.hasAC3Core { s += " (with Dolby Digital core)" }
        return s
    }

    /// "a", "a, and b", "a, b and c" appended to a main clause; always ends with one full stop.
    static func sentence(_ main: String, _ extras: [String] = []) -> String {
        switch extras.count {
        case 0: return main + "."
        case 1: return main + ", and " + extras[0] + "."
        default:
            return main + ", " + extras.dropLast().joined(separator: ", ") + " and " + extras[extras.count - 1] + "."
        }
    }

    static let unknownChannelsClause = "the number of channels this output supports is unknown"

    private static func decodedText(_ channels: Int, source: Int, by: String?) -> String {
        var s = StatusText.layout(channels) + " PCM (decoded"
        if let by = by { s += " by " + by }
        if channels < source { s += ", downmixed from " + StatusText.layout(source) }
        return s + ")"
    }

    // MARK: Main entry point

    public static func audio(_ track: AudioTrackContent, route: AudioRoute, engine: PlaybackEngine) -> AudioStatus {
        let contains = audioContains(track)
        let src = track.channels
        let routeMax = route.maxChannels

        // ----- Fallback player: everything is decoded to PCM, never passthrough. (UNVERIFIED assumption)
        if engine == .fallback {
            let out = min(src, 8, routeMax ?? 8)
            var extras: [String] = []
            if routeMax == nil && track.kind != .pcm { extras.append(unknownChannelsClause) }
            let objects = track.hasAtmos && (track.kind == .eac3 || track.kind == .trueHD)
            let dtsX = track.kind == .dtsX
            var note: String?
            switch track.kind {
            case .ac3, .eac3, .trueHD, .dts, .dtsHDMA, .dtsX, .dtsHDHRA:
                let main = "The fallback player decodes all audio to PCM, so \(passthroughWord(track.kind)) is unavailable"
                if objects { extras.insert("the Atmos objects are not played", at: 0) }
                if dtsX { extras.insert("the DTS:X objects are not rendered", at: 0) }
                note = sentence(main, extras)
            case .aac, .flac, .opus, .vorbis, .pcm:
                if !extras.isEmpty { note = sentence("The fallback player decodes all audio to PCM", extras) }
            }
            let out8 = decodedText(out, source: src, by: nil)
            return AudioStatus(contains: contains, output: track.kind == .pcm && out == src ? StatusText.layout(out) + " PCM" : out8,
                               note: note, path: track.kind == .pcm ? .pcm : .decodedByFallback, outputChannels: out)
        }

        // ----- Primary player
        switch track.kind {
        case .ac3, .eac3:
            return dolbyBitstream(track, route: route, contains: contains)
        case .trueHD:
            return trueHD(track, route: route, contains: contains)
        case .dts, .dtsHDMA, .dtsX, .dtsHDHRA:
            let out = min(src, 8, routeMax ?? 8)
            var extras: [String] = []
            // The decoder plays the DTS:X 7.1 bed (the encoder folds the height channels into it; docs/AUDIO_PIPELINE.md).
            if track.kind == .dtsX { extras.append("the DTS:X objects are not rendered, only the \(StatusText.layout(src)) bed plays") }
            if routeMax == nil { extras.append(unknownChannelsClause) }
            if let r = highRateClause(track) { extras.append(r) }
            return AudioStatus(contains: contains, output: decodedText(out, source: src, by: nil),
                               note: sentence("Apple's player cannot pass DTS audio, so it is decoded to PCM", extras),
                               path: .decodedByApp, outputChannels: out)
        case .aac:
            let out = src
            return AudioStatus(contains: contains, output: "AAC \(StatusText.layout(out)) (passthrough)",
                               note: nil, path: .passthrough, outputChannels: out)
        case .pcm:
            let out = min(src, 8, routeMax ?? 8)
            let text = out < src ? decodedText(out, source: src, by: nil) : StatusText.layout(out) + " PCM"
            return AudioStatus(contains: contains, output: text,
                               note: routeMax == nil && src > 2 ? sentence("The number of channels this output supports is unknown") : nil,
                               path: .pcm, outputChannels: out)
        case .flac, .opus, .vorbis:
            let out = min(src, 8, routeMax ?? 8)
            var clauses: [String] = []
            if routeMax == nil && src > 2 { clauses.append(unknownChannelsClause) }
            if let r = highRateClause(track) { clauses.append(r) }
            var note: String? = nil
            if let first = clauses.first {
                note = sentence(first.prefix(1).uppercased() + first.dropFirst(), Array(clauses.dropFirst()))
            }
            return AudioStatus(contains: contains, output: decodedText(out, source: src, by: nil),
                               note: note, path: .decodedByApp, outputChannels: out)
        }
    }

    private static func passthroughWord(_ kind: AudioCodecKind) -> String {
        switch kind {
        case .ac3, .eac3, .trueHD: return "Dolby passthrough"
        default: return "DTS passthrough"
        }
    }

    // MARK: Dolby Digital / Digital Plus

    private static func dolbyBitstream(_ t: AudioTrackContent, route: AudioRoute, contains: String) -> AudioStatus {
        let name = codecName(t.kind)
        let atmosFile = t.kind == .eac3 && t.hasAtmos
        let layout = StatusText.layout(t.channels)

        // Output cannot take a Dolby bitstream: Apple TV decodes it.
        if route.passesDolbyBitstream == .no {
            let out = min(t.channels, 8, route.maxChannels ?? 2)
            var extras: [String] = []
            if atmosFile { extras.append("the Atmos objects are not played") }
            return AudioStatus(contains: contains, output: decodedText(out, source: t.channels, by: "Apple TV"),
                               note: sentence("This audio output cannot take \(name), so Apple TV decodes it to PCM", extras),
                               path: .decodedBySystem, outputChannels: out)
        }

        if atmosFile {
            if route.atmos == .yes {
                return AudioStatus(contains: contains, output: "Dolby Atmos (passthrough)", note: nil, path: .passthrough, outputChannels: nil)
            }
            let note: String
            if route.atmos == .no {
                note = "This audio output does not support Dolby Atmos, so only the channel bed plays."
            } else {
                note = "Apple TV does not report whether Dolby Atmos is active on this output."
            }
            return AudioStatus(contains: contains, output: "\(name) \(layout) (passthrough)", note: note, path: .passthrough, outputChannels: t.channels)
        }

        var note: String?
        if route.passesDolbyBitstream == .unknown {
            note = "Apple TV does not report whether this output takes \(name), and decodes it if it does not."
        }
        return AudioStatus(contains: contains, output: "\(name) \(layout) (passthrough)", note: note, path: .passthrough, outputChannels: t.channels)
    }

    // MARK: Dolby TrueHD

    private static func trueHD(_ t: AudioTrackContent, route: AudioRoute, contains: String) -> AudioStatus {
        let atmos = t.hasAtmos
        // The full (lossless) decode is the default; the Dolby Digital core plays only with the compatibility setting.
        if t.hasAC3Core && t.usesCompatibilityCore {
            let coreChannels = min(t.channels, 6)
            var extras: [String] = []
            if atmos { extras.append("the Atmos objects are not played") }
            if route.passesDolbyBitstream == .no {
                let out = min(coreChannels, route.maxChannels ?? 2)
                return AudioStatus(contains: contains,
                                   output: decodedText(out, source: coreChannels, by: "Apple TV").replacingOccurrences(of: "PCM (decoded", with: "PCM (Dolby Digital core, decoded"),
                                   note: sentence("Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and this output cannot take Dolby Digital so Apple TV decodes it to PCM", extras),
                                   path: .decodedBySystem, outputChannels: out)
            }
            if route.passesDolbyBitstream == .unknown {
                extras.append("Apple TV does not report whether this output takes Dolby Digital")
            }
            return AudioStatus(contains: contains,
                               output: "Dolby Digital \(StatusText.layout(coreChannels)) (TrueHD core, passthrough)",
                               note: sentence("Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used", extras),
                               path: .ac3CorePassthrough, outputChannels: coreChannels)
        }
        let out = min(t.channels, 8, route.maxChannels ?? 8)
        var extras: [String] = []
        // Atmos in TrueHD cannot reach the output: the decoder plays the channel presentation (the bed) only.
        if atmos { extras.append("the Atmos objects are not played, only the \(StatusText.layout(t.channels)) bed") }
        if route.maxChannels == nil { extras.append(unknownChannelsClause) }
        if let r = highRateClause(t) { extras.append(r) }
        return AudioStatus(contains: contains, output: decodedText(out, source: t.channels, by: nil),
                           note: sentence("Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM", extras),
                           path: .decodedByApp, outputChannels: out)
    }
}
