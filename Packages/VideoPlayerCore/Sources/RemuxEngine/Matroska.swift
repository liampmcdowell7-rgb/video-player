import Foundation
import VideoPlayerCore

// A minimal Matroska / WebM reader written for the remux engine. It is deliberately separate from the metadata
// reader in the MetadataLocal target (feature targets never depend on each other): this one reads everything the
// remuxer needs (tracks incl. colour and Dolby Vision mappings, cues, cluster layout, blocks) and nothing else.

enum EBMLID {
    static let ebml: UInt32 = 0x1A45DFA3
    static let segment: UInt32 = 0x18538067
    static let seekHead: UInt32 = 0x114D9B74
    static let seek: UInt32 = 0x4DBB
    static let seekID: UInt32 = 0x53AB
    static let seekPosition: UInt32 = 0x53AC
    static let info: UInt32 = 0x1549A966
    static let timecodeScale: UInt32 = 0x2AD7B1
    static let duration: UInt32 = 0x4489
    static let tracks: UInt32 = 0x1654AE6B
    static let trackEntry: UInt32 = 0xAE
    static let trackNumber: UInt32 = 0xD7
    static let trackUID: UInt32 = 0x73C5
    static let trackType: UInt32 = 0x83
    static let flagEnabled: UInt32 = 0xB9
    static let flagDefault: UInt32 = 0x88
    static let flagForced: UInt32 = 0x55AA
    static let flagHearingImpaired: UInt32 = 0x55AB
    static let flagCommentary: UInt32 = 0x55AF
    static let defaultDuration: UInt32 = 0x23E383
    static let trackName: UInt32 = 0x536E
    static let language: UInt32 = 0x22B59C
    static let languageBCP47: UInt32 = 0x22B59D
    static let codecID: UInt32 = 0x86
    static let codecPrivate: UInt32 = 0x63A2
    static let codecDelay: UInt32 = 0x56AA
    static let seekPreRoll: UInt32 = 0x56BB
    static let video: UInt32 = 0xE0
    static let pixelWidth: UInt32 = 0xB0
    static let pixelHeight: UInt32 = 0xBA
    static let displayWidth: UInt32 = 0x54B0
    static let displayHeight: UInt32 = 0x54BA
    static let colour: UInt32 = 0x55B0
    static let matrixCoefficients: UInt32 = 0x55B1
    static let range: UInt32 = 0x55B9
    static let transferCharacteristics: UInt32 = 0x55BA
    static let primaries: UInt32 = 0x55BB
    static let maxCLL: UInt32 = 0x55BC
    static let maxFALL: UInt32 = 0x55BD
    static let masteringMetadata: UInt32 = 0x55D0
    static let primaryRX: UInt32 = 0x55D1, primaryRY: UInt32 = 0x55D2
    static let primaryGX: UInt32 = 0x55D3, primaryGY: UInt32 = 0x55D4
    static let primaryBX: UInt32 = 0x55D5, primaryBY: UInt32 = 0x55D6
    static let whiteX: UInt32 = 0x55D7, whiteY: UInt32 = 0x55D8
    static let lumMax: UInt32 = 0x55D9, lumMin: UInt32 = 0x55DA
    static let audio: UInt32 = 0xE1
    static let samplingFrequency: UInt32 = 0xB5
    static let outputSamplingFrequency: UInt32 = 0x78B5
    static let channels: UInt32 = 0x9F
    static let bitDepth: UInt32 = 0x6264
    static let blockAdditionMapping: UInt32 = 0x41E4
    static let blockAddIDType: UInt32 = 0x41E7
    static let blockAddIDExtraData: UInt32 = 0x41ED
    static let contentEncodings: UInt32 = 0x6D80
    static let contentEncoding: UInt32 = 0x6240
    static let contentCompression: UInt32 = 0x5034
    static let contentCompAlgo: UInt32 = 0x4254
    static let contentCompSettings: UInt32 = 0x4255
    static let contentEncryption: UInt32 = 0x5035
    static let cues: UInt32 = 0x1C53BB6B
    static let cuePoint: UInt32 = 0xBB
    static let cueTime: UInt32 = 0xB3
    static let cueTrackPositions: UInt32 = 0xB7
    static let cueTrack: UInt32 = 0xF7
    static let cueClusterPosition: UInt32 = 0xF1
    static let cueRelativePosition: UInt32 = 0xF0
    static let cluster: UInt32 = 0x1F43B675
    static let clusterTimecode: UInt32 = 0xE7
    static let simpleBlock: UInt32 = 0xA3
    static let blockGroup: UInt32 = 0xA0
    static let block: UInt32 = 0xA1
    static let blockDuration: UInt32 = 0x9B
    static let referenceBlock: UInt32 = 0xFB
    static let void: UInt32 = 0xEC
    static let crc32: UInt32 = 0xBF
}

/// One element found while walking a buffer. Positions are indexes into that buffer.
struct EBMLElement {
    var id: UInt32
    var headerStart: Int
    var dataStart: Int
    var dataEnd: Int
    var sizeUnknown: Bool
}

