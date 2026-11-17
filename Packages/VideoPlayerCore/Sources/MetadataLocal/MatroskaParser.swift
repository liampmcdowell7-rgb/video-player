import Foundation

/// Where the parts of the file are, in file offsets. Lets a caller (or a later seek) find them again without re-scanning.
public struct MatroskaLayout: Equatable, Codable, Sendable {
    /// File offset of the first byte after the Segment header; SeekHead positions count from here.
    public var segmentDataOffset: Int64
    public var seekHeadOffset: Int64?
    public var infoOffset: Int64?
    public var tracksOffset: Int64?
    public var chaptersOffset: Int64?
    public var tagsOffset: Int64?
    public var attachmentsOffset: Int64?
    public var cuesOffset: Int64?
    /// File offset of the first Cluster, when the scan or the SeekHead found one. Clusters are never read.
    public var firstClusterOffset: Int64?

    init() { segmentDataOffset = 0 }
}

/// A top-level element whose body lies partly or wholly past the bytes already read.
struct PendingElement {
    let id: UInt32
    let offset: Int64
}

/// Interprets the elements of one file. Pure and synchronous: `MatroskaReader` feeds it bytes.
final class MatroskaParser {
    private(set) var docType = "matroska"
    private(set) var info: MatroskaInfo?
    private(set) var tracks: [MatroskaTrack] = []
    private(set) var editions: [MatroskaEdition] = []
    private(set) var tags: [MatroskaTag] = []
    private(set) var attachments: [MatroskaAttachment] = []
    private(set) var warnings: [String] = []
    var layout = MatroskaLayout()
    /// SeekHead entries: element ID and absolute file offset.
    private(set) var seekEntries: [(id: UInt32, offset: Int64)] = []
    /// Elements to fetch with a second read.
    private(set) var pending: [PendingElement] = []
    /// File offsets of top-level elements already interpreted.
    private(set) var ingested: Set<Int64> = []

    private static let maxDepth = 12
    private static let maxWarnings = 100

    func warn(_ message: String) {
        guard warnings.count < MatroskaParser.maxWarnings, !warnings.contains(message) else { return }
        warnings.append(message)
    }

    private func merge(_ local: [String]) { for message in local { warn(message) } }

    // MARK: EBML header and Segment

    /// Reads the EBML header at the start of the file and returns the buffer index of the first byte after it.
    func parseEBMLHeader(_ view: EBMLView) throws -> Int {
        let b = view.bytes
        guard !b.isEmpty else { throw MatroskaError.emptyFile }
        guard let id = EBMLView.readID(b, at: 0, limit: b.count), id.id == MKV.ebmlHeader else {
            throw MatroskaError.notMatroska("the file does not start with an EBML header")
        }
        guard let size = EBMLView.readSize(b, at: id.length, limit: b.count) else {
            throw MatroskaError.truncated("the EBML header size is cut off")
        }
        guard let declared = size.value else {
            throw MatroskaError.notMatroska("the EBML header has an unknown size")
        }
        let bodyStart = id.length + size.length
        guard declared <= UInt64(b.count - bodyStart) else {
            throw MatroskaError.truncated("the EBML header is cut off")
        }
        let bodyEnd = bodyStart + Int(declared)
        var local: [String] = []
        var typeSeen = false
        for child in view.children(in: bodyStart..<bodyEnd, context: "EBML header", warnings: &local) where child.id == MKV.docType {
            if let text = view.string(child) {
                docType = text.lowercased()
                typeSeen = true
            }
        }
        merge(local)
        if !typeSeen { warn("The EBML header has no DocType; treated as matroska") }
        guard docType == "matroska" || docType == "webm" else {
            throw MatroskaError.unsupportedDocType(docType)
        }
        return bodyEnd
    }

