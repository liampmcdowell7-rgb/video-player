import Foundation

// HEVC / AVC bitstream helpers: decoder configuration records, NAL walking, SEI (mastering display and content
// light level), SPS colour description, parameter-set / Dolby Vision NAL filtering, and codec strings.

public struct NALArray: Equatable, Sendable {
    public var completeness: Bool
    public var type: Int
    public var nalus: [[UInt8]]
}

/// HEVCDecoderConfigurationRecord (ISO 14496-15 section 8.3.3), the content of the `hvcC` box.
public struct HVCConfig: Equatable, Sendable {
    public var raw: [UInt8]
    public var profileSpace: Int
    public var tier: Int
    public var profileIDC: Int
    public var compatibilityFlags: UInt32
    public var constraintFlags: [UInt8]      // 6 bytes
    public var levelIDC: Int
    public var chromaFormat: Int
    public var bitDepthLuma: Int
    public var bitDepthChroma: Int
    public var lengthSize: Int               // lengthSizeMinusOne + 1
    public var arrays: [NALArray]

    public init(parsing raw: [UInt8]) throws {
        self.raw = raw
        var c = ByteCursor(raw)
        guard try c.u8() == 1 else { throw RemuxError.unsupported("hvcC configurationVersion != 1") }
        let b1 = try c.u8()
        profileSpace = Int(b1 >> 6); tier = Int((b1 >> 5) & 1); profileIDC = Int(b1 & 0x1F)
        compatibilityFlags = try c.u32()
        constraintFlags = try c.take(6)
        levelIDC = Int(try c.u8())
        _ = try c.u16()                       // min_spatial_segmentation_idc
        _ = try c.u8()                        // parallelismType
        chromaFormat = Int(try c.u8() & 3)
        bitDepthLuma = Int(try c.u8() & 7) + 8
        bitDepthChroma = Int(try c.u8() & 7) + 8
        _ = try c.u16()                       // avgFrameRate
        let b21 = try c.u8()
        lengthSize = Int(b21 & 3) + 1
        let n = Int(try c.u8())
        var arrs: [NALArray] = []
        for _ in 0..<n {
            let h = try c.u8()
            let count = Int(try c.u16())
            var nalus: [[UInt8]] = []
            for _ in 0..<count { let len = Int(try c.u16()); nalus.append(try c.take(len)) }
            arrs.append(NALArray(completeness: h & 0x80 != 0, type: Int(h & 0x3F), nalus: nalus))
        }
        arrays = arrs
    }

    public func nalus(ofType t: Int) -> [[UInt8]] { arrays.filter { $0.type == t }.flatMap { $0.nalus } }

    /// The CODECS string for HLS ("hvc1.2.4.L120.B0"): RFC 6381 / ISO 14496-15 annex E.
    public func codecString(fourCC: String = "hvc1") -> String {
        let space = ["", "A", "B", "C"][profileSpace]
        // Compatibility flags are written bit-reversed, hex, without leading zeros.
        var rev: UInt32 = 0
        for i in 0..<32 where compatibilityFlags & (1 << UInt32(i)) != 0 { rev |= 1 << UInt32(31 - i) }
        let compat = String(rev, radix: 16, uppercase: true)
        var constraint = Array(constraintFlags)
        while let last = constraint.last, last == 0 { constraint.removeLast() }
        let cons = constraint.map { String(format: "%02X", $0) }.joined(separator: ".")
        var s = "\(fourCC).\(space)\(profileIDC).\(compat).\(tier == 1 ? "H" : "L")\(levelIDC)"
        if !cons.isEmpty { s += ".\(cons)" }
        return s
    }
}

/// Split a length-prefixed sample into NAL units. Returns slices (without the length prefix).
public func splitLengthPrefixed(_ sample: [UInt8], lengthSize: Int) throws -> [ArraySlice<UInt8>] {
    guard (1...4).contains(lengthSize) else { throw RemuxError.malformed("NAL length size \(lengthSize)") }
    var out: [ArraySlice<UInt8>] = []
    var pos = 0
    while pos < sample.count {
        guard pos + lengthSize <= sample.count else { throw RemuxError.truncated("NAL length at \(pos)") }
        var len = 0
        for i in 0..<lengthSize { len = len << 8 | Int(sample[pos + i]) }
        pos += lengthSize
        guard len >= 0, pos + len <= sample.count else { throw RemuxError.truncated("NAL of \(len) bytes at \(pos)") }
        out.append(sample[pos..<pos + len])
        pos += len
    }
    return out
}

