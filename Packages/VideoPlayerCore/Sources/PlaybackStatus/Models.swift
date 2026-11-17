import Foundation

// Vocabulary for the Playback Stats overlay and the honest audio / HDR status.
// Everything here is Foundation-only. The app target reads AVFoundation / AVAudioSession and fills
// these types in; the rules (docs/PLAYBACK_STATUS.md) are tested in WSL.

/// Which player is playing the file.
public enum PlaybackEngine: String, Sendable, CaseIterable {
    /// AVPlayer fed by the remuxer.
    case primary
    /// The MPVKit fallback.
    case fallback

    public var label: String { self == .primary ? "Primary player" : "Fallback player" }
}

/// A fact the system may or may not tell us. `.unknown` is never treated as `.yes`.
public enum Tri: String, Sendable, CaseIterable {
    case yes, no, unknown
}

// MARK: - What the file contains (video)

public enum DolbyVisionProfile: String, Sendable, CaseIterable {
    case p5, p7FEL, p7MEL, p8_1, p8_2, p8_4

    /// What a player that does not do Dolby Vision can still show.
    public enum BaseLayer: String, Sendable { case none, sdr, hdr10, hlg }

    public var baseLayer: BaseLayer {
        switch self {
        case .p5: return .none      // IPT-PQ-C2, not viewable without Dolby Vision
        case .p7FEL, .p7MEL: return .hdr10
        case .p8_1: return .hdr10
        case .p8_2: return .sdr
        case .p8_4: return .hlg
        }
    }

    public var isProfile7: Bool { self == .p7FEL || self == .p7MEL }

    /// "Profile 8.1" and so on.
    public var displayName: String {
        switch self {
        case .p5: return "Profile 5"
        case .p7FEL: return "Profile 7 (FEL)"
        case .p7MEL: return "Profile 7 (MEL)"
        case .p8_1: return "Profile 8.1"
        case .p8_2: return "Profile 8.2"
        case .p8_4: return "Profile 8.4"
        }
    }
}

public enum HDRFormat: Equatable, Hashable, Sendable {
    case sdr, hdr10, hdr10Plus, hlg
    case dolbyVision(DolbyVisionProfile)

    /// Every format the rules cover, in the order the docs list them.
    public static let all: [HDRFormat] = [.sdr, .hdr10, .hdr10Plus, .hlg] + DolbyVisionProfile.allCases.map { .dolbyVision($0) }

    /// What the file contains, as shown to the user.
    public var containsText: String {
        switch self {
        case .sdr: return "SDR"
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .hlg: return "HLG"
        case .dolbyVision(let p):
            switch p.baseLayer {
            case .none: return "Dolby Vision \(p.displayName)"
            case .hdr10 where p.isProfile7: return "Dolby Vision \(p.displayName)"
            case .hdr10: return "Dolby Vision \(p.displayName) (HDR10 compatible)"
            case .sdr: return "Dolby Vision \(p.displayName) (SDR compatible)"
            case .hlg: return "Dolby Vision \(p.displayName) (HLG compatible)"
            }
        }
    }
}

// MARK: - What the display is doing

/// Which HDR modes the display chain reports (`AVPlayer.availableHDRModes` on tvOS).
public struct DisplayHDRModes: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let hlg = DisplayHDRModes(rawValue: 1)
    public static let hdr10 = DisplayHDRModes(rawValue: 2)
    public static let dolbyVision = DisplayHDRModes(rawValue: 4)
}

public enum DisplayMode: String, Sendable, CaseIterable {
    case sdr, hdr10, hlg, dolbyVision

    public var displayName: String {
        switch self {
        case .sdr: return "SDR"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "Dolby Vision"
        }
    }
}

public struct DisplayState: Equatable, Hashable, Sendable {
    /// nil when tvOS did not tell us. An empty set means "reports no HDR support" (an SDR display).
    public var availableHDR: DisplayHDRModes?
    /// The mode the display is in right now, when something actually reports it. nil if not known.
    public var activeMode: DisplayMode?
    /// The user's "Match Dynamic Range" setting. When `.no` the app cannot switch the display.
    public var matchDynamicRange: Tri
    /// Whether this Apple TV model sends HDR10+ dynamic metadata to the display. No API reports it (AVPlayer's HDR
    /// modes are HLG, HDR10 and Dolby Vision only); the app derives it from the model (support.apple.com/102339:
    /// "HDR10+ is a supported format only on Apple TV 4K (3rd generation) and later"). Even when `.yes`, nothing
    /// reports whether the display itself uses the metadata.
    public var sendsHDR10Plus: Tri

    public init(availableHDR: DisplayHDRModes?, activeMode: DisplayMode? = nil, matchDynamicRange: Tri = .yes, sendsHDR10Plus: Tri = .unknown) {
        self.availableHDR = availableHDR
        self.activeMode = activeMode
        self.matchDynamicRange = matchDynamicRange
        self.sendsHDR10Plus = sendsHDR10Plus
    }

    public static let unknown = DisplayState(availableHDR: nil, matchDynamicRange: .unknown)
}

