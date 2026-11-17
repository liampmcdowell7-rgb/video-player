import Foundation

// Audio codec configuration for the fMP4 sample entries, built from the Matroska track and the first frame.
// Supported pass-through: AC-3, E-AC-3 (no Atmos detection, see `eac3JOCComplexity`), AAC, FLAC.
// Everything else (DTS, DTS-HD, TrueHD, Opus, Vorbis...) goes through `AudioTranscoding` or is reported unsupported.

public enum AudioCodec: String, Sendable { case ac3, eac3, aac, flac }

public struct AudioTrackConfig: Equatable, Sendable {
    public var trackID: UInt32
    public var codec: AudioCodec
    public var sampleRate: UInt32
    public var channels: Int
    public var bitsPerSample: Int
    /// Payload of the codec box: dac3 (3 bytes), dec3, the AudioSpecificConfig for esds, or the dfLa metadata blocks.
    public var specific: [UInt8]
    public var language: String
    /// Nominal samples per frame (1536 for AC-3, 256 x blocks for E-AC-3, 1024 for AAC, FLAC block size).
    public var samplesPerFrame: Int
    /// Average bitrate in bits per second (for esds, bandwidth in the playlist). 0 if unknown.
    public var bitrate: Int
    /// HLS CODECS string: "ac-3", "ec-3", "mp4a.40.2", "fLaC".
    public var codecString: String
    /// E-AC-3 with Dolby Atmos (JOC) signalled in the first access unit (EAC3Atmos). Never set by guesswork.
    public var isAtmos = false

    public var timescale: UInt32 { sampleRate }
}

public struct AC3FrameInfo: Equatable, Sendable {
    public var fscod: Int, frmsizecod: Int, bsid: Int, bsmod: Int, acmod: Int, lfeon: Int
    public var sampleRate: Int { [48000, 44100, 32000, 0][min(fscod, 3)] }
    public var channels: Int { [2, 1, 2, 3, 3, 4, 4, 5][acmod] + lfeon }
}

public struct EAC3FrameInfo: Equatable, Sendable {
    public var streamType: Int          // 0 independent, 1 dependent, 2 AC-3 convert, 3 reserved
    public var substreamID: Int
    public var frameBytes: Int
    public var fscod: Int
    public var numBlocks: Int
    public var acmod: Int, lfeon: Int, bsid: Int
    /// chan_loc (9 bits) of a dependent substream, 0 when none.
    public var chanLoc: Int
    public var sampleRate: Int { fscod == 3 ? 0 : [48000, 44100, 32000][fscod] }
    public var channels: Int { [2, 1, 2, 3, 3, 4, 4, 5][acmod] + lfeon }
}

public enum AudioConfigBuilder {
    public static func parseAC3(_ f: [UInt8]) throws -> AC3FrameInfo {
        guard f.count >= 8, f[0] == 0x0B, f[1] == 0x77 else { throw RemuxError.malformed("not an AC-3 syncframe") }
        var r = BitReader(Array(f[4...]))
        let fscod = try r.bits(2), frmsizecod = try r.bits(6)
        guard fscod != 3 else { throw RemuxError.unsupported("AC-3 reserved sample rate code") }
        let bsid = try r.bits(5), bsmod = try r.bits(3), acmod = try r.bits(3)
        if acmod & 1 != 0 && acmod != 1 { try r.skip(2) }
        if acmod & 4 != 0 { try r.skip(2) }
        if acmod == 2 { try r.skip(2) }
        let lfe = try r.bit()
        return AC3FrameInfo(fscod: fscod, frmsizecod: frmsizecod, bsid: bsid, bsmod: bsmod, acmod: acmod, lfeon: lfe)
    }

    /// Parses one E-AC-3 syncframe header at `offset`.
    public static func parseEAC3Frame(_ f: [UInt8], at offset: Int = 0) throws -> EAC3FrameInfo {
        guard f.count >= offset + 8, f[offset] == 0x0B, f[offset + 1] == 0x77 else { throw RemuxError.malformed("not an E-AC-3 syncframe") }
        var r = BitReader(Array(f[(offset + 2)...]))
        let strmtyp = try r.bits(2), sub = try r.bits(3), frmsiz = try r.bits(11)
        let fscod = try r.bits(2)
        var numblks = 6
        if fscod == 3 { try r.skip(2) } else { numblks = [1, 2, 3, 6][try r.bits(2)] }
        let acmod = try r.bits(3), lfe = try r.bit(), bsid = try r.bits(5)
        var chanLoc = 0
        if strmtyp == 1 {
            // Dependent substream BSI: dialnorm, compre(+compr), (acmod 0: dialnorm2, compr2e(+compr2)), chanmape, chanmap.
            try r.skip(5)
            if try r.bit() == 1 { try r.skip(8) }
            if acmod == 0 { try r.skip(5); if try r.bit() == 1 { try r.skip(8) } }
            if try r.bit() == 1 {
                let chanmap = try r.bits(16)
                // chanmap bit index i counts from the MSB; chan_loc bit k comes from index 5 + k.
                for k in 0..<9 where chanmap & (1 << (15 - (5 + k))) != 0 { chanLoc |= 1 << k }
            }
        }
        return EAC3FrameInfo(streamType: strmtyp, substreamID: sub, frameBytes: (frmsiz + 1) * 2, fscod: fscod,
                             numBlocks: numblks, acmod: acmod, lfeon: lfe, bsid: bsid, chanLoc: chanLoc)
    }