public enum HEVCNAL {
    public static let vps = 32, sps = 33, pps = 34, prefixSEI = 39, suffixSEI = 40
    public static let dolbyVisionRPU = 62, dolbyVisionEL = 63
    public static func type(of nal: ArraySlice<UInt8>) -> Int { nal.count >= 2 ? Int((nal[nal.startIndex] >> 1) & 0x3F) : -1 }
    /// IRAP pictures (BLA, IDR, CRA) are types 16...23.
    public static func isIRAP(_ type: Int) -> Bool { (16...23).contains(type) }
}

/// Rewrites a length-prefixed sample without the NAL units whose type is in `drop`. Returns the input unchanged
/// (same bytes) when nothing is dropped.
public func dropNALs(_ sample: [UInt8], lengthSize: Int, hevc: Bool, drop: Set<Int>) throws -> [UInt8] {
    if drop.isEmpty { return sample }
    var out: [UInt8] = []
    out.reserveCapacity(sample.count)
    var changed = false
    for nal in try splitLengthPrefixed(sample, lengthSize: lengthSize) {
        let t = hevc ? HEVCNAL.type(of: nal) : (nal.isEmpty ? -1 : Int(nal[nal.startIndex] & 0x1F))
        if drop.contains(t) { changed = true; continue }
        var len = nal.count
        var prefix = [UInt8](repeating: 0, count: lengthSize)
        for i in stride(from: lengthSize - 1, through: 0, by: -1) { prefix[i] = UInt8(len & 0xFF); len >>= 8 }
        out.append(contentsOf: prefix)
        out.append(contentsOf: nal)
    }
    return changed ? out : sample
}

// MARK: SEI

/// HDR static metadata found in SEI messages.
public struct HDRStaticMetadata: Equatable, Sendable {
    /// The 24 payload bytes of the mastering display colour volume SEI (payloadType 137). These are exactly the
    /// bytes of the `mdcv` box: display_primaries[3] in G, B, R order (x, y as 0.00002 units), white point x, y,
    /// max and min luminance (0.0001 cd/m^2 units).
    public var mdcv: [UInt8]?
    /// The 4 payload bytes of the content light level SEI (payloadType 144): MaxCLL then MaxFALL, 16 bits each.
    /// Exactly the bytes of the `clli` box.
    public var clli: [UInt8]?
    public var isEmpty: Bool { mdcv == nil && clli == nil }
}

public enum HEVCSEI {
    /// Parses the SEI RBSP of a prefix SEI NAL (without the 2-byte NAL header) and returns the messages found.
    public static func messages(inNAL nal: ArraySlice<UInt8>) -> [(type: Int, payload: [UInt8])] {
        guard nal.count > 2 else { return [] }
        let rbsp = unescapeRBSP(nal.dropFirst(2))
        var out: [(Int, [UInt8])] = []
        var pos = 0
        while pos + 2 <= rbsp.count {
            if rbsp[pos] == 0x80 && pos == rbsp.count - 1 { break }     // rbsp trailing bits
            var type = 0
            while pos < rbsp.count, rbsp[pos] == 0xFF { type += 255; pos += 1 }
            guard pos < rbsp.count else { break }
            type += Int(rbsp[pos]); pos += 1
            var size = 0
            while pos < rbsp.count, rbsp[pos] == 0xFF { size += 255; pos += 1 }
            guard pos < rbsp.count else { break }
            size += Int(rbsp[pos]); pos += 1
            guard pos + size <= rbsp.count else { break }
            out.append((type, Array(rbsp[pos..<pos + size])))
            pos += size
        }
        return out
    }

    /// Looks for HDR static metadata in the SEI NAL units of the hvcC arrays and of the given sample.
    public static func staticMetadata(config: HVCConfig, firstKeyframe: [UInt8]?) -> HDRStaticMetadata {
        var result = HDRStaticMetadata()
        func scan(_ nal: ArraySlice<UInt8>) {
            guard HEVCNAL.type(of: nal) == HEVCNAL.prefixSEI else { return }
            for m in messages(inNAL: nal) {
                if m.type == 137, m.payload.count == 24, result.mdcv == nil { result.mdcv = m.payload }
                if m.type == 144, m.payload.count == 4, result.clli == nil { result.clli = m.payload }
            }
        }
        for n in config.nalus(ofType: HEVCNAL.prefixSEI) { scan(n[...]) }
        if let s = firstKeyframe, let nals = try? splitLengthPrefixed(s, lengthSize: config.lengthSize) { nals.forEach(scan) }
        return result
    }

