import Foundation
import VideoPlayerCore
@testable import MetadataLocal

// A small Matroska writer for tests. There is no mkvmerge in this environment, so the files the reader is tested
// against are built here, byte by byte, from the Matroska specification. They are hand-written test data, not
// recordings of any real muxer: real MakeMKV / mkvmerge / ffmpeg quirks are NOT covered by anything that uses them.

enum W {
    /// Element ID bytes (IDs keep their marker bits, so they are written as they are).
    static func id(_ value: UInt32) -> [UInt8] {
        var out: [UInt8] = []
        var started = false
        var shift: UInt32 = 24
        while true {
            let byte = UInt8((value >> shift) & 0xFF)
            if byte != 0 || started { out.append(byte); started = true }
            if shift == 0 { break }
            shift -= 8
        }
        return out
    }

    /// A data size as an EBML variable-length integer, at least `minLength` bytes.
    static func size(_ n: Int, minLength: Int = 1) -> [UInt8] {
        var length = max(1, minLength)
        while length < 8 && n >= (1 << (7 * length)) - 1 { length += 1 }
        var out = [UInt8](repeating: 0, count: length)
        var v = UInt64(n)
        var i = length - 1
        while i >= 0 {
            out[i] = UInt8(v & 0xFF)
            v >>= 8
            i -= 1
        }
        out[0] |= UInt8(0x80 >> (length - 1))
        return out
    }

    static let unknownSize: [UInt8] = [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]

    static func element(_ idValue: UInt32, _ body: [UInt8], sizeLength: Int = 1) -> [UInt8] {
        id(idValue) + size(body.count, minLength: sizeLength) + body
    }

    static func unknownSizeElement(_ idValue: UInt32, _ body: [UInt8]) -> [UInt8] {
        id(idValue) + unknownSize + body
    }

    static func uintBody(_ v: UInt64, width: Int? = nil) -> [UInt8] {
        var bytes: [UInt8] = []
        var x = v
        repeat {
            bytes.insert(UInt8(x & 0xFF), at: 0)
            x >>= 8
        } while x > 0
        if let width { while bytes.count < width { bytes.insert(0, at: 0) } }
        return bytes
    }

    static func uint(_ idValue: UInt32, _ v: UInt64, width: Int? = nil) -> [UInt8] { element(idValue, uintBody(v, width: width)) }

    static func sint(_ idValue: UInt32, _ v: Int64) -> [UInt8] {
        var bytes: [UInt8] = []
        let raw = UInt64(bitPattern: v)
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((raw >> UInt64(shift)) & 0xFF)) }
        return element(idValue, bytes)
    }

    static func float64(_ idValue: UInt32, _ v: Double) -> [UInt8] {
        let bits = v.bitPattern
        return element(idValue, (0..<8).map { UInt8((bits >> UInt64(56 - 8 * $0)) & 0xFF) })
    }

    static func float32(_ idValue: UInt32, _ v: Float) -> [UInt8] {
        let bits = v.bitPattern
        return element(idValue, (0..<4).map { UInt8((bits >> UInt32(24 - 8 * $0)) & 0xFF) })
    }

    static func string(_ idValue: UInt32, _ s: String) -> [UInt8] { element(idValue, Array(s.utf8)) }

    static func master(_ idValue: UInt32, _ children: [[UInt8]], sizeLength: Int = 1) -> [UInt8] {
        element(idValue, children.flatMap { $0 }, sizeLength: sizeLength)
    }

    /// An EBML Void element that is exactly `total` bytes long (2 <= total).
    static func void(total: Int) -> [UInt8] {
        precondition(total >= 2)
        var sizeLen = 1
        while total - 1 - sizeLen >= (1 << (7 * sizeLen)) - 1 { sizeLen += 1 }
        let body = total - 1 - sizeLen
        return [0xEC] + size(body, minLength: sizeLen) + [UInt8](repeating: 0, count: body)
    }

    /// A real CRC-32 (IEEE) element, as the spec's first child of a master element.
    static func crc32Element(over payload: [UInt8]) -> [UInt8] {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in payload {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        crc = ~crc
        return element(MKV.crc32, [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 24) & 0xFF)])
    }
}

// MARK: Test model

struct TColour {
    var matrix: Int? = nil
    var transfer: Int? = nil
    var primaries: Int? = nil
    var range: Int? = nil
    var bits: Int? = nil
    var maxCLL: Int? = nil
    var maxFALL: Int? = nil
    var mastering: Bool = false
}

