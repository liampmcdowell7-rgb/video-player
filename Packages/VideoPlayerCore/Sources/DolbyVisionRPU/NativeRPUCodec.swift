#if canImport(CDolbyVisionRPU)
import Foundation
import RemuxEngine
import CDolbyVisionRPU

/// The RPU codec backed by the prebuilt native RPU library (version 3.3.2; Frameworks/DolbyVisionRPULib.xcframework on
/// Apple platforms, a local build on Linux). Every call parses its own RPU object and frees it before returning, so the
/// codec holds no state and can be used from any thread.
public struct NativeRPUCodec: DolbyVisionRPUCodec {
    /// Library conversion mode 2: "to profile 8.1". In the 3.3.2 sources modes 2 and 3 both select the 8.1 conversion
    /// (the header comment lists an older numbering); it is the same conversion the reference command line tool runs
    /// with `-m 2`, and the tests compare against that tool byte for byte (docs/DOLBY_VISION.md).
    static let modeProfile81: UInt8 = 2

    public init() {}

    public func convertToProfile81(_ nal: ArraySlice<UInt8>) throws -> [UInt8] {
        try nal.withUnsafeBufferPointer { buf -> [UInt8] in
            guard let base = buf.baseAddress, let rpu = dovi_parse_unspec62_nalu(base, buf.count) else {
                throw DolbyVisionRPUError("empty RPU")
            }
            defer { dovi_rpu_free(rpu) }
            if let e = dovi_rpu_get_error(rpu) { throw DolbyVisionRPUError("parse: " + String(cString: e)) }
            guard dovi_convert_rpu_with_mode(rpu, Self.modeProfile81) == 0 else {
                throw DolbyVisionRPUError("convert: " + (dovi_rpu_get_error(rpu).map { String(cString: $0) } ?? "failed"))
            }
            guard let data = dovi_write_unspec62_nalu(rpu) else {
                throw DolbyVisionRPUError("write: " + (dovi_rpu_get_error(rpu).map { String(cString: $0) } ?? "failed"))
            }
            defer { dovi_data_free(data) }
            guard let bytes = data.pointee.data, data.pointee.len > 2 else { throw DolbyVisionRPUError("write: empty") }
            return Array(UnsafeBufferPointer(start: bytes, count: data.pointee.len))
        }
    }

    public func describe(_ nal: ArraySlice<UInt8>) -> (profile: Int, enhancementLayer: DolbyVisionSampleInfo.EnhancementLayer?)? {
        nal.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress, let rpu = dovi_parse_unspec62_nalu(base, buf.count) else { return nil }
            defer { dovi_rpu_free(rpu) }
            guard dovi_rpu_get_error(rpu) == nil, let header = dovi_rpu_get_header(rpu) else { return nil }
            defer { dovi_rpu_free_header(header) }
            let profile = Int(header.pointee.guessed_profile)
            var layer: DolbyVisionSampleInfo.EnhancementLayer?
            if let t = header.pointee.el_type { layer = DolbyVisionSampleInfo.EnhancementLayer(rawValue: String(cString: t)) }
            return (profile, layer)
        }
    }
}
#endif