    /// Builds the 24-byte mdcv payload from Matroska mastering metadata (chromaticities and luminance).
    public static func mdcvPayload(_ m: MKVColour.Mastering) -> [UInt8] {
        func c(_ v: Double) -> UInt16 { UInt16(max(0, min(65535, (v * 50000).rounded()))) }
        var w = ByteWriter()
        // Box order is G, B, R (same as the SEI).
        w.u16(c(m.gx)); w.u16(c(m.gy)); w.u16(c(m.bx)); w.u16(c(m.by)); w.u16(c(m.rx)); w.u16(c(m.ry))
        w.u16(c(m.wx)); w.u16(c(m.wy))
        w.u32(UInt32(max(0, min(Double(UInt32.max), (m.maxLuminance * 10000).rounded()))))
        w.u32(UInt32(max(0, min(Double(UInt32.max), (m.minLuminance * 10000).rounded()))))
        return w.bytes
    }
}

// MARK: SPS

/// What the remuxer needs from an HEVC SPS.
public struct HEVCSPSInfo: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var bitDepthLuma: Int
    public var maxNumReorderPics: Int
    public var colourPrimaries: Int?
    public var transferCharacteristics: Int?
    public var matrixCoefficients: Int?
    public var fullRange: Bool?
    public var chromaFormatIdc: Int
}

public enum HEVCSPS {
    /// Parses an SPS NAL (including its 2-byte header). Returns nil when something unexpected is hit.
    public static func parse(_ nal: [UInt8]) -> HEVCSPSInfo? {
        guard nal.count > 4 else { return nil }
        var r = BitReader(unescapeRBSP(nal[2...]))
        do {
            try r.skip(4)                                   // sps_video_parameter_set_id
            let maxSubLayersMinus1 = try r.bits(3)
            try r.skip(1)                                   // temporal_id_nesting
            try profileTierLevel(&r, maxSubLayersMinus1: maxSubLayersMinus1)
            _ = try r.ue()                                  // sps_seq_parameter_set_id
            let chroma = try r.ue()
            if chroma == 3 { try r.skip(1) }
            var width = try r.ue(), height = try r.ue()
            if try r.bit() == 1 {                           // conformance_window
                let l = try r.ue(), rr = try r.ue(), t = try r.ue(), b = try r.ue()
                let subW = (chroma == 1 || chroma == 2) ? 2 : 1, subH = chroma == 1 ? 2 : 1
                width -= subW * (l + rr); height -= subH * (t + b)
            }
            let bdLuma = try r.ue() + 8
            _ = try r.ue()                                  // bit_depth_chroma
            let log2MaxPocLsb = try r.ue() + 4
            let subLayerOrderingInfo = try r.bit() == 1
            var maxReorder = 0
            for i in (subLayerOrderingInfo ? 0 : maxSubLayersMinus1)...maxSubLayersMinus1 {
                _ = try r.ue()                              // max_dec_pic_buffering_minus1
                let reorder = try r.ue()
                _ = try r.ue()                              // max_latency_increase_plus1
                if i == maxSubLayersMinus1 { maxReorder = reorder }
            }
            _ = try r.ue(); _ = try r.ue()                  // log2_min_luma_coding_block_size_minus3, log2_diff_max_min
            _ = try r.ue(); _ = try r.ue()                  // transform block sizes
            _ = try r.ue(); _ = try r.ue()                  // max_transform_hierarchy_depth inter, intra
            if try r.bit() == 1 {                           // scaling_list_enabled_flag
                if try r.bit() == 1 { try scalingListData(&r) }
            }
            try r.skip(2)                                   // amp_enabled_flag, sample_adaptive_offset_enabled_flag
            if try r.bit() == 1 {                           // pcm_enabled_flag
                try r.skip(4 + 4)
                _ = try r.ue(); _ = try r.ue()
                try r.skip(1)
            }
            let numStRps = try r.ue()
            var rpsSizes: [Int] = []                        // NumDeltaPocs per set
            for i in 0..<numStRps { rpsSizes.append(try shortTermRPS(&r, index: i, numSets: numStRps, sizes: rpsSizes)) }
            if try r.bit() == 1 {                           // long_term_ref_pics_present_flag
                let n = try r.ue()
                for _ in 0..<n { try r.skip(log2MaxPocLsb); try r.skip(1) }
            }
            try r.skip(2)                                   // sps_temporal_mvp_enabled_flag, strong_intra_smoothing
            var info = HEVCSPSInfo(width: width, height: height, bitDepthLuma: bdLuma, maxNumReorderPics: maxReorder,
                                   colourPrimaries: nil, transferCharacteristics: nil, matrixCoefficients: nil,
                                   fullRange: nil, chromaFormatIdc: chroma)
            if try r.bit() == 1 {                           // vui_parameters_present_flag
                try vui(&r, into: &info)
            }
            return info
        } catch {
            return nil
        }
    }