enum EBML {
    /// Reads an element ID (marker bits kept). Returns (id, length).
    static func readID(_ b: [UInt8], _ pos: Int) throws -> (UInt32, Int) {
        guard pos < b.count else { throw RemuxError.truncated("EBML id at \(pos)") }
        let first = b[pos]
        if first == 0 { throw RemuxError.malformed("EBML id with 0 first byte at \(pos)") }
        let len = first.leadingZeroBitCount + 1
        guard len <= 4 else { throw RemuxError.malformed("EBML id longer than 4 bytes at \(pos)") }
        guard pos + len <= b.count else { throw RemuxError.truncated("EBML id at \(pos)") }
        var v: UInt32 = 0
        for i in 0..<len { v = v << 8 | UInt32(b[pos + i]) }
        return (v, len)
    }

    /// Reads a data size. Returns (size or nil when "unknown", length).
    static func readSize(_ b: [UInt8], _ pos: Int) throws -> (Int64?, Int) {
        guard pos < b.count else { throw RemuxError.truncated("EBML size at \(pos)") }
        let first = b[pos]
        if first == 0 { throw RemuxError.malformed("EBML size with 0 first byte at \(pos)") }
        let len = first.leadingZeroBitCount + 1
        guard pos + len <= b.count else { throw RemuxError.truncated("EBML size at \(pos)") }
        var v = UInt64(first) & ((1 << UInt64(8 - len)) - 1)
        var allOnes = v == (1 << UInt64(8 - len)) - 1
        for i in 1..<max(len, 1) where len > 1 {
            v = v << 8 | UInt64(b[pos + i])
            if b[pos + i] != 0xFF { allOnes = false }
        }
        if allOnes { return (nil, len) }
        guard v < UInt64(Int64.max) else { throw RemuxError.malformed("EBML size too large") }
        return (Int64(v), len)
    }

    /// The children of the element range [from, to) in `b`.
    static func children(_ b: [UInt8], from: Int, to: Int) throws -> [EBMLElement] {
        var out: [EBMLElement] = []
        var pos = from
        while pos < to {
            let (id, idLen) = try readID(b, pos)
            let (size, sizeLen) = try readSize(b, pos + idLen)
            let dataStart = pos + idLen + sizeLen
            let end: Int
            if let size { end = dataStart + Int(size) } else { end = to }
            guard end <= to else { throw RemuxError.truncated("element \(String(id, radix: 16)) at \(pos) ends past its parent") }
            out.append(EBMLElement(id: id, headerStart: pos, dataStart: dataStart, dataEnd: end, sizeUnknown: size == nil))
            pos = end
        }
        return out
    }

    static func uint(_ b: [UInt8], _ e: EBMLElement) -> UInt64 {
        var v: UInt64 = 0
        for i in e.dataStart..<min(e.dataEnd, e.dataStart + 8) { v = v << 8 | UInt64(b[i]) }
        return v
    }
    static func float(_ b: [UInt8], _ e: EBMLElement) -> Double {
        let n = e.dataEnd - e.dataStart
        var bits: UInt64 = 0
        for i in e.dataStart..<e.dataEnd { bits = bits << 8 | UInt64(b[i]) }
        if n == 4 { return Double(Float(bitPattern: UInt32(bits))) }
        if n == 8 { return Double(bitPattern: bits) }
        return 0
    }
    static func string(_ b: [UInt8], _ e: EBMLElement) -> String {
        var bytes = Array(b[e.dataStart..<e.dataEnd])
        while bytes.last == 0 { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self)
    }
    static func bytes(_ b: [UInt8], _ e: EBMLElement) -> [UInt8] { Array(b[e.dataStart..<e.dataEnd]) }
}

// MARK: Model

public enum MKVTrackType: Int, Sendable { case video = 1, audio = 2, subtitle = 17, other = 0 }

/// Colour description from the Matroska Colour element (CICP numbers as in ISO 23091-2).
public struct MKVColour: Equatable, Sendable {
    public var matrix: Int?
    public var range: Int?           // 0 unspecified, 1 limited (broadcast), 2 full
    public var transfer: Int?
    public var primaries: Int?
    public var maxCLL: Int?
    public var maxFALL: Int?
    /// Mastering display, chromaticities as 0...1 floats and luminance in cd/m^2.
    public var mastering: Mastering?

    public struct Mastering: Equatable, Sendable {
        public var rx: Double, ry: Double, gx: Double, gy: Double, bx: Double, by: Double
        public var wx: Double, wy: Double
        public var maxLuminance: Double, minLuminance: Double
    }
}

public struct MKVDolbyVisionMapping: Equatable, Sendable {
    /// 0x64766343 "dvcC" or 0x64767643 "dvvC".
    public var type: UInt32
    /// The 24-byte DOVIDecoderConfigurationRecord.
    public var record: [UInt8]
    /// Profile number from the record (bits 15..9 of the third and fourth byte).
    public var profile: Int { record.count >= 3 ? Int(record[2] >> 1) : 0 }
    public var level: Int { record.count >= 4 ? Int(record[2] & 1) << 5 | Int(record[3] >> 3) : 0 }
    public var rpuPresent: Bool { record.count >= 4 && record[3] & 0x04 != 0 }
    public var elPresent: Bool { record.count >= 4 && record[3] & 0x02 != 0 }
    public var blPresent: Bool { record.count >= 4 && record[3] & 0x01 != 0 }
    public var blCompatibilityID: Int { record.count >= 5 ? Int(record[4] >> 4) : 0 }
}

