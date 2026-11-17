import Foundation

// Dynamic HDR metadata helpers (Dolby Vision and HDR10+) that need no native library: the Dolby Vision configuration
// record, the Dolby Vision level from picture size and frame rate, enhancement-layer NAL detection, and HDR10+ SEI
// detection. The RPU itself is converted by the DolbyVisionRPU target (docs/DOLBY_VISION.md).

extension MKVDolbyVisionMapping {
    /// Builds a 24-byte Dolby Vision decoder configuration record (version 1.0). The box / BlockAddIDType follows the
    /// profile: "dvcC" up to profile 7, "dvvC" for 8 to 10 (Matroska block additional mappings; the ISO box names agree).
    public static func make(profile: Int, level: Int, rpuPresent: Bool = true, elPresent: Bool, blPresent: Bool = true,
                            compatibilityID: Int) -> MKVDolbyVisionMapping {
        var rec = [UInt8](repeating: 0, count: 24)
        rec[0] = 1                                                          // dv_version_major
        rec[1] = 0                                                          // dv_version_minor
        rec[2] = UInt8((profile & 0x7F) << 1) | UInt8((level >> 5) & 1)     // dv_profile (7 bits), dv_level bit 5
        rec[3] = UInt8((level & 0x1F) << 3) | (rpuPresent ? 4 : 0) | (elPresent ? 2 : 0) | (blPresent ? 1 : 0)
        rec[4] = UInt8((compatibilityID & 0x0F) << 4)                       // dv_bl_signal_compatibility_id, then zeros
        return MKVDolbyVisionMapping(type: profile <= 7 ? 0x64766343 : 0x64767643, record: rec)
    }

    /// The profile 8.1 record that replaces a profile 7 record after conversion: same level, RPU and base layer present,
    /// no enhancement layer, HDR10 compatible (compatibility id 1).
    public func profile81() -> MKVDolbyVisionMapping {
        .make(profile: 8, level: level, elPresent: false, compatibilityID: 1)
    }
}

public enum DolbyVisionLevel {
    /// Dolby Vision level (1...13) for a picture size and frame rate: the lowest level whose maximum pixel rate and width
    /// hold the stream. Pixel rates are those of Dolby's level examples (720p24 ... 4320p120). PROVISIONAL: the width
    /// limits (2048 / 4096 / 8192) are this app's reading of the examples; only used when a file has no record.
    public static func level(width: Int, height: Int, framesPerSecond: Double) -> Int {
        let rate = Double(width * height) * framesPerSecond
        let table: [(level: Int, maxRate: Double, maxWidth: Int)] = [
            (1, 22_118_400, 2048), (2, 27_648_000, 2048), (3, 49_766_400, 2048), (4, 62_208_000, 2048), (5, 124_416_000, 2048),
            (6, 199_065_600, 4096), (7, 248_832_000, 4096), (8, 398_131_200, 4096), (9, 497_664_000, 4096), (10, 995_328_000, 4096),
            (11, 995_328_000, 8192), (12, 1_990_656_000, 8192), (13, 3_981_312_000, 8192)]
        for row in table where rate <= row.maxRate * 1.001 && width <= row.maxWidth { return row.level }
        return 13
    }
}

public enum DolbyVisionNAL {
    /// nuh_layer_id of an HEVC NAL unit (6 bits across the two header bytes).
    public static func layerID(of nal: ArraySlice<UInt8>) -> Int {
        guard nal.count >= 2 else { return 0 }
        return Int(nal[nal.startIndex] & 1) << 5 | Int(nal[nal.startIndex + 1] >> 3)
    }

    /// An enhancement-layer NAL unit: wrapped in UNSPEC63 (single-track dual layer, as muxed from discs) or carried with
    /// nuh_layer_id > 0.
    public static func isEnhancementLayer(_ nal: ArraySlice<UInt8>) -> Bool {
        HEVCNAL.type(of: nal) == HEVCNAL.dolbyVisionEL || layerID(of: nal) > 0
    }

