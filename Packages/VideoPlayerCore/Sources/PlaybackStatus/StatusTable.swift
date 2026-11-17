import Foundation

extension StatusRules {
    /// The whole status for one playback: audio line, video line and the fallback notice.
    public static func status(track: AudioTrackContent, route: AudioRoute, format: HDRFormat, display: DisplayState,
                              engine: PlaybackEngine, profile7: Profile7Conversion) -> PlaybackStatus {
        PlaybackStatus(audio: audio(track, route: route, engine: engine),
                       video: video(format, display: display, engine: engine, profile7: profile7),
                       engineNotice: engine == .fallback ? StatusText.fallbackNotice : nil)
    }
}

/// Builds `PlaybackStatus` inputs from what tvOS reports. The mapping from AVAudioSession to these
/// values happens in the app target; this function only holds the judgement calls so they are tested.
public enum RouteClassifier {
    /// - Parameters:
    ///   - maxChannels: `AVAudioSession.maximumOutputNumberOfChannels` (nil if unavailable).
    ///   - atmosRenderingReported: true / false when the system says whether Atmos rendering is active, nil when it does not say.
    public static func classify(kind: AudioRouteKind, maxChannels: Int?, atmosRenderingReported: Bool?) -> AudioRoute {
        let atmos: Tri = atmosRenderingReported.map { $0 ? .yes : .no } ?? .unknown
        switch kind {
        case .hdmi:
            // A TV on ARC often reports 2 channels yet passes Dolby Digital, so 2 channels is "unknown", not "no".
            let bitstream: Tri = (maxChannels ?? 0) > 2 ? .yes : .unknown
            return AudioRoute(kind: kind, maxChannels: maxChannels, passesDolbyBitstream: bitstream,
                              atmos: bitstream == .yes ? atmos : (atmos == .yes ? .yes : .unknown))
        case .bluetooth, .airPlay, .builtIn:
            return AudioRoute(kind: kind, maxChannels: maxChannels ?? 2, passesDolbyBitstream: .no, atmos: atmos == .yes ? .yes : .no)
        case .unknown:
            return AudioRoute(kind: kind, maxChannels: maxChannels, passesDolbyBitstream: .unknown, atmos: atmos)
        }
    }
}

// MARK: - The complete table (docs/PLAYBACK_STATUS.md is generated from this)

public enum StatusTable {
    public struct AudioRoutePreset: Sendable {
        public let name: String
        public let route: AudioRoute
    }

