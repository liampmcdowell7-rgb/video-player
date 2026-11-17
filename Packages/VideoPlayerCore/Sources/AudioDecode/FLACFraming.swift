import Foundation

// Pure helpers for the FLAC output: block size, frame renumbering (with both CRCs), the dfLa payload, and the channel
// layouts. No codec library calls here, so all of it is tested without the library.

public enum FLACFraming {
    /// Output block size by sample rate. PROVISIONAL (docs/AUDIO_PIPELINE.md): about 85 ms per block, inside the FLAC
    /// "subset" limits (at most 4608 samples up to 48 kHz, 16384 above). Alternative: 4608 / 9216 / 16384.
    public static func blockSize(sampleRate: Int) -> Int {
        if sampleRate <= 48000 { return 4096 }
        if sampleRate <= 96000 { return 8192 }
        return 16384
    }

    /// The codec-box payload for an fMP4 FLAC sample entry: one metadata block header (last block, type STREAMINFO,
    /// length 34) and the 34 STREAMINFO bytes.
    public static func dfLaPayload(streamInfo: [UInt8]) -> [UInt8] { [0x80, 0x00, 0x00, 0x22] + streamInfo }

    /// A complete .flac file from STREAMINFO and frames (tests and the device checklist use it to listen to the output).
    public static func file(streamInfo: [UInt8], frames: [[UInt8]]) -> [UInt8] {
        var out = Array("fLaC".utf8) + dfLaPayload(streamInfo: streamInfo)
        for f in frames { out += f }
        return out
    }

    /// Rewrites the frame number of a fixed-block-size FLAC frame and recomputes CRC-8 (header) and CRC-16 (frame).
    /// The encoder numbers frames from 0 every time it is opened; the output is numbered on the track's own block grid
    /// instead, so frames from different encoder sessions (after a seek) still form one valid stream.
    /// Returns nil when the bytes are not a fixed-block-size FLAC frame.
    public static func renumber(_ f: [UInt8], frameNumber: Int64) -> [UInt8]? {
        guard f.count >= 8, f[0] == 0xFF, f[1] == 0xF8, frameNumber >= 0, frameNumber < (1 << 31) else { return nil }
        let bsCode = Int(f[2] >> 4), rateCode = Int(f[2] & 0x0F)
        guard let numLen = utf8Length(lead: f[4]) else { return nil }
        let bsExtra = bsCode == 6 ? 1 : (bsCode == 7 ? 2 : 0)
        let rateExtra = rateCode == 12 ? 1 : ((rateCode == 13 || rateCode == 14) ? 2 : 0)
        let crc8At = 4 + numLen + bsExtra + rateExtra
        guard f.count > crc8At + 2 else { return nil }
        var header = Array(f[0..<4]) + utf8Number(frameNumber) + Array(f[(4 + numLen)..<crc8At])
        header.append(crc8(header))
        var out = header + Array(f[(crc8At + 1)..<(f.count - 2)])
        let c = crc16(out)
        out.append(UInt8(c >> 8)); out.append(UInt8(c & 0xFF))
        return out
    }

    /// Frame number stored in a FLAC frame header (nil when it is not a frame).
    public static func frameNumber(_ f: [UInt8]) -> Int64? {
        guard f.count >= 6, f[0] == 0xFF, f[1] & 0xFE == 0xF8, let n = utf8Length(lead: f[4]), f.count >= 4 + n else { return nil }
        if n == 1 { return Int64(f[4]) }
        var v = Int64(f[4]) & Int64((1 << (7 - n)) - 1)
        for i in 1..<n { v = (v << 6) | Int64(f[4 + i] & 0x3F) }
        return v
    }

    static func utf8Length(lead: UInt8) -> Int? {
        if lead & 0x80 == 0 { return 1 }
        if lead & 0xE0 == 0xC0 { return 2 }
        if lead & 0xF0 == 0xE0 { return 3 }
        if lead & 0xF8 == 0xF0 { return 4 }
        if lead & 0xFC == 0xF8 { return 5 }
        if lead & 0xFE == 0xFC { return 6 }
        if lead == 0xFE { return 7 }
        return nil
    }

