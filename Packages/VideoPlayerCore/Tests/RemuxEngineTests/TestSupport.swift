import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Helpers shared by the RemuxEngine tests: a hand-built Matroska writer (so container logic is tested on bytes whose
// layout the test controls), lookup of the generated media, and a runner for ffmpeg / ffprobe / curl.

// MARK: EBML writing (independent of the parser under test)

enum EW {
    static func vint(_ n: Int) -> [UInt8] {
        var len = 1
        while len < 8 && n >= (1 << (7 * len)) - 1 { len += 1 }
        var out = [UInt8](repeating: 0, count: len)
        var v = n
        for i in stride(from: len - 1, through: 0, by: -1) { out[i] = UInt8(v & 0xFF); v >>= 8 }
        out[0] |= UInt8(0x80 >> (len - 1))
        return out
    }
    static func idBytes(_ id: UInt32) -> [UInt8] {
        var out: [UInt8] = []
        var v = id
        while v > 0 { out.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return out
    }
    static func el(_ id: UInt32, _ payload: [UInt8]) -> [UInt8] { idBytes(id) + vint(payload.count) + payload }
    static func uint(_ id: UInt32, _ v: UInt64, width: Int? = nil) -> [UInt8] {
        var bytes: [UInt8] = []
        var x = v
        repeat { bytes.insert(UInt8(x & 0xFF), at: 0); x >>= 8 } while x > 0
        if let w = width { while bytes.count < w { bytes.insert(0, at: 0) } }
        return el(id, bytes)
    }
    static func str(_ id: UInt32, _ s: String) -> [UInt8] { el(id, Array(s.utf8)) }
    static func float64(_ id: UInt32, _ d: Double) -> [UInt8] {
        let bits = d.bitPattern
        return el(id, (0..<8).map { UInt8((bits >> UInt64(56 - 8 * $0)) & 0xFF) })
    }
}

/// A small, valid-enough HEVC hvcC (the parameter sets are placeholders; `HEVCSPS.parse` returns nil for them).
func makeHvcC(profile: Int = 2, level: Int = 120, bitDepth: Int = 10, lengthSize: Int = 4, sps: [UInt8] = [0x42, 0x01, 0xAA, 0xBB, 0xCC, 0xDD]) -> [UInt8] {
    var w = ByteWriter()
    w.u8(1); w.u8(UInt8(profile)); w.u32(0x6000_0000)
    w.append([0x90, 0, 0, 0, 0, 0]); w.u8(UInt8(level))
    w.u16(0xF000); w.u8(0xFC); w.u8(0xFD); w.u8(0xF8 | UInt8(bitDepth - 8)); w.u8(0xF8 | UInt8(bitDepth - 8))
    w.u16(0); w.u8(UInt8(0x03 | ((lengthSize - 1) & 3)))
    w.u8(3)
    for (type, nal) in [(32, [0x40, 0x01, 0x0C, 0x01] as [UInt8]), (33, sps), (34, [0x44, 0x01, 0xC1, 0x72] as [UInt8])] {
        w.u8(0x80 | UInt8(type)); w.u16(1); w.u16(UInt16(nal.count)); w.append(nal)
    }
    return w.bytes
}

/// Inserts emulation prevention bytes (00 00 0x -> 00 00 03 0x).
func escapeRBSP(_ b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var zeros = 0
    for x in b {
        if zeros >= 2 && x <= 3 { out.append(3); zeros = 0 }
        out.append(x)
        zeros = x == 0 ? zeros + 1 : 0
    }
    return out
}

/// A prefix SEI NAL carrying the given messages (type, payload).
func makeSEINAL(_ messages: [(Int, [UInt8])], suffix: Bool = false) -> [UInt8] {
    var rbsp: [UInt8] = []
    for (t, p) in messages {
        var tt = t; while tt >= 255 { rbsp.append(0xFF); tt -= 255 }; rbsp.append(UInt8(tt))
        var sz = p.count; while sz >= 255 { rbsp.append(0xFF); sz -= 255 }; rbsp.append(UInt8(sz))
        rbsp += p
    }
    rbsp.append(0x80)
    return [UInt8((suffix ? 40 : 39) << 1), 0x01] + escapeRBSP(rbsp)
}

func lengthPrefixed(_ nals: [[UInt8]]) -> [UInt8] {
    var out: [UInt8] = []
    for n in nals { out += [UInt8(n.count >> 24), UInt8((n.count >> 16) & 0xFF), UInt8((n.count >> 8) & 0xFF), UInt8(n.count & 0xFF)] + n }
    return out
}

/// An AC-3 syncframe header (5.1, 48 kHz) padded to `size` bytes.
func makeAC3Frame(size: Int = 64, tag: UInt8 = 0) -> [UInt8] {
    // syncword, crc1, fscod=0 frmsizecod=28, bsid=8 bsmod=0 acmod=7 (3/2), cmixlev, surmixlev, lfeon=1
    var f: [UInt8] = [0x0B, 0x77, 0, 0, 0x1C, 0x40, 0xE0 | 0x00, 0]
    // bits after byte 5: bsid(5)=01000 bsmod(3)=000 -> 0x40; acmod(3)=111 cmix(2)=00 smix(2)=00 lfeon(1)=1 -> 0xE1
    f[6] = 0xE1
    while f.count < size { f.append(tag) }
    return f
}

// MARK: Synthetic Matroska file

/// A subtitle track for the synthetic file. FIXTURE: shaped like the subtitle tracks mkvmerge writes (BlockGroups with BlockDuration).
struct SynthSubtitle {
    var number: Int
    var codecID = "S_TEXT/UTF8"
    var language = "eng"
    var name = ""
    var isDefault = false
    var isForced = false
    var isHearingImpaired = false
    var zlib = false
    var cues: [(ms: Int, durMs: Int, payload: [UInt8])] = []
}

/// A zlib stream made of one stored (uncompressed) DEFLATE block with a correct Adler-32.
func zlibStored(_ bytes: [UInt8]) -> [UInt8] {
    var a: UInt32 = 1, b: UInt32 = 0
    for x in bytes { a = (a + UInt32(x)) % 65521; b = (b + a) % 65521 }
    let n = bytes.count
    precondition(n < 65536)
    var out: [UInt8] = [0x78, 0x01, 0x01, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
    out += bytes
    let adler = b << 16 | a
    out += [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)]
    return out
}

struct SynthMKV {
    var subtitles: [SynthSubtitle] = []
    var fps = 24
    var seconds = 6
    var gopFrames = 24
    var reorder = false
    var withCues = true
    var cuesAtEnd = false
    var audio = true
    var hdrSEI = true
    var colour = true
    var timecodeScale = 1_000_000
    var dolbyVisionProfile: Int? = nil
    var hvcC: [UInt8] = makeHvcC()
    /// Extra filler bytes in every video frame (to build high-bitrate files).
    var videoFrameExtra = 0

    struct Result {
        var data: Data
        var keyframeMs: [Int]
        /// (decode-order index, pts ms, isKey) of every video frame in file order.
        var videoFrames: [(pts: Int, key: Bool, payload: [UInt8])]
        var audioFrames: [(ms: Int, payload: [UInt8])]
        var segmentDataStart: Int
        var clusterOffsets: [Int]       // relative to the segment data start
        var mdcv: [UInt8]
        var clli: [UInt8]
    }

    // G(13250,34500) B(7500,3000) R(34000,16000) WP(15635,16450) max 10000000 min 1: the MKV Colour element below says the same.
    static let mdcv24: [UInt8] = [0x33, 0xC2, 0x86, 0xC4, 0x1D, 0x4C, 0x0B, 0xB8, 0x84, 0xD0, 0x3E, 0x80, 0x3D, 0x13, 0x40, 0x42, 0x00, 0x98, 0x96, 0x80, 0x00, 0x00, 0x00, 0x01]
    static let clliPayload: [UInt8] = [0x03, 0xE8, 0x01, 0x90]

    func ms(_ frame: Int) -> Int { Int((Double(frame) * 1000 / Double(fps)).rounded()) }

    func build() -> Result {
        var colourEl: [UInt8] = []
        if colour {
            var mm: [UInt8] = []
            mm += EW.el(EBMLID.primaryRX, EW.float4(0.68)) + EW.el(EBMLID.primaryRY, EW.float4(0.32))
            mm += EW.el(EBMLID.primaryGX, EW.float4(0.265)) + EW.el(EBMLID.primaryGY, EW.float4(0.69))
            mm += EW.el(EBMLID.primaryBX, EW.float4(0.15)) + EW.el(EBMLID.primaryBY, EW.float4(0.06))
            mm += EW.el(EBMLID.whiteX, EW.float4(0.3127)) + EW.el(EBMLID.whiteY, EW.float4(0.329))
            mm += EW.el(EBMLID.lumMax, EW.float4(1000)) + EW.el(EBMLID.lumMin, EW.float4(0.0001))
            colourEl = EW.el(EBMLID.colour,
                EW.uint(EBMLID.matrixCoefficients, 9) + EW.uint(EBMLID.range, 1) + EW.uint(EBMLID.transferCharacteristics, 16)
                + EW.uint(EBMLID.primaries, 9) + EW.uint(EBMLID.maxCLL, 1000) + EW.uint(EBMLID.maxFALL, 400)
                + EW.el(EBMLID.masteringMetadata, mm))
        }
        var videoEntry = EW.uint(EBMLID.trackNumber, 1) + EW.uint(EBMLID.trackUID, 11) + EW.uint(EBMLID.trackType, 1)
            + EW.str(EBMLID.codecID, "V_MPEGH/ISO/HEVC") + EW.el(EBMLID.codecPrivate, hvcC)
            + EW.uint(EBMLID.defaultDuration, UInt64(1_000_000_000 / fps))
            + EW.el(EBMLID.video, EW.uint(EBMLID.pixelWidth, 1280) + EW.uint(EBMLID.pixelHeight, 720) + colourEl)
        if let p = dolbyVisionProfile {
            var rec = ByteWriter()
            rec.u8(1); rec.u8(0)
            rec.u8(UInt8(p << 1) | 0)                 // profile (7 bits) + level high bit
            rec.u8(UInt8(6 << 3) | 0x04 | 0x01)       // level low bits, rpu_present, bl_present
            rec.u8(p == 5 ? 0x00 : 0x10)              // bl_signal_compatibility_id << 4
            rec.zeros(19)
            videoEntry += EW.el(EBMLID.blockAdditionMapping,
                                EW.uint(EBMLID.blockAddIDType, UInt64(p <= 7 ? 0x64766343 : 0x64767643)) + EW.el(EBMLID.blockAddIDExtraData, rec.bytes))
        }
        var tracks = EW.el(EBMLID.trackEntry, videoEntry)
        if audio {
            tracks += EW.el(EBMLID.trackEntry, EW.uint(EBMLID.trackNumber, 2) + EW.uint(EBMLID.trackUID, 12) + EW.uint(EBMLID.trackType, 2)
                + EW.str(EBMLID.codecID, "A_AC3") + EW.str(EBMLID.language, "eng") + EW.str(EBMLID.trackName, "English 5.1")
                + EW.el(EBMLID.audio, EW.float64(EBMLID.samplingFrequency, 48000) + EW.uint(EBMLID.channels, 6)))
            tracks += EW.el(EBMLID.trackEntry, EW.uint(EBMLID.trackNumber, 3) + EW.uint(EBMLID.trackUID, 13) + EW.uint(EBMLID.trackType, 2)
                + EW.str(EBMLID.codecID, "A_AAC") + EW.str(EBMLID.language, "fra") + EW.el(EBMLID.codecPrivate, [0x11, 0x90])
                + EW.el(EBMLID.audio, EW.float64(EBMLID.samplingFrequency, 48000) + EW.uint(EBMLID.channels, 2)))
            tracks += EW.el(EBMLID.trackEntry, EW.uint(EBMLID.trackNumber, 4) + EW.uint(EBMLID.trackUID, 14) + EW.uint(EBMLID.trackType, 2)
                + EW.str(EBMLID.codecID, "A_DTS") + EW.str(EBMLID.language, "eng")
                + EW.el(EBMLID.audio, EW.float64(EBMLID.samplingFrequency, 48000) + EW.uint(EBMLID.channels, 6)))
        }
        for s in subtitles {
            var entry = EW.uint(EBMLID.trackNumber, UInt64(s.number)) + EW.uint(EBMLID.trackUID, UInt64(100 + s.number)) + EW.uint(EBMLID.trackType, 17)
                + EW.str(EBMLID.codecID, s.codecID) + EW.str(EBMLID.language, s.language)
                + EW.uint(EBMLID.flagDefault, s.isDefault ? 1 : 0) + EW.uint(EBMLID.flagForced, s.isForced ? 1 : 0)
            if s.isHearingImpaired { entry += EW.uint(EBMLID.flagHearingImpaired, 1) }
            if !s.name.isEmpty { entry += EW.str(EBMLID.trackName, s.name) }
            if s.zlib {
                entry += EW.el(EBMLID.contentEncodings, EW.el(EBMLID.contentEncoding, EW.el(EBMLID.contentCompression, EW.uint(EBMLID.contentCompAlgo, 0))))
            }
            tracks += EW.el(EBMLID.trackEntry, entry)
        }
        tracks = EW.el(EBMLID.tracks, tracks)
        let info = EW.el(EBMLID.info, EW.uint(EBMLID.timecodeScale, UInt64(timecodeScale)) + EW.float64(EBMLID.duration, Double(seconds * 1000)))

        // Frames. Decode order inside a GOP with optional B-frame reordering (I P B B P B B ...).
        let total = fps * seconds
        var videoOrder: [Int] = []
        var g = 0
        while g * gopFrames < total {
            let base = g * gopFrames
            let n = min(gopFrames, total - base)
            videoOrder.append(base)
            if reorder {
                var k = 3
                while k < n { videoOrder += [base + k, base + k - 2, base + k - 1]; k += 3 }
                var rest = k - 2
                while rest < n { videoOrder.append(base + rest); rest += 1 }
            } else { var k = 1; while k < n { videoOrder.append(base + k); k += 1 } }
            g += 1
        }
        precondition(videoOrder.count == total && Set(videoOrder).count == total, "decode order must be a permutation")

        struct Block { var track: Int; var ms: Int; var key: Bool; var data: [UInt8]; var order: Double; var durMs: Int? = nil }
        var gops: [[Block]] = Array(repeating: [], count: (total + gopFrames - 1) / gopFrames)
        var videoFrames: [(pts: Int, key: Bool, payload: [UInt8])] = []
        var firstSEI: [UInt8] = []
        if hdrSEI { firstSEI = makeSEINAL([(137, Self.mdcv24), (144, Self.clliPayload)]) }
        for (decodeIndex, f) in videoOrder.enumerated() {
            let key = f % gopFrames == 0
            let payload = [UInt8(f >> 8), UInt8(f & 0xFF)] + [UInt8](repeating: UInt8(truncatingIfNeeded: f &* 7 &+ 1), count: 40 + (f % 13) + videoFrameExtra)
            var nals: [[UInt8]] = []
            if key && f == 0 && hdrSEI { nals.append(firstSEI) }
            nals.append((key ? [0x26, 0x01] : [0x02, 0x01]) + payload)
            let data = lengthPrefixed(nals)
            // Interleave key: decode time in ms (pts of the frame at the same decode position).
            let order = Double(ms(decodeIndex))
            gops[f / gopFrames].append(Block(track: 1, ms: ms(f), key: key, data: data, order: order))
            videoFrames.append((ms(f), key, data))
        }
        var audioFrames: [(ms: Int, payload: [UInt8])] = []
        if audio {
            let ac3Count = seconds * 1000 / 32
            for k in 0..<ac3Count {
                let t = k * 32
                let data = makeAC3Frame(size: 96, tag: UInt8(k & 0xFF))
                gops[min(gops.count - 1, t * fps / 1000 / gopFrames)].append(Block(track: 2, ms: t, key: true, data: data, order: Double(t)))
                audioFrames.append((t, data))
            }
            let aacCount = Int(Double(seconds) * 48000 / 1024)
            for k in 0..<aacCount {
                let t = Int((Double(k) * 1024 / 48.0).rounded())
                let data = [0x21, UInt8(k & 0xFF)] + [UInt8](repeating: UInt8(k & 0x7F), count: 30)
                gops[min(gops.count - 1, t * fps / 1000 / gopFrames)].append(Block(track: 3, ms: t, key: true, data: data, order: Double(t)))
            }
            for k in 0..<(seconds * 1000 / 32) {
                let t = k * 32
                let data: [UInt8] = [0x7F, 0xFE, 0x80, 0x01, UInt8(k & 0xFF), 0x55, 0x66, 0x77]
                gops[min(gops.count - 1, t * fps / 1000 / gopFrames)].append(Block(track: 4, ms: t, key: true, data: data, order: Double(t)))
            }
        }
        for s in subtitles {
            for c in s.cues {
                let data = s.zlib ? zlibStored(c.payload) : c.payload
                gops[min(gops.count - 1, c.ms * fps / 1000 / gopFrames)].append(Block(track: s.number, ms: c.ms, key: true, data: data, order: Double(c.ms), durMs: c.durMs))
            }
        }
        // Sort inside each GOP: the video keyframe first, then by order (audio and video interleaved by time).
        var clusters: [[UInt8]] = []
        var clusterStartsMs: [Int] = []
        for gop in gops {
            let key = gop.first(where: { $0.track == 1 && $0.key }) ?? gop[0]
            let rest = gop.filter { !($0.track == 1 && $0.key) }.sorted { $0.order < $1.order }
            let clusterMs = key.ms
            var body = EW.uint(EBMLID.clusterTimecode, UInt64(clusterMs * 1_000_000 / timecodeScale))
            for b in [key] + rest {
                let rel = (b.ms - clusterMs) * 1_000_000 / timecodeScale
                var blk = EW.vint(b.track)
                blk += [UInt8((rel >> 8) & 0xFF), UInt8(rel & 0xFF), b.key ? 0x80 : 0x00]
                blk += b.data
                if let d = b.durMs {
                    body += EW.el(EBMLID.blockGroup, EW.el(EBMLID.block, blk) + EW.uint(EBMLID.blockDuration, UInt64(d * 1_000_000 / timecodeScale)))
                } else {
                    body += EW.el(EBMLID.simpleBlock, blk)
                }
            }
            clusters.append(EW.el(EBMLID.cluster, body))
            clusterStartsMs.append(clusterMs)
        }
        // Layout: [SeekHead] Info Tracks [Cues] Clusters [Cues]
        func seekHead(cuesPos: Int) -> [UInt8] {
            EW.el(EBMLID.seekHead, EW.el(EBMLID.seek, EW.el(EBMLID.seekID, EW.idBytes(EBMLID.cues)) + EW.uint(EBMLID.seekPosition, UInt64(cuesPos), width: 4)))
        }
        func cuesBytes(_ offsets: [Int]) -> [UInt8] {
            var pts: [UInt8] = []
            for (i, off) in offsets.enumerated() {
                pts += EW.el(EBMLID.cuePoint, EW.uint(EBMLID.cueTime, UInt64(clusterStartsMs[i] * 1_000_000 / timecodeScale))
                    + EW.el(EBMLID.cueTrackPositions, EW.uint(EBMLID.cueTrack, 1) + EW.uint(EBMLID.cueClusterPosition, UInt64(off), width: 4)))
            }
            return EW.el(EBMLID.cues, pts)
        }
        let useSeekHead = withCues && cuesAtEnd
        let seekHeadLen = useSeekHead ? seekHead(cuesPos: 0).count : 0
        let dummyCues = withCues ? cuesBytes(Array(repeating: 0, count: clusters.count)).count : 0
        let headLen = seekHeadLen + info.count + tracks.count + ((withCues && !cuesAtEnd) ? dummyCues : 0)
        var offsets: [Int] = []
        var pos = headLen
        for c in clusters { offsets.append(pos); pos += c.count }
        let cues = withCues ? cuesBytes(offsets) : []
        var seg: [UInt8] = []
        if useSeekHead { seg += seekHead(cuesPos: pos) }
        seg += info + tracks
        if withCues && !cuesAtEnd { seg += cues }
        for c in clusters { seg += c }
        if withCues && cuesAtEnd { seg += cues }
        let header = EW.el(EBMLID.ebml, EW.str(0x4282, "matroska") + EW.uint(0x4287, 4) + EW.uint(0x4285, 2))
        let segHeaderLen = EW.idBytes(EBMLID.segment).count + EW.vint(seg.count).count
        let file = header + EW.el(EBMLID.segment, seg)
        return Result(data: Data(file), keyframeMs: clusterStartsMs, videoFrames: videoFrames, audioFrames: audioFrames,
                      segmentDataStart: header.count + segHeaderLen, clusterOffsets: offsets, mdcv: Self.mdcv24, clli: Self.clliPayload)
    }
}

extension EW {
    static func float4(_ d: Double) -> [UInt8] {
        let bits = Float(d).bitPattern
        return (0..<4).map { UInt8((bits >> UInt32(24 - 8 * $0)) & 0xFF) }
    }
}

// MARK: Generated media and external tools

enum TestMedia {
    static var toolsHome: String { ProcessInfo.processInfo.environment["VP_REMUX_TOOLS"] ?? (NSHomeDirectory() + "/vp-remux-spike") }
    static var mediaDir: String { ProcessInfo.processInfo.environment["VP_REMUX_MEDIA"] ?? (toolsHome + "/media") }

    /// The bytes of a generated file, or an XCTSkip (reported as skipped, never as passed) when it was not generated.
    static func load(_ name: String) throws -> Data {
        let p = mediaDir + "/" + name
        guard FileManager.default.fileExists(atPath: p), let d = FileManager.default.contents(atPath: p) else {
            throw XCTSkip("generated media \(p) is missing: run scripts/remux-generate.sh")
        }
        return d
    }
    static func path(_ name: String) throws -> String {
        let p = mediaDir + "/" + name
        guard FileManager.default.fileExists(atPath: p) else { throw XCTSkip("generated media \(p) is missing: run scripts/remux-generate.sh") }
        return p
    }
    static func tool(_ name: String) throws -> String {
        let p = toolsHome + "/tools/lgpl/bin/" + name
        guard FileManager.default.isExecutableFile(atPath: p) else { throw XCTSkip("\(p) is missing: run scripts/spikes/remux/00-setup.sh") }
        return p
    }
    static func curl() throws -> String {
        for p in ["/usr/bin/curl", "/bin/curl", "/usr/local/bin/curl"] where FileManager.default.isExecutableFile(atPath: p) { return p }
        throw XCTSkip("curl not installed")
    }
}

struct ProcessResult { var status: Int32; var out: String; var err: String }

func runProcess(_ exe: String, _ args: [String], timeout: TimeInterval = 120) throws -> ProcessResult {
    let dir = NSTemporaryDirectory()
    let outPath = dir + "/rx-out-\(UUID().uuidString)", errPath = dir + "/rx-err-\(UUID().uuidString)"
    FileManager.default.createFile(atPath: outPath, contents: nil); FileManager.default.createFile(atPath: errPath, contents: nil)
    defer { try? FileManager.default.removeItem(atPath: outPath); try? FileManager.default.removeItem(atPath: errPath) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardOutput = FileHandle(forWritingAtPath: outPath)
    p.standardError = FileHandle(forWritingAtPath: errPath)
    try p.run()
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    if p.isRunning { p.terminate(); throw RemuxError.io("\(exe) timed out") }
    let out = String(decoding: FileManager.default.contents(atPath: outPath) ?? Data(), as: UTF8.self)
    let err = String(decoding: FileManager.default.contents(atPath: errPath) ?? Data(), as: UTF8.self)
    return ProcessResult(status: p.terminationStatus, out: out, err: err)
}

/// A scratch directory removed after the test.
func makeTempDir() -> String {
    let d = NSTemporaryDirectory() + "/rx-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

final class ResultBox<T>: @unchecked Sendable { var result: Result<T, Error>? }

/// Synchronous await for tests that need it inside callbacks.
func blocking<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let sem = DispatchSemaphore(value: 0)
    Task { do { box.result = .success(try await body()) } catch { box.result = .failure(error) }; sem.signal() }
    sem.wait()
    switch box.result {
    case .success(let v): return v
    case .failure(let e): throw e
    case nil: throw RemuxError.io("blocking task produced no result")
    }
}
