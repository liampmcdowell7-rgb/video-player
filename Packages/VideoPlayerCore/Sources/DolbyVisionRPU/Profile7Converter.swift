import Foundation
import RemuxEngine

// Dolby Vision profile 7 to profile 8.1, one access unit at a time (docs/DOLBY_VISION.md):
//  - enhancement-layer NAL units (UNSPEC63 wrapped, or nuh_layer_id > 0) are dropped,
//  - the RPU NAL unit (UNSPEC62) is rewritten as a profile 8.1 RPU by the native RPU library (conversion mode 2:
//    FEL loses its residual and its mapping curves become identity; MEL keeps its mapping; all dynamic metadata
//    levels stay as they are),
//  - every other NAL unit (parameter sets, SEI, base-layer slices) is copied byte for byte and in the same order.
// No state is kept between access units, so segments can be produced in any order (seeking, read-ahead).

/// The RPU work the converter needs. The native implementation sits in NativeRPUCodec.swift; tests can pass a fake.
public protocol DolbyVisionRPUCodec: Sendable {
    /// Rewrites one RPU NAL unit (2-byte header 0x7C01, emulation-prevention bytes as in the stream) as a profile 8.1
    /// RPU NAL unit in the same form. Throws when the RPU cannot be read or written.
    func convertToProfile81(_ nal: ArraySlice<UInt8>) throws -> [UInt8]
    /// Profile and enhancement-layer type the RPU describes. nil when it cannot be read.
    func describe(_ nal: ArraySlice<UInt8>) -> (profile: Int, enhancementLayer: DolbyVisionSampleInfo.EnhancementLayer?)?
}

public struct DolbyVisionRPUError: Error, CustomStringConvertible, Equatable {
    public var description: String
    public init(_ description: String) { self.description = description }
}

public final class DolbyVisionProfile7Converter: DolbyVisionConverting, @unchecked Sendable {
    /// Counters for the status overlay and the logs.
    public struct Stats: Equatable, Sendable {
        public var convertedAccessUnits = 0
        public var rejectedAccessUnits = 0
        public var lastRejection: String?
    }

    let codec: any DolbyVisionRPUCodec
    private let lock = NSLock()
    private var counters = Stats()

    public init(codec: any DolbyVisionRPUCodec) { self.codec = codec }

    /// The converter backed by the native RPU library, or nil when this build has no such library (Linux test builds
    /// without it). The app shows the base-layer fallback in that case, never a silent one.
    public static func native() -> DolbyVisionProfile7Converter? {
        #if canImport(CDolbyVisionRPU)
        return DolbyVisionProfile7Converter(codec: NativeRPUCodec())
        #else
        return nil
        #endif
    }

    /// True when this build links the native RPU library.
    public static var isAvailable: Bool {
        #if canImport(CDolbyVisionRPU)
        return true
        #else
        return false
        #endif
    }

    public var stats: Stats { lock.lock(); defer { lock.unlock() }; return counters }

    public func outputRecord(for source: MKVDolbyVisionMapping) -> MKVDolbyVisionMapping {
        source.profile == 7 ? source.profile81() : source
    }

    public func convert(sample: [UInt8], lengthSize: Int) throws -> [UInt8] {
        let nals = try splitLengthPrefixed(sample, lengthSize: lengthSize)
        guard nals.contains(where: { DolbyVisionNAL.isEnhancementLayer($0) || HEVCNAL.type(of: $0) == HEVCNAL.dolbyVisionRPU }) else { return sample }
        var out: [UInt8] = []
        out.reserveCapacity(sample.count)
        for nal in nals {
            if DolbyVisionNAL.isEnhancementLayer(nal) { continue }
            if HEVCNAL.type(of: nal) == HEVCNAL.dolbyVisionRPU {
                let converted: [UInt8]
                do { converted = try codec.convertToProfile81(nal) } catch {
                    note(rejected: "\(error)")
                    throw error
                }
                appendLengthPrefixed(converted[...], lengthSize: lengthSize, to: &out)
            } else {
                appendLengthPrefixed(nal, lengthSize: lengthSize, to: &out)
            }
        }
        note(rejected: nil)
        return out
    }

    public func inspect(sample: [UInt8], lengthSize: Int) -> DolbyVisionSampleInfo? {
        guard let nals = try? splitLengthPrefixed(sample, lengthSize: lengthSize),
              let rpu = nals.first(where: { HEVCNAL.type(of: $0) == HEVCNAL.dolbyVisionRPU }),
              let d = codec.describe(rpu) else { return nil }
        return DolbyVisionSampleInfo(profile: d.profile, enhancementLayer: d.enhancementLayer,
                                     hasEnhancementLayerNALs: nals.contains(where: DolbyVisionNAL.isEnhancementLayer))
    }

    private func note(rejected: String?) {
        lock.lock(); defer { lock.unlock() }
        if let rejected { counters.rejectedAccessUnits += 1; counters.lastRejection = rejected } else { counters.convertedAccessUnits += 1 }
    }
}