public struct MKVTrack: Equatable, Sendable {
    public var number: Int
    public var uid: UInt64
    public var type: MKVTrackType
    public var codecID: String
    public var codecPrivate: [UInt8]
    public var name: String
    public var language: String
    public var isDefault: Bool
    public var isEnabled: Bool
    public var defaultDurationNs: Int64?
    public var codecDelayNs: Int64
    public var seekPreRollNs: Int64
    // video
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var displayWidth: Int?
    public var displayHeight: Int?
    public var colour: MKVColour?
    public var dolbyVision: MKVDolbyVisionMapping?
    // audio
    public var sampleRate: Double
    public var channels: Int
    public var bitDepth: Int
    /// Header-stripping bytes (ContentCompAlgo 3) to put back in front of every frame of this track.
    public var strippedHeader: [UInt8]
    // subtitle flags and storage (defaults keep every existing initialiser call valid)
    public var isForced = false
    public var isHearingImpaired = false
    public var isCommentary = false
    /// Every block of this track is zlib compressed (ContentCompAlgo 0; mkvmerge uses it for subtitle tracks). Only subtitle
    /// tracks may use it: the engine inflates their blocks when it builds a rendition.
    public var zlibCompressed = false
}

public struct MKVCuePoint: Equatable, Sendable {
    public var timeNs: Int64
    public var track: Int
    /// Absolute file offset of the cluster.
    public var clusterOffset: Int64
    /// Offset of the block inside the cluster (from the cluster data start), when the muxer wrote it.
    public var relativePosition: Int64?
}

public struct MKVIndex: Sendable {
    public var timecodeScale: Int64
    public var durationNs: Int64
    public var tracks: [MKVTrack]
    public var cues: [MKVCuePoint]
    /// Absolute offset where the Segment data starts (SeekPosition values are relative to this).
    public var segmentDataStart: Int64
    /// Absolute offset of the first Cluster.
    public var firstClusterOffset: Int64
    /// Absolute end of the cluster region: the Cues position when they follow the clusters, else the file size.
    public var clusterRegionEnd: Int64
    public var fileSize: Int64
    /// True when the file has no Cues, so keyframes must come from `MatroskaClusterScanner`.
    public var needsClusterScan: Bool { cues.isEmpty }

    public func track(number: Int) -> MKVTrack? { tracks.first { $0.number == number } }
    public var videoTrack: MKVTrack? {
        tracks.filter { $0.type == .video && $0.isEnabled }.first(where: { $0.isDefault }) ?? tracks.first { $0.type == .video && $0.isEnabled }
    }
    public var audioTracks: [MKVTrack] { tracks.filter { $0.type == .audio && $0.isEnabled } }
    public var subtitleTracks: [MKVTrack] { tracks.filter { $0.type == .subtitle && $0.isEnabled } }
}

// MARK: Index loading

public enum MatroskaIndexer {
    /// Reads the Matroska header, tracks and cues using a few small reads (header walk) and one read for the cues.
    public static func load(from reader: any ByteRangeReader) async throws -> MKVIndex {
        let cached = BlockCachedReader(reader)
        let size = reader.size
        // EBML header.
        let head = try await cached.read(ByteRange(offset: 0, length: 64))
        let hb = [UInt8](head)
        let (hid, hl) = try EBML.readID(hb, 0)
        guard hid == EBMLID.ebml else { throw RemuxError.malformed("not an EBML file") }
        let (hsize, hsl) = try EBML.readSize(hb, hl)
        guard let hsize else { throw RemuxError.malformed("EBML header of unknown size") }
        var pos = Int64(hl + hsl) + hsize
        // Segment.
        let sh = [UInt8](try await cached.read(ByteRange(offset: pos, length: 16)))
        let (sid, sl) = try EBML.readID(sh, 0)
        guard sid == EBMLID.segment else { throw RemuxError.malformed("no Segment element") }
        let (ssize, ssl) = try EBML.readSize(sh, sl)
        let segStart = pos + Int64(sl + ssl)
        let segEnd = ssize.map { min(segStart + $0, size) } ?? size
        pos = segStart

        var timecodeScale: Int64 = 1_000_000
        var durationTicks: Double = 0
        var tracks: [MKVTrack] = []
        var cues: [MKVCuePoint] = []
        var firstCluster: Int64 = -1
        var seekTargets: [UInt32: Int64] = [:]
        var cuesPos: Int64? = nil
        var sawTracks = false

        walk: while pos < segEnd {
            let hdr = [UInt8](try await cached.read(ByteRange(offset: pos, length: 16)))
            if hdr.isEmpty { break }
            let (id, idl) = try EBML.readID(hdr, 0)
            let (esize, esl) = try EBML.readSize(hdr, idl)
            let dataStart = pos + Int64(idl + esl)
            guard let esize else {
                if id == EBMLID.cluster { firstCluster = pos; break walk }
                throw RemuxError.unsupported("unknown-size element \(String(id, radix: 16)) before the first cluster")
            }
            let dataEnd = dataStart + esize
            switch id {
            case EBMLID.cluster:
                firstCluster = pos
                break walk
            case EBMLID.seekHead, EBMLID.info, EBMLID.tracks, EBMLID.cues:
                guard esize <= 256 * 1024 * 1024 else { throw RemuxError.unsupported("header element too large") }
                let body = [UInt8](try await cached.read(ByteRange(offset: dataStart, length: esize)))
                guard Int64(body.count) == esize else { throw RemuxError.truncated("header element \(String(id, radix: 16))") }
                switch id {
                case EBMLID.seekHead: for (k, v) in try parseSeekHead(body) { seekTargets[k] = segStart + v }
                case EBMLID.info:
                    let r = try parseInfo(body)
                    timecodeScale = r.scale; durationTicks = r.duration
                case EBMLID.tracks: tracks = try parseTracks(body, timecodeScale: timecodeScale); sawTracks = true
                default:
                    cues = try parseCues(body, timecodeScale: timecodeScale, segmentStart: segStart)
                    cuesPos = pos
                }
            default:
                break   // Void, Tags, Chapters, Attachments: skipped
            }
            pos = dataEnd
        }

        // Elements that sit after the clusters (Tracks is legal there, Cues is the usual case): follow the SeekHead.
        if !sawTracks, let p = seekTargets[EBMLID.tracks] {
            let (body, _) = try await readElementBody(cached, at: p, expecting: EBMLID.tracks)
            tracks = try parseTracks(body, timecodeScale: timecodeScale); sawTracks = true
        }
        if cues.isEmpty, let p = seekTargets[EBMLID.cues] {
            let (body, _) = try await readElementBody(reader, at: p, expecting: EBMLID.cues)
            cues = try parseCues(body, timecodeScale: timecodeScale, segmentStart: segStart)
            cuesPos = p
        }
        guard sawTracks else { throw RemuxError.malformed("no Tracks element") }
        guard firstCluster >= 0 else { throw RemuxError.malformed("no Cluster found") }
        let regionEnd: Int64 = {
            if let c = cuesPos, c > firstCluster { return c }
            return segEnd
        }()
        cues.sort { $0.timeNs < $1.timeNs }
        return MKVIndex(timecodeScale: timecodeScale,
                        durationNs: Int64(durationTicks * Double(timecodeScale)),
                        tracks: tracks, cues: cues, segmentDataStart: segStart, firstClusterOffset: firstCluster,
                        clusterRegionEnd: regionEnd, fileSize: size)
    }

