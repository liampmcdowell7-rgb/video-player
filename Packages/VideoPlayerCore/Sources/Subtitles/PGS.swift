import Foundation

/// One bitmap on screen: indexed pixels plus the palette that applies to it.
public struct PGSBitmapObject: Equatable, Sendable {
    /// Top-left corner in the stream's own frame (`PGSBitmapCue.frameWidth` x `frameHeight`).
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    /// `width * height` palette indices, row by row.
    public var indices: [UInt8]
    /// 256 entries; entries the stream never defined are fully transparent.
    public var palette: [SubtitleColor]
    /// The composition marked this object "forced" (shown even when subtitles are off).
    public var isForced: Bool
    /// True when the RLE data did not fill the bitmap exactly and was padded or cut.
    public var isDamaged: Bool

    /// Straight (non-premultiplied) RGBA bytes, `width * height * 4`.
    public func rgba() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: indices.count * 4)
        for (n, index) in indices.enumerated() {
            let c = palette[Int(index)]
            out[n * 4] = c.red
            out[n * 4 + 1] = c.green
            out[n * 4 + 2] = c.blue
            out[n * 4 + 3] = c.alpha
        }
        return out
    }
}

/// An image subtitle shown from `start` to `end` (seconds).
public struct PGSBitmapCue: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    /// Size of the video frame the coordinates refer to (from the stream, e.g. 1920x1080).
    public var frameWidth: Int
    public var frameHeight: Int
    public var objects: [PGSBitmapObject]

    public var isForced: Bool { objects.contains { $0.isForced } }
}

public struct PGSParseResult: Sendable {
    public var cues: [PGSBitmapCue]
    public var warnings: [String]
    public var segmentsRead: Int
    /// Segments that were damaged: bad header, impossible size, missing parts, bad RLE.
    public var damagedSegments: Int
}

/// Reads HDMV Presentation Graphic Stream (.sup) data.
///
/// Format (from the Blu-ray / ffmpeg `pgssubdec` layout; checked only against streams made by this
/// package's own test encoder, see docs/SUBTITLES.md): each segment is `"PG"`, PTS (u32, 90 kHz), DTS (u32), type (u8),
/// size (u16), payload. Types: 0x14 palette (PDS), 0x15 object (ODS), 0x16 composition (PCS), 0x17 window (WDS), 0x80 end.
public enum PGSParser {

    /// How long a cue stays when the stream ends without a clearing composition.
    public static let unterminatedDuration: TimeInterval = 5

    private struct RawPaletteEntry {
        var y: UInt8 = 0, cr: UInt8 = 128, cb: UInt8 = 128, a: UInt8 = 0
    }

    private struct DecodedObject {
        var width: Int
        var height: Int
        var indices: [UInt8]
        var damaged: Bool
    }

    private struct PendingObject {
        var width: Int
        var height: Int
        var expectedLength: Int
        var data: [UInt8]
    }

    private struct CompositionObject {
        var objectID: UInt16
        var x: Int
        var y: Int
        var forced: Bool
        var crop: (x: Int, y: Int, w: Int, h: Int)?
    }

    private struct Composition {
        var pts: TimeInterval
        var width: Int
        var height: Int
        var state: UInt8
        var paletteID: UInt8
        var objects: [CompositionObject]
    }

