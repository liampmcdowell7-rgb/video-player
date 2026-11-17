import Foundation
import RemuxEngine

// Decodes the audio codecs the player cannot play (DTS, DTS-HD, TrueHD, MLP, Opus, Vorbis) and repackages them as FLAC
// for fragmented MP4 (the remux spike's decision, docs/spikes/REMUX.md). docs/AUDIO_PIPELINE.md explains every rule here.
//
// Quality rules:
//  - Lossless sources (DTS-HD Master Audio, TrueHD, MLP) keep their exact samples, bit depth (16 or 24) and sample rate.
//  - Lossy sources keep the decoder's output: DTS core in its integer (bit-exact) mode, Opus and Vorbis as 24-bit.
//  - Channels keep their positions (FLAC channel order); a layout with no FLAC equivalent gets silent channels added,
//    never a downmix. TrueHD is fully decoded by default; the Dolby Digital frames some TrueHD tracks carry are used only
//    when the compatibility setting asks for them.
//  - Nothing fails silently: damaged frames become silence and are counted, and every reduction is reported.

public struct DecodedAudioSettings: Sendable, Equatable {
    /// TrueHD tracks that carry Dolby Digital frames inside them: play those frames instead of the full decode.
    /// Off by default (the full decode is lossless; the Dolby Digital frames are a lossy 5.1 version).
    public var trueHDUseEmbeddedCore = false
    /// Optional ceiling for the output sample rate (nil: keep the source rate, the default). When set and the source is
    /// higher, the audio is resampled and is no longer bit-exact.
    public var maxSampleRate: Int? = nil
    /// FLAC compression level (0...12). The output is lossless at every level; higher levels cost more CPU for a smaller
    /// stream on the loopback connection. PROVISIONAL default 5 (the library default); docs/AUDIO_PIPELINE.md has the timing.
    public var flacCompression = 5
    public init(trueHDUseEmbeddedCore: Bool = false, maxSampleRate: Int? = nil, flacCompression: Int = 5) {
        self.trueHDUseEmbeddedCore = trueHDUseEmbeddedCore; self.maxSampleRate = maxSampleRate; self.flacCompression = flacCompression
    }
}

public actor DecodedAudioTranscoder: AudioTranscoding {
    public nonisolated let supportedCodecIDs: Set<String> = ["A_DTS", "A_DTS/EXPRESS", "A_DTS/LOSSLESS", "A_TRUEHD", "A_MLP", "A_OPUS", "A_VORBIS"]
    public nonisolated let settings: DecodedAudioSettings
    private var workers: [Int: TrackWorker] = [:]

    public init(settings: DecodedAudioSettings = DecodedAudioSettings()) { self.settings = settings }

    public func outputConfig(for track: MKVTrack, firstFrame: [UInt8]) async throws -> AudioTrackConfig {
        try configure(track, frames: [MKVFrame(track: track.number, timeNs: 0, bytes: firstFrame[...])])
    }

    public func outputConfig(for track: MKVTrack, firstFrames: [MKVFrame]) async throws -> AudioTrackConfig {
        try configure(track, frames: firstFrames)
    }

    private func configure(_ track: MKVTrack, frames: [MKVFrame]) throws -> AudioTrackConfig {
        let w = try TrackWorker.probe(track: track, frames: frames, settings: settings)
        workers[track.number] = w
        return w.config
    }

    /// Whole-stream form of the original contract: the frames are treated as one segment that ends the track.
    public func transcode(frames: [MKVFrame], track: MKVTrack, config: AudioTrackConfig) async throws -> [MKVFrame] {
        guard let w = workers[track.number] else { throw AudioDecodeError("track \(track.number) was not configured") }
        let input = AudioTranscodeInput(segmentIndex: Int.min, frames: frames, startNs: nil, endNs: nil,
                                        anchorNs: frames.first?.timeNs ?? 0)
        return try w.transcode(input)
    }

    public func transcode(_ input: AudioTranscodeInput, track: MKVTrack, config: AudioTrackConfig) async throws -> [MKVFrame] {
        guard let w = workers[track.number] else { throw AudioDecodeError("track \(track.number) was not configured") }
        return try w.transcode(input)
    }

    public func sourceInfo(for track: MKVTrack) async -> TranscodedAudioSource? { workers[track.number]?.source }

    public func diagnostics(for trackNumber: Int) async -> AudioTranscodeDiagnostics? { workers[trackNumber]?.diag }
}