struct TTrack {
    var number = 1
    var uid: UInt64 = 1001
    var type = 1
    var codec = "V_MPEGH/ISO/HEVC"
    var name: String? = nil
    var language: String? = nil
    var bcp47: String? = nil
    var isDefault: Bool? = nil
    var isForced: Bool? = nil
    var isEnabled: Bool? = nil
    var isHearingImpaired: Bool? = nil
    var defaultDuration: UInt64? = nil
    var codecPrivate: [UInt8]? = nil
    var video: (w: Int, h: Int, dw: Int?, dh: Int?)? = nil
    var colour: TColour? = nil
    var dolbyVision: [UInt8]? = nil
    var dolbyVisionBox: UInt32 = 0x6476_7643
    var audio: (rate: Double, channels: Int, bits: Int?)? = nil
}

struct TDisplay {
    var title: String
    var languages: [String] = ["eng"]
    var bcp47: [String] = []
    var countries: [String] = []
}

struct TAtom {
    var uid: UInt64 = 1
    var start: UInt64
    var end: UInt64? = nil
    var hidden: Bool? = nil
    var enabled: Bool? = nil
    var displays: [TDisplay] = []
    var children: [TAtom] = []
}

struct TEdition {
    var uid: UInt64 = 1
    var hidden: Bool? = nil
    var isDefault: Bool? = nil
    var ordered: Bool? = nil
    var atoms: [TAtom] = []
}

struct TSimple {
    var name: String
    var string: String? = nil
    var language: String? = nil
    var children: [TSimple] = []
}

struct TTag {
    var targetValue: Int? = nil
    var targetType: String? = nil
    var trackUID: UInt64? = nil
    var simple: [TSimple] = []
}

struct TAttachment {
    var name: String
    var mime: String
    var data: [UInt8]
}

struct TInfo {
    var title: String? = "Test Movie"
    var muxingApp = "test-writer 1.0"
    var writingApp = "test-writer 1.0"
    var timecodeScale: UInt64 = 1_000_000
    /// In timecode units (so with the default scale, milliseconds).
    var duration: Double? = 5_400_000
    var dateUTC: Int64? = nil
}

struct TFile {
    var docType = "matroska"
    var info = TInfo()
    var tracks: [TTrack] = []
    var editions: [TEdition] = []
    var tags: [TTag] = []
    var attachments: [TAttachment] = []

    // Layout choices
    var seekHead = true
    var chaptersAtEnd = false
    var tagsAtEnd = false
    var unknownSizeSegment = false
    var unknownSizeClusters = false
    var crc = false
    var voidBetweenElements = false
    /// Void padding between the head elements and the first Cluster (as mkvmerge leaves room for later edits).
    var headPadding = 0
    var clusterCount = 2
    var clusterBytes = 2000
    var cues = true
    /// Bytes of garbage written between two head elements.
    var garbageAfterInfo = 0
}

/// A built file plus where its parts are, so tests can assert on offsets.
struct BuiltMKV {
    var bytes: [UInt8]
    var clusterRanges: [Range<Int>]
    var segmentDataStart: Int
    var chaptersOffset: Int?
    var tagsOffset: Int?
    var firstClusterOffset: Int
}