    /// True when a length-prefixed access unit carries any enhancement-layer NAL unit.
    public static func hasEnhancementLayer(_ sample: [UInt8], lengthSize: Int) -> Bool {
        guard let nals = try? splitLengthPrefixed(sample, lengthSize: lengthSize) else { return false }
        return nals.contains(where: isEnhancementLayer)
    }
}

/// Rewrites a length-prefixed access unit without its Dolby Vision RPU and enhancement-layer NAL units (the base layer
/// only). Returns the input unchanged when there is nothing to drop.
public func dropDolbyVisionNALs(_ sample: [UInt8], lengthSize: Int) throws -> [UInt8] {
    let nals = try splitLengthPrefixed(sample, lengthSize: lengthSize)
    guard nals.contains(where: { DolbyVisionNAL.isEnhancementLayer($0) || HEVCNAL.type(of: $0) == HEVCNAL.dolbyVisionRPU }) else { return sample }
    var out: [UInt8] = []
    out.reserveCapacity(sample.count)
    for nal in nals where !(DolbyVisionNAL.isEnhancementLayer(nal) || HEVCNAL.type(of: nal) == HEVCNAL.dolbyVisionRPU) {
        appendLengthPrefixed(nal, lengthSize: lengthSize, to: &out)
    }
    return out
}

/// Appends one NAL unit with a big-endian length prefix of `lengthSize` bytes.
public func appendLengthPrefixed(_ nal: ArraySlice<UInt8>, lengthSize: Int, to out: inout [UInt8]) {
    var len = nal.count
    var prefix = [UInt8](repeating: 0, count: lengthSize)
    for i in stride(from: lengthSize - 1, through: 0, by: -1) { prefix[i] = UInt8(len & 0xFF); len >>= 8 }
    out.append(contentsOf: prefix)
    out.append(contentsOf: nal)
}

/// How the session rewrites the video samples of a Dolby Vision file.
enum DolbyVisionSampleMode: Equatable, Sendable {
    /// Not Dolby Vision, profile 5, or profile 8 without a converter: samples pass unchanged.
    case untouched
    /// Profile 7 converted to 8.1: every access unit goes through the converter.
    case convertAll
    /// A profile 8 file: only access units that carry an enhancement layer (a profile 7 section) are converted; all other
    /// samples pass byte for byte.
    case convertWhereEnhancementLayer
    /// Profile 7 without a working converter: the RPU and enhancement layer are dropped and the HDR10 base layer plays.
    case baseLayerOnly
}

struct DolbyVisionFacts: Equatable, Sendable {
    /// The record of the file, or the one derived from its first RPU.
    var source: MKVDolbyVisionMapping?
    var enhancementLayer: DolbyVisionSampleInfo.EnhancementLayer?
    var conversionFailed = false
    var derived = false
    var hdr10Plus = false
}

enum DolbyVisionPlanner {
    struct Decision { var mode: DolbyVisionSampleMode; var facts: DolbyVisionFacts; var signalled: MKVDolbyVisionMapping? }

