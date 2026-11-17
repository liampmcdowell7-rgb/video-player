import Foundation
import CMediaCodecs

// Owning Swift wrappers over the C handles in CMediaCodecs. Each one is used by a single track worker inside the
// transcoder actor, never shared between threads.

public struct AudioDecodeError: Error, CustomStringConvertible, Equatable {
    public var description: String
    public init(_ d: String) { description = d }
}

/// Source codecs (numbers match mediacodecs.h `mc_codec`).
enum SourceCodec: Int32 {
    case dts = 1, trueHD = 2, mlp = 3, opus = 4, vorbis = 5

    init?(codecID: String) {
        switch codecID {
        case "A_DTS", "A_DTS/EXPRESS", "A_DTS/LOSSLESS": self = .dts
        case "A_TRUEHD": self = .trueHD
        case "A_MLP": self = .mlp
        case "A_OPUS": self = .opus
        case "A_VORBIS": self = .vorbis
        default: return nil
        }
    }

    /// Opus and Vorbis need the Matroska CodecPrivate (OpusHead, the three Vorbis headers); the others carry everything in-band.
    var needsCodecPrivate: Bool { self == .opus || self == .vorbis }
}

/// Profile numbers reported by the decoder (mediacodecs.h MC_PROFILE_*).
enum DecodedProfile {
    static let dts = 1, dtsES = 2, dts9624 = 3, dtsHDHRA = 4, dtsHDMA = 5, dtsExpress = 6, dtsX = 7, dtsXIMAX = 8, trueHDAtmos = 20
    static func isMasterAudio(_ p: Int) -> Bool { p == dtsHDMA || p == dtsX || p == dtsXIMAX }
}

struct DecodedBlock {
    var samples: [Int32]          // interleaved, MSB-aligned
    var count: Int                // samples per channel
    var channels: Int
    var mask: UInt64
    var sampleRate: Int
    var bits: Int
    var fromFloat: Bool
    var ptsNs: Int64?
    var profile: Int
}

private func errorText(_ buf: [CChar]) -> String {
    let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}

final class Decoder {
    private let handle: OpaquePointer
    let codec: SourceCodec

    init(codec: SourceCodec, extradata: [UInt8], sampleRate: Int, channels: Int, bitExact: Bool) throws {
        var err = [CChar](repeating: 0, count: 256)
        let flags: Int32 = bitExact ? 1 : 0
        let h: OpaquePointer? = extradata.withUnsafeBufferPointer { ext in
            err.withUnsafeMutableBufferPointer { e in
                mc_decoder_open(codec.rawValue, ext.count > 0 ? ext.baseAddress : nil, Int32(ext.count), Int32(sampleRate),
                                Int32(channels), flags, e.baseAddress, Int32(e.count))
            }
        }
        guard let h else { throw AudioDecodeError("decoder: \(errorText(err))") }
        handle = h
        self.codec = codec
    }

    deinit { mc_decoder_close(handle) }

    /// 0, or a negative library error (damaged data).
    func send(_ data: ArraySlice<UInt8>, ptsNs: Int64?) -> Int32 {
        data.withUnsafeBufferPointer { b in
            mc_decoder_send(handle, b.baseAddress, Int32(b.count), ptsNs ?? Int64.min)
        }
    }

    func sendEOF() { _ = mc_decoder_send_eof(handle) }

    enum Received { case block(DecodedBlock), needMore, failed(Int32) }

    func receive() -> Received {
        var f = mc_frame()
        let r = mc_decoder_receive(handle, &f)
        if r == 0 { return .needMore }
        if r < 0 { return .failed(r) }
        let n = Int(f.nb_samples), ch = Int(f.channels)
        var samples = [Int32](repeating: 0, count: n * ch)
        if n * ch > 0, let src = f.samples {
            samples.withUnsafeMutableBufferPointer { dst in dst.baseAddress!.update(from: src, count: n * ch) }
        }
        return .block(DecodedBlock(samples: samples, count: n, channels: ch, mask: f.channel_mask, sampleRate: Int(f.sample_rate),
                                   bits: Int(f.bits), fromFloat: f.from_float != 0, ptsNs: f.pts_ns == Int64.min ? nil : f.pts_ns,
                                   profile: Int(f.profile)))
    }
}

final class FLACEncoder {
    private let handle: OpaquePointer
    let streamInfo: [UInt8]
    let channels: Int

    init(sampleRate: Int, channels: Int, bits: Int, blockSize: Int, compression: Int) throws {
        var err = [CChar](repeating: 0, count: 256)
        var si = [UInt8](repeating: 0, count: 34)
        let h: OpaquePointer? = si.withUnsafeMutableBufferPointer { s in
            err.withUnsafeMutableBufferPointer { e in
                mc_flac_open(Int32(sampleRate), Int32(channels), Int32(bits), Int32(blockSize), Int32(compression), s.baseAddress,
                             e.baseAddress, Int32(e.count))
            }
        }
        guard let h else { throw AudioDecodeError("FLAC encoder: \(errorText(err))") }
        handle = h
        streamInfo = si
        self.channels = channels
    }

    deinit { mc_flac_close(handle) }

    /// Encodes `count` samples per channel starting at sample `offset` of `pcm` (interleaved).
    func encode(_ pcm: [Int32], offset: Int, count: Int) throws -> [UInt8] {
        var out: UnsafePointer<UInt8>? = nil
        let size = pcm.withUnsafeBufferPointer { b in
            mc_flac_encode(handle, b.baseAddress! + offset * channels, Int32(count), &out)
        }
        guard size > 0, let out else { throw AudioDecodeError("FLAC encoder returned \(size)") }
        return Array(UnsafeBufferPointer(start: out, count: Int(size)))
    }
}

final class Resampler {
    private let handle: OpaquePointer
    let inRate: Int, outRate: Int, channels: Int

    init(inRate: Int, outRate: Int, channels: Int) throws {
        var err = [CChar](repeating: 0, count: 256)
        let h = err.withUnsafeMutableBufferPointer { e in
            mc_resampler_open(Int32(inRate), Int32(outRate), Int32(channels), e.baseAddress, Int32(e.count))
        }
        guard let h else { throw AudioDecodeError("resampler: \(errorText(err))") }
        handle = h
        self.inRate = inRate; self.outRate = outRate; self.channels = channels
    }

    deinit { mc_resampler_close(handle) }

    func convert(_ pcm: [Int32], count: Int) -> [Int32] {
        let cap = count * outRate / max(1, inRate) + 256
        var out = [Int32](repeating: 0, count: cap * channels)
        let got = pcm.withUnsafeBufferPointer { i in
            out.withUnsafeMutableBufferPointer { o in mc_resample(handle, i.baseAddress, Int32(count), o.baseAddress, Int32(cap)) }
        }
        return got > 0 ? Array(out.prefix(Int(got) * channels)) : []
    }
}

/// The library's version string (diagnostics only).
public func audioDecoderLibraryVersion() -> String { String(cString: mc_library_version()) }