    static func utf8Number(_ v: Int64) -> [UInt8] {
        if v < 0x80 { return [UInt8(v)] }
        let n: Int
        switch v {
        case ..<0x800: n = 2
        case ..<0x10000: n = 3
        case ..<0x200000: n = 4
        case ..<0x4000000: n = 5
        default: n = 6
        }
        var out = [UInt8](repeating: 0, count: n)
        var x = v
        for i in stride(from: n - 1, through: 1, by: -1) { out[i] = 0x80 | UInt8(x & 0x3F); x >>= 6 }
        let leadMark: UInt8 = UInt8((0xFF << (8 - n)) & 0xFF)
        out[0] = leadMark | UInt8(x)
        return out
    }

    public static func crc8(_ b: [UInt8]) -> UInt8 {
        var c: UInt8 = 0
        for x in b {
            c ^= x
            for _ in 0..<8 { c = c & 0x80 != 0 ? (c << 1) ^ 0x07 : c << 1 }
        }
        return c
    }

    public static func crc16(_ b: [UInt8]) -> UInt16 {
        var c: UInt16 = 0
        for x in b {
            c ^= UInt16(x) << 8
            for _ in 0..<8 { c = c & 0x8000 != 0 ? (c << 1) ^ 0x8005 : c << 1 }
        }
        return c
    }
}

/// Speaker positions, numbered like the codec library's native channel-mask bits.
public enum Speaker: Int, CaseIterable, Sendable {
    case frontLeft = 0, frontRight, frontCenter, lfe, backLeft, backRight, frontLeftOfCenter, frontRightOfCenter, backCenter
    case sideLeft, sideRight, topCenter, topFrontLeft, topFrontCenter, topFrontRight, topBackLeft, topBackCenter, topBackRight

    public var shortName: String {
        ["FL", "FR", "FC", "LFE", "BL", "BR", "FLC", "FRC", "BC", "SL", "SR", "TC", "TFL", "TFC", "TFR", "TBL", "TBC", "TBR"][rawValue]
    }
}

/// How decoded channels are placed in a FLAC output layout.
public struct ChannelLayoutMap: Equatable, Sendable {
    /// Speakers of the output, in FLAC order.
    public var output: [Speaker]
    /// For each output channel, the index of the decoded channel that feeds it (nil: silence).
    public var sourceIndex: [Int?]
    /// Decoded channels that have no place in the output (short names).
    public var dropped: [String]

    /// The FLAC channel orders (FLAC format specification, "Channels bits"): 1 mono, 2 L R, 3 L R C, 4 FL FR BL BR,
    /// 5 FL FR FC BL BR, 6 FL FR FC LFE BL BR, 7 FL FR FC LFE BC SL SR, 8 FL FR FC LFE BL BR SL SR.
    public static let flacLayouts: [[Speaker]] = [
        [.frontCenter],
        [.frontLeft, .frontRight],
        [.frontLeft, .frontRight, .frontCenter],
        [.frontLeft, .frontRight, .backLeft, .backRight],
        [.frontLeft, .frontRight, .frontCenter, .backLeft, .backRight],
        [.frontLeft, .frontRight, .frontCenter, .lfe, .backLeft, .backRight],
        [.frontLeft, .frontRight, .frontCenter, .lfe, .backCenter, .sideLeft, .sideRight],
        [.frontLeft, .frontRight, .frontCenter, .lfe, .backLeft, .backRight, .sideLeft, .sideRight],
    ]

    /// Decoded channel order for a channel mask (ascending bits). Mask 0 (no named layout): the FLAC order of that count.
    public static func speakers(mask: UInt64, channels: Int) -> [Speaker?] {
        if mask == 0 {
            guard channels >= 1, channels <= 8 else { return Array(repeating: nil, count: channels) }
            return flacLayouts[channels - 1].map { Optional($0) }
        }
        var out: [Speaker?] = []
        for bit in 0..<64 where mask & (UInt64(1) << UInt64(bit)) != 0 { out.append(Speaker(rawValue: bit)) }
        while out.count < channels { out.append(nil) }
        return Array(out.prefix(channels))
    }