    private static func readElementBody(_ r: any ByteRangeReader, at pos: Int64, expecting: UInt32) async throws -> ([UInt8], Int64) {
        let hdr = [UInt8](try await r.read(ByteRange(offset: pos, length: 16)))
        let (id, idl) = try EBML.readID(hdr, 0)
        guard id == expecting else { throw RemuxError.malformed("SeekHead points at \(String(id, radix: 16)), expected \(String(expecting, radix: 16))") }
        let (size, sl) = try EBML.readSize(hdr, idl)
        guard let size, size <= 256 * 1024 * 1024 else { throw RemuxError.unsupported("seek target size") }
        let body = [UInt8](try await r.read(ByteRange(offset: pos + Int64(idl + sl), length: size)))
        guard Int64(body.count) == size else { throw RemuxError.truncated("element at \(pos)") }
        return (body, pos)
    }

    static func parseSeekHead(_ b: [UInt8]) throws -> [UInt32: Int64] {
        var out: [UInt32: Int64] = [:]
        for s in try EBML.children(b, from: 0, to: b.count) where s.id == EBMLID.seek {
            var id: UInt32?; var position: Int64?
            for c in try EBML.children(b, from: s.dataStart, to: s.dataEnd) {
                if c.id == EBMLID.seekID { id = UInt32(truncatingIfNeeded: EBML.uint(b, c)) }
                if c.id == EBMLID.seekPosition { position = Int64(EBML.uint(b, c)) }
            }
            if let id, let position { out[id] = position }
        }
        return out
    }

    static func parseInfo(_ b: [UInt8]) throws -> (scale: Int64, duration: Double) {
        var scale: Int64 = 1_000_000; var duration = 0.0
        for c in try EBML.children(b, from: 0, to: b.count) {
            if c.id == EBMLID.timecodeScale { scale = max(1, Int64(EBML.uint(b, c))) }
            if c.id == EBMLID.duration { duration = EBML.float(b, c) }
        }
        return (scale, duration)
    }

