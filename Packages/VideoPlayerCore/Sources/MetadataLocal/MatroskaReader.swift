import Foundation
import VideoPlayerCore

/// Why a file could not be read as Matroska/WebM. Damage that still leaves something usable is reported as
/// `EmbeddedMetadata.warnings` instead.
public enum MatroskaError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The first read returned no bytes.
    case emptyFile
    /// The bytes are not a Matroska or WebM file.
    case notMatroska(String)
    /// An EBML file of another kind (the DocType is given).
    case unsupportedDocType(String)
    /// The file is cut off before the header and Segment start could be read.
    case truncated(String)
    /// The byte reader failed on the first read.
    case readFailed(String)

    public var description: String {
        switch self {
        case .emptyFile: return "The file is empty"
        case .notMatroska(let why): return "Not a Matroska file: \(why)"
        case .unsupportedDocType(let type): return "Unsupported EBML document type \"\(type)\""
        case .truncated(let why): return "The file is cut off: \(why)"
        case .readFailed(let why): return "Reading failed: \(why)"
        }
    }
}

/// Reads a range of bytes from the file. Over a `MediaSource` this is `source.read(path, range:)`.
public typealias MatroskaRangeReader = @Sendable (ByteRange) async throws -> Data

/// Reads the header metadata of a Matroska/WebM file using only ranged reads.
///
/// Strategy: read the first `headBytes` (default 512 KiB), parse the EBML header and walk the Segment's
/// children until the first Cluster. Elements that start in that window but end beyond it, and elements the
/// SeekHead points to beyond it (typically Chapters and Tags written after the clusters), are fetched with one or
/// two more reads each, sized to the element. Clusters are never read.
public struct MatroskaReader: Sendable {
    /// Bytes read from the start of the file. Real files keep Info, Tracks and usually Chapters in the first few KiB.
    public var headBytes: Int
    /// The largest single element fetched with a second read; bigger ones (an Attachments element full of fonts) are skipped.
    public var maxElementBytes: Int
    /// The most extra reads after the first one.
    public var maxFetches: Int

    public init(headBytes: Int = 512 * 1024, maxElementBytes: Int = 4 * 1024 * 1024, maxFetches: Int = 12) {
        self.headBytes = max(64, headBytes)
        self.maxElementBytes = max(1024, maxElementBytes)
        self.maxFetches = max(0, maxFetches)
    }

    /// First extra read size for an element found through the SeekHead; most elements fit in it.
    private static let fetchChunk = 64 * 1024

    /// Reads the metadata of one file through `reader`.
    /// - Throws: `MatroskaError` when the file is not Matroska/WebM or its start cannot be read; `CancellationError` when cancelled.
    public func read(using reader: MatroskaRangeReader) async throws -> EmbeddedMetadata {
        let headData: Data
        do {
            headData = try await reader(ByteRange(offset: 0, length: Int64(headBytes)))
        } catch is CancellationError {
            throw CancellationError()
        } catch SourceError.rangeNotSatisfiable {
            // A source answers a range read of a zero-byte file with "range not satisfiable".
            throw MatroskaError.emptyFile
        } catch {
            throw MatroskaError.readFailed(String(describing: error))
        }
        let head = EBMLView(bytes: [UInt8](headData.prefix(headBytes)), base: 0)
        let parser = MatroskaParser()
        let afterHeader = try parser.parseEBMLHeader(head)
        let segmentStart = try parser.findSegment(head, from: afterHeader)
        parser.walkSegment(head, from: segmentStart)

        let budget = ReadBudget(limit: maxFetches)
        var attempted = Set<Int64>()
        var noted = 0
        while true {
            while noted < parser.seekEntries.count {
                parser.noteSeekTarget(id: parser.seekEntries[noted].id, offset: parser.seekEntries[noted].offset)
                noted += 1
            }
            var targets: [PendingElement] = parser.pending.filter { !parser.ingested.contains($0.offset) && !attempted.contains($0.offset) }
            for entry in parser.seekEntries where MatroskaReader.wanted.contains(entry.id)
                && !parser.ingested.contains(entry.offset) && !attempted.contains(entry.offset)
                && !targets.contains(where: { $0.offset == entry.offset }) {
                targets.append(PendingElement(id: entry.id, offset: entry.offset))
            }
            guard let next = targets.first else { break }
            attempted.insert(next.offset)
            try await load(next, head: head, parser: parser, reader: reader, budget: budget)
        }

        if parser.info == nil { parser.warn("No Info element was found") }
        if parser.tracks.isEmpty { parser.warn("No Tracks element was found") }
        if parser.seekEntries.isEmpty && parser.layout.firstClusterOffset != nil {
            parser.warn("The file has no SeekHead; elements after the first Cluster (often Chapters and Tags) were not searched for")
        }
        return parser.result()
    }