enum MKVBuilder {
    static func build(_ f: TFile) -> BuiltMKV {
        // Element bodies.
        func wrap(_ idValue: UInt32, _ children: [[UInt8]]) -> [UInt8] {
            let payload = children.flatMap { $0 }
            let body = f.crc ? W.crc32Element(over: payload) + payload : payload
            return W.element(idValue, body, sizeLength: 4)
        }
        let info = wrap(MKV.info, infoChildren(f.info))
        let tracks = wrap(MKV.tracks, f.tracks.map(trackEntry))
        let chapters: [UInt8]? = f.editions.isEmpty ? nil : wrap(MKV.chapters, f.editions.map(edition))
        let tags: [UInt8]? = f.tags.isEmpty ? nil : wrap(MKV.tags, f.tags.map(tag))
        let attachments: [UInt8]? = f.attachments.isEmpty ? nil : wrap(MKV.attachments, f.attachments.map(attached))

        var head: [(UInt32, [UInt8])] = [(MKV.info, info)]
        if f.garbageAfterInfo > 0 { head.append((0, [UInt8](repeating: 0xFF, count: f.garbageAfterInfo))) }
        head.append((MKV.tracks, tracks))
        if let chapters, !f.chaptersAtEnd { head.append((MKV.chapters, chapters)) }
        if let tags, !f.tagsAtEnd { head.append((MKV.tags, tags)) }
        if let attachments { head.append((MKV.attachments, attachments)) }

        var tail: [(UInt32, [UInt8])] = []
        if let chapters, f.chaptersAtEnd { tail.append((MKV.chapters, chapters)) }
        if let tags, f.tagsAtEnd { tail.append((MKV.tags, tags)) }
        let cuesElement = W.element(MKV.cues, W.master(0xBB, [W.uint(0xB3, 0), W.master(0xB7, [W.uint(0xF7, 1), W.uint(0xF1, 0)])]))
        if f.cues { tail.append((MKV.cues, cuesElement)) }

        func cluster(_ index: Int) -> [UInt8] {
            let block = [UInt8](repeating: UInt8(0xA0 &+ UInt8(index & 0xF)), count: f.clusterBytes)
            let body = W.uint(0xE7, UInt64(index) * 5000) + W.element(0xA3, [0x81, 0x00, 0x00, 0x80] + block)
            return f.unknownSizeClusters ? W.unknownSizeElement(MKV.cluster, body) : W.element(MKV.cluster, body, sizeLength: 4)
        }

        // SeekHead has a fixed size (4-byte positions), so positions can be computed before it is written.
        let seekIDs: [UInt32] = head.map { $0.0 }.filter { $0 != 0 } + (f.clusterCount > 0 ? [MKV.cluster] : []) + tail.map { $0.0 }
        func seekHead(_ positions: [Int]) -> [UInt8] {
            var entries: [[UInt8]] = []
            for (i, idValue) in seekIDs.enumerated() {
                entries.append(W.master(MKV.seek, [W.element(MKV.seekID, W.id(idValue)), W.uint(MKV.seekPosition, UInt64(positions[i]), width: 4)]))
            }
            return W.master(MKV.seekHead, entries, sizeLength: 2)
        }
        let seekSize = f.seekHead ? seekHead([Int](repeating: 0, count: seekIDs.count)).count : 0

        var body: [UInt8] = []
        var offsets: [UInt32: Int] = [:]
        var cursor = seekSize
        if f.voidBetweenElements { cursor += 9 }
        for (idValue, element) in head {
            if idValue != 0 { offsets[idValue] = cursor }
            cursor += element.count
            if f.voidBetweenElements { cursor += 7 }
        }
        cursor += f.headPadding
        let firstCluster = cursor
        var clusters: [[UInt8]] = []
        var clusterRangesRelative: [Range<Int>] = []
        for i in 0..<f.clusterCount {
            let c = cluster(i)
            clusterRangesRelative.append(cursor..<(cursor + c.count))
            clusters.append(c)
            cursor += c.count
        }
        for (idValue, element) in tail {
            offsets[idValue] = cursor
            cursor += element.count
        }
        if f.clusterCount > 0 { offsets[MKV.cluster] = firstCluster }
        let positions = seekIDs.map { offsets[$0] ?? 0 }

        if f.seekHead { body += seekHead(positions) }
        if f.voidBetweenElements { body += W.void(total: 9) }
        for (_, element) in head {
            body += element
            if f.voidBetweenElements { body += W.void(total: 7) }
        }
        if f.headPadding >= 2 { body += W.void(total: f.headPadding) }
        for c in clusters { body += c }
        for (_, element) in tail { body += element }

        let header = W.master(MKV.ebmlHeader, [
            W.uint(0x4286, 1), W.uint(0x42F7, 1), W.uint(0x42F2, 4), W.uint(0x42F3, 8),
            W.string(MKV.docType, f.docType), W.uint(0x4287, 4), W.uint(0x4285, 2),
        ])
        let segment = f.unknownSizeSegment
            ? W.unknownSizeElement(MKV.segment, body)
            : W.id(MKV.segment) + W.size(body.count, minLength: 8) + body
        let segmentHeaderLength = segment.count - body.count
        let start = header.count + segmentHeaderLength
        return BuiltMKV(
            bytes: header + segment,
            clusterRanges: clusterRangesRelative.map { ($0.lowerBound + start)..<($0.upperBound + start) },
            segmentDataStart: start,
            chaptersOffset: offsets[MKV.chapters].map { $0 + start },
            tagsOffset: offsets[MKV.tags].map { $0 + start },
            firstClusterOffset: firstCluster + start)
    }

    // MARK: Info

    static func infoChildren(_ i: TInfo) -> [[UInt8]] {
        var out: [[UInt8]] = [W.uint(MKV.timecodeScale, i.timecodeScale)]
        if let d = i.duration { out.append(W.float64(MKV.duration, d)) }
        if let t = i.title { out.append(W.string(MKV.title, t)) }
        out.append(W.string(MKV.muxingApp, i.muxingApp))
        out.append(W.string(MKV.writingApp, i.writingApp))
        if let date = i.dateUTC { out.append(W.sint(MKV.dateUTC, date)) }
        return out
    }