    static func parseTracks(_ b: [UInt8], timecodeScale: Int64) throws -> [MKVTrack] {
        var out: [MKVTrack] = []
        for e in try EBML.children(b, from: 0, to: b.count) where e.id == EBMLID.trackEntry {
            var t = MKVTrack(number: 0, uid: 0, type: .other, codecID: "", codecPrivate: [], name: "", language: "eng",
                             isDefault: true, isEnabled: true, defaultDurationNs: nil, codecDelayNs: 0, seekPreRollNs: 0,
                             pixelWidth: 0, pixelHeight: 0, displayWidth: nil, displayHeight: nil, colour: nil,
                             dolbyVision: nil, sampleRate: 8000, channels: 1, bitDepth: 0, strippedHeader: [])
            var bcp47: String?
            var encodingError: Error?
            for c in try EBML.children(b, from: e.dataStart, to: e.dataEnd) {
                switch c.id {
                case EBMLID.trackNumber: t.number = Int(EBML.uint(b, c))
                case EBMLID.trackUID: t.uid = EBML.uint(b, c)
                case EBMLID.trackType: t.type = MKVTrackType(rawValue: Int(EBML.uint(b, c))) ?? .other
                case EBMLID.flagDefault: t.isDefault = EBML.uint(b, c) != 0
                case EBMLID.flagForced: t.isForced = EBML.uint(b, c) != 0
                case EBMLID.flagHearingImpaired: t.isHearingImpaired = EBML.uint(b, c) != 0
                case EBMLID.flagCommentary: t.isCommentary = EBML.uint(b, c) != 0
                case EBMLID.flagEnabled: t.isEnabled = EBML.uint(b, c) != 0
                case EBMLID.defaultDuration: t.defaultDurationNs = Int64(EBML.uint(b, c))
                case EBMLID.trackName: t.name = EBML.string(b, c)
                case EBMLID.language: t.language = EBML.string(b, c)
                case EBMLID.languageBCP47: bcp47 = EBML.string(b, c)
                case EBMLID.codecID: t.codecID = EBML.string(b, c)
                case EBMLID.codecPrivate: t.codecPrivate = EBML.bytes(b, c)
                case EBMLID.codecDelay: t.codecDelayNs = Int64(EBML.uint(b, c))
                case EBMLID.seekPreRoll: t.seekPreRollNs = Int64(EBML.uint(b, c))
                case EBMLID.video: try parseVideo(b, c, into: &t)
                case EBMLID.audio: try parseAudio(b, c, into: &t)
                case EBMLID.blockAdditionMapping:
                    var type: UInt32 = 0; var extra: [UInt8] = []
                    for m in try EBML.children(b, from: c.dataStart, to: c.dataEnd) {
                        if m.id == EBMLID.blockAddIDType { type = UInt32(truncatingIfNeeded: EBML.uint(b, m)) }
                        if m.id == EBMLID.blockAddIDExtraData { extra = EBML.bytes(b, m) }
                    }
                    if type == 0x64766343 || type == 0x64767643 { t.dolbyVision = MKVDolbyVisionMapping(type: type, record: extra) }
                case EBMLID.contentEncodings:
                    // zlib compression is mkvmerge's default for subtitle tracks, which the engine never reads: only a video or
                    // audio track with an unsupported encoding is an error (checked after the whole entry is read).
                    do { let enc = try parseContentEncodings(b, c); t.strippedHeader = enc.header; t.zlibCompressed = enc.zlib } catch { encodingError = error }
                default: break
                }
            }
            if let encodingError, t.type == .video || t.type == .audio { throw encodingError }
            // zlib is read only for subtitle tracks (their blocks are inflated when a rendition is built).
            if t.zlibCompressed, t.type == .video || t.type == .audio {
                throw RemuxError.unsupported("Matroska content compression algorithm 0 (zlib) on a video or audio track")
            }
            if let bcp47, !bcp47.isEmpty, t.language == "eng" || t.language.isEmpty { t.language = bcp47 }
            if t.number == 0 { throw RemuxError.malformed("track without a number") }
            out.append(t)
        }
        return out
    }

    private static func parseContentEncodings(_ b: [UInt8], _ e: EBMLElement) throws -> (header: [UInt8], zlib: Bool) {
        var header: [UInt8] = []
        var zlib = false
        for enc in try EBML.children(b, from: e.dataStart, to: e.dataEnd) where enc.id == EBMLID.contentEncoding {
            for c in try EBML.children(b, from: enc.dataStart, to: enc.dataEnd) {
                if c.id == EBMLID.contentEncryption { throw RemuxError.unsupported("encrypted Matroska track") }
                if c.id == EBMLID.contentCompression {
                    var algo: UInt64 = 0; var settings: [UInt8] = []
                    for s in try EBML.children(b, from: c.dataStart, to: c.dataEnd) {
                        if s.id == EBMLID.contentCompAlgo { algo = EBML.uint(b, s) }
                        if s.id == EBMLID.contentCompSettings { settings = EBML.bytes(b, s) }
                    }
                    guard algo == 3 || algo == 0 else { throw RemuxError.unsupported("Matroska content compression algorithm \(algo) (only header stripping and zlib are supported)") }
                    if algo == 0 { zlib = true } else { header = settings }
                }
            }
        }
        return (header, zlib)
    }

    private static func parseVideo(_ b: [UInt8], _ e: EBMLElement, into t: inout MKVTrack) throws {
        for c in try EBML.children(b, from: e.dataStart, to: e.dataEnd) {
            switch c.id {
            case EBMLID.pixelWidth: t.pixelWidth = Int(EBML.uint(b, c))
            case EBMLID.pixelHeight: t.pixelHeight = Int(EBML.uint(b, c))
            case EBMLID.displayWidth: t.displayWidth = Int(EBML.uint(b, c))
            case EBMLID.displayHeight: t.displayHeight = Int(EBML.uint(b, c))
            case EBMLID.colour: t.colour = try parseColour(b, c)
            default: break
            }
        }
    }