    /// Finds the Segment after the header (skipping Void and CRC-32) and returns the index of its first body byte.
    func findSegment(_ view: EBMLView, from start: Int) throws -> Int {
        var pos = start
        let b = view.bytes
        while pos < b.count {
            guard let id = EBMLView.readID(b, at: pos, limit: b.count),
                  let size = EBMLView.readSize(b, at: pos + id.length, limit: b.count) else {
                throw MatroskaError.truncated("the Segment header is cut off")
            }
            let bodyStart = pos + id.length + size.length
            if id.id == MKV.segment {
                layout.segmentDataOffset = view.fileOffset(bodyStart)
                return bodyStart
            }
            guard id.id == MKV.void || id.id == MKV.crc32, let declared = size.value, declared <= UInt64(Int.max - bodyStart) else {
                throw MatroskaError.notMatroska("expected a Segment after the EBML header, found element \(MKV.label(id.id))")
            }
            pos = bodyStart + Int(declared)
        }
        throw MatroskaError.truncated("the file ends before the Segment starts")
    }

    private static let resyncIDs: [[UInt8]] = {
        let ids: [UInt32] = [MKV.seekHead, MKV.info, MKV.tracks, MKV.chapters, MKV.tags, MKV.attachments, MKV.cues, MKV.cluster]
        return ids.map { (id: UInt32) -> [UInt8] in
            let b0 = UInt8(truncatingIfNeeded: id >> 24)
            let b1 = UInt8(truncatingIfNeeded: id >> 16)
            let b2 = UInt8(truncatingIfNeeded: id >> 8)
            let b3 = UInt8(truncatingIfNeeded: id)
            return [b0, b1, b2, b3]
        }
    }()

    private func looksLikeTopLevel(_ view: EBMLView, at index: Int) -> Bool {
        guard index < view.bytes.count, let id = EBMLView.readID(view.bytes, at: index, limit: view.bytes.count) else { return false }
        return MKV.segmentChildren.contains(id.id)
    }

    /// Next index at or after `from` where a known 4-byte top-level ID starts, nil if none in the buffer.
    private func resync(_ view: EBMLView, from: Int) -> Int? {
        let b = view.bytes
        var i = from
        while i + 4 <= b.count {
            let first = b[i]
            if first == 0x11 || first == 0x15 || first == 0x16 || first == 0x10 || first == 0x12 || first == 0x19 || first == 0x1C || first == 0x1F {
                for pattern in MatroskaParser.resyncIDs where b[i] == pattern[0] && b[i + 1] == pattern[1] && b[i + 2] == pattern[2] && b[i + 3] == pattern[3] {
                    return i
                }
            }
            i += 1
        }
        return nil
    }

    /// Walks the Segment's children inside the buffer. Stops at the first Cluster. Elements that start in the
    /// buffer but are not wholly inside it become `pending` for a second read.
    func walkSegment(_ view: EBMLView, from start: Int) {
        let b = view.bytes
        var pos = start
        while pos < b.count {
            guard let id = EBMLView.readID(b, at: pos, limit: b.count),
                  let size = EBMLView.readSize(b, at: pos + id.length, limit: b.count) else {
                // Either the read window ends inside an element header, or the bytes here are not an element.
                if let again = resync(view, from: pos + 1) {
                    warn("Skipped damaged data at file offset \(view.fileOffset(pos))")
                    pos = again
                    continue
                }
                warn("The header read ends inside an element header at file offset \(view.fileOffset(pos))")
                return
            }
            let offset = view.fileOffset(pos)
            let bodyStart = pos + id.length + size.length
            if id.id == MKV.cluster {
                if layout.firstClusterOffset == nil { layout.firstClusterOffset = offset }
                return
            }
            let known = MKV.segmentChildren.contains(id.id)
            guard let declared = size.value else {
                if known {
                    warn("\(MKV.label(id.id)) at file offset \(offset) has an unknown size and was not read")
                    return
                }
                warn("Skipped damaged data at file offset \(offset)")
                guard let again = resync(view, from: pos + 1) else { return }
                pos = again
                continue
            }
            let remaining = b.count - bodyStart
            let fits = declared <= UInt64(remaining)
            if !known {
                // An element this reader does not know. Trust it only if the next element looks right.
                if fits {
                    let next = bodyStart + Int(declared)
                    if next >= b.count || looksLikeTopLevel(view, at: next) {
                        pos = next
                        continue
                    }
                } else {
                    return
                }
                warn("Skipped damaged data at file offset \(offset)")
                guard let again = resync(view, from: pos + 1) else { return }
                pos = again
                continue
            }
            switch id.id {
            case MKV.void, MKV.crc32:
                guard fits else { return }
                pos = bodyStart + Int(declared)
                continue
            case MKV.cues:
                if layout.cuesOffset == nil { layout.cuesOffset = offset }
            default:
                if fits {
                    ingest(id: id.id, view: view, body: bodyStart..<(bodyStart + Int(declared)), fileOffset: offset, truncated: false)
                } else {
                    if !ingested.contains(offset) && !pending.contains(where: { $0.offset == offset }) {
                        pending.append(PendingElement(id: id.id, offset: offset))
                    }
                    if layout.offset(of: id.id) == nil { layout.setOffset(of: id.id, offset) }
                    return
                }
            }
            guard fits else { return }
            pos = bodyStart + Int(declared)
        }
    }