    // MARK: Tracks

    static func trackEntry(_ t: TTrack) -> [UInt8] {
        var c: [[UInt8]] = [W.uint(MKV.trackNumber, UInt64(t.number)), W.uint(MKV.trackUID, t.uid), W.uint(MKV.trackType, UInt64(t.type))]
        if let v = t.isEnabled { c.append(W.uint(MKV.flagEnabled, v ? 1 : 0)) }
        if let v = t.isDefault { c.append(W.uint(MKV.flagDefault, v ? 1 : 0)) }
        if let v = t.isForced { c.append(W.uint(MKV.flagForced, v ? 1 : 0)) }
        if let v = t.isHearingImpaired { c.append(W.uint(MKV.flagHearingImpaired, v ? 1 : 0)) }
        if let d = t.defaultDuration { c.append(W.uint(MKV.defaultDuration, d)) }
        if let n = t.name { c.append(W.string(MKV.name, n)) }
        if let l = t.language { c.append(W.string(MKV.language, l)) }
        if let b = t.bcp47 { c.append(W.string(MKV.languageBCP47, b)) }
        c.append(W.string(MKV.codecID, t.codec))
        if let p = t.codecPrivate { c.append(W.element(MKV.codecPrivate, p)) }
        if let v = t.video {
            var vc: [[UInt8]] = [W.uint(MKV.pixelWidth, UInt64(v.w)), W.uint(MKV.pixelHeight, UInt64(v.h))]
            if let dw = v.dw { vc.append(W.uint(MKV.displayWidth, UInt64(dw))) }
            if let dh = v.dh { vc.append(W.uint(MKV.displayHeight, UInt64(dh))) }
            if let col = t.colour { vc.append(colour(col)) }
            c.append(W.master(MKV.video, vc))
        }
        if let a = t.audio {
            var ac: [[UInt8]] = [W.float64(MKV.samplingFrequency, a.rate), W.uint(MKV.channels, UInt64(a.channels))]
            if let bits = a.bits { ac.append(W.uint(MKV.bitDepth, UInt64(bits))) }
            c.append(W.master(MKV.audio, ac))
        }
        if let dv = t.dolbyVision {
            c.append(W.master(MKV.blockAdditionMapping, [
                W.uint(0x41F0, 1), W.string(0x41A4, "Dolby Vision configuration"),
                W.uint(MKV.blockAddIDType, UInt64(t.dolbyVisionBox)), W.element(MKV.blockAddIDExtraData, dv),
            ]))
        }
        return W.master(MKV.trackEntry, c)
    }

    static func colour(_ col: TColour) -> [UInt8] {
        var c: [[UInt8]] = []
        if let v = col.matrix { c.append(W.uint(MKV.matrixCoefficients, UInt64(v))) }
        if let v = col.bits { c.append(W.uint(MKV.bitsPerChannel, UInt64(v))) }
        if let v = col.range { c.append(W.uint(MKV.range, UInt64(v))) }
        if let v = col.transfer { c.append(W.uint(MKV.transferCharacteristics, UInt64(v))) }
        if let v = col.primaries { c.append(W.uint(MKV.primaries, UInt64(v))) }
        if let v = col.maxCLL { c.append(W.uint(MKV.maxCLL, UInt64(v))) }
        if let v = col.maxFALL { c.append(W.uint(MKV.maxFALL, UInt64(v))) }
        if col.mastering {
            c.append(W.master(MKV.masteringMetadata, [
                W.float64(MKV.primaryRX, 0.68), W.float64(MKV.primaryRY, 0.32),
                W.float64(MKV.primaryGX, 0.265), W.float64(MKV.primaryGY, 0.69),
                W.float64(MKV.primaryBX, 0.15), W.float64(MKV.primaryBY, 0.06),
                W.float64(MKV.whiteX, 0.3127), W.float64(MKV.whiteY, 0.329),
                W.float64(MKV.luminanceMax, 1000), W.float64(MKV.luminanceMin, 0.0001),
            ]))
        }
        return W.master(MKV.colour, c)
    }

    /// A DOVIDecoderConfigurationRecord: profile, level, rpu/el/bl flags, base-layer compatibility id.
    static func dolbyVisionRecord(profile: Int, level: Int, rpu: Bool = true, el: Bool = false, bl: Bool = true, compat: Int) -> [UInt8] {
        let b2 = UInt8((profile << 1) | (level >> 5))
        let b3 = UInt8(((level & 0x1F) << 3) | ((rpu ? 1 : 0) << 2) | ((el ? 1 : 0) << 1) | (bl ? 1 : 0))
        return [1, 0, b2, b3, UInt8(compat << 4)] + [UInt8](repeating: 0, count: 19)
    }

