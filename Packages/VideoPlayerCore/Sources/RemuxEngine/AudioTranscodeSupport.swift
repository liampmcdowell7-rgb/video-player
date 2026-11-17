import Foundation

// Shared vocabulary between the session and a decoding audio transcoder (the AudioDecode target): what one segment
// request hands over, what the transcoder says about the source, and its running diagnostics. Pure Swift.
// docs/AUDIO_PIPELINE.md describes the whole path.

/// Everything a transcoder gets for one audio segment.
public struct AudioTranscodeInput: Sendable {
    /// Segment number (the same numbering as the playlists).
    public var segmentIndex: Int
    /// The track's frames whose time falls inside the segment, in decode order.
    public var frames: [MKVFrame]
    /// Frames just before the segment, when the session already holds them (empty after a seek). They warm up the decoder.
    public var preroll: [MKVFrame]
    /// Frames just after the segment: the last output block of a segment may need a little audio from the next one.
    public var lookahead: [MKVFrame]
    /// File time where the segment starts (nil for the first segment: everything from the track's first frame).
    public var startNs: Int64?
    /// File time where the next segment starts (nil for the last segment: everything to the end of the track).
    public var endNs: Int64?
    /// Time of the track's first frame: output sample 0.
    public var anchorNs: Int64

    public var isLast: Bool { endNs == nil }

    public init(segmentIndex: Int, frames: [MKVFrame], preroll: [MKVFrame] = [], lookahead: [MKVFrame] = [],
                startNs: Int64?, endNs: Int64?, anchorNs: Int64) {
        self.segmentIndex = segmentIndex; self.frames = frames; self.preroll = preroll; self.lookahead = lookahead
        self.startNs = startNs; self.endNs = endNs; self.anchorNs = anchorNs
    }
}

/// What a decoded track really is (read from the stream, not from the codec ID: Matroska uses "A_DTS" for every DTS kind).
public struct TranscodedAudioSource: Equatable, Sendable {
    public enum Format: String, Sendable, CaseIterable {
        case dts, dtsES, dts9624, dtsHDHighResolution, dtsHDMasterAudio, dtsX, dtsExpress
        case trueHD, trueHDAtmos, mlp, opus, vorbis
    }

    public var format: Format
    /// Channels the source carries (for TrueHD with Atmos: the channels of the presentation that is decoded).
    public var sourceChannels: Int
    /// Channels in the output (FLAC order; silent channels are added when the source layout has no FLAC equivalent).
    public var outputChannels: Int
    public var sourceSampleRate: Int
    public var outputSampleRate: Int
    /// Bits per sample of the output (16 or 24).
    public var outputBits: Int
    /// The decoded audio is the exact lossless signal (DTS-HD Master Audio, TrueHD, MLP).
    public var isLossless: Bool
    /// TrueHD only: Dolby Digital frames are carried inside the track.
    public var hasEmbeddedCore: Bool
    /// TrueHD only: the compatibility setting is on and the embedded Dolby Digital frames are played instead of the decode.
    public var usesEmbeddedCore: Bool
    /// Source channels that have no place in the output layout (named like "TFL"); empty almost always.
    public var droppedChannels: [String]

    public init(format: Format, sourceChannels: Int, outputChannels: Int, sourceSampleRate: Int, outputSampleRate: Int,
                outputBits: Int, isLossless: Bool, hasEmbeddedCore: Bool = false, usesEmbeddedCore: Bool = false,
                droppedChannels: [String] = []) {
        self.format = format; self.sourceChannels = sourceChannels; self.outputChannels = outputChannels
        self.sourceSampleRate = sourceSampleRate; self.outputSampleRate = outputSampleRate; self.outputBits = outputBits
        self.isLossless = isLossless; self.hasEmbeddedCore = hasEmbeddedCore; self.usesEmbeddedCore = usesEmbeddedCore
        self.droppedChannels = droppedChannels
    }
}