    /// Interprets one top-level element whose body is `body` inside `view`.
    func ingest(id: UInt32, view: EBMLView, body: Range<Int>, fileOffset: Int64, truncated: Bool) {
        guard !ingested.contains(fileOffset) else { return }
        ingested.insert(fileOffset)
        if layout.offset(of: id) == nil { layout.setOffset(of: id, fileOffset) }
        if truncated { warn("\(MKV.label(id)) at file offset \(fileOffset) is cut off; only the part that could be read is used") }
        var local: [String] = []
        switch id {
        case MKV.seekHead: parseSeekHead(view, body, &local)
        case MKV.info: parseInfo(view, body, &local)
        case MKV.tracks: parseTracks(view, body, &local)
        case MKV.chapters: parseChapters(view, body, &local)
        case MKV.tags: parseTags(view, body, &local)
        case MKV.attachments: parseAttachments(view, body, &local)
        default: break
        }
        merge(local)
    }

    /// Records an element found only through the SeekHead (no body read).
    func noteSeekTarget(id: UInt32, offset: Int64) {
        if id == MKV.cluster {
            if layout.firstClusterOffset == nil || offset < (layout.firstClusterOffset ?? Int64.max) { layout.firstClusterOffset = offset }
        } else if layout.offset(of: id) == nil {
            layout.setOffset(of: id, offset)
        }
    }

    /// The smallest file offset above `offset` among everything the file has pointed at (SeekHead entries, elements
    /// met in the walk, the first Cluster). An element at `offset` cannot extend past it.
    func nextKnownOffset(after offset: Int64) -> Int64? {
        var candidates: [Int64] = seekEntries.map { $0.offset }
        candidates.append(contentsOf: pending.map { $0.offset })
        for value in [layout.seekHeadOffset, layout.infoOffset, layout.tracksOffset, layout.chaptersOffset, layout.tagsOffset,
                      layout.attachmentsOffset, layout.cuesOffset, layout.firstClusterOffset] {
            if let value { candidates.append(value) }
        }
        return candidates.filter { $0 > offset }.min()
    }

    // MARK: SeekHead

    private func parseSeekHead(_ v: EBMLView, _ body: Range<Int>, _ w: inout [String]) {
        for entry in v.children(in: body, context: "SeekHead", warnings: &w) where entry.id == MKV.seek {
            var seekID: UInt32?
            var position: UInt64?
            for field in v.children(in: entry.range, context: "Seek", warnings: &w) {
                if field.id == MKV.seekID, !field.truncated, field.end - field.start >= 1, field.end - field.start <= 4 {
                    var value: UInt32 = 0
                    for i in field.start..<field.end { value = (value << 8) | UInt32(v.bytes[i]) }
                    seekID = value
                } else if field.id == MKV.seekPosition {
                    position = v.uint(field)
                }
            }
            guard let seekID, let position, position <= UInt64(Int64.max - layout.segmentDataOffset) else {
                w.append("SeekHead: an entry is missing its ID or position and was ignored")
                continue
            }
            seekEntries.append((seekID, layout.segmentDataOffset + Int64(position)))
        }
    }

    // MARK: Info