/// Decoder, encoder and PCM state of one track. Owned by the actor; never touched from two places at once.
final class TrackWorker {
    let track: MKVTrack
    let codec: SourceCodec
    let settings: DecodedAudioSettings
    let config: AudioTrackConfig
    let source: TranscodedAudioSource
    var diag = AudioTranscodeDiagnostics()

    // Output format (fixed for the whole track: the init segment cannot change).
    let outRate: Int, outBits: Int, outChannels: Int, block: Int
    let layout: [Speaker]
    let usesEmbeddedCore: Bool
    private let initialProfile: Int
    private let initialKey: String
    /// Opus: the codec delay in Matroska (pre-skip) is taken off the block times.
    private let codecDelayNs: Int64
    /// Steady-state timing tolerance: decoded audio is laid down back to back and re-aligned to the block times only
    /// when they disagree by more than this (or after a damaged frame). PROVISIONAL 40 ms; alternative: always follow
    /// the block times (Matroska stores milliseconds, so that adds up to 0.5 ms of jitter per block).
    private let toleranceSamples: Int64

    private var decoder: Decoder?
    private var encoder: FLACEncoder?
    private var maps: [String: ChannelLayoutMap] = [:]
    private var lastKey: String
    private var lastRate: Int
    private var resampler: Resampler?
    private var pcm: [Int32] = []
    private var pcmStart: Int64 = 0
    private var positioned = false
    private var resync = false
    private var lastSentNs: Int64?
    private var sentAtLastTime: [ArraySlice<UInt8>] = []
    private var lastSegment: Int?

    private init(track: MKVTrack, codec: SourceCodec, settings: DecodedAudioSettings, config: AudioTrackConfig, source: TranscodedAudioSource,
                 outRate: Int, outBits: Int, layout: [Speaker], block: Int, usesEmbeddedCore: Bool, initialProfile: Int, initialKey: String,
                 sourceRate: Int, encoder: FLACEncoder?) {
        self.track = track; self.codec = codec; self.settings = settings; self.config = config; self.source = source
        self.outRate = outRate; self.outBits = outBits; self.layout = layout; self.outChannels = layout.count; self.block = block
        self.usesEmbeddedCore = usesEmbeddedCore; self.initialProfile = initialProfile; self.initialKey = initialKey
        self.lastKey = initialKey; self.lastRate = sourceRate; self.encoder = encoder
        self.codecDelayNs = codec == .opus ? track.codecDelayNs : 0
        self.toleranceSamples = Int64(outRate) * 40 / 1000
        self.accessUnitNs = sourceRate % 44100 == 0 ? 907_029 : 833_333
    }
    private let accessUnitNs: Int64

    // MARK: Probe