    /// Places `source` into `layout`: exact positions first, then surround pairs into the other surround pair
    /// (side into back, back into side) when that slot is free. Anything else is dropped.
    public static func assign(source: [Speaker?], to layout: [Speaker]) -> ChannelLayoutMap {
        var slots = [Int?](repeating: nil, count: layout.count)
        var used = Set<Int>()
        for (i, s) in source.enumerated() { if let s, let at = layout.firstIndex(of: s), slots[at] == nil { slots[at] = i; used.insert(i) } }
        let alias: [Speaker: Speaker] = [.sideLeft: .backLeft, .sideRight: .backRight, .backLeft: .sideLeft, .backRight: .sideRight]
        for (i, s) in source.enumerated() where !used.contains(i) {
            if let s, let a = alias[s], let at = layout.firstIndex(of: a), slots[at] == nil { slots[at] = i; used.insert(i) }
        }
        var dropped: [String] = []
        for (i, s) in source.enumerated() where !used.contains(i) { dropped.append(s?.shortName ?? "ch\(i + 1)") }
        return ChannelLayoutMap(output: layout, sourceIndex: slots, dropped: dropped)
    }

    /// The smallest FLAC layout that holds every decoded channel (silent channels fill the gaps); 8 channels when none
    /// holds them all (the rest is dropped and reported).
    public static func choose(mask: UInt64, channels: Int) -> ChannelLayoutMap {
        let src = speakers(mask: mask, channels: channels)
        for layout in flacLayouts where layout.count >= min(channels, 8) {
            let m = assign(source: src, to: layout)
            if m.dropped.isEmpty { return m }
        }
        return assign(source: src, to: flacLayouts[7])
    }
}

/// Splits a TrueHD block into its access units and any Dolby Digital (AC-3) syncframes carried in the same track.
public enum TrueHDCoreSplitter {
    public struct Parts: Equatable, Sendable {
        public var trueHD: [ArraySlice<UInt8>] = []
        public var ac3: [ArraySlice<UInt8>] = []
    }

    // AC-3 frame sizes in 16-bit words, by frmsizecod / 2 (ATSC A/52, table 5.18).
    private static let words48: [Int] = [64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512, 640, 768, 896, 1024, 1152, 1280]
    private static let words441: [Int] = [69, 87, 104, 121, 139, 174, 208, 243, 278, 348, 417, 487, 557, 696, 835, 975, 1114, 1253, 1393]

    /// Byte length of the AC-3 syncframe at `p`, or nil when the bytes there are not one.
    public static func ac3FrameLength(_ b: ArraySlice<UInt8>, at p: Int) -> Int? {
        guard p + 5 <= b.endIndex, b[p] == 0x0B, b[p + 1] == 0x77 else { return nil }
        let fscod = Int(b[p + 4] >> 6), frmsizecod = Int(b[p + 4] & 0x3F)
        let bsid = p + 5 < b.endIndex ? Int(b[p + 5] >> 3) : 0
        guard frmsizecod < 38, bsid <= 10 else { return nil }
        switch fscod {
        case 0: return words48[frmsizecod >> 1] * 2
        case 1: return (words441[frmsizecod >> 1] + (frmsizecod & 1)) * 2
        case 2: return words48[frmsizecod >> 1] * 3
        default: return nil
        }
    }

    public static func split(_ b: ArraySlice<UInt8>) -> Parts {
        var parts = Parts()
        var p = b.startIndex
        while p + 4 <= b.endIndex {
            if let n = ac3FrameLength(b, at: p), p + n <= b.endIndex {
                parts.ac3.append(b[p..<(p + n)]); p += n; continue
            }
            // TrueHD access unit: 4-bit check nibble, 12-bit length in 16-bit words, 16-bit timing.
            let len = (Int(b[p] & 0x0F) << 8 | Int(b[p + 1])) * 2
            guard len >= 4, p + len <= b.endIndex else { break }
            parts.trueHD.append(b[p..<(p + len)]); p += len
        }
        if p < b.endIndex { parts.trueHD.append(b[p..<b.endIndex]) }
        return parts
    }
}