    private func parseInfo(_ v: EBMLView, _ body: Range<Int>, _ w: inout [String]) {
        var scale: UInt64 = 1_000_000
        var rawDuration: Double?
        var result = MatroskaInfo(timecodeScale: scale)
        for c in v.children(in: body, context: "Info", warnings: &w) {
            switch c.id {
            case MKV.timecodeScale: if let n = v.uint(c), n > 0 { scale = n }
            case MKV.duration: rawDuration = v.float(c)
            case MKV.title: result.title = v.string(c)
            case MKV.muxingApp: result.muxingApp = v.string(c)
            case MKV.writingApp: result.writingApp = v.string(c)
            case MKV.segmentUID: result.segmentUID = v.data(c)
            case MKV.dateUTC:
                // Signed nanoseconds since 2001-01-01T00:00:00 UTC, which is Foundation's reference date.
                if let ns = v.int(c) { result.dateUTC = Date(timeIntervalSinceReferenceDate: Double(ns) / 1e9) }
            default: break
            }
        }
        result.timecodeScale = scale
        if let raw = rawDuration, raw.isFinite, raw >= 0 { result.durationSeconds = raw * Double(scale) / 1e9 }
        if info == nil { info = result } else { w.append("Info: a second Info element was ignored") }
    }

    // MARK: Tracks

    private func parseTracks(_ v: EBMLView, _ body: Range<Int>, _ w: inout [String]) {
        for entry in v.children(in: body, context: "Tracks", warnings: &w) where entry.id == MKV.trackEntry {
            if let track = parseTrackEntry(v, entry, &w) { tracks.append(track) }
        }
    }

    private func parseTrackEntry(_ v: EBMLView, _ entry: EBMLChild, _ w: inout [String]) -> MatroskaTrack? {
        let kids = v.children(in: entry.range, context: "TrackEntry", warnings: &w)
        var track = MatroskaTrack(number: 0, type: .unknown, codecID: "")
        var haveNumber = false
        for c in kids {
            switch c.id {
            case MKV.trackNumber: if let n = v.uint(c), n <= UInt64(Int32.max) { track.number = Int(n); haveNumber = true }
            case MKV.trackUID: track.uid = v.uint(c)
            case MKV.trackType: if let n = v.uint(c) { track.type = MatroskaTrackType(rawValue: Int(truncatingIfNeeded: n)) ?? .unknown }
            case MKV.flagEnabled: if let f = v.bool(c) { track.isEnabled = f }
            case MKV.flagDefault: if let f = v.bool(c) { track.isDefault = f }
            case MKV.flagForced: if let f = v.bool(c) { track.isForced = f }
            case MKV.flagHearingImpaired: if let f = v.bool(c) { track.isHearingImpaired = f }
            case MKV.flagVisualImpaired: if let f = v.bool(c) { track.isVisualImpaired = f }
            case MKV.flagTextDescriptions: if let f = v.bool(c) { track.isTextDescriptions = f }
            case MKV.flagOriginal: if let f = v.bool(c) { track.isOriginalLanguage = f }
            case MKV.flagCommentary: if let f = v.bool(c) { track.isCommentary = f }
            case MKV.defaultDuration: track.defaultDurationNanos = v.uint(c)
            case MKV.name: track.name = v.string(c)
            case MKV.language: if let s = v.string(c), !s.isEmpty { track.language = s }
            case MKV.languageBCP47: track.languageBCP47 = v.string(c)
            case MKV.codecID: if let s = v.string(c) { track.codecID = s }
            case MKV.codecPrivate: track.codecPrivate = v.data(c)
            case MKV.codecName: track.codecName = v.string(c)
            case MKV.contentEncodings: track.hasContentEncoding = true
            case MKV.video: parseVideo(v, c, &track, &w)
            case MKV.audio: parseAudio(v, c, &track, &w)
            case MKV.blockAdditionMapping: parseBlockAdditionMapping(v, c, &track, &w)
            default: break
            }
        }
        guard haveNumber else {
            w.append("Tracks: a TrackEntry without a track number was ignored")
            return nil
        }
        return track
    }