    /// Decodes the first frames to learn the real format (Matroska says "A_DTS" for every DTS kind, and its channel count
    /// and rate may be missing), then fixes the output format and opens the encoder.
    static func probe(track: MKVTrack, frames: [MKVFrame], settings: DecodedAudioSettings) throws -> TrackWorker {
        guard let codec = SourceCodec(codecID: track.codecID) else { throw AudioDecodeError("codec \(track.codecID) is not decoded here") }
        if codec.needsCodecPrivate && track.codecPrivate.isEmpty { throw AudioDecodeError("\(track.codecID) track without codec headers") }
        let isTrueHD = codec == .trueHD || codec == .mlp
        var ac3Frames: [ArraySlice<UInt8>] = []
        if isTrueHD { for f in frames { ac3Frames += TrueHDCoreSplitter.split(f.data).ac3 } }

        let dec = try Decoder(codec: codec, extradata: track.codecPrivate, sampleRate: Int(track.sampleRate), channels: track.channels, bitExact: true)
        var first: DecodedBlock?
        var tried = 0
        outer: for f in frames {
            let units: [ArraySlice<UInt8>] = isTrueHD ? TrueHDCoreSplitter.split(f.data).trueHD : [f.data]
            for u in units {
                tried += 1
                _ = dec.send(u, ptsNs: nil)
                while case .block(let b) = dec.receive() { if b.count > 0 { first = b; break outer } }
            }
        }
        if first == nil { dec.sendEOF(); while case .block(let b) = dec.receive() { if b.count > 0 { first = b; break } } }
        guard let first else { throw AudioDecodeError("no audio could be decoded from the first \(tried) frames") }

        let sourceRate = first.sampleRate
        var outRate = sourceRate
        if let cap = settings.maxSampleRate, cap > 0, sourceRate > cap { outRate = cap }
        let outBits = (first.fromFloat || first.bits > 16) ? 24 : 16
        let map = ChannelLayoutMap.choose(mask: first.mask, channels: first.channels)
        let block = FLACFraming.blockSize(sampleRate: outRate)
        let key = "\(first.mask)/\(first.channels)"
        let format = Self.format(codec: codec, profile: first.profile)
        let sourceLossless = [.dtsHDMasterAudio, .dtsX, .trueHD, .trueHDAtmos, .mlp].contains(format)
        let useCore = isTrueHD && settings.trueHDUseEmbeddedCore && !ac3Frames.isEmpty

        let config: AudioTrackConfig
        var encoder: FLACEncoder? = nil
        if useCore {
            config = try AudioConfigBuilder.ac3(track: track, firstFrame: Array(ac3Frames[0]))
        } else {
            let enc = try FLACEncoder(sampleRate: outRate, channels: map.output.count, bits: outBits, blockSize: block, compression: settings.flacCompression)
            encoder = enc
            let rate = outRate * map.output.count * outBits * 6 / 10
            config = .decodedFLAC(trackID: UInt32(track.number), sampleRate: UInt32(outRate), channels: map.output.count,
                                  bitsPerSample: outBits, dfLa: FLACFraming.dfLaPayload(streamInfo: enc.streamInfo),
                                  language: track.language, blockSize: block, bitrate: rate)
        }
        let source = TranscodedAudioSource(
            format: format, sourceChannels: first.channels, outputChannels: useCore ? config.channels : map.output.count,
            sourceSampleRate: sourceRate, outputSampleRate: useCore ? Int(config.sampleRate) : outRate,
            outputBits: useCore ? 16 : outBits,
            isLossless: !useCore && sourceLossless && outRate == sourceRate && first.bits <= outBits && map.dropped.isEmpty,
            hasEmbeddedCore: !ac3Frames.isEmpty, usesEmbeddedCore: useCore, droppedChannels: map.dropped)
        let w = TrackWorker(track: track, codec: codec, settings: settings, config: config, source: source, outRate: outRate, outBits: outBits,
                            layout: map.output, block: block, usesEmbeddedCore: useCore, initialProfile: first.profile, initialKey: key,
                            sourceRate: sourceRate, encoder: encoder)
        w.maps[key] = map
        w.diag.droppedChannels = map.dropped
        return w
    }

    static func format(codec: SourceCodec, profile: Int) -> TranscodedAudioSource.Format {
        switch codec {
        case .dts:
            switch profile {
            case DecodedProfile.dtsES: return .dtsES
            case DecodedProfile.dts9624: return .dts9624
            case DecodedProfile.dtsHDHRA: return .dtsHDHighResolution
            case DecodedProfile.dtsHDMA: return .dtsHDMasterAudio
            case DecodedProfile.dtsExpress: return .dtsExpress
            case DecodedProfile.dtsX, DecodedProfile.dtsXIMAX: return .dtsX
            default: return .dts
            }
        case .trueHD: return profile == DecodedProfile.trueHDAtmos ? .trueHDAtmos : .trueHD
        case .mlp: return .mlp
        case .opus: return .opus
        case .vorbis: return .vorbis
        }
    }

    // MARK: Segments

    private var pcmEnd: Int64 { pcmStart + Int64(pcm.count / outChannels) }