    private static func u16(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) << 8 | Int(d[o + 1]) }
    private static func u32(_ d: [UInt8], _ o: Int) -> UInt32 {
        UInt32(d[o]) << 24 | UInt32(d[o + 1]) << 16 | UInt32(d[o + 2]) << 8 | UInt32(d[o + 3])
    }

    public static func parse(_ data: Data) -> PGSParseResult {
        let bytes = [UInt8](data)
        var cues: [PGSBitmapCue] = []
        var warnings: [String] = []
        var segments = 0
        var damaged = 0

        var palettes: [UInt8: [RawPaletteEntry]] = [:]
        var objects: [UInt16: DecodedObject] = [:]
        var pending: [UInt16: PendingObject] = [:]
        var composition: Composition?
        var open: (start: TimeInterval, cue: PGSBitmapCue)?
        var orphanFragments = 0
        var missingObjects = 0
        var missingPalettes = 0
        var resyncs = 0
        var truncated = false

        func close(at time: TimeInterval) {
            if let o = open {
                var cue = o.cue
                cue.end = time
                if cue.end > cue.start { cues.append(cue) }
            }
            open = nil
        }

        func present(_ comp: Composition) {
            close(at: comp.pts)
            if comp.objects.isEmpty { return }
            let raw = palettes[comp.paletteID]
            if raw == nil { missingPalettes += 1 }
            let palette = convert(raw ?? [], frameHeight: comp.height)
            var shown: [PGSBitmapObject] = []
            for co in comp.objects {
                guard let obj = objects[co.objectID] else { missingObjects += 1; continue }
                var x = co.x, y = co.y, w = obj.width, h = obj.height
                var pixels = obj.indices
                if let crop = co.crop {
                    let cx = max(0, min(crop.x, obj.width)), cy = max(0, min(crop.y, obj.height))
                    let cw = max(0, min(crop.w, obj.width - cx)), ch = max(0, min(crop.h, obj.height - cy))
                    if cw == 0 || ch == 0 { continue }
                    var cropped = [UInt8](repeating: 0, count: cw * ch)
                    for row in 0..<ch {
                        for col in 0..<cw { cropped[row * cw + col] = obj.indices[(cy + row) * obj.width + cx + col] }
                    }
                    pixels = cropped
                    w = cw
                    h = ch
                    x = co.x
                    y = co.y
                }
                shown.append(PGSBitmapObject(x: x, y: y, width: w, height: h, indices: pixels, palette: palette, isForced: co.forced, isDamaged: obj.damaged))
            }
            if shown.isEmpty { return }
            let cue = PGSBitmapCue(start: comp.pts, end: comp.pts + unterminatedDuration, frameWidth: comp.width, frameHeight: comp.height, objects: shown)
            open = (comp.pts, cue)
        }

        var pos = 0
        while pos + 13 <= bytes.count {
            if bytes[pos] != 0x50 || bytes[pos + 1] != 0x47 {
                // Lost sync: look for the next "PG" that starts a plausible segment.
                resyncs += 1
                damaged += 1
                var next = pos + 1
                var found = false
                while next + 13 <= bytes.count {
                    if bytes[next] == 0x50, bytes[next + 1] == 0x47, [0x14, 0x15, 0x16, 0x17, 0x18, 0x80].contains(bytes[next + 10]) { found = true; break }
                    next += 1
                }
                if !found { break }
                pos = next
                continue
            }
            let pts = TimeInterval(u32(bytes, pos + 2)) / 90_000
            let type = bytes[pos + 10]
            let size = u16(bytes, pos + 11)
            let bodyStart = pos + 13
            if bodyStart + size > bytes.count {
                damaged += 1
                truncated = true
                warnings.append("The stream ends in the middle of a segment")
                break
            }
            let body = Array(bytes[bodyStart..<(bodyStart + size)])
            pos = bodyStart + size
            segments += 1

            switch type {
            case 0x16: // PCS
                if body.count < 11 {
                    damaged += 1
                    composition = nil
                    continue
                }
                let state = body[7]
                let count = Int(body[10])
                var list: [CompositionObject] = []
                var o = 11
                var ok = true
                for _ in 0..<count {
                    if o + 8 > body.count { ok = false; break }
                    let flag = body[o + 3]
                    var co = CompositionObject(objectID: UInt16(u16(body, o)), x: u16(body, o + 4), y: u16(body, o + 6), forced: flag & 0x40 != 0, crop: nil)
                    o += 8
                    if flag & 0x80 != 0 {
                        if o + 8 > body.count { ok = false; break }
                        co.crop = (u16(body, o), u16(body, o + 2), u16(body, o + 4), u16(body, o + 6))
                        o += 8
                    }
                    list.append(co)
                }
                if !ok { damaged += 1 }
                if state & 0x80 != 0 {
                    // Epoch start: everything defined earlier is gone.
                    palettes.removeAll()
                    objects.removeAll()
                    pending.removeAll()
                }
                composition = Composition(pts: pts, width: u16(body, 0), height: u16(body, 2), state: state, paletteID: body[9], objects: ok ? list : [])
            case 0x14: // PDS
                if body.count < 2 { damaged += 1; continue }
                let id = body[0]
                var entries = palettes[id] ?? [RawPaletteEntry](repeating: RawPaletteEntry(), count: 256)
                var o = 2
                while o + 5 <= body.count {
                    entries[Int(body[o])] = RawPaletteEntry(y: body[o + 1], cr: body[o + 2], cb: body[o + 3], a: body[o + 4])
                    o += 5
                }
                if o != body.count { damaged += 1 }
                palettes[id] = entries
            case 0x15: // ODS
                if body.count < 4 { damaged += 1; continue }
                let id = UInt16(u16(body, 0))
                let sequence = body[3]
                var payload = Array(body[4...])
                if sequence & 0x80 != 0 {
                    if payload.count < 7 { damaged += 1; pending[id] = nil; continue }
                    let total = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                    let w = u16(payload, 3), h = u16(payload, 5)
                    payload.removeFirst(7)
                    if w == 0 || h == 0 || w * h > 16_000_000 || total < 4 {
                        damaged += 1
                        pending[id] = nil
                        continue
                    }
                    pending[id] = PendingObject(width: w, height: h, expectedLength: total - 4, data: [])
                } else if pending[id] == nil {
                    orphanFragments += 1
                    damaged += 1
                    continue
                }
                guard var p = pending[id] else { continue }
                p.data.append(contentsOf: payload)
                if sequence & 0x40 != 0 {
                    pending[id] = nil
                    let result = decodeRLE(p.data, width: p.width, height: p.height)
                    var isDamaged = result.damaged
                    if p.data.count != p.expectedLength { isDamaged = true }
                    if isDamaged { damaged += 1 }
                    objects[id] = DecodedObject(width: p.width, height: p.height, indices: result.pixels, damaged: isDamaged)
                } else {
                    pending[id] = p
                }
            case 0x80: // END
                if let comp = composition { present(comp) }
                composition = nil
            default:
                break   // WDS (0x17), IDS (0x18) and unknown types do not change what is drawn
            }
        }
        if pos < bytes.count, !truncated {
            damaged += 1
            warnings.append("The stream ends with data that is too short to be a segment")
        }
        // A display set without END at the very end of the data.
        if let comp = composition { present(comp) }
        if let o = open { var c = o.cue; c.end = c.start + unterminatedDuration; cues.append(c); open = nil }

        if resyncs > 0 { warnings.append("Lost sync \(resyncs) time(s) and skipped ahead to the next segment") }
        if orphanFragments > 0 { warnings.append("\(orphanFragments) object fragment(s) had no start and were dropped") }
        if missingObjects > 0 { warnings.append("\(missingObjects) composition(s) referred to an object that was never defined") }
        if missingPalettes > 0 { warnings.append("\(missingPalettes) composition(s) used a palette that was never defined (shown transparent)") }
        cues.sort { $0.start < $1.start }
        return PGSParseResult(cues: cues, warnings: warnings, segmentsRead: segments, damagedSegments: damaged)
    }

    // MARK: RLE

    /// Decodes the PGS run-length data. Lines end with `00 00`. Short or long lines are padded or cut and
    /// reported through `damaged`.
    static func decodeRLE(_ data: [UInt8], width: Int, height: Int) -> (pixels: [UInt8], damaged: Bool) {
        var pixels = [UInt8](repeating: 0, count: width * height)
        var damaged = false
        var x = 0, y = 0
        var i = 0
        func put(_ value: UInt8, _ count: Int) {
            if y >= height { damaged = true; return }
            var remaining = count
            while remaining > 0 {
                if x >= width { damaged = true; return }
                pixels[y * width + x] = value
                x += 1
                remaining -= 1
            }
        }
        while i < data.count, y < height {
            let b = data[i]
            i += 1
            if b != 0 { put(b, 1); continue }
            guard i < data.count else { damaged = true; break }
            let c = data[i]
            i += 1
            if c == 0 {
                if x < width { damaged = true }   // short line
                x = 0
                y += 1
                continue
            }
            switch c & 0xC0 {
            case 0x00:
                put(0, Int(c & 0x3F))
            case 0x40:
                guard i < data.count else { damaged = true; return (pixels, true) }
                put(0, Int(c & 0x3F) << 8 | Int(data[i]))
                i += 1
            case 0x80:
                guard i < data.count else { damaged = true; return (pixels, true) }
                put(data[i], Int(c & 0x3F))
                i += 1
            default:
                guard i + 1 < data.count else { damaged = true; return (pixels, true) }
                put(data[i + 1], Int(c & 0x3F) << 8 | Int(data[i]))
                i += 2
            }
        }
        if y < height { damaged = true }   // too few lines
        return (pixels, damaged)
    }

    // MARK: Colour

    /// YCrCb (limited range) to RGB. BT.709 for frames 720 lines or taller, BT.601 below.
    private static func convert(_ raw: [RawPaletteEntry], frameHeight: Int) -> [SubtitleColor] {
        var out = [SubtitleColor](repeating: SubtitleColor(red: 0, green: 0, blue: 0, alpha: 0), count: 256)
        let hd = frameHeight >= 720
        for (i, e) in raw.enumerated() where i < 256 {
            let y = 1.164 * (Double(e.y) - 16)
            let cb = Double(e.cb) - 128
            let cr = Double(e.cr) - 128
            let r = hd ? y + 1.793 * cr : y + 1.596 * cr
            let g = hd ? y - 0.213 * cb - 0.533 * cr : y - 0.392 * cb - 0.813 * cr
            let b = hd ? y + 2.112 * cb : y + 2.017 * cb
            out[i] = SubtitleColor(red: clamp(r), green: clamp(g), blue: clamp(b), alpha: e.a)
        }
        return out
    }

    private static func clamp(_ v: Double) -> UInt8 {
        if v.isNaN { return 0 }
        return UInt8(max(0, min(255, v.rounded())))
    }
}