    private func parseVideo(_ v: EBMLView, _ element: EBMLChild, _ track: inout MatroskaTrack, _ w: inout [String]) {
        for c in v.children(in: element.range, context: "Video", warnings: &w) {
            switch c.id {
            case MKV.pixelWidth: track.pixelWidth = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.pixelHeight: track.pixelHeight = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.displayWidth: track.displayWidth = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.displayHeight: track.displayHeight = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.flagInterlaced: if let n = v.uint(c) { track.isInterlaced = n == 1 ? true : (n == 2 ? false : nil) }
            case MKV.colour: track.colour = parseColour(v, c, &w)
            default: break
            }
        }
    }

    private func parseColour(_ v: EBMLView, _ element: EBMLChild, _ w: inout [String]) -> ColourInfo {
        var colour = ColourInfo()
        for c in v.children(in: element.range, context: "Colour", warnings: &w) {
            switch c.id {
            case MKV.matrixCoefficients: colour.matrixCoefficients = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.bitsPerChannel: colour.bitsPerChannel = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.range: colour.range = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.transferCharacteristics: colour.transferCharacteristics = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.primaries: colour.primaries = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.maxCLL: colour.maxCLL = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.maxFALL: colour.maxFALL = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.masteringMetadata:
                var m = MasteringDisplay()
                for f in v.children(in: c.range, context: "MasteringMetadata", warnings: &w) {
                    let value = v.float(f)
                    switch f.id {
                    case MKV.primaryRX: m.redX = value
                    case MKV.primaryRY: m.redY = value
                    case MKV.primaryGX: m.greenX = value
                    case MKV.primaryGY: m.greenY = value
                    case MKV.primaryBX: m.blueX = value
                    case MKV.primaryBY: m.blueY = value
                    case MKV.whiteX: m.whiteX = value
                    case MKV.whiteY: m.whiteY = value
                    case MKV.luminanceMax: m.luminanceMax = value
                    case MKV.luminanceMin: m.luminanceMin = value
                    default: break
                    }
                }
                colour.mastering = m
            default: break
            }
        }
        return colour
    }

    private func parseAudio(_ v: EBMLView, _ element: EBMLChild, _ track: inout MatroskaTrack, _ w: inout [String]) {
        var output: Double?
        for c in v.children(in: element.range, context: "Audio", warnings: &w) {
            switch c.id {
            case MKV.samplingFrequency: track.samplingFrequency = v.float(c)
            case MKV.outputSamplingFrequency: output = v.float(c)
            case MKV.channels: track.channels = v.uint(c).flatMap { Int(exactly: $0) }
            case MKV.bitDepth: track.bitDepth = v.uint(c).flatMap { Int(exactly: $0) }
            default: break
            }
        }
        // For SBR AAC the output rate is the one the listener hears; keep the stored rate unless there is none.
        if track.samplingFrequency == nil { track.samplingFrequency = output }
    }

    /// The Dolby Vision configuration lives in a BlockAdditionMapping whose type is the FourCC "dvcC" or "dvvC".
    private func parseBlockAdditionMapping(_ v: EBMLView, _ element: EBMLChild, _ track: inout MatroskaTrack, _ w: inout [String]) {
        var type: UInt64?
        var extra: EBMLChild?
        for c in v.children(in: element.range, context: "BlockAdditionMapping", warnings: &w) {
            if c.id == MKV.blockAddIDType { type = v.uint(c) }
            if c.id == MKV.blockAddIDExtraData { extra = c }
        }
        guard let type, let extra, !extra.truncated else { return }
        let box: String
        switch type {
        case 0x6476_6343: box = "dvcC"
        case 0x6476_7643: box = "dvvC"
        default: return
        }
        let record = Array(v.bytes[extra.start..<extra.end])
        if let config = DolbyVisionConfig(record: record, boxType: box) {
            track.dolbyVision = config
        } else {
            w.append("Tracks: a Dolby Vision \(box) record is shorter than 5 bytes and was ignored")
        }
    }

    // MARK: Chapters

