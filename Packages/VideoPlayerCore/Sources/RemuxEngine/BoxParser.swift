import Foundation

/// A parsed ISO base media box, used by the tests and by `FMP4Checker` to check what the writer (and FFmpeg) produced.
public struct BoxNode: Sendable {
    public var type: String
    public var offset: Int
    public var headerSize: Int
    public var size: Int
    public var children: [BoxNode]
    /// Bytes after the header (and, for sample entries, after the fixed fields): the box content.
    public var payload: [UInt8]

    /// First descendant at a slash-separated path ("moov/trak/mdia/minf/stbl/stsd/hvc1/hvcC").
    public func find(_ path: String) -> BoxNode? {
        var node: BoxNode = self
        for part in path.split(separator: "/") {
            guard let c = node.children.first(where: { $0.type == String(part) }) else { return nil }
            node = c
        }
        return node
    }
    public func findAll(_ type: String) -> [BoxNode] { children.filter { $0.type == type } }
    /// Every descendant box of that type, depth first.
    public func descendants(_ type: String) -> [BoxNode] {
        var out: [BoxNode] = []
        for c in children { if c.type == type { out.append(c) }; out.append(contentsOf: c.descendants(type)) }
        return out
    }
}

public enum BoxParser {
    static let containers: Set<String> = ["moov", "trak", "mdia", "minf", "stbl", "dinf", "mvex", "moof", "traf", "edts", "udta"]
    static let visualEntries: Set<String> = ["hvc1", "hev1", "dvh1", "dvhe", "avc1", "avc3"]
    static let audioEntries: Set<String> = ["ac-3", "ec-3", "mp4a", "fLaC", "ipcm", "alac", "Opus"]

    /// Parses a sequence of boxes. The result is a synthetic root whose children are the top-level boxes.
    public static func parse(_ bytes: [UInt8]) throws -> BoxNode {
        let kids = try parseRange(bytes, 0, bytes.count)
        return BoxNode(type: "root", offset: 0, headerSize: 0, size: bytes.count, children: kids, payload: [])
    }

    static func parseRange(_ b: [UInt8], _ from: Int, _ to: Int) throws -> [BoxNode] {
        var out: [BoxNode] = []
        var pos = from
        while pos < to {
            var c = ByteCursor(b, pos: pos, end: to)
            var size = Int(try c.u32())
            let type = try c.fourCC()
            var header = 8
            if size == 1 { size = Int(try c.u64()); header = 16 }
            if size == 0 { size = to - pos }
            guard size >= header, pos + size <= to else { throw RemuxError.malformed("box \(type) at \(pos) has size \(size) (limit \(to - pos))") }
            let bodyStart = pos + header
            let bodyEnd = pos + size
            var node = BoxNode(type: type, offset: pos, headerSize: header, size: size, children: [], payload: Array(b[bodyStart..<bodyEnd]))
            if containers.contains(type) {
                node.children = try parseRange(b, bodyStart, bodyEnd)
            } else if type == "stsd" {
                // fullbox header (4) + entry_count (4), then entries.
                node.children = try parseRange(b, bodyStart + 8, bodyEnd)
            } else if visualEntries.contains(type), bodyEnd - bodyStart >= 78 {
                node.children = try parseRange(b, bodyStart + 78, bodyEnd)
            } else if audioEntries.contains(type), bodyEnd - bodyStart >= 28 {
                node.children = try parseRange(b, bodyStart + 28, bodyEnd)
            }
            out.append(node)
            pos += size
        }
        return out
    }
}

/// Structured view of a movie fragment (moof + mdat) for tests.
public struct ParsedFragment: Sendable {
    public struct Sample: Sendable { public var duration: UInt32; public var size: UInt32; public var flags: UInt32; public var cto: Int32 }
    public var sequence: UInt32
    public var trackID: UInt32
    public var baseDecodeTime: UInt64
    public var dataOffset: Int32
    public var samples: [Sample]
    public var moofOffset: Int
    public var moofSize: Int
    public var mdatOffset: Int
    public var mdatPayloadSize: Int