    private func note(_ error: String) {
        if diag.errors.count < 5 { diag.errors.append(error) }
    }

    static func ceilDiv(_ a: Int64, _ b: Int64) -> Int64 { a >= 0 ? (a + b - 1) / b : -((-a) / b) }

    /// First block index of the segment that starts at `ns`: block j belongs to the segment whose time range holds the
    /// block's first sample, so every block is served exactly once whatever order the segments are asked in.
    func firstBlock(atNs ns: Int64, anchorNs: Int64) -> Int64 {
        max(0, Self.ceilDiv((ns - anchorNs) * Int64(outRate), 1_000_000_000 * Int64(block)))
    }

    func transcode(_ input: AudioTranscodeInput) throws -> [MKVFrame] {
        let clock = ContinuousClock()
        let t0 = clock.now
        defer {
            let d = clock.now - t0
            diag.processingSeconds += Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        }
        if usesEmbeddedCore { return embeddedCoreFrames(input) }

        let B = Int64(block)
        let j0 = input.startNs.map { firstBlock(atNs: $0, anchorNs: input.anchorNs) } ?? 0
        let j1 = input.endNs.map { firstBlock(atNs: $0, anchorNs: input.anchorNs) }
        let keepFrom = j0 * B
        let warm = decoder != nil && positioned && lastSegment != nil && lastSegment == input.segmentIndex - 1 && pcmStart == keepFrom
        if !warm {
            try coldStart()
            feed(input.preroll, anchorNs: input.anchorNs, keepFrom: keepFrom)
        }
        feed(input.frames, anchorNs: input.anchorNs, keepFrom: keepFrom)
        if let j1 {
            for f in input.lookahead where !positioned || pcmEnd < (j1 * B) { feed([f], anchorNs: input.anchorNs, keepFrom: keepFrom) }
        } else {
            drain(anchorNs: input.anchorNs, keepFrom: keepFrom)
        }

        if !positioned || pcm.isEmpty && pcmStart < keepFrom { pcm.removeAll(); pcmStart = keepFrom; positioned = true }
        if pcmStart > keepFrom {
            let gap = Int(pcmStart - keepFrom)
            pcm.insert(contentsOf: [Int32](repeating: 0, count: gap * outChannels), at: 0)
            pcmStart = keepFrom
            diag.silentSamples += Int64(gap)
        }

        var out: [MKVFrame] = []
        var j = j0
        var produced: Int64 = 0
        while true {
            if let j1, j >= j1 { break }
            let have = pcmEnd - j * B
            if have >= B {
                out.append(try encodeBlock(j, count: block, anchorNs: input.anchorNs))
                produced += B
            } else if j1 == nil {
                if have > 0 { out.append(try encodeLastBlock(j, count: Int(have), anchorNs: input.anchorNs)); produced += have }
                break
            } else {
                let missing = Int(B - max(0, have))
                pcm += [Int32](repeating: 0, count: missing * outChannels)
                diag.silentSamples += Int64(missing)
                out.append(try encodeBlock(j, count: block, anchorNs: input.anchorNs))
                produced += B
            }
            j += 1
        }
        if out.isEmpty {
            // The track ended before this (last) segment starts: one silent block keeps the segment valid, and it is counted.
            pcm = [Int32](repeating: 0, count: block * outChannels); pcmStart = j0 * B
            out.append(try encodeBlock(j0, count: block, anchorNs: input.anchorNs))
            diag.silentSamples += B; produced += B; j = j0 + 1
        }
        // Keep what belongs to the next segment.
        let drop = min(pcm.count, Int(max(0, j * B - pcmStart)) * outChannels)
        pcm.removeFirst(drop)
        pcmStart = j * B
        diag.producedSeconds += Double(produced) / Double(outRate)
        lastSegment = input.isLast ? nil : input.segmentIndex
        if input.isLast { decoder = nil; positioned = false }
        return out
    }