    private func parseChapters(_ v: EBMLView, _ body: Range<Int>, _ w: inout [String]) {
        for edition in v.children(in: body, context: "Chapters", warnings: &w) where edition.id == MKV.editionEntry {
            var result = MatroskaEdition(uid: nil, isHidden: false, isDefault: false, isOrdered: false, chapters: [])
            for c in v.children(in: edition.range, context: "EditionEntry", warnings: &w) {
                switch c.id {
                case MKV.editionUID: result.uid = v.uint(c)
                case MKV.editionHidden: if let f = v.bool(c) { result.isHidden = f }
                case MKV.editionDefault: if let f = v.bool(c) { result.isDefault = f }
                case MKV.editionOrdered: if let f = v.bool(c) { result.isOrdered = f }
                case MKV.chapterAtom: if let a = parseAtom(v, c, depth: 0, &w) { result.chapters.append(a) }
                default: break
                }
            }
            editions.append(result)
        }
    }

    private func parseAtom(_ v: EBMLView, _ element: EBMLChild, depth: Int, _ w: inout [String]) -> MatroskaChapter? {
        guard depth < MatroskaParser.maxDepth else {
            w.append("Chapters: chapters nested deeper than \(MatroskaParser.maxDepth) levels were ignored")
            return nil
        }
        var chapter = MatroskaChapter(uid: nil, stringUID: nil, startNanos: 0, endNanos: nil, isHidden: false, isEnabled: true, displays: [], children: [])
        var haveStart = false
        for c in v.children(in: element.range, context: "ChapterAtom", warnings: &w) {
            switch c.id {
            case MKV.chapterUID: chapter.uid = v.uint(c)
            case MKV.chapterStringUID: chapter.stringUID = v.string(c)
            case MKV.chapterTimeStart:
                if let n = v.uint(c), n <= UInt64(Int64.max) { chapter.startNanos = Int64(n); haveStart = true }
            case MKV.chapterTimeEnd: chapter.endNanos = v.uint(c).flatMap { Int64(exactly: $0) }
            case MKV.chapterHidden: if let f = v.bool(c) { chapter.isHidden = f }
            case MKV.chapterEnabled: if let f = v.bool(c) { chapter.isEnabled = f }
            case MKV.chapterDisplay:
                if let d = parseDisplay(v, c, &w) { chapter.displays.append(d) }
            case MKV.chapterAtom:
                if let child = parseAtom(v, c, depth: depth + 1, &w) { chapter.children.append(child) }
            default: break
            }
        }
        if !haveStart { w.append("Chapters: a chapter without a start time was kept at 0") }
        return chapter
    }

    private func parseDisplay(_ v: EBMLView, _ element: EBMLChild, _ w: inout [String]) -> ChapterDisplay? {
        var title: String?
        var languages: [String] = []
        var bcp: [String] = []
        var countries: [String] = []
        for c in v.children(in: element.range, context: "ChapterDisplay", warnings: &w) {
            switch c.id {
            case MKV.chapString: title = v.string(c)
            case MKV.chapLanguage: if let s = v.string(c) { languages.append(s) }
            case MKV.chapLanguageBCP47: if let s = v.string(c) { bcp.append(s) }
            case MKV.chapCountry: if let s = v.string(c) { countries.append(s) }
            default: break
            }
        }
        guard let title else { return nil }
        if languages.isEmpty && bcp.isEmpty { languages = ["eng"] }
        return ChapterDisplay(title: title, languages: languages, languagesBCP47: bcp, countries: countries)
    }

    // MARK: Tags

    private func parseTags(_ v: EBMLView, _ body: Range<Int>, _ w: inout [String]) {
        for element in v.children(in: body, context: "Tags", warnings: &w) where element.id == MKV.tag {
            var tag = MatroskaTag(targetTypeValue: nil, targetType: nil, trackUIDs: [], editionUIDs: [], chapterUIDs: [],
                                  attachmentUIDs: [], simpleTags: [])
            for c in v.children(in: element.range, context: "Tag", warnings: &w) {
                switch c.id {
                case MKV.targets:
                    for t in v.children(in: c.range, context: "Targets", warnings: &w) {
                        switch t.id {
                        case MKV.targetTypeValue: tag.targetTypeValue = v.uint(t).flatMap { Int(exactly: $0) }
                        case MKV.targetType: tag.targetType = v.string(t)
                        case MKV.tagTrackUID: if let n = v.uint(t), n != 0 { tag.trackUIDs.append(n) }
                        case MKV.tagEditionUID: if let n = v.uint(t), n != 0 { tag.editionUIDs.append(n) }
                        case MKV.tagChapterUID: if let n = v.uint(t), n != 0 { tag.chapterUIDs.append(n) }
                        case MKV.tagAttachmentUID: if let n = v.uint(t), n != 0 { tag.attachmentUIDs.append(n) }
                        default: break
                        }
                    }
                case MKV.simpleTag:
                    if let s = parseSimpleTag(v, c, depth: 0, &w) { tag.simpleTags.append(s) }
                default: break
                }
            }
            tags.append(tag)
        }
    }

