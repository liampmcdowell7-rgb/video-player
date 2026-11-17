import Foundation
import RemuxEngine
import PlaybackStatus

// What the converting player knows about a file, turned into what the rest of the app needs:
//  - the inputs of the honest audio / picture status rules (docs/PLAYBACK_STATUS.md),
//  - the notices about tracks that were left out (and why),
//  - the picture subtitle choices.
// Foundation only; tested on Linux. The app reads `RemuxMediaInfo` from the session and calls these.

/// One thing the person should be told about this file. `text` is the whole message.
public struct PlaybackNotice: Equatable, Sendable {
    public enum Severity: Int, Sendable, Comparable {
        /// Shown in the Playback Stats overlay only.
        case info = 0
        /// A feature is limited (shown in the overlay, listed first).
        case warning = 1
        /// Something the person would otherwise be confused about (for example no sound): also shown once before playback.
        case important = 2
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    public var severity: Severity
    public var text: String
    public var advice: String?
    /// A short heading when the notice is shown on its own (the alert before playback).
    public var title: String?

    public init(severity: Severity, text: String, advice: String? = nil, title: String? = nil) {
        self.severity = severity
        self.text = text
        self.advice = advice
        self.title = title
    }

    public var fullText: String { advice.map { text + " " + $0 } ?? text }
}

public enum RemuxPlaybackModel {
    // MARK: Status inputs

    /// The audio track the status rules describe. `selectedTrack` is the Matroska track number of the rendition playing
    /// (nil: the default rendition). nil when the file has no playable audio.
    public static func audioContent(_ info: RemuxMediaInfo, selectedTrack: Int? = nil) -> AudioTrackContent? {
        guard let rendition = rendition(info, selectedTrack: selectedTrack) else { return nil }
        let id = rendition.codecID.uppercased()
        let kind: AudioCodecKind
        // A track the app decodes is described by what the FILE holds (read from the stream by the decoder); the status
        // rules then say it was decoded by the app.
        if let src = rendition.transcodedSource {
            var hasAtmos = false
            switch src.format {
            case .dts, .dtsES, .dts9624, .dtsExpress: kind = .dts
            case .dtsHDHighResolution: kind = .dtsHDHRA
            case .dtsHDMasterAudio: kind = .dtsHDMA
            case .dtsX: kind = .dtsX
            case .trueHD, .mlp: kind = .trueHD
            case .trueHDAtmos: kind = .trueHD; hasAtmos = true
            case .opus: kind = .opus
            case .vorbis: kind = .vorbis
            }
            return AudioTrackContent(kind: kind, channels: src.sourceChannels, hasAtmos: hasAtmos,
                                     hasAC3Core: src.hasEmbeddedCore, usesCompatibilityCore: src.usesEmbeddedCore,
                                     sampleRate: src.outputSampleRate)
        }
        if rendition.transcoded, id.hasPrefix("A_DTS") { kind = id.contains("MA") || id.contains("LOSSLESS") ? .dtsHDMA : .dts }
        else if rendition.transcoded, id == "A_TRUEHD" { kind = .trueHD }
        else if rendition.transcoded, id == "A_OPUS" { kind = .opus }
        else if rendition.transcoded { kind = .flac }
        else if id == "A_AC3" { kind = .ac3 }
        else if id == "A_EAC3" { kind = .eac3 }
        else if id.hasPrefix("A_AAC") { kind = .aac }
        else if id == "A_FLAC" { kind = .flac }
        else { return nil }
        return AudioTrackContent(kind: kind, channels: rendition.channels, hasAtmos: kind == .eac3 && rendition.isAtmos)
    }

    public static func rendition(_ info: RemuxMediaInfo, selectedTrack: Int?) -> AudioRenditionInfo? {
        if let selectedTrack, let found = info.audio.first(where: { $0.trackNumber == selectedTrack }) { return found }
        return info.audio.first(where: { $0.isDefault }) ?? info.audio.first
    }