    private func coldStart() throws {
        decoder = try Decoder(codec: codec, extradata: track.codecPrivate, sampleRate: Int(track.sampleRate), channels: track.channels, bitExact: true)
        pcm.removeAll(); pcmStart = 0; positioned = false; resync = false; lastSentNs = nil; sentAtLastTime.removeAll(); resampler = nil
    }

    private func feed(_ frames: [MKVFrame], anchorNs: Int64, keepFrom: Int64) {
        guard let decoder else { return }
        for f in frames {
            // A frame already fed (the previous segment's look-ahead) is not fed twice. Matroska stores milliseconds, so two
            // frames can share a time (TrueHD access units are 0.83 ms apart): equal times are told apart by their bytes.
            if let last = lastSentNs {
                if f.timeNs < last { continue }
                if f.timeNs == last && sentAtLastTime.contains(f.data) { continue }
            }
            if lastSentNs != f.timeNs { sentAtLastTime.removeAll() }
            lastSentNs = f.timeNs
            sentAtLastTime.append(f.data)
            let units: [ArraySlice<UInt8>] = (codec == .trueHD || codec == .mlp) ? TrueHDCoreSplitter.split(f.data).trueHD : [f.data]
            for (i, u) in units.enumerated() {
                // A TrueHD / MLP access unit lasts 1/1200 s (48 kHz family) or 1/1102.5 s (44.1 kHz family).
                let r = decoder.send(u, ptsNs: f.timeNs + Int64(i) * accessUnitNs)
                if r < 0 {
                    diag.concealedFrames += 1; resync = true
                    note("frame at \(Double(f.timeNs) / 1e9) s could not be decoded (error \(r)); silence in its place")
                    continue
                }
                receiveAll(anchorNs: anchorNs, keepFrom: keepFrom)
            }
        }
    }

    private func drain(anchorNs: Int64, keepFrom: Int64) {
        guard let decoder else { return }
        decoder.sendEOF()
        receiveAll(anchorNs: anchorNs, keepFrom: keepFrom)
    }

    private func receiveAll(anchorNs: Int64, keepFrom: Int64) {
        guard let decoder else { return }
        while true {
            switch decoder.receive() {
            case .needMore: return
            case .failed(let r):
                diag.concealedFrames += 1; resync = true
                note("decoder error \(r); silence in its place")
                return
            case .block(let b):
                if b.count > 0 { place(b, anchorNs: anchorNs, keepFrom: keepFrom) }
            }
        }
    }

    /// Converts one decoded block to the output layout and rate, and lays it on the track's sample timeline.
    private func place(_ b: DecodedBlock, anchorNs: Int64, keepFrom: Int64) {
        // Layout.
        let key = "\(b.mask)/\(b.channels)"
        if key != lastKey { diag.layoutChanges += 1; lastKey = key }
        let map: ChannelLayoutMap
        if let m = maps[key] { map = m } else {
            map = ChannelLayoutMap.assign(source: ChannelLayoutMap.speakers(mask: b.mask, channels: b.channels), to: layout)
            maps[key] = map
            for d in map.dropped where !diag.droppedChannels.contains(d) { diag.droppedChannels.append(d) }
            if key != initialKey { note("channel layout changed to \(b.channels) channels; kept the \(outChannels)-channel output, missing channels silent") }
        }
        // Depth and extensions.
        if b.bits > outBits { diag.framesWithReducedBitDepth += 1 }
        if DecodedProfile.isMasterAudio(initialProfile) && !DecodedProfile.isMasterAudio(b.profile) { diag.framesWithoutLosslessExtension += 1 }

        var samples: [Int32]
        if key == initialKey && map.sourceIndex.enumerated().allSatisfy({ $0.element == $0.offset }) && b.channels == outChannels {
            samples = b.samples
        } else {
            samples = [Int32](repeating: 0, count: b.count * outChannels)
            for (o, src) in map.sourceIndex.enumerated() {
                guard let src else { continue }
                var i = 0
                while i < b.count { samples[i * outChannels + o] = b.samples[i * b.channels + src]; i += 1 }
            }
        }
        // Rate.
        var count = b.count
        var usePts = true
        if b.sampleRate != lastRate { diag.sampleRateChanges += 1; lastRate = b.sampleRate
            note("sample rate changed to \(b.sampleRate) Hz; resampled to \(outRate) Hz")
        }
        if b.sampleRate != outRate {
            if resampler == nil || resampler?.inRate != b.sampleRate {
                resampler = try? Resampler(inRate: b.sampleRate, outRate: outRate, channels: outChannels)
            }
            guard let r = resampler else { note("no resampler for \(b.sampleRate) Hz; block replaced by silence"); diag.concealedFrames += 1; resync = true; return }
            samples = r.convert(samples, count: count)
            count = samples.count / outChannels
            usePts = false
            if count == 0 { return }
        } else {
            resampler = nil
        }

        // Position.
        var idx = pcmEnd
        if let pts = b.ptsNs, usePts || !positioned {
            let fromPts = Self.roundDiv((pts - codecDelayNs - anchorNs) * Int64(outRate), 1_000_000_000)
            if !positioned || resync || abs(fromPts - pcmEnd) > toleranceSamples { idx = fromPts }
        }
        resync = false
        if !positioned { pcmStart = idx; positioned = true; pcm.removeAll() }
        var skip = 0
        if idx > pcmEnd {
            let gap = Int(idx - pcmEnd)
            pcm += [Int32](repeating: 0, count: gap * outChannels)
            diag.silentSamples += Int64(gap)
        } else if idx < pcmEnd {
            skip = Int(min(Int64(count), pcmEnd - idx))
        }
        if skip < count { pcm += samples[(skip * outChannels)...] }
        // Nothing before the first block of this segment is kept.
        if pcmStart < keepFrom {
            let drop = min(pcm.count / outChannels, Int(keepFrom - pcmStart))
            pcm.removeFirst(drop * outChannels)
            pcmStart += Int64(drop)
        }
    }