    // MARK: Chapters

    static func edition(_ e: TEdition) -> [UInt8] {
        var c: [[UInt8]] = [W.uint(MKV.editionUID, e.uid)]
        if let v = e.hidden { c.append(W.uint(MKV.editionHidden, v ? 1 : 0)) }
        if let v = e.isDefault { c.append(W.uint(MKV.editionDefault, v ? 1 : 0)) }
        if let v = e.ordered { c.append(W.uint(MKV.editionOrdered, v ? 1 : 0)) }
        c.append(contentsOf: e.atoms.map(atom))
        return W.master(MKV.editionEntry, c)
    }

    static func atom(_ a: TAtom) -> [UInt8] {
        var c: [[UInt8]] = [W.uint(MKV.chapterUID, a.uid), W.uint(MKV.chapterTimeStart, a.start)]
        if let e = a.end { c.append(W.uint(MKV.chapterTimeEnd, e)) }
        if let v = a.hidden { c.append(W.uint(MKV.chapterHidden, v ? 1 : 0)) }
        if let v = a.enabled { c.append(W.uint(MKV.chapterEnabled, v ? 1 : 0)) }
        for d in a.displays {
            var dc: [[UInt8]] = [W.string(MKV.chapString, d.title)]
            dc.append(contentsOf: d.languages.map { W.string(MKV.chapLanguage, $0) })
            dc.append(contentsOf: d.bcp47.map { W.string(MKV.chapLanguageBCP47, $0) })
            dc.append(contentsOf: d.countries.map { W.string(MKV.chapCountry, $0) })
            c.append(W.master(MKV.chapterDisplay, dc))
        }
        c.append(contentsOf: a.children.map(atom))
        return W.master(MKV.chapterAtom, c)
    }

    // MARK: Tags

    static func tag(_ t: TTag) -> [UInt8] {
        var targets: [[UInt8]] = []
        if let v = t.targetValue { targets.append(W.uint(MKV.targetTypeValue, UInt64(v))) }
        if let v = t.targetType { targets.append(W.string(MKV.targetType, v)) }
        if let v = t.trackUID { targets.append(W.uint(MKV.tagTrackUID, v)) }
        return W.master(MKV.tag, [W.master(MKV.targets, targets)] + t.simple.map(simpleTag))
    }

    static func simpleTag(_ s: TSimple) -> [UInt8] {
        var c: [[UInt8]] = [W.string(MKV.tagName, s.name)]
        if let l = s.language { c.append(W.string(MKV.tagLanguage, l)) }
        if let v = s.string { c.append(W.string(MKV.tagString, v)) }
        c.append(contentsOf: s.children.map(simpleTag))
        return W.master(MKV.simpleTag, c)
    }

    // MARK: Attachments

    static func attached(_ a: TAttachment) -> [UInt8] {
        W.master(MKV.attachedFile, [
            W.string(MKV.fileName, a.name), W.string(MKV.fileMediaType, a.mime),
            W.uint(MKV.fileUID, UInt64(a.name.utf8.count) + 77), W.element(MKV.fileData, a.data),
        ])
    }
}

// MARK: Byte reader over an in-memory file

final class ReadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(offset: Int64, length: Int64)] = []
    func add(_ r: ByteRange) { lock.lock(); storage.append((r.offset, r.length)); lock.unlock() }
    var ranges: [(offset: Int64, length: Int64)] { lock.lock(); defer { lock.unlock() }; return storage }
    var totalBytes: Int64 { ranges.reduce(0) { $0 + $1.length } }
}

enum BeyondEnd { case empty, throwError }

/// A reader over `bytes` that logs every request. Reads past the end behave like a real source: a short or
/// empty answer, or `.rangeNotSatisfiable` when the offset is past the end.
func memoryReader(_ bytes: [UInt8], log: ReadLog = ReadLog(), beyondEnd: BeyondEnd = .throwError) -> MatroskaRangeReader {
    { range in
        log.add(range)
        let total = bytes.count
        if range.offset >= Int64(total) {
            switch beyondEnd {
            case .empty: return Data()
            case .throwError: throw SourceError.rangeNotSatisfiable
            }
        }
        let start = Int(range.offset)
        let end = min(total, start + Int(clamping: range.length))
        return Data(bytes[start..<end])
    }
}