    /// What the picture in the file is, from the Dolby Vision record and the signalled range.
    /// PROVISIONAL: a Dolby Vision profile this app has no rule for (4, 9, 10) is described by its base layer.
    public static func hdrFormat(_ info: RemuxMediaInfo) -> HDRFormat {
        let base: HDRFormat
        switch info.videoRange {
        case .sdr: base = .sdr
        case .pq: base = .hdr10
        case .hlg: base = .hlg
        }
        guard let profile = info.dolbyVisionSourceProfile else {
            // HDR10+ is HDR10 (PQ) plus per-scene metadata in the video samples.
            return base == .hdr10 && info.hasHDR10PlusMetadata ? .hdr10Plus : base
        }
        switch profile {
        case 5: return .dolbyVision(.p5)
        case 7:
            // FEL or MEL comes from the RPU (the configuration record sets "enhancement layer present" for both).
            // PROVISIONAL: when the RPU could not be read the file is described as FEL, so the status never claims that
            // nothing was lost. Alternative: a separate "Profile 7" wording without FEL / MEL.
            return .dolbyVision(info.dolbyVisionEnhancementLayerType == .minimal ? .p7MEL : .p7FEL)
        case 8:
            switch info.dolbyVisionCompatibilityID ?? 0 {
            case 1: return .dolbyVision(.p8_1)
            case 2: return .dolbyVision(.p8_2)
            case 4: return .dolbyVision(.p8_4)
            default:
                // No usable compatibility id: the signalled range decides.
                switch info.videoRange {
                case .pq: return .dolbyVision(.p8_1)
                case .hlg: return .dolbyVision(.p8_4)
                case .sdr: return .dolbyVision(.p8_2)
                }
            }
        default: return base
        }
    }

    public static func profile7Conversion(_ info: RemuxMediaInfo) -> Profile7Conversion {
        if info.dolbyVisionConverted { return .available }
        return info.dolbyVisionConversionFailed ? .failedForThisFile : .notAvailableOnDevice
    }

    /// Stats for the overlay that the file itself answers (the system player adds buffer, bitrate and dropped frames).
    public static func snapshot(_ info: RemuxMediaInfo, selectedTrack: Int? = nil) -> PlaybackStatsSnapshot {
        var s = PlaybackStatsSnapshot()
        s.width = info.width
        s.height = info.height
        s.videoCodec = info.videoCodecString.hasPrefix("avc") ? "H.264" : "HEVC"
        s.hdr = hdrFormat(info)
        s.audio = audioContent(info, selectedTrack: selectedTrack)
        s.decodePath = .remux
        s.container = "MKV"
        s.engine = .primary
        return s
    }

    // MARK: Notices

    public static func notices(_ info: RemuxMediaInfo) -> [PlaybackNotice] {
        var out: [PlaybackNotice] = []

        out += audioNotices(info)

        if let source = info.dolbyVisionSourceProfile, source == 7, !info.dolbyVisionConverted {
            out.append(PlaybackNotice(severity: .warning,
                                      text: info.dolbyVisionConversionFailed
                                        ? "This file has Dolby Vision profile 7 that could not be converted, so the HDR10 base layer plays."
                                        : "This file has Dolby Vision profile 7. This version cannot convert it, so the HDR10 base layer plays."))
        }
        for skipped in info.skippedSubtitles {
            out.append(PlaybackNotice(severity: .info, text: "Subtitle track \(skipped.trackNumber) is not offered: \(skipped.reason)"))
        }
        if info.warnings.contains(where: { $0.hasPrefix("no Cues") }) {
            out.append(PlaybackNotice(severity: .info,
                                      text: "This file has no seek index, so it took longer to open and jumping to a point may be less exact."))
        }
        if info.isOverBudget {
            out.append(PlaybackNotice(severity: .warning,
                                      text: "This file has a very high bitrate. Playback may stutter and jumping to a point may be slow."))
        }
        return out.sorted { $0.severity > $1.severity }
    }