    private static func parseColour(_ b: [UInt8], _ e: EBMLElement) throws -> MKVColour {
        var col = MKVColour()
        for c in try EBML.children(b, from: e.dataStart, to: e.dataEnd) {
            switch c.id {
            case EBMLID.matrixCoefficients: col.matrix = Int(EBML.uint(b, c))
            case EBMLID.range: col.range = Int(EBML.uint(b, c))
            case EBMLID.transferCharacteristics: col.transfer = Int(EBML.uint(b, c))
            case EBMLID.primaries: col.primaries = Int(EBML.uint(b, c))
            case EBMLID.maxCLL: col.maxCLL = Int(EBML.uint(b, c))
            case EBMLID.maxFALL: col.maxFALL = Int(EBML.uint(b, c))
            case EBMLID.masteringMetadata:
                var v: [UInt32: Double] = [:]
                for m in try EBML.children(b, from: c.dataStart, to: c.dataEnd) { v[m.id] = EBML.float(b, m) }
                if v[EBMLID.lumMax] != nil || v[EBMLID.primaryRX] != nil {
                    col.mastering = MKVColour.Mastering(
                        rx: v[EBMLID.primaryRX] ?? 0, ry: v[EBMLID.primaryRY] ?? 0, gx: v[EBMLID.primaryGX] ?? 0,
                        gy: v[EBMLID.primaryGY] ?? 0, bx: v[EBMLID.primaryBX] ?? 0, by: v[EBMLID.primaryBY] ?? 0,
                        wx: v[EBMLID.whiteX] ?? 0, wy: v[EBMLID.whiteY] ?? 0,
                        maxLuminance: v[EBMLID.lumMax] ?? 0, minLuminance: v[EBMLID.lumMin] ?? 0)
                }
            default: break
            }
        }
        return col
    }

    private static func parseAudio(_ b: [UInt8], _ e: EBMLElement, into t: inout MKVTrack) throws {
        for c in try EBML.children(b, from: e.dataStart, to: e.dataEnd) {
            switch c.id {
            case EBMLID.samplingFrequency: t.sampleRate = EBML.float(b, c)
            case EBMLID.channels: t.channels = Int(EBML.uint(b, c))
            case EBMLID.bitDepth: t.bitDepth = Int(EBML.uint(b, c))
            default: break
            }
        }
    }

    static func parseCues(_ b: [UInt8], timecodeScale: Int64, segmentStart: Int64) throws -> [MKVCuePoint] {
        var out: [MKVCuePoint] = []
        for cp in try EBML.children(b, from: 0, to: b.count) where cp.id == EBMLID.cuePoint {
            var time: Int64 = 0
            var positions: [(track: Int, cluster: Int64, rel: Int64?)] = []
            for c in try EBML.children(b, from: cp.dataStart, to: cp.dataEnd) {
                if c.id == EBMLID.cueTime { time = Int64(EBML.uint(b, c)) }
                if c.id == EBMLID.cueTrackPositions {
                    var track = 0; var cluster: Int64 = 0; var rel: Int64?
                    for p in try EBML.children(b, from: c.dataStart, to: c.dataEnd) {
                        if p.id == EBMLID.cueTrack { track = Int(EBML.uint(b, p)) }
                        if p.id == EBMLID.cueClusterPosition { cluster = Int64(EBML.uint(b, p)) }
                        if p.id == EBMLID.cueRelativePosition { rel = Int64(EBML.uint(b, p)) }
                    }
                    positions.append((track, cluster, rel))
                }
            }
            for p in positions {
                out.append(MKVCuePoint(timeNs: time * timecodeScale, track: p.track, clusterOffset: segmentStart + p.cluster, relativePosition: p.rel))
            }
        }
        return out
    }
}

// MARK: Frames

/// One block of a track.
public struct MKVFrame: Sendable {
    public var track: Int
    /// Presentation timestamp in nanoseconds.
    public var timeNs: Int64
    public var isKeyframe: Bool
    public var durationNs: Int64?
    public var data: ArraySlice<UInt8>
}

/// Parses Cluster elements out of a window of the file that starts exactly at a Cluster ID.
public enum MatroskaClusterParser {
    public struct Result: Sendable {
        public var frames: [MKVFrame]
        /// Absolute offset of the first byte after the last complete cluster that was parsed.
        public var endOffset: Int64
        /// True when the window ended in the middle of a cluster (those frames are not returned).
        public var endedInsideCluster: Bool
    }

    /// - Parameters:
    ///   - window: bytes of the file starting at `windowOffset`, which must be the start of a Cluster element.
    ///   - tracks: needed for header-stripping and lacing checks.
    ///   - timecodeScale: nanoseconds per tick.
    public static func parse(window: [UInt8], windowOffset: Int64, tracks: [MKVTrack], timecodeScale: Int64) throws -> Result {
        var frames: [MKVFrame] = []
        var defaultDurations: [Int: Int64] = [:]
        for t in tracks { if let d = t.defaultDurationNs { defaultDurations[t.number] = d } }
        let stripped: [Int: [UInt8]] = Dictionary(uniqueKeysWithValues: tracks.filter { !$0.strippedHeader.isEmpty }.map { ($0.number, $0.strippedHeader) })
        var pos = 0
        var endedInside = false
        while pos < window.count {
            let id: UInt32, idl: Int, size: Int64?, sl: Int
            do {
                (id, idl) = try EBML.readID(window, pos)
                (size, sl) = try EBML.readSize(window, pos + idl)
            } catch RemuxError.truncated { endedInside = true; break }
            if id != EBMLID.cluster {
                // Cues / Tags etc. after the last cluster end the cluster region.
                if id == EBMLID.cues || id == EBMLID.void || id == EBMLID.crc32 || id == EBMLID.seekHead || id == EBMLID.tracks || id == EBMLID.info {
                    break
                }
                throw RemuxError.malformed("unexpected element \(String(id, radix: 16)) at offset \(windowOffset + Int64(pos))")
            }
            let dataStart = pos + idl + sl
            let dataEnd: Int
            if let size {
                dataEnd = dataStart + Int(size)
                if dataEnd > window.count { endedInside = true; break }
            } else {
                // Unknown-size cluster (live capture): runs until the next top-level element.
                var q = dataStart
                while q < window.count {
                    guard let (cid, _) = try? EBML.readID(window, q) else { break }
                    if cid == EBMLID.cluster || cid == EBMLID.cues { break }
                    guard let (csz, csl) = try? EBML.readSize(window, q + (try EBML.readID(window, q).1)), let csz else { break }
                    q += (try EBML.readID(window, q).1) + csl + Int(csz)
                }
                dataEnd = min(q, window.count)
            }
            try parseClusterBody(window, dataStart, dataEnd, timecodeScale: timecodeScale, stripped: stripped, defaultDurations: defaultDurations, into: &frames)
            pos = dataEnd
        }
        return Result(frames: frames, endOffset: windowOffset + Int64(pos), endedInsideCluster: endedInside)
    }