    public static let audioRoutes: [AudioRoutePreset] = [
        .init(name: "HDMI 7.1, Atmos active", route: AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .yes)),
        .init(name: "HDMI 7.1, Atmos not reported", route: AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .unknown)),
        .init(name: "HDMI 7.1, no Atmos", route: AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .no)),
        .init(name: "HDMI 5.1", route: AudioRoute(kind: .hdmi, maxChannels: 6, passesDolbyBitstream: .yes, atmos: .no)),
        .init(name: "HDMI stereo (TV or ARC)", route: AudioRoute(kind: .hdmi, maxChannels: 2, passesDolbyBitstream: .unknown, atmos: .unknown)),
        .init(name: "Bluetooth or AirPlay stereo", route: AudioRoute(kind: .bluetooth, maxChannels: 2, passesDolbyBitstream: .no, atmos: .no)),
        .init(name: "Unknown output", route: .unknown)
    ]

    public static let audioSources: [AudioTrackContent] = [
        AudioTrackContent(kind: .ac3, channels: 6),
        AudioTrackContent(kind: .eac3, channels: 6),
        AudioTrackContent(kind: .eac3, channels: 8, hasAtmos: true),
        AudioTrackContent(kind: .trueHD, channels: 8, hasAC3Core: true),
        AudioTrackContent(kind: .trueHD, channels: 8),
        AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true, hasAC3Core: true),
        AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true),
        AudioTrackContent(kind: .dts, channels: 6),
        AudioTrackContent(kind: .dtsHDMA, channels: 8),
        AudioTrackContent(kind: .dtsX, channels: 8),
        AudioTrackContent(kind: .aac, channels: 2),
        AudioTrackContent(kind: .flac, channels: 2),
        AudioTrackContent(kind: .pcm, channels: 2),
        AudioTrackContent(kind: .opus, channels: 2)
    ]

    /// Sources added with the audio decoding work (docs/AUDIO_PIPELINE.md). Their rows come after every row of
    /// `audioSources` (both players), so the earlier row IDs stay the same.
    public static let addedAudioSources: [AudioTrackContent] = [
        AudioTrackContent(kind: .trueHD, channels: 8, hasAC3Core: true, usesCompatibilityCore: true),
        AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true, hasAC3Core: true, usesCompatibilityCore: true),
        AudioTrackContent(kind: .dtsHDHRA, channels: 6),
        AudioTrackContent(kind: .dtsHDMA, channels: 8, sampleRate: 96000),
        AudioTrackContent(kind: .vorbis, channels: 6)
    ]

    public struct AudioRow: Sendable {
        public let id: String
        public let track: AudioTrackContent
        public let routeName: String
        public let route: AudioRoute
        public let engine: PlaybackEngine
        public let status: AudioStatus
    }

    public static func audioRows() -> [AudioRow] {
        var rows: [AudioRow] = []
        for sources in [audioSources, addedAudioSources] {
            for engine in PlaybackEngine.allCases {
                for track in sources {
                    for preset in audioRoutes {
                        let id = String(format: "A%03d", rows.count + 1)
                        rows.append(AudioRow(id: id, track: track, routeName: preset.name, route: preset.route, engine: engine,
                                             status: StatusRules.audio(track, route: preset.route, engine: engine)))
                    }
                }
            }
        }
        return rows
    }

    public struct DisplayPreset: Sendable {
        public let name: String
        public let state: DisplayState
    }

    public static let displays: [DisplayPreset] = [
        .init(name: "Dolby Vision, HDR10 and HLG display", state: DisplayState(availableHDR: [.dolbyVision, .hdr10, .hlg])),
        .init(name: "HDR10 and HLG display", state: DisplayState(availableHDR: [.hdr10, .hlg])),
        .init(name: "HLG-only display", state: DisplayState(availableHDR: [.hlg])),
        .init(name: "SDR display", state: DisplayState(availableHDR: [])),
        .init(name: "Display abilities unknown", state: .unknown),
        .init(name: "HDR10 display, Match Dynamic Range off", state: DisplayState(availableHDR: [.hdr10, .hlg], matchDynamicRange: .no)),
        .init(name: "Dolby Vision display, currently in HDR10 mode", state: DisplayState(availableHDR: [.dolbyVision, .hdr10, .hlg], activeMode: .hdr10)),
        .init(name: "Display abilities unknown, currently in HDR10 mode", state: DisplayState(availableHDR: nil, activeMode: .hdr10))
    ]

    public struct VideoRow: Sendable {
        public let id: String
        public let format: HDRFormat
        public let profile7: Profile7Conversion
        public let displayName: String
        public let display: DisplayState
        public let engine: PlaybackEngine
        public let status: VideoStatus
    }

    public static func profile7Text(_ c: Profile7Conversion) -> String {
        switch c {
        case .available: return "conversion available"
        case .notAvailableOnDevice: return "conversion not available on this device"
        case .failedForThisFile: return "conversion failed for this file"
        }
    }

    public static func videoRows() -> [VideoRow] {
        var rows: [VideoRow] = []
        for engine in PlaybackEngine.allCases {
            for format in HDRFormat.all {
                var conversions: [Profile7Conversion] = [.available]
                if case .dolbyVision(let p) = format, p.isProfile7, engine == .primary {
                    conversions = [.available, .notAvailableOnDevice, .failedForThisFile]
                }
                for conv in conversions {
                    for d in displays {
                        let id = String(format: "V%03d", rows.count + 1)
                        rows.append(VideoRow(id: id, format: format, profile7: conv, displayName: d.name, display: d.state, engine: engine,
                                             status: StatusRules.video(format, display: d.state, engine: engine, profile7: conv)))
                    }
                }
            }
        }
        // HDR10+ by Apple TV model (3rd generation and later send the metadata; earlier models do not). Appended after
        // the rows above so their IDs stay the same; the rows above use a model that is not known.
        for (sends, label) in [(Tri.yes, "Apple TV that sends HDR10+"), (Tri.no, "Apple TV without HDR10+")] {
            for d in displays {
                var state = d.state
                state.sendsHDR10Plus = sends
                let id = String(format: "V%03d", rows.count + 1)
                rows.append(VideoRow(id: id, format: .hdr10Plus, profile7: .available, displayName: d.name + ", " + label, display: state,
                                     engine: .primary, status: StatusRules.video(.hdr10Plus, display: state, engine: .primary, profile7: .available)))
            }
        }
        return rows
    }

    // MARK: Markdown

    static func cell(_ s: String?) -> String { (s ?? "—").replacingOccurrences(of: "|", with: "/") }

    public static func markdown() -> String {
        var out = ""
        out += "### Audio rules\n\n"
        out += "| ID | File audio | Audio output | Player | Audio line | Why (shown when present) |\n"
        out += "|---|---|---|---|---|---|\n"
        for r in audioRows() {
            out += "| \(r.id) | \(cell(r.status.contains)) | \(cell(r.routeName)) | \(r.engine.label) | \(cell(r.status.output)) | \(cell(r.status.note)) |\n"
        }
        out += "\n### Video and HDR rules\n\n"
        out += "| ID | File video | Display | Player | Video line | Why (shown when present) |\n"
        out += "|---|---|---|---|---|---|\n"
        for r in videoRows() {
            var file = r.status.contains
            if case .dolbyVision(let p) = r.format, p.isProfile7, r.engine == .primary { file += ", " + profile7Text(r.profile7) }
            out += "| \(r.id) | \(cell(file)) | \(cell(r.displayName)) | \(r.engine.label) | \(cell(r.status.output)) | \(cell(r.status.note)) |\n"
        }
        out += "\nWhen the fallback player is used, every screen also shows: \(StatusText.fallbackNotice)\n"
        return out
    }
}