    /// Audio notices: a track that could not be decoded names the track that plays instead (never silence without a
    /// message), and each decoded track says what it became.
    public static func audioNotices(_ info: RemuxMediaInfo) -> [PlaybackNotice] {
        var out: [PlaybackNotice] = []
        if info.audio.isEmpty {
            if info.skippedAudio.isEmpty {
                out.append(PlaybackNotice(severity: .warning, text: "This file has no audio track."))
            } else {
                let names = unique(info.skippedAudio.map { audioCodecName($0.codecID) })
                out.append(PlaybackNotice(severity: .important,
                                          text: "None of the audio tracks in this file could be decoded (\(names.joined(separator: ", "))), so the video plays without sound.",
                                          advice: info.skippedAudio.first.map { "Reason: \($0.reason)" }, title: "Playing Without Sound"))
            }
            return out
        }
        var named: Set<Int> = []
        if let fb = info.audioFallback {
            named.insert(fb.unplayable.trackNumber)
            let lost = audioCodecName(fb.unplayable.codecID)
            let instead = fb.replacement.flatMap { n in audioContent(info, selectedTrack: n).map { StatusRules.audioContains($0) } }
                ?? fb.replacement.flatMap { n in info.audio.first { $0.trackNumber == n }.map { audioCodecName($0.codecID) } }
                ?? "another"
            out.append(PlaybackNotice(severity: .important,
                                      text: "The \(lost) track (track \(fb.unplayable.trackNumber)) could not be decoded, so the \(instead) track plays instead.",
                                      advice: "Reason: \(fb.unplayable.reason)", title: "Playing a Different Audio Track"))
        }
        for skipped in info.skippedAudio where !named.contains(skipped.trackNumber) {
            out.append(PlaybackNotice(severity: .warning,
                                      text: "Audio track \(skipped.trackNumber) (\(audioCodecName(skipped.codecID))) cannot be played: \(skipped.reason)"))
        }
        for r in info.audio {
            guard let src = r.transcodedSource else { continue }
            out.append(PlaybackNotice(severity: .info, text: "Audio track \(r.trackNumber): " + decodedDescription(src)))
            if !src.droppedChannels.isEmpty {
                out.append(PlaybackNotice(severity: .warning,
                                          text: "Audio track \(r.trackNumber): the channels \(src.droppedChannels.joined(separator: ", ")) have no place in the output layout and are not played."))
            }
        }
        return out
    }

    /// "DTS-HD Master Audio 7.1, decoded losslessly to FLAC (24-bit, 96 kHz)."
    public static func decodedDescription(_ src: TranscodedAudioSource) -> String {
        let name: String
        switch src.format {
        case .dts: name = "DTS"
        case .dtsES: name = "DTS-ES"
        case .dts9624: name = "DTS 96/24"
        case .dtsHDHighResolution: name = "DTS-HD High Resolution"
        case .dtsHDMasterAudio: name = "DTS-HD Master Audio"
        case .dtsX: name = "DTS:X"
        case .dtsExpress: name = "DTS Express"
        case .trueHD: name = "Dolby TrueHD"
        case .trueHDAtmos: name = "Dolby TrueHD with Atmos"
        case .mlp: name = "MLP"
        case .opus: name = "Opus"
        case .vorbis: name = "Vorbis"
        }
        let rate = src.outputSampleRate % 1000 == 0 ? "\(src.outputSampleRate / 1000) kHz"
            : String(format: "%.1f kHz", Double(src.outputSampleRate) / 1000)
        if src.usesEmbeddedCore {
            return "\(name) \(StatusText.layout(src.sourceChannels)): the embedded Dolby Digital core plays (compatibility setting)."
        }
        var s = "\(name) \(StatusText.layout(src.sourceChannels)), decoded "
        s += src.isLossless ? "losslessly to FLAC" : "to FLAC (the source is lossy; nothing further is lost)"
        s += " (\(src.outputBits)-bit, \(rate))"
        var extras: [String] = []
        if src.format == .trueHDAtmos { extras.append("Atmos plays as its \(StatusText.layout(src.sourceChannels)) bed") }
        if src.format == .dtsX { extras.append("DTS:X plays as its \(StatusText.layout(src.sourceChannels)) bed") }
        if src.outputSampleRate != src.sourceSampleRate {
            let from = src.sourceSampleRate % 1000 == 0 ? "\(src.sourceSampleRate / 1000) kHz" : String(format: "%.1f kHz", Double(src.sourceSampleRate) / 1000)
            extras.append("resampled from \(from)")
        }
        if src.outputChannels > src.sourceChannels { extras.append("\(src.outputChannels - src.sourceChannels) silent channel(s) fill the output layout") }
        return extras.isEmpty ? s + "." : s + "; " + extras.joined(separator: "; ") + "."
    }