    private static func profileTierLevel(_ r: inout BitReader, maxSubLayersMinus1: Int) throws {
        try r.skip(2 + 1 + 5 + 32 + 4 + 43 + 1 + 8)         // general profile/tier/flags/level
        var profilePresent: [Bool] = [], levelPresent: [Bool] = []
        for _ in 0..<maxSubLayersMinus1 { profilePresent.append(try r.bit() == 1); levelPresent.append(try r.bit() == 1) }
        if maxSubLayersMinus1 > 0 { for _ in maxSubLayersMinus1..<8 { try r.skip(2) } }
        for i in 0..<maxSubLayersMinus1 {
            if profilePresent[i] { try r.skip(88) }
            if levelPresent[i] { try r.skip(8) }
        }
    }

    private static func scalingListData(_ r: inout BitReader) throws {
        for sizeId in 0..<4 {
            var matrixId = 0
            while matrixId < 6 {
                if try r.bit() == 0 {
                    _ = try r.ue()                          // scaling_list_pred_matrix_id_delta
                } else {
                    let coefNum = min(64, 1 << (4 + (sizeId << 1)))
                    if sizeId > 1 { _ = try r.se() }
                    for _ in 0..<coefNum { _ = try r.se() }
                }
                matrixId += sizeId == 3 ? 3 : 1
            }
        }
    }

    /// Returns NumDeltaPocs of the set.
    private static func shortTermRPS(_ r: inout BitReader, index: Int, numSets: Int, sizes: [Int]) throws -> Int {
        var interPred = false
        if index != 0 { interPred = try r.bit() == 1 }
        if interPred {
            var deltaIdx = 1
            if index == numSets { deltaIdx = try r.ue() + 1 }
            guard deltaIdx <= index else { throw RemuxError.malformed("rps delta idx") }
            _ = try r.bit(); _ = try r.ue()                 // delta_rps_sign, abs_delta_rps_minus1
            let refNum = sizes[index - deltaIdx]
            var n = 0
            for _ in 0...refNum {
                let used = try r.bit()
                var useDelta = 1
                if used == 0 { useDelta = try r.bit() }
                if used == 1 || useDelta == 1 { n += 1 }
            }
            return n
        }
        let neg = try r.ue(), pos = try r.ue()
        for _ in 0..<(neg + pos) { _ = try r.ue(); try r.skip(1) }
        return neg + pos
    }

    private static func vui(_ r: inout BitReader, into info: inout HEVCSPSInfo) throws {
        if try r.bit() == 1 {                               // aspect_ratio_info_present_flag
            if try r.bits(8) == 255 { try r.skip(32) }
        }
        if try r.bit() == 1 { try r.skip(1) }               // overscan
        if try r.bit() == 1 {                               // video_signal_type_present_flag
            try r.skip(3)                                   // video_format
            info.fullRange = try r.bit() == 1
            if try r.bit() == 1 {                           // colour_description_present_flag
                info.colourPrimaries = try r.bits(8)
                info.transferCharacteristics = try r.bits(8)
                info.matrixCoefficients = try r.bits(8)
            }
        }
    }
}

// MARK: AVC

/// AVCDecoderConfigurationRecord essentials.
public struct AVCConfig: Equatable, Sendable {
    public var raw: [UInt8]
    public var profileIDC: Int
    public var profileCompatibility: Int
    public var levelIDC: Int
    public var lengthSize: Int

    public init(parsing raw: [UInt8]) throws {
        self.raw = raw
        var c = ByteCursor(raw)
        guard try c.u8() == 1 else { throw RemuxError.unsupported("avcC configurationVersion != 1") }
        profileIDC = Int(try c.u8()); profileCompatibility = Int(try c.u8()); levelIDC = Int(try c.u8())
        lengthSize = Int(try c.u8() & 3) + 1
    }

    public func codecString() -> String {
        String(format: "avc1.%02X%02X%02X", profileIDC, profileCompatibility, levelIDC)
    }
}
