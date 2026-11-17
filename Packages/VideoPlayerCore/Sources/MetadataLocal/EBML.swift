import Foundation

// EBML primitives (the binary format Matroska and WebM are written in). Pure functions over byte arrays;
// every function checks bounds and returns nil instead of trapping, so damaged input can never crash.

/// Element IDs from the Matroska specification. IDs keep their length marker bits, as the spec writes them.
enum MKV {
    static let ebmlHeader: UInt32 = 0x1A45DFA3
    static let docType: UInt32 = 0x4282
    static let segment: UInt32 = 0x18538067
    static let seekHead: UInt32 = 0x114D9B74
    static let seek: UInt32 = 0x4DBB
    static let seekID: UInt32 = 0x53AB
    static let seekPosition: UInt32 = 0x53AC
    static let info: UInt32 = 0x1549A966
    static let timecodeScale: UInt32 = 0x2AD7B1
    static let duration: UInt32 = 0x4489
    static let dateUTC: UInt32 = 0x4461
    static let title: UInt32 = 0x7BA9
    static let muxingApp: UInt32 = 0x4D80
    static let writingApp: UInt32 = 0x5741
    static let segmentUID: UInt32 = 0x73A4
    static let tracks: UInt32 = 0x1654AE6B
    static let trackEntry: UInt32 = 0xAE
    static let trackNumber: UInt32 = 0xD7
    static let trackUID: UInt32 = 0x73C5
    static let trackType: UInt32 = 0x83
    static let flagEnabled: UInt32 = 0xB9
    static let flagDefault: UInt32 = 0x88
    static let flagForced: UInt32 = 0x55AA
    static let flagHearingImpaired: UInt32 = 0x55AB
    static let flagVisualImpaired: UInt32 = 0x55AC
    static let flagTextDescriptions: UInt32 = 0x55AD
    static let flagOriginal: UInt32 = 0x55AE
    static let flagCommentary: UInt32 = 0x55AF
    static let defaultDuration: UInt32 = 0x23E383
    static let name: UInt32 = 0x536E
    static let language: UInt32 = 0x22B59C
    static let languageBCP47: UInt32 = 0x22B59D
    static let codecID: UInt32 = 0x86
    static let codecPrivate: UInt32 = 0x63A2
    static let codecName: UInt32 = 0x258688
    static let contentEncodings: UInt32 = 0x6D80
    static let video: UInt32 = 0xE0
    static let flagInterlaced: UInt32 = 0x9A
    static let pixelWidth: UInt32 = 0xB0
    static let pixelHeight: UInt32 = 0xBA
    static let displayWidth: UInt32 = 0x54B0
    static let displayHeight: UInt32 = 0x54BA
    static let colour: UInt32 = 0x55B0
    static let matrixCoefficients: UInt32 = 0x55B1
    static let bitsPerChannel: UInt32 = 0x55B2
    static let range: UInt32 = 0x55B9
    static let transferCharacteristics: UInt32 = 0x55BA
    static let primaries: UInt32 = 0x55BB
    static let maxCLL: UInt32 = 0x55BC
    static let maxFALL: UInt32 = 0x55BD
    static let masteringMetadata: UInt32 = 0x55D0
    static let primaryRX: UInt32 = 0x55D1
    static let primaryRY: UInt32 = 0x55D2
    static let primaryGX: UInt32 = 0x55D3
    static let primaryGY: UInt32 = 0x55D4
    static let primaryBX: UInt32 = 0x55D5
    static let primaryBY: UInt32 = 0x55D6
    static let whiteX: UInt32 = 0x55D7
    static let whiteY: UInt32 = 0x55D8
    static let luminanceMax: UInt32 = 0x55D9
    static let luminanceMin: UInt32 = 0x55DA
    static let audio: UInt32 = 0xE1
    static let samplingFrequency: UInt32 = 0xB5
    static let outputSamplingFrequency: UInt32 = 0x78B5
    static let channels: UInt32 = 0x9F
    static let bitDepth: UInt32 = 0x6264
    static let blockAdditionMapping: UInt32 = 0x41E4
    static let blockAddIDType: UInt32 = 0x41E7
    static let blockAddIDExtraData: UInt32 = 0x41ED
    static let chapters: UInt32 = 0x1043A770
    static let editionEntry: UInt32 = 0x45B9
    static let editionUID: UInt32 = 0x45BC
    static let editionHidden: UInt32 = 0x45BD
    static let editionDefault: UInt32 = 0x45DB
    static let editionOrdered: UInt32 = 0x45DD
    static let chapterAtom: UInt32 = 0xB6
    static let chapterUID: UInt32 = 0x73C4
    static let chapterStringUID: UInt32 = 0x5654
    static let chapterTimeStart: UInt32 = 0x91
    static let chapterTimeEnd: UInt32 = 0x92
    static let chapterHidden: UInt32 = 0x98
    static let chapterEnabled: UInt32 = 0x4598
    static let chapterDisplay: UInt32 = 0x80
    static let chapString: UInt32 = 0x85
    static let chapLanguage: UInt32 = 0x437C
    static let chapLanguageBCP47: UInt32 = 0x437D
    static let chapCountry: UInt32 = 0x437E
    static let tags: UInt32 = 0x1254C367
    static let tag: UInt32 = 0x7373
    static let targets: UInt32 = 0x63C0
    static let targetTypeValue: UInt32 = 0x68CA
    static let targetType: UInt32 = 0x63CA
    static let tagTrackUID: UInt32 = 0x63C5
    static let tagEditionUID: UInt32 = 0x63C9
    static let tagChapterUID: UInt32 = 0x63C4
    static let tagAttachmentUID: UInt32 = 0x63C6
    static let simpleTag: UInt32 = 0x67C8
    static let tagName: UInt32 = 0x45A3
    static let tagLanguage: UInt32 = 0x447A
    static let tagLanguageBCP47: UInt32 = 0x447B
    static let tagDefault: UInt32 = 0x4484
    static let tagString: UInt32 = 0x4487
    static let tagBinary: UInt32 = 0x4485
    static let attachments: UInt32 = 0x1941A469
    static let attachedFile: UInt32 = 0x61A7
    static let fileDescription: UInt32 = 0x467E
    static let fileName: UInt32 = 0x466E
    static let fileMediaType: UInt32 = 0x4660
    static let fileData: UInt32 = 0x465C
    static let fileUID: UInt32 = 0x46AE
    static let cluster: UInt32 = 0x1F43B675
    static let cues: UInt32 = 0x1C53BB6B
    static let void: UInt32 = 0xEC
    static let crc32: UInt32 = 0xBF