/// Running counters of one decoded track: everything that was concealed, changed or reduced. Shown in the stats overlay.
public struct AudioTranscodeDiagnostics: Equatable, Sendable {
    /// Frames the decoder rejected (damaged data). Their time is filled with silence.
    public var concealedFrames = 0
    /// Output samples (per channel) filled with silence: damaged frames, gaps in the file, a decoder that had not started yet.
    public var silentSamples: Int64 = 0
    public var layoutChanges = 0
    public var sampleRateChanges = 0
    /// DTS-HD Master Audio frames that arrived without their lossless extension (decoded from the lossy core).
    public var framesWithoutLosslessExtension = 0
    /// Frames whose source bit depth was above the output's (truncated, no dither).
    public var framesWithReducedBitDepth = 0
    public var droppedChannels: [String] = []
    /// The first few error descriptions (for the overlay, never more than 5).
    public var errors: [String] = []
    /// Time spent decoding and encoding, and the audio produced in that time.
    public var processingSeconds: Double = 0
    public var producedSeconds: Double = 0
    public init() {}

    /// Processing time per second of audio (0.05 means 5% of one CPU core in real time). 0 when nothing was produced.
    public var realTimeLoad: Double { producedSeconds > 0 ? processingSeconds / producedSeconds : 0 }
}

/// Default implementations, so a simple transcoder only implements the original three requirements.
public extension AudioTranscoding {
    func outputConfig(for track: MKVTrack, firstFrames: [MKVFrame]) async throws -> AudioTrackConfig {
        guard let first = firstFrames.first else { throw RemuxError.malformed("no audio frame to configure track \(track.number)") }
        return try await outputConfig(for: track, firstFrame: Array(first.data))
    }
    func transcode(_ input: AudioTranscodeInput, track: MKVTrack, config: AudioTrackConfig) async throws -> [MKVFrame] {
        try await transcode(frames: input.frames, track: track, config: config)
    }
    func sourceInfo(for track: MKVTrack) async -> TranscodedAudioSource? { nil }
    func diagnostics(for trackNumber: Int) async -> AudioTranscodeDiagnostics? { nil }
}

/// Public initialisers for the value types a transcoder outside this module builds.
public extension MKVFrame {
    init(track: Int, timeNs: Int64, isKeyframe: Bool = true, durationNs: Int64? = nil, bytes: ArraySlice<UInt8>) {
        self.init(track: track, timeNs: timeNs, isKeyframe: isKeyframe, durationNs: durationNs, data: bytes)
    }
}

public extension AudioTrackConfig {
    /// FLAC output of a decoding transcoder (`specific` is the dfLa payload: block header plus STREAMINFO).
    static func decodedFLAC(trackID: UInt32, sampleRate: UInt32, channels: Int, bitsPerSample: Int, dfLa: [UInt8],
                            language: String, blockSize: Int, bitrate: Int) -> AudioTrackConfig {
        AudioTrackConfig(trackID: trackID, codec: .flac, sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample,
                         specific: dfLa, language: language, samplesPerFrame: blockSize, bitrate: bitrate, codecString: "fLaC")
    }
}

/// When the file's preferred audio track cannot be played, which offered track replaces it: the person is told on screen.
public struct AudioFallbackInfo: Equatable, Sendable {
    /// The track the file marks as default (or the first audio track) that could not be offered.
    public var unplayable: SkippedTrack
    /// The Matroska track number of the track that plays instead (nil: no audio track could be offered at all).
    public var replacement: Int?
    public init(unplayable: SkippedTrack, replacement: Int?) { self.unplayable = unplayable; self.replacement = replacement }
}

/// Picks the best replacement for an unplayable track. PROVISIONAL rule (docs/AUDIO_PIPELINE.md): same language first, then
/// lossless before lossy, then more channels, then the file's order. Alternative: the file's order only.
public enum AudioTrackRanking {
    public static func replacement(for lost: MKVTrack?, among offered: [AudioRenditionInfo], losslessTracks: Set<Int>) -> AudioRenditionInfo? {
        guard !offered.isEmpty else { return nil }
        let lang = lost?.language.lowercased()
        func score(_ r: AudioRenditionInfo) -> (Int, Int, Int) {
            let sameLanguage = (lang != nil && lang != "" && lang != "und" && r.language.lowercased() == lang) ? 1 : 0
            return (sameLanguage, losslessTracks.contains(r.trackNumber) ? 1 : 0, r.channels)
        }
        var best = offered[0]
        for r in offered.dropFirst() where score(r) > score(best) { best = r }
        return best
    }
}