    /// Reads from a media source: `source.read(path, range:)` is the byte reader.
    public func read(from source: any MediaSource, path: String) async throws -> EmbeddedMetadata {
        try await read { range in try await source.read(path, range: range) }
    }

    private static let wanted: Set<UInt32> = [MKV.seekHead, MKV.info, MKV.tracks, MKV.chapters, MKV.tags, MKV.attachments]

    // MARK: Loading one element

    /// Counts the extra reads (after the first one) against `maxFetches`.
    private final class ReadBudget {
        let limit: Int
        var used = 0
        init(limit: Int) { self.limit = limit }
        func take() -> Bool {
            guard used < limit else { return false }
            used += 1
            return true
        }
    }

    private func load(_ target: PendingElement, head: EBMLView, parser: MatroskaParser, reader: MatroskaRangeReader, budget: ReadBudget) async throws {
        let label = MKV.label(target.id)
        var window: EBMLView?
        var index = 0
        if target.offset >= 0 && target.offset < Int64(head.bytes.count) {
            window = head
            index = Int(target.offset)
        } else {
            // First extra read: a chunk starting at the element, enough for most elements.
            // The next element the file has told us about bounds this one, so the read never runs into a Cluster.
            var length = MatroskaReader.fetchChunk
            if let upper = parser.nextKnownOffset(after: target.offset) {
                length = min(length, max(16, Int(clamping: upper - target.offset)))
            }
            guard let chunk = try await fetch(target.offset, length, reader, parser, label, budget) else { return }
            window = EBMLView(bytes: chunk, base: target.offset)
            index = 0
        }
        guard let view = window,
              let id = EBMLView.readID(view.bytes, at: index, limit: view.bytes.count),
              let size = EBMLView.readSize(view.bytes, at: index + id.length, limit: view.bytes.count) else {
            parser.warn("\(label) at file offset \(target.offset): the element header could not be read")
            return
        }
        guard id.id == target.id else {
            parser.warn("The SeekHead points at \(label) at file offset \(target.offset), but \(MKV.label(id.id)) is there; it was ignored")
            return
        }
        guard let declared = size.value else {
            parser.warn("\(label) at file offset \(target.offset) has an unknown size and was not read")
            return
        }
        let bodyStart = index + id.length + size.length
        if declared <= UInt64(view.bytes.count - bodyStart) {
            parser.ingest(id: id.id, view: view, body: bodyStart..<(bodyStart + Int(declared)), fileOffset: target.offset, truncated: false)
            return
        }
        // The element is longer than the bytes in hand.
        guard declared <= UInt64(maxElementBytes) else {
            parser.warn("\(label) at file offset \(target.offset) is \(declared) bytes, over the \(maxElementBytes) byte limit; it was not read" + (view.base == 0 ? ", only its start was used" : ""))
            if view.base == 0 { partial(target, view, bodyStart, parser) }
            return
        }
        let headerLength = id.length + size.length
        let total = headerLength + Int(declared)
        guard let whole = try await fetch(target.offset, total, reader, parser, label, budget) else {
            if view.base == 0 { partial(target, view, bodyStart, parser) }
            return
        }
        let full = EBMLView(bytes: whole, base: target.offset)
        if whole.count >= total {
            parser.ingest(id: id.id, view: full, body: headerLength..<total, fileOffset: target.offset, truncated: false)
        } else if whole.count > headerLength {
            parser.ingest(id: id.id, view: full, body: headerLength..<whole.count, fileOffset: target.offset, truncated: true)
        } else if view.base == 0 {
            partial(target, view, bodyStart, parser)
        } else {
            parser.warn("\(label) at file offset \(target.offset) could not be read (the file ends first)")
        }
    }

    /// Uses the part of an element that lies inside the head window.
    private func partial(_ target: PendingElement, _ head: EBMLView, _ bodyStart: Int, _ parser: MatroskaParser) {
        guard bodyStart <= head.bytes.count else { return }
        parser.ingest(id: target.id, view: head, body: bodyStart..<head.bytes.count, fileOffset: target.offset, truncated: true)
    }

    /// One ranged read. Returns nil (with a warning) when the read fails or returns nothing.
    private func fetch(_ offset: Int64, _ length: Int, _ reader: MatroskaRangeReader, _ parser: MatroskaParser, _ label: String,
                       _ budget: ReadBudget) async throws -> [UInt8]? {
        guard offset >= 0, length > 0 else { return nil }
        guard budget.take() else {
            parser.warn("Stopped after \(budget.limit) extra reads; \(label) at file offset \(offset) was not read")
            return nil
        }
        do {
            let data = try await reader(ByteRange(offset: offset, length: Int64(length)))
            guard !data.isEmpty else {
                parser.warn("\(label) at file offset \(offset) could not be read (the file ends first)")
                return nil
            }
            return [UInt8](data.prefix(length))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            parser.warn("\(label) at file offset \(offset) could not be read: \(error)")
            return nil
        }
    }
}