    /// Decides once per file, from the Matroska record and the first keyframe, what is signalled and how samples change.
    static func decide(record: MKVDolbyVisionMapping?, firstKeyframe: [UInt8], lengthSize: Int, converter: (any DolbyVisionConverting)?,
                       transfer: Int?, width: Int, height: Int, framesPerSecond: Double, warnings: inout [String]) -> Decision {
        var facts = DolbyVisionFacts()
        facts.hdr10Plus = HDR10Plus.present(in: firstKeyframe, lengthSize: lengthSize)
        let first = converter?.inspect(sample: firstKeyframe, lengthSize: lengthSize)
        var source = record
        if source == nil, let first, first.profile == 7 || first.profile == 8 {
            // No record in the file (older muxers): derive it. PROVISIONAL: compatibility id from the signalled transfer for
            // profile 8 (PQ 1, HLG 4, otherwise 2); profile 7 is the disc layout (6). Alternative: play such files untouched.
            let compat = first.profile == 7 ? 6 : (transfer == 18 ? 4 : (transfer == 16 ? 1 : 2))
            source = .make(profile: first.profile, level: DolbyVisionLevel.level(width: width, height: height, framesPerSecond: framesPerSecond),
                           elPresent: first.profile == 7, compatibilityID: compat)
            facts.derived = true
            warnings.append("no Dolby Vision record in the file: derived profile \(first.profile) from the first RPU")
        } else if let rec = source, rec.profile == 8, let first, first.profile == 7 {
            // The record says profile 8 but the stream starts with a profile 7 section (some muxers write the record of a
            // later section, e.g. for a file that switches profile). The stream wins: every access unit goes through the
            // profile 7 conversion, its profile 8.1 sections included, as the reference tool does. PROVISIONAL: alternative is to
            // trust the record and convert only access units that carry an enhancement layer.
            source = .make(profile: 7, level: rec.level, elPresent: true, compatibilityID: 6)
            facts.derived = true
            warnings.append("the Dolby Vision record says profile 8 but the stream starts with profile 7: converting it")
        }
        facts.source = source
        guard let src = source else { return Decision(mode: .untouched, facts: facts, signalled: nil) }
        switch src.profile {
        case 7:
            facts.enhancementLayer = first?.enhancementLayer
            guard let converter else {
                warnings.append("Dolby Vision profile 7 without a converter: playing the HDR10 base layer")
                return Decision(mode: .baseLayerOnly, facts: facts, signalled: nil)
            }
            do {
                // Probe on the first keyframe: a file whose RPU the library rejects falls back to the base layer, and says so.
                let probe = try converter.convert(sample: firstKeyframe, lengthSize: lengthSize)
                guard !DolbyVisionNAL.hasEnhancementLayer(probe, lengthSize: lengthSize) else { throw RemuxError.malformed("enhancement layer left in the sample") }
                guard first != nil else { throw RemuxError.malformed("no readable RPU in the first keyframe") }
                return Decision(mode: .convertAll, facts: facts, signalled: converter.outputRecord(for: src))
            } catch {
                facts.conversionFailed = true
                warnings.append("Dolby Vision profile 7 conversion failed (\(error)): playing the HDR10 base layer")
                return Decision(mode: .baseLayerOnly, facts: facts, signalled: nil)
            }
        case 8:
            return Decision(mode: converter == nil ? .untouched : .convertWhereEnhancementLayer, facts: facts, signalled: src)
        default:
            return Decision(mode: .untouched, facts: facts, signalled: src)
        }
    }
}

public enum HDR10Plus {
    /// The start of an HDR10+ (SMPTE ST 2094-40) user_data_registered_itu_t_t35 SEI payload: country code 0xB5 (USA),
    /// terminal provider code 0x003C, provider oriented code 0x0001, application identifier 4.
    static let prefix: [UInt8] = [0xB5, 0x00, 0x3C, 0x00, 0x01, 0x04]

    /// True when a prefix SEI NAL unit (with its 2-byte header) holds an HDR10+ message (payloadType 4).
    public static func isHDR10PlusSEI(_ nal: ArraySlice<UInt8>) -> Bool {
        guard HEVCNAL.type(of: nal) == HEVCNAL.prefixSEI else { return false }
        return HEVCSEI.messages(inNAL: nal).contains { $0.type == 4 && $0.payload.starts(with: prefix) }
    }

    /// True when the length-prefixed access unit carries HDR10+ dynamic metadata.
    public static func present(in sample: [UInt8], lengthSize: Int) -> Bool {
        guard let nals = try? splitLengthPrefixed(sample, lengthSize: lengthSize) else { return false }
        return nals.contains(where: isHDR10PlusSEI)
    }
}
