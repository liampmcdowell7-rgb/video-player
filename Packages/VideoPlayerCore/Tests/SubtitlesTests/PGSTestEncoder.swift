import Foundation

/// A small PGS (.sup) writer used only by the tests. It follows the same segment layout the parser reads, so a
/// passing test shows the parser and this encoder agree, not that either matches a real Blu-ray (see docs/SUBTITLES.md).
struct PGSTestEncoder {
    var data = Data()

    struct CompObject {
        var id: UInt16
        var x: Int
        var y: Int
        var forced = false
        var crop: (x: Int, y: Int, w: Int, h: Int)?
    }

    static func ticks(_ seconds: Double) -> UInt32 { UInt32((seconds * 90_000).rounded()) }

    private static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    mutating func segment(type: UInt8, pts: Double, body: [UInt8]) {
        let t = PGSTestEncoder.ticks(pts)
        data.append(contentsOf: [0x50, 0x47])
        data.append(contentsOf: [UInt8(t >> 24 & 0xFF), UInt8(t >> 16 & 0xFF), UInt8(t >> 8 & 0xFF), UInt8(t & 0xFF)])
        data.append(contentsOf: [0, 0, 0, 0])
        data.append(type)
        data.append(contentsOf: PGSTestEncoder.be16(body.count))
        data.append(contentsOf: body)
    }

    mutating func pcs(pts: Double, width: Int = 1920, height: Int = 1080, number: Int = 0, state: UInt8, paletteUpdate: Bool = false, paletteID: UInt8 = 0, objects: [CompObject]) {
        var b: [UInt8] = PGSTestEncoder.be16(width) + PGSTestEncoder.be16(height) + [0x10] + PGSTestEncoder.be16(number)
        b += [state, paletteUpdate ? 0x80 : 0, paletteID, UInt8(objects.count)]
        for o in objects {
            b += PGSTestEncoder.be16(Int(o.id)) + [0, (o.forced ? 0x40 : 0) | (o.crop != nil ? 0x80 : 0)]
            b += PGSTestEncoder.be16(o.x) + PGSTestEncoder.be16(o.y)
            if let c = o.crop { b += PGSTestEncoder.be16(c.x) + PGSTestEncoder.be16(c.y) + PGSTestEncoder.be16(c.w) + PGSTestEncoder.be16(c.h) }
        }
        segment(type: 0x16, pts: pts, body: b)
    }

    mutating func wds(pts: Double, x: Int, y: Int, width: Int, height: Int) {
        segment(type: 0x17, pts: pts, body: [1, 0] + PGSTestEncoder.be16(x) + PGSTestEncoder.be16(y) + PGSTestEncoder.be16(width) + PGSTestEncoder.be16(height))
    }

    /// entries: (index, Y, Cr, Cb, A)
    mutating func pds(pts: Double, id: UInt8 = 0, version: UInt8 = 0, entries: [(UInt8, UInt8, UInt8, UInt8, UInt8)]) {
        var b: [UInt8] = [id, version]
        for e in entries { b += [e.0, e.1, e.2, e.3, e.4] }
        segment(type: 0x14, pts: pts, body: b)
    }

    /// Writes the object as one or more ODS segments, each carrying at most `fragmentSize` bytes of RLE data.
    mutating func ods(pts: Double, id: UInt16, width: Int, height: Int, indices: [UInt8], fragmentSize: Int = 60_000) {
        let rle = PGSTestEncoder.rle(indices, width: width, height: height)
        odsRaw(pts: pts, id: id, width: width, height: height, rle: rle, fragmentSize: fragmentSize)
    }

    mutating func odsRaw(pts: Double, id: UInt16, width: Int, height: Int, rle: [UInt8], fragmentSize: Int) {
        var chunks: [[UInt8]] = []
        var i = 0
        repeat {
            chunks.append(Array(rle[i..<min(rle.count, i + fragmentSize)]))
            i += fragmentSize
        } while i < rle.count
        for (n, chunk) in chunks.enumerated() {
            var flag: UInt8 = 0
            if n == 0 { flag |= 0x80 }
            if n == chunks.count - 1 { flag |= 0x40 }
            var b: [UInt8] = PGSTestEncoder.be16(Int(id)) + [0, flag]
            if n == 0 {
                let total = rle.count + 4
                b += [UInt8(total >> 16 & 0xFF), UInt8(total >> 8 & 0xFF), UInt8(total & 0xFF)]
                b += PGSTestEncoder.be16(width) + PGSTestEncoder.be16(height)
            }
            b += chunk
            segment(type: 0x15, pts: pts, body: b)
        }
    }

    mutating func end(pts: Double) { segment(type: 0x80, pts: pts, body: []) }

    static func rle(_ indices: [UInt8], width: Int, height: Int) -> [UInt8] {
        var out: [UInt8] = []
        for row in 0..<height {
            var x = 0
            while x < width {
                let c = indices[row * width + x]
                var run = 1
                while x + run < width, indices[row * width + x + run] == c, run < 16_383 { run += 1 }
                if c == 0 {
                    if run < 64 { out += [0, UInt8(run)] } else { out += [0, 0x40 | UInt8(run >> 8), UInt8(run & 0xFF)] }
                } else if run == 1 {
                    out += [c]
                } else if run < 64 {
                    out += [0, 0x80 | UInt8(run), c]
                } else {
                    out += [0, 0xC0 | UInt8(run >> 8), UInt8(run & 0xFF), c]
                }
                x += run
            }
            out += [0, 0]
        }
        return out
    }

    /// A complete display set that shows `objects` (one bitmap each) with `palette`.
    mutating func showSet(
        pts: Double, width: Int = 1920, height: Int = 1080, state: UInt8 = 0x80, number: Int = 0,
        bitmaps: [(id: UInt16, x: Int, y: Int, w: Int, h: Int, indices: [UInt8], forced: Bool)],
        palette: [(UInt8, UInt8, UInt8, UInt8, UInt8)]?, fragmentSize: Int = 60_000
    ) {
        pcs(pts: pts, width: width, height: height, number: number, state: state, objects: bitmaps.map { CompObject(id: $0.id, x: $0.x, y: $0.y, forced: $0.forced, crop: nil) })
        if let first = bitmaps.first { wds(pts: pts, x: first.x, y: first.y, width: first.w, height: first.h) }
        if let palette { pds(pts: pts, entries: palette) }
        for b in bitmaps { ods(pts: pts, id: b.id, width: b.w, height: b.h, indices: b.indices, fragmentSize: fragmentSize) }
        end(pts: pts)
    }

    /// A display set with no objects: clears the screen.
    mutating func clearSet(pts: Double, width: Int = 1920, height: Int = 1080, number: Int = 0) {
        pcs(pts: pts, width: width, height: height, number: number, state: 0x00, objects: [])
        end(pts: pts)
    }
}