    /// Notices from the running decode counters (shown in the stats overlay). Nothing is hidden: every concealment is counted.
    public static func audioDiagnosticNotices(trackNumber: Int, _ d: AudioTranscodeDiagnostics) -> [PlaybackNotice] {
        var out: [PlaybackNotice] = []
        if d.concealedFrames > 0 {
            out.append(PlaybackNotice(severity: .warning,
                                      text: "Audio track \(trackNumber): \(d.concealedFrames) damaged frame(s) were replaced by silence."))
        }
        if d.framesWithoutLosslessExtension > 0 {
            out.append(PlaybackNotice(severity: .warning,
                                      text: "Audio track \(trackNumber): \(d.framesWithoutLosslessExtension) frame(s) had no lossless extension, so their lossy DTS core played."))
        }
        if d.layoutChanges > 0 {
            out.append(PlaybackNotice(severity: .info,
                                      text: "Audio track \(trackNumber): the channel layout changed \(d.layoutChanges) time(s); the output keeps its first layout."))
        }
        if d.sampleRateChanges > 0 {
            out.append(PlaybackNotice(severity: .info,
                                      text: "Audio track \(trackNumber): the sample rate changed \(d.sampleRateChanges) time(s); the audio is resampled to the first rate."))
        }
        if d.framesWithReducedBitDepth > 0 {
            out.append(PlaybackNotice(severity: .info,
                                      text: "Audio track \(trackNumber): \(d.framesWithReducedBitDepth) frame(s) carried more than 24 bits and were shortened to 24."))
        }
        return out
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// "A_DTS" becomes "DTS". Unknown ids are shown as written.
    public static func audioCodecName(_ codecID: String) -> String {
        let id = codecID.uppercased()
        if id == "A_DTS/LOSSLESS" { return "DTS-HD Master Audio" }
        if id == "A_DTS/EXPRESS" { return "DTS Express" }
        if id.hasPrefix("A_DTS") { return id.contains("MA") || id.contains("HD") ? "DTS-HD" : "DTS" }
        if id == "A_TRUEHD" { return "Dolby TrueHD" }
        if id == "A_MLP" { return "MLP" }
        if id == "A_AC3" { return "Dolby Digital" }
        if id == "A_EAC3" { return "Dolby Digital Plus" }
        if id.hasPrefix("A_AAC") { return "AAC" }
        if id == "A_FLAC" { return "FLAC" }
        if id == "A_OPUS" { return "Opus" }
        if id == "A_VORBIS" { return "Vorbis" }
        if id.hasPrefix("A_MPEG/L3") { return "MP3" }
        if id.hasPrefix("A_MPEG/L2") { return "MP2" }
        if id.hasPrefix("A_PCM") { return "PCM" }
        if id.hasPrefix("A_ALAC") { return "ALAC" }
        return codecID
    }
}