    private static func parseClusterBody(_ b: [UInt8], _ from: Int, _ to: Int, timecodeScale: Int64,
                                         stripped: [Int: [UInt8]], defaultDurations: [Int: Int64], into frames: inout [MKVFrame]) throws {
        var clusterTime: Int64 = 0
        for e in try EBML.children(b, from: from, to: to) {
            switch e.id {
            case EBMLID.clusterTimecode: clusterTime = Int64(EBML.uint(b, e))
            case EBMLID.simpleBlock:
                frames += try block(b, e.dataStart, e.dataEnd, clusterTime: clusterTime, scale: timecodeScale, simple: true,
                                    duration: nil, referenced: false, stripped: stripped, defaultDurations: defaultDurations)
            case EBMLID.blockGroup:
                var blockEl: EBMLElement?; var dur: Int64?; var referenced = false
                for c in try EBML.children(b, from: e.dataStart, to: e.dataEnd) {
                    if c.id == EBMLID.block { blockEl = c }
                    if c.id == EBMLID.blockDuration { dur = Int64(EBML.uint(b, c)) * timecodeScale }
                    if c.id == EBMLID.referenceBlock { referenced = true }
                }
                if let blockEl {
                    frames += try block(b, blockEl.dataStart, blockEl.dataEnd, clusterTime: clusterTime, scale: timecodeScale,
                                        simple: false, duration: dur, referenced: referenced, stripped: stripped, defaultDurations: defaultDurations)
                }
            default: break
            }
        }
    }

    private static func block(_ b: [UInt8], _ from: Int, _ to: Int, clusterTime: Int64, scale: Int64, simple: Bool,
                              duration: Int64?, referenced: Bool, stripped: [Int: [UInt8]], defaultDurations: [Int: Int64]) throws -> [MKVFrame] {
        let (track, tl) = try EBML.readSize(b, from)
        guard let track else { throw RemuxError.malformed("block track number") }
        guard from + tl + 3 <= to else { throw RemuxError.truncated("block header") }
        let rel = Int16(bitPattern: UInt16(b[from + tl]) << 8 | UInt16(b[from + tl + 1]))
        let flags = b[from + tl + 2]
        let base = (clusterTime + Int64(rel)) * scale
        let key = simple ? (flags & 0x80 != 0) : !referenced
        let header = stripped[Int(track)] ?? []
        let payloadStart = from + tl + 3
        let lacing = (flags >> 1) & 0x03
        if lacing == 0 {
            let data: ArraySlice<UInt8> = header.isEmpty ? b[payloadStart..<to] : ArraySlice(header + b[payloadStart..<to])
            return [MKVFrame(track: Int(track), timeNs: base, isKeyframe: key, durationNs: duration, data: data)]
        }
        // Laced block (RFC 9559 section 10.3): 1 byte = frame count - 1, then the sizes of all frames but the last.
        // Found by the real-media tests: mkvmerge laces small audio and subtitle frames.
        guard payloadStart < to else { throw RemuxError.truncated("laced block header") }
        let count = Int(b[payloadStart]) + 1
        var pos = payloadStart + 1
        var sizes: [Int] = []
        if count > 1 {
            switch lacing {
            case 1: // Xiph: each size is a run of 255s ended by a byte below 255
                for _ in 0..<(count - 1) {
                    var s = 0
                    while true {
                        guard pos < to else { throw RemuxError.truncated("Xiph lace size") }
                        let v = Int(b[pos]); pos += 1; s += v
                        if v != 255 { break }
                    }
                    sizes.append(s)
                }
            case 3: // EBML: first size as an unsigned vint, the others as signed differences from the previous size
                let (first, fl) = try EBML.readSize(b, pos)
                guard let first else { throw RemuxError.malformed("EBML lace size") }
                pos += fl; sizes.append(Int(first))
                if count > 2 {
                    for _ in 1..<(count - 1) {
                        let (raw, l) = try EBML.readSize(b, pos)
                        guard let raw else { throw RemuxError.malformed("EBML lace size") }
                        pos += l
                        let bias = (Int64(1) << Int64(7 * l - 1)) - 1
                        let size = Int64(sizes[sizes.count - 1]) + (raw - bias)
                        guard size >= 0 else { throw RemuxError.malformed("negative EBML lace size") }
                        sizes.append(Int(size))
                    }
                }
            default: // fixed-size lacing: all frames equal
                let each = (to - pos) / count
                sizes = Array(repeating: each, count: count - 1)
            }
        }
        let lastSize = to - pos - sizes.reduce(0, +)
        guard lastSize >= 0 else { throw RemuxError.malformed("lace sizes exceed the block") }
        sizes.append(lastSize)
        // Frame times inside a laced block are not stored: they follow from the block duration or the track's default duration.
        let each: Int64
        if let duration { each = duration / Int64(count) }
        else if let d = defaultDurations[Int(track)], d > 0 { each = d }
        else { throw RemuxError.unsupported("laced Matroska block without a duration (track \(track))") }
        var frames: [MKVFrame] = []
        var p = pos
        for (i, s) in sizes.enumerated() {
            let slice: ArraySlice<UInt8> = header.isEmpty ? b[p..<(p + s)] : ArraySlice(header + b[p..<(p + s)])
            frames.append(MKVFrame(track: Int(track), timeNs: base + Int64(i) * each, isKeyframe: key, durationNs: each, data: slice))
            p += s
        }
        return frames
    }
}