    public static func parse(_ bytes: [UInt8]) throws -> ParsedFragment {
        let root = try BoxParser.parse(bytes)
        guard let moof = root.children.first(where: { $0.type == "moof" }), let mdat = root.children.first(where: { $0.type == "mdat" }) else {
            throw RemuxError.malformed("fragment without moof and mdat")
        }
        guard let mfhd = moof.find("mfhd"), let tfhd = moof.find("traf/tfhd"), let tfdt = moof.find("traf/tfdt"), let trun = moof.find("traf/trun") else {
            throw RemuxError.malformed("fragment without mfhd/tfhd/tfdt/trun")
        }
        var m = ByteCursor(mfhd.payload); try m.skip(4)
        let sequence = try m.u32()
        var t = ByteCursor(tfhd.payload); try t.skip(4)
        let trackID = try t.u32()
        var d = ByteCursor(tfdt.payload)
        let version = try d.u8(); try d.skip(3)
        let base = version == 1 ? try d.u64() : UInt64(try d.u32())
        var r = ByteCursor(trun.payload)
        let rv = try r.u8(); let flags = try r.u24()
        let count = Int(try r.u32())
        let dataOffset = flags & 1 != 0 ? Int32(bitPattern: try r.u32()) : 0
        if flags & 4 != 0 { try r.skip(4) }
        var samples: [Sample] = []
        for _ in 0..<count {
            let dur = flags & 0x100 != 0 ? try r.u32() : 0
            let size = flags & 0x200 != 0 ? try r.u32() : 0
            let fl = flags & 0x400 != 0 ? try r.u32() : 0
            let cto = flags & 0x800 != 0 ? Int32(bitPattern: try r.u32()) : 0
            _ = rv
            samples.append(Sample(duration: dur, size: size, flags: fl, cto: cto))
        }
        return ParsedFragment(sequence: sequence, trackID: trackID, baseDecodeTime: base, dataOffset: dataOffset, samples: samples,
                              moofOffset: moof.offset, moofSize: moof.size, mdatOffset: mdat.offset, mdatPayloadSize: mdat.size - mdat.headerSize)
    }
}

/// Consistency checks on a fragment: the things a player relies on.
public enum FMP4Checker {
    /// Returns a list of problems (empty when the fragment is consistent).
    public static func check(fragment bytes: [UInt8]) -> [String] {
        var problems: [String] = []
        guard let f = try? ParsedFragment.parse(bytes) else { return ["fragment does not parse"] }
        let total = f.samples.reduce(0) { $0 + Int($1.size) }
        if total != f.mdatPayloadSize { problems.append("sum of sample sizes \(total) != mdat payload \(f.mdatPayloadSize)") }
        if Int(f.dataOffset) != f.moofSize + 8 { problems.append("data_offset \(f.dataOffset) != moof size + 8 (\(f.moofSize + 8))") }
        if f.mdatOffset != f.moofOffset + f.moofSize { problems.append("mdat does not follow moof") }
        if f.samples.isEmpty { problems.append("no samples") }
        return problems
    }

    /// Checks an init segment: required boxes present, sample entry has the expected config boxes.
    public static func check(initSegment bytes: [UInt8], expectedEntry: String) -> [String] {
        var problems: [String] = []
        guard let root = try? BoxParser.parse(bytes) else { return ["init segment does not parse"] }
        if root.children.first?.type != "ftyp" { problems.append("first box is not ftyp") }
        for p in ["moov/mvhd", "moov/trak/tkhd", "moov/trak/mdia/mdhd", "moov/trak/mdia/hdlr", "moov/trak/mdia/minf/stbl/stsd",
                  "moov/mvex/trex", "moov/trak/mdia/minf/stbl/stts", "moov/trak/mdia/minf/stbl/stsz"] where root.find(p) == nil {
            problems.append("missing \(p)")
        }
        if root.find("moov/trak/mdia/minf/stbl/stsd/\(expectedEntry)") == nil { problems.append("missing sample entry \(expectedEntry)") }
        return problems
    }
}