    private func parseSimpleTag(_ v: EBMLView, _ element: EBMLChild, depth: Int, _ w: inout [String]) -> MatroskaSimpleTag? {
        guard depth < MatroskaParser.maxDepth else {
            w.append("Tags: tags nested deeper than \(MatroskaParser.maxDepth) levels were ignored")
            return nil
        }
        var tag = MatroskaSimpleTag(name: "", language: nil, languageBCP47: nil, isDefault: true, string: nil, binarySize: nil, children: [])
        var haveName = false
        for c in v.children(in: element.range, context: "SimpleTag", warnings: &w) {
            switch c.id {
            case MKV.tagName: if let s = v.string(c) { tag.name = s; haveName = true }
            case MKV.tagLanguage: tag.language = v.string(c)
            case MKV.tagLanguageBCP47: tag.languageBCP47 = v.string(c)
            case MKV.tagDefault: if let f = v.bool(c) { tag.isDefault = f }
            case MKV.tagString: tag.string = v.string(c)
            case MKV.tagBinary: tag.binarySize = c.end - c.start
            case MKV.simpleTag: if let child = parseSimpleTag(v, c, depth: depth + 1, &w) { tag.children.append(child) }
            default: break
            }
        }
        return haveName ? tag : nil
    }

    // MARK: Attachments

    private func parseAttachments(_ v: EBMLView, _ body: Range<Int>, _ w: inout [String]) {
        for element in v.children(in: body, context: "Attachments", warnings: &w) where element.id == MKV.attachedFile {
            var file = MatroskaAttachment(fileName: "", mediaType: nil, description: nil, uid: nil, dataSize: nil)
            var haveName = false
            for c in v.children(in: element.range, context: "AttachedFile", warnings: &w) {
                switch c.id {
                case MKV.fileName: if let s = v.string(c) { file.fileName = s; haveName = true }
                case MKV.fileMediaType: file.mediaType = v.string(c)
                case MKV.fileDescription: file.description = v.string(c)
                case MKV.fileUID: file.uid = v.uint(c)
                case MKV.fileData: if !c.truncated { file.dataSize = Int64(c.end - c.start) }
                default: break
                }
            }
            if haveName { attachments.append(file) }
        }
    }

    // MARK: Result

    func result() -> EmbeddedMetadata {
        EmbeddedMetadata(docType: docType, info: info, tracks: tracks, editions: editions, tags: tags,
                         attachments: attachments, warnings: warnings, layout: layout)
    }
}

extension MatroskaLayout {
    func offset(of id: UInt32) -> Int64? {
        switch id {
        case MKV.seekHead: return seekHeadOffset
        case MKV.info: return infoOffset
        case MKV.tracks: return tracksOffset
        case MKV.chapters: return chaptersOffset
        case MKV.tags: return tagsOffset
        case MKV.attachments: return attachmentsOffset
        case MKV.cues: return cuesOffset
        default: return nil
        }
    }

    mutating func setOffset(of id: UInt32, _ value: Int64) {
        switch id {
        case MKV.seekHead: seekHeadOffset = value
        case MKV.info: infoOffset = value
        case MKV.tracks: tracksOffset = value
        case MKV.chapters: chaptersOffset = value
        case MKV.tags: tagsOffset = value
        case MKV.attachments: attachmentsOffset = value
        case MKV.cues: cuesOffset = value
        default: break
        }
    }
}