// MARK: Cluster scan (files without Cues)

/// Walks cluster headers to find where clusters start and when. One small read per cluster.
/// Assumption (documented in docs/ENGINE_DESIGN.md): a cluster that contains a keyframe of the video track starts with
/// it. That is how mkvmerge and ffmpeg write files; a file that does not is reported as having fewer cut points.
public enum MatroskaClusterScanner {
    public static func scan(reader: any ByteRangeReader, index: MKVIndex, videoTrack: Int) async throws -> [MKVCuePoint] {
        let cached = BlockCachedReader(reader, blockSize: 64 * 1024, maxBlocks: 4)
        var pos = index.firstClusterOffset
        var out: [MKVCuePoint] = []
        while pos < index.clusterRegionEnd {
            if Task.isCancelled { throw RemuxError.cancelled }
            let head = [UInt8](try await reader.read(ByteRange(offset: pos, length: 4096)))
            if head.count < 12 { break }
            let (id, idl) = try EBML.readID(head, 0)
            guard id == EBMLID.cluster else { break }
            let (size, sl) = try EBML.readSize(head, idl)
            guard let size else { throw RemuxError.unsupported("unknown-size cluster in a file without Cues") }
            // Timecode is the first child by convention; first video block header follows within the 4 KiB head.
            var p = idl + sl
            var clusterTime: Int64 = 0
            var firstVideoKey: (Int64)? = nil
            let end = min(head.count, idl + sl + Int(min(size, Int64(head.count))))
            scanChildren: while p < end {
                guard let (cid, cl) = try? EBML.readID(head, p), let (csz, csl) = try? EBML.readSize(head, p + cl), let csz else { break }
                let ds = p + cl + csl
                if cid == EBMLID.clusterTimecode, ds + Int(csz) <= head.count {
                    var v: Int64 = 0; for i in ds..<(ds + Int(csz)) { v = v << 8 | Int64(head[i]) }
                    clusterTime = v
                } else if cid == EBMLID.simpleBlock, let (tn, tl) = try? EBML.readSize(head, ds), ds + tl + 3 <= head.count {
                    if Int(tn ?? -1) == videoTrack {
                        if head[ds + tl + 2] & 0x80 != 0 {
                            let rel = Int16(bitPattern: UInt16(head[ds + tl]) << 8 | UInt16(head[ds + tl + 1]))
                            firstVideoKey = clusterTime + Int64(rel)
                        }
                        break scanChildren
                    }
                } else if cid == EBMLID.blockGroup {
                    // A BlockGroup first block is a keyframe only when no ReferenceBlock follows; give up on this cluster.
                    break scanChildren
                }
                p = ds + Int(csz)
            }
            if let t = firstVideoKey {
                out.append(MKVCuePoint(timeNs: t * index.timecodeScale, track: videoTrack, clusterOffset: pos, relativePosition: nil))
            }
            pos += Int64(idl + sl) + size
        }
        _ = cached
        return out
    }

    /// Finds the next Cluster start at or after `offset` by searching for the Cluster ID and checking that the element
    /// after it is plausible. Used to resynchronise after a byte-offset jump (a seek to an estimated position).
    public static func resync(reader: any ByteRangeReader, from offset: Int64, limit: Int64, windowSize: Int = 256 * 1024) async throws -> Int64? {
        var pos = offset
        let id: [UInt8] = [0x1F, 0x43, 0xB6, 0x75]
        while pos < min(limit, reader.size) {
            let win = [UInt8](try await reader.read(ByteRange(offset: pos, length: Int64(windowSize))))
            if win.count < 8 { return nil }
            var i = 0
            while i + 8 <= win.count {
                if win[i] == id[0], win[i + 1] == id[1], win[i + 2] == id[2], win[i + 3] == id[3] {
                    if let (size, sl) = try? EBML.readSize(win, i + 4), let size, size > 0, i + 4 + sl + 1 <= win.count {
                        // The first child of a cluster is nearly always Timecode (E7) or Position/PrevSize/CRC.
                        let c = win[i + 4 + sl]
                        if c == 0xE7 || c == 0xA7 || c == 0xAB || c == 0xBF { return pos + Int64(i) }
                    }
                }
                i += 1
            }
            pos += Int64(win.count - 7)
        }
        return nil
    }
}