    /// Children of the Segment that this reader knows how to find.
    static let segmentChildren: Set<UInt32> = [seekHead, info, tracks, chapters, tags, attachments, cues, cluster, void, crc32]

    static func label(_ id: UInt32) -> String {
        switch id {
        case seekHead: return "SeekHead"
        case info: return "Info"
        case tracks: return "Tracks"
        case chapters: return "Chapters"
        case tags: return "Tags"
        case attachments: return "Attachments"
        case cues: return "Cues"
        case cluster: return "Cluster"
        default: return "0x" + String(id, radix: 16, uppercase: true)
        }
    }
}

/// A child element found inside a master element: where its body lies in the buffer.
struct EBMLChild {
    let id: UInt32
    /// Body range inside the buffer.
    let start: Int
    let end: Int
    /// The element said it was longer than the bytes that were available; `end` was clamped.
    let truncated: Bool
    var range: Range<Int> { start..<end }
}

/// A byte buffer plus the file offset of its first byte, so messages and layouts can name real file positions.
struct EBMLView {
    let bytes: [UInt8]
    let base: Int64

    func fileOffset(_ index: Int) -> Int64 { base + Int64(index) }

    /// Reads the element ID at `index`. IDs are 1 to 4 bytes; the first byte's leading zero bits give the length.
    static func readID(_ b: [UInt8], at index: Int, limit: Int) -> (id: UInt32, length: Int)? {
        guard index >= 0, index < limit, index < b.count else { return nil }
        let first = b[index]
        guard first != 0 else { return nil }
        let length = first.leadingZeroBitCount + 1
        guard length <= 4, index + length <= limit, index + length <= b.count else { return nil }
        var value: UInt32 = 0
        for k in 0..<length { value = (value << 8) | UInt32(b[index + k]) }
        return (value, length)
    }