/// Dolby Vision profile 7 needs a conversion to 8.1 before Apple TV can play it as Dolby Vision.
public enum Profile7Conversion: Equatable, Hashable, Sendable {
    case available
    /// Not possible on this device (or not built yet).
    case notAvailableOnDevice
    /// Tried and failed for this file.
    case failedForThisFile
}

// MARK: - What the file contains (audio)

public enum AudioCodecKind: String, Sendable, CaseIterable {
    case ac3, eac3, trueHD, dts, dtsHDMA, dtsX, aac, flac, pcm, opus
    // Added with the audio decoding work (docs/AUDIO_PIPELINE.md).
    case dtsHDHRA, vorbis
}

public struct AudioTrackContent: Equatable, Hashable, Sendable {
    public var kind: AudioCodecKind
    /// Channels in the file (6 = 5.1, 8 = 7.1).
    public var channels: Int
    /// E-AC-3 with Joint Object Coding, or TrueHD with Atmos objects.
    public var hasAtmos: Bool
    /// TrueHD only: the track carries an AC-3 core next to the lossless stream.
    public var hasAC3Core: Bool
    /// TrueHD only: the compatibility setting is on and the AC-3 core plays instead of the full decode (off by default).
    public var usesCompatibilityCore: Bool
    /// Sample rate of the decoded output when known (shown when it is above 48 kHz).
    public var sampleRate: Int?

    public init(kind: AudioCodecKind, channels: Int, hasAtmos: Bool = false, hasAC3Core: Bool = false,
                usesCompatibilityCore: Bool = false, sampleRate: Int? = nil) {
        self.kind = kind
        self.channels = max(1, channels)
        self.hasAtmos = hasAtmos
        self.hasAC3Core = hasAC3Core
        self.usesCompatibilityCore = usesCompatibilityCore
        self.sampleRate = sampleRate
    }
}

// MARK: - What the audio output is doing

public enum AudioRouteKind: String, Sendable, CaseIterable {
    case hdmi, bluetooth, airPlay, builtIn, unknown
}

public struct AudioRoute: Equatable, Hashable, Sendable {
    public var kind: AudioRouteKind
    /// Most channels the route accepts (`AVAudioSession.maximumOutputNumberOfChannels`). nil when unknown.
    public var maxChannels: Int?
    /// Whether Dolby Digital / Digital Plus can reach the sink as a bitstream.
    public var passesDolbyBitstream: Tri
    /// Whether the system reports Dolby Atmos rendering on this route.
    public var atmos: Tri

    public init(kind: AudioRouteKind, maxChannels: Int?, passesDolbyBitstream: Tri, atmos: Tri) {
        self.kind = kind
        self.maxChannels = maxChannels
        self.passesDolbyBitstream = passesDolbyBitstream
        self.atmos = atmos
    }

    public static let unknown = AudioRoute(kind: .unknown, maxChannels: nil, passesDolbyBitstream: .unknown, atmos: .unknown)
}

// MARK: - Results

public enum AudioPath: String, Sendable {
    /// The app hands the stream to Apple's player unchanged (Dolby Digital, Digital Plus, Atmos).
    case passthrough
    /// The Dolby Digital core of a TrueHD track is handed over unchanged.
    case ac3CorePassthrough
    /// The app decodes to PCM before Apple's player.
    case decodedByApp
    /// Apple TV decodes it because the output cannot take the bitstream.
    case decodedBySystem
    /// The fallback player decodes it.
    case decodedByFallback
    /// The file already holds PCM.
    case pcm
}

public struct AudioStatus: Equatable, Sendable {
    public var contains: String
    public var output: String
    /// One plain sentence, only when something is unavailable or different from what the file holds.
    public var note: String?
    public var path: AudioPath
    /// Channels actually produced or passed, when known (nil for the Atmos bitstream).
    public var outputChannels: Int?
}

public enum VideoPath: String, Sendable {
    case sdr
    /// The signal is handed to the display as the file holds it.
    case passthrough
    /// Dolby Vision profile 7 converted to 8.1.
    case convertedProfile7
    /// A Dolby Vision file played through its HDR10, HLG or SDR layer.
    case baseLayer
    case toneMappedToSDR
    /// We cannot tell what the display shows.
    case unknown
}

public struct VideoStatus: Equatable, Sendable {
    public var contains: String
    public var output: String
    public var note: String?
    public var path: VideoPath
    /// The display mode the output text describes. nil when unknown.
    public var mode: DisplayMode?
}

public struct PlaybackStatus: Equatable, Sendable {
    public var audio: AudioStatus
    public var video: VideoStatus
    /// Shown whenever the fallback player is in use.
    public var engineNotice: String?
}

// MARK: - Plain text helpers

public enum StatusText {
    /// "Mono", "Stereo", "5.1", "7.1", "3.0", "10 channels".
    public static func layout(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 3: return "3.0"
        case 4: return "4.0"
        case 5: return "5.0"
        case 6: return "5.1"
        case 7: return "6.1"
        case 8: return "7.1"
        default: return "\(channels) channels"
        }
    }

    public static let fallbackNotice = "Dolby Vision and Atmos are unavailable in fallback mode."
}