    /// The access unit may hold several syncframes (independent, then dependent substreams).
    public static func parseEAC3AccessUnit(_ au: [UInt8]) throws -> [EAC3FrameInfo] {
        var out: [EAC3FrameInfo] = []
        var pos = 0
        while pos + 8 <= au.count, au[pos] == 0x0B, au[pos + 1] == 0x77 {
            let f = try parseEAC3Frame(au, at: pos)
            out.append(f)
            pos += f.frameBytes
        }
        guard !out.isEmpty else { throw RemuxError.malformed("no E-AC-3 syncframe") }
        return out
    }

    public static func ac3(track: MKVTrack, firstFrame: [UInt8]) throws -> AudioTrackConfig {
        let i = try parseAC3(firstFrame)
        var w = BitWriter()
        w.put(i.fscod, 2); w.put(i.bsid, 5); w.put(i.bsmod, 3); w.put(i.acmod, 3); w.put(i.lfeon, 1)
        w.put(i.frmsizecod >> 1, 5); w.put(0, 5)
        let brTable = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 576, 640]
        let rate = (i.frmsizecod >> 1) < brTable.count ? brTable[i.frmsizecod >> 1] * 1000 : 0
        return AudioTrackConfig(trackID: UInt32(track.number), codec: .ac3, sampleRate: UInt32(i.sampleRate), channels: i.channels,
                                bitsPerSample: 16, specific: w.bytes, language: track.language, samplesPerFrame: 1536,
                                bitrate: rate, codecString: "ac-3")
    }

    /// - Parameter jocComplexityIndex: the complexity index to write in the dec3 extension. nil: detected from the stream
    ///   (`EAC3Atmos`, PROVISIONAL, never run against a real Atmos file) and absent when the stream does not signal JOC.
    public static func eac3(track: MKVTrack, firstAccessUnit: [UInt8], jocComplexityIndex: Int? = nil) throws -> AudioTrackConfig {
        let frames = try parseEAC3AccessUnit(firstAccessUnit)
        let independents = frames.filter { $0.streamType == 0 || $0.streamType == 2 }
        guard let first = independents.first else { throw RemuxError.unsupported("E-AC-3 access unit without an independent substream") }
        guard first.fscod != 3 else { throw RemuxError.unsupported("E-AC-3 reduced sample rates") }
        let perFrame = first.numBlocks * 256
        let bytesIndep = independents.reduce(0) { $0 + $1.frameBytes } + frames.filter { $0.streamType == 1 }.reduce(0) { $0 + $1.frameBytes }
        let bitrate = bytesIndep * 8 * first.sampleRate / perFrame
        var w = BitWriter()
        w.put(min(8191, (bitrate + 500) / 1000), 13)
        w.put(independents.count - 1, 3)
        for ind in independents {
            let deps = frames.filter { $0.streamType == 1 && $0.substreamID == ind.substreamID }
            w.put(ind.fscod, 2); w.put(ind.bsid, 5); w.put(0, 1); w.put(0, 1); w.put(0, 3)
            w.put(ind.acmod, 3); w.put(ind.lfeon, 1); w.put(0, 3); w.put(deps.count, 4)
            if deps.isEmpty { w.put(0, 1) } else { w.put(deps.reduce(0) { $0 | $1.chanLoc }, 9) }
        }
        let joc = jocComplexityIndex ?? EAC3Atmos.complexityIndex(accessUnit: firstAccessUnit)
        if let joc {
            w.put(0, 7); w.put(1, 1); w.put(joc & 0xFF, 8)
        }
        let channels = first.channels + frames.filter { $0.streamType == 1 }.reduce(0) { $0 + Self.channelsAdded(by: $1) }
        return AudioTrackConfig(trackID: UInt32(track.number), codec: .eac3, sampleRate: UInt32(first.sampleRate), channels: channels,
                                bitsPerSample: 16, specific: w.bytes, language: track.language, samplesPerFrame: perFrame,
                                bitrate: bitrate, codecString: "ec-3", isAtmos: joc != nil)
    }

    private static func channelsAdded(by dep: EAC3FrameInfo) -> Int {
        // Lc/Rc, Lrs/Rrs, Lsd/Rsd, Lw/Rw, Lvh/Rvh are pairs; Cs, Ts, Cvh, LFE2 are single.
        let pairs = [0, 1, 4, 5, 6], singles = [2, 3, 7, 8]
        return pairs.filter { dep.chanLoc & (1 << $0) != 0 }.count * 2 + singles.filter { dep.chanLoc & (1 << $0) != 0 }.count
    }

    public static func aac(track: MKVTrack) throws -> AudioTrackConfig {
        guard track.codecPrivate.count >= 2 else { throw RemuxError.malformed("AAC track without AudioSpecificConfig") }
        var r = BitReader(track.codecPrivate)
        var aot = try r.bits(5)
        if aot == 31 { aot = 32 + (try r.bits(6)) }
        let sfi = try r.bits(4)
        let rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let rate = sfi == 15 ? (try r.bits(24)) : (sfi < rates.count ? rates[sfi] : Int(track.sampleRate))
        let chan = try r.bits(4)
        let channels = chan == 0 ? track.channels : [0, 1, 2, 3, 4, 5, 6, 8][min(chan, 7)]
        return AudioTrackConfig(trackID: UInt32(track.number), codec: .aac, sampleRate: UInt32(rate), channels: channels,
                                bitsPerSample: 16, specific: track.codecPrivate, language: track.language, samplesPerFrame: 1024,
                                bitrate: 0, codecString: "mp4a.40.\(aot)")
    }

    public static func flac(track: MKVTrack) throws -> AudioTrackConfig {
        var cp = track.codecPrivate
        guard cp.count >= 4 + 4 + 34, Array(cp[0..<4]) == Array("fLaC".utf8) else { throw RemuxError.malformed("FLAC track without STREAMINFO") }
        cp.removeFirst(4)
        // STREAMINFO: min/max block size, min/max frame size, 20 bits rate, 3 bits channels-1, 5 bits bps-1.
        let si = Array(cp[4..<(4 + 34)])
        let minBlock = Int(si[0]) << 8 | Int(si[1]), maxBlock = Int(si[2]) << 8 | Int(si[3])
        let rate = Int(si[10]) << 12 | Int(si[11]) << 4 | Int(si[12] >> 4)
        let channels = Int((si[12] >> 1) & 7) + 1
        let bps = (Int(si[12] & 1) << 4 | Int(si[13] >> 4)) + 1
        return AudioTrackConfig(trackID: UInt32(track.number), codec: .flac, sampleRate: UInt32(rate), channels: channels,
                                bitsPerSample: bps, specific: cp, language: track.language,
                                samplesPerFrame: minBlock == maxBlock ? maxBlock : 0, bitrate: 0, codecString: "fLaC")
    }

    /// Samples in one FLAC frame, from the frame header (needed when the stream has variable block sizes).
    public static func flacFrameSamples(_ f: [UInt8]) -> Int? {
        guard f.count >= 6, f[0] == 0xFF, f[1] & 0xFC == 0xF8 else { return nil }
        let code = Int(f[2] >> 4)
        switch code {
        case 1: return 192
        case 2...5: return 576 << (code - 2)
        case 8...15: return 256 << (code - 8)
        case 6, 7:
            // The (variable-length UTF-8 style) frame number precedes the explicit block size.
            let first = f[4]
            let extra = first & 0x80 == 0 ? 0 : (first & 0xE0 == 0xC0 ? 1 : first & 0xF0 == 0xE0 ? 2 : first & 0xF8 == 0xF0 ? 3 : first & 0xFC == 0xF8 ? 4 : first & 0xFE == 0xFC ? 5 : 6)
            let at = 5 + extra
            if code == 6, f.count > at { return Int(f[at]) + 1 }
            if code == 7, f.count > at + 1 { return (Int(f[at]) << 8 | Int(f[at + 1])) + 1 }
            return nil
        default: return nil
        }
    }

    /// Samples in one frame of `config`, using the frame bytes when the codec has variable frame lengths.
    public static func frameSamples(_ config: AudioTrackConfig, frame: [UInt8]) -> Int {
        switch config.codec {
        case .ac3: return 1536
        case .eac3:
            if let f = try? parseEAC3Frame(frame) { return f.numBlocks * 256 }
            return config.samplesPerFrame
        case .aac: return 1024
        case .flac: return flacFrameSamples(frame) ?? config.samplesPerFrame
        }
    }
}

/// Tiny MSB-first bit writer for the small config boxes.
struct BitWriter {
    private(set) var bytes: [UInt8] = []
    private var bitCount = 0
    mutating func put(_ value: Int, _ n: Int) {
        for i in stride(from: n - 1, through: 0, by: -1) {
            if bitCount % 8 == 0 { bytes.append(0) }
            if (value >> i) & 1 == 1 { bytes[bytes.count - 1] |= UInt8(0x80 >> (bitCount % 8)) }
            bitCount += 1
        }
    }
}