    static func roundDiv(_ a: Int64, _ b: Int64) -> Int64 { a >= 0 ? (a + b / 2) / b : -((-a + b / 2) / b) }

    private func frameTime(_ j: Int64, anchorNs: Int64) -> Int64 {
        anchorNs + Self.roundDiv(j * Int64(block) * 1_000_000_000, Int64(outRate))
    }

    private func encodeBlock(_ j: Int64, count: Int, anchorNs: Int64) throws -> MKVFrame {
        guard let encoder else { throw AudioDecodeError("no encoder") }
        let offset = Int(j * Int64(block) - pcmStart)
        let bytes = try encoder.encode(pcm, offset: offset, count: count)
        let numbered = FLACFraming.renumber(bytes, frameNumber: j) ?? bytes
        return MKVFrame(track: track.number, timeNs: frameTime(j, anchorNs: anchorNs), durationNs: nil, bytes: numbered[...])
    }

    /// The shorter final block of the track: a one-off encoder (the library accepts a short block only as the last one).
    private func encodeLastBlock(_ j: Int64, count: Int, anchorNs: Int64) throws -> MKVFrame {
        let enc = try FLACEncoder(sampleRate: outRate, channels: outChannels, bits: outBits, blockSize: block, compression: settings.flacCompression)
        let offset = Int(j * Int64(block) - pcmStart)
        let bytes = try enc.encode(pcm, offset: offset, count: count)
        let numbered = FLACFraming.renumber(bytes, frameNumber: j) ?? bytes
        return MKVFrame(track: track.number, timeNs: frameTime(j, anchorNs: anchorNs), durationNs: nil, bytes: numbered[...])
    }

    /// Compatibility setting: the Dolby Digital frames carried in the TrueHD track, passed through unchanged.
    private func embeddedCoreFrames(_ input: AudioTranscodeInput) -> [MKVFrame] {
        var out: [MKVFrame] = []
        let frameNs = Int64(1536) * 1_000_000_000 / Int64(max(1, config.sampleRate))
        for f in input.frames {
            for (i, a) in TrueHDCoreSplitter.split(f.data).ac3.enumerated() {
                out.append(MKVFrame(track: track.number, timeNs: f.timeNs + Int64(i) * frameNs, durationNs: frameNs, bytes: a))
            }
        }
        return out
    }
}