    /// Reads a data size. `value` is nil for the reserved "unknown size" encoding (all value bits set).
    static func readSize(_ b: [UInt8], at index: Int, limit: Int) -> (value: UInt64?, length: Int)? {
        guard index >= 0, index < limit, index < b.count else { return nil }
        let first = b[index]
        guard first != 0 else { return nil }
        let length = first.leadingZeroBitCount + 1
        guard length <= 8, index + length <= limit, index + length <= b.count else { return nil }
        let mask = UInt64(0xFF) >> UInt64(length)
        var value = UInt64(first) & mask
        var allOnes = value == mask
        var k = 1
        while k < length {
            let byte = b[index + k]
            value = (value << 8) | UInt64(byte)
            if byte != 0xFF { allOnes = false }
            k += 1
        }
        return (allOnes ? nil : value, length)
    }

    /// The children of the master element whose body is `range`. Problems become warnings and end the scan.
    func children(in range: Range<Int>, context: String, warnings: inout [String]) -> [EBMLChild] {
        var out: [EBMLChild] = []
        var pos = max(0, range.lowerBound)
        let limit = min(range.upperBound, bytes.count)
        while pos < limit {
            guard let id = EBMLView.readID(bytes, at: pos, limit: limit) else {
                warnings.append("\(context): unreadable element ID at file offset \(fileOffset(pos)); the rest of it was skipped")
                break
            }
            guard let size = EBMLView.readSize(bytes, at: pos + id.length, limit: limit) else {
                warnings.append("\(context): unreadable element size at file offset \(fileOffset(pos)); the rest of it was skipped")
                break
            }
            let bodyStart = pos + id.length + size.length
            var bodyEnd = limit
            var truncated = false
            if let declared = size.value {
                if declared > UInt64(limit - bodyStart) {
                    truncated = true
                    warnings.append("\(context): element \(MKV.label(id.id)) at file offset \(fileOffset(pos)) is cut off (declares \(declared) bytes, \(limit - bodyStart) available)")
                } else {
                    bodyEnd = bodyStart + Int(declared)
                }
            }
            out.append(EBMLChild(id: id.id, start: bodyStart, end: bodyEnd, truncated: truncated))
            pos = bodyEnd
        }
        return out
    }

    // MARK: Values (nil when the element was cut off or the length is not valid for the type)

    func uint(_ c: EBMLChild) -> UInt64? {
        guard !c.truncated, c.end - c.start <= 8 else { return nil }
        var value: UInt64 = 0
        for i in c.start..<c.end { value = (value << 8) | UInt64(bytes[i]) }
        return value
    }

    func int(_ c: EBMLChild) -> Int64? {
        guard !c.truncated, c.end > c.start, c.end - c.start <= 8 else { return nil }
        var value: Int64 = (bytes[c.start] & 0x80) != 0 ? -1 : 0
        for i in c.start..<c.end { value = (value << 8) | Int64(bytes[i]) }
        return value
    }

    func float(_ c: EBMLChild) -> Double? {
        guard !c.truncated else { return nil }
        let n = c.end - c.start
        if n == 4 {
            var bits: UInt32 = 0
            for i in c.start..<c.end { bits = (bits << 8) | UInt32(bytes[i]) }
            return Double(Float(bitPattern: bits))
        }
        if n == 8 {
            var bits: UInt64 = 0
            for i in c.start..<c.end { bits = (bits << 8) | UInt64(bytes[i]) }
            return Double(bitPattern: bits)
        }
        return n == 0 ? 0 : nil
    }

    /// UTF-8 text up to the first NUL (padding), nil when cut off.
    func string(_ c: EBMLChild) -> String? {
        guard !c.truncated else { return nil }
        var end = c.end
        if let nul = bytes[c.start..<c.end].firstIndex(of: 0) { end = nul }
        return String(decoding: bytes[c.start..<end], as: UTF8.self)
    }

    func data(_ c: EBMLChild) -> Data? {
        guard !c.truncated else { return nil }
        return Data(bytes[c.start..<c.end])
    }

    func bool(_ c: EBMLChild) -> Bool? { uint(c).map { $0 != 0 } }
}
