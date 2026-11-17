import XCTest
@testable import Subtitles

final class PGSTests: XCTestCase {

    private typealias Bitmap = (id: UInt16, x: Int, y: Int, w: Int, h: Int, indices: [UInt8], forced: Bool)

    private func gradient(_ w: Int, _ h: Int, seed: UInt64 = 1) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        // Mostly runs, some noise, plenty of zeros: exercises every RLE form.
        var out: [UInt8] = []
        while out.count < w * h {
            let value = UInt8(rng.int(4) == 0 ? 0 : 1 + rng.int(200))
            let run = 1 + rng.int(rng.int(5) == 0 ? 200 : 6)
            out.append(contentsOf: [UInt8](repeating: value, count: min(run, w * h - out.count)))
        }
        return out
    }

    private let simplePalette: [(UInt8, UInt8, UInt8, UInt8, UInt8)] = [
        (0, 16, 128, 128, 0),       // transparent
        (1, 235, 128, 128, 255),    // white
        (2, 16, 128, 128, 255),     // black
    ]

    // MARK: RLE

    func testRLERoundTripsEveryRunForm() {
        for (w, h) in [(1, 1), (7, 3), (300, 4), (64, 2), (63, 2), (16_384 / 8, 2)] {
            let pixels = gradient(w, h, seed: UInt64(w * 31 + h))
            let encoded = PGSTestEncoder.rle(pixels, width: w, height: h)
            let decoded = PGSParser.decodeRLE(encoded, width: w, height: h)
            XCTAssertEqual(decoded.pixels, pixels, "\(w)x\(h)")
            XCTAssertFalse(decoded.damaged, "\(w)x\(h)")
        }
    }

    func testRLELongRunsUseTheFourteenBitForms() {
        let row = [UInt8](repeating: 0, count: 1000) + [UInt8](repeating: 9, count: 1000)
        let encoded = PGSTestEncoder.rle(row, width: 2000, height: 1)
        XCTAssertEqual(encoded, [0, 0x43, 0xE8, 0, 0xC3, 0xE8, 9, 0, 0])   // 1000 = 0x03E8
        XCTAssertEqual(PGSParser.decodeRLE(encoded, width: 2000, height: 1).pixels, row)
    }

    func testRLEDamageIsReportedNotFatal() {
        // Short line, long line, missing lines, truncated escape.
        XCTAssertTrue(PGSParser.decodeRLE([1, 1, 0, 0, 1, 1, 0, 0], width: 3, height: 2).damaged)       // short lines
        XCTAssertTrue(PGSParser.decodeRLE([1, 1, 1, 1, 1, 0, 0], width: 3, height: 1).damaged)          // overlong line
        XCTAssertTrue(PGSParser.decodeRLE([1, 1, 1, 0, 0], width: 3, height: 3).damaged)                // missing lines
        XCTAssertTrue(PGSParser.decodeRLE([1, 1, 1, 0], width: 3, height: 1).damaged)                   // truncated
        XCTAssertTrue(PGSParser.decodeRLE([0, 0xC0], width: 3, height: 1).damaged)
        let ok = PGSParser.decodeRLE([1, 2, 3, 0, 0], width: 3, height: 1)
        XCTAssertEqual(ok.pixels, [1, 2, 3])
        XCTAssertFalse(ok.damaged)
    }

    // MARK: Display sets

    func testSingleBitmapCue() throws {
        var e = PGSTestEncoder()
        let pixels = gradient(40, 20)
        e.showSet(pts: 1.0, bitmaps: [(1, 100, 900, 40, 20, pixels, false)], palette: simplePalette)
        e.clearSet(pts: 3.5)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 1)
        XCTAssertEqual(r.damagedSegments, 0)
        XCTAssertEqual(r.warnings, [])
        let c = try XCTUnwrap(r.cues.first)
        XCTAssertEqual(c.start, 1.0, accuracy: 1e-5)
        XCTAssertEqual(c.end, 3.5, accuracy: 1e-5)
        XCTAssertEqual([c.frameWidth, c.frameHeight], [1920, 1080])
        XCTAssertEqual(c.objects.count, 1)
        let o = c.objects[0]
        XCTAssertEqual([o.x, o.y, o.width, o.height], [100, 900, 40, 20])
        XCTAssertEqual(o.indices, pixels)
        XCTAssertFalse(o.isForced)
        XCTAssertFalse(o.isDamaged)
        XCTAssertEqual(o.palette.count, 256)
        XCTAssertEqual(o.palette[1], SubtitleColor(red: 255, green: 255, blue: 255, alpha: 255))
        XCTAssertEqual(o.palette[2], SubtitleColor(red: 0, green: 0, blue: 0, alpha: 255))
        XCTAssertEqual(o.palette[0].alpha, 0)
        XCTAssertEqual(o.palette[77].alpha, 0, "entries the stream never defined are transparent")
        let rgba = o.rgba()
        XCTAssertEqual(rgba.count, 40 * 20 * 4)
        let first = Int(pixels[0])
        XCTAssertEqual(rgba[3], o.palette[first].alpha)
    }

    func testMultiFragmentObjectIsReassembled() throws {
        var e = PGSTestEncoder()
        let a = gradient(120, 40, seed: 11)
        let b = gradient(90, 30, seed: 12)
        // Tiny fragments force many ODS segments per object.
        e.showSet(pts: 2.0, bitmaps: [(1, 10, 20, 120, 40, a, false), (2, 10, 80, 90, 30, b, false)], palette: simplePalette, fragmentSize: 17)
        e.clearSet(pts: 4.0)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.damagedSegments, 0)
        let c = try XCTUnwrap(r.cues.first)
        XCTAssertEqual(c.objects.count, 2)
        XCTAssertEqual(c.objects[0].indices, a)
        XCTAssertEqual(c.objects[1].indices, b)
        XCTAssertGreaterThan(r.segmentsRead, 20, "many fragments were read")
    }

    func testForcedFlagAndTimingOfSuccessiveSets() throws {
        var e = PGSTestEncoder()
        e.showSet(pts: 1.0, bitmaps: [(1, 0, 0, 4, 4, [UInt8](repeating: 1, count: 16), false)], palette: simplePalette)
        e.showSet(pts: 5.0, state: 0x00, number: 1, bitmaps: [(2, 0, 0, 4, 4, [UInt8](repeating: 2, count: 16), true)], palette: nil)
        e.clearSet(pts: 6.0, number: 2)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 2)
        XCTAssertEqual(r.cues[0].end, 5.0, accuracy: 1e-5, "a new composition ends the previous cue")
        XCTAssertFalse(r.cues[0].isForced)
        XCTAssertTrue(r.cues[1].isForced)
        XCTAssertEqual(r.cues[1].start, 5.0, accuracy: 1e-5)
        XCTAssertEqual(r.cues[1].end, 6.0, accuracy: 1e-5)
        XCTAssertEqual(r.cues[1].objects[0].indices, [UInt8](repeating: 2, count: 16))
    }

    func testPaletteUpdateChangesColoursWithoutResendingObjects() throws {
        var e = PGSTestEncoder()
        let pixels = [UInt8](repeating: 1, count: 6 * 6)
        e.showSet(pts: 1.0, bitmaps: [(1, 50, 50, 6, 6, pixels, false)], palette: [(0, 16, 128, 128, 0), (1, 235, 128, 128, 255)])
        // Palette-only update: new PCS (palette update flag), new palette, no ODS.
        e.pcs(pts: 2.0, state: 0x00, paletteUpdate: true, objects: [PGSTestEncoder.CompObject(id: 1, x: 50, y: 50)])
        e.pds(pts: 2.0, entries: [(1, 16, 128, 128, 255)])     // index 1 becomes black
        e.end(pts: 2.0)
        e.clearSet(pts: 3.0)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 2)
        XCTAssertEqual(r.cues[0].objects[0].palette[1], SubtitleColor(red: 255, green: 255, blue: 255, alpha: 255))
        XCTAssertEqual(r.cues[1].objects[0].palette[1], SubtitleColor(red: 0, green: 0, blue: 0, alpha: 255))
        XCTAssertEqual(r.cues[1].objects[0].indices, pixels, "the object is reused")
        XCTAssertEqual(r.cues[0].end, r.cues[1].start, accuracy: 1e-5)
        XCTAssertEqual(r.cues[1].end, 3.0, accuracy: 1e-5)
    }

    func testPaletteColourMatricesBT709AndBT601() throws {
        // Y/Cr/Cb of a pure red in each matrix (limited range).
        func firstColour(height: Int, entry: (UInt8, UInt8, UInt8, UInt8, UInt8)) throws -> SubtitleColor {
            var e = PGSTestEncoder()
            e.showSet(pts: 1, width: height * 16 / 9, height: height, bitmaps: [(1, 0, 0, 1, 1, [1], false)], palette: [entry])
            e.clearSet(pts: 2, width: height * 16 / 9, height: height)
            return try XCTUnwrap(PGSParser.parse(e.data).cues.first?.objects.first?.palette[1])
        }
        let hd = try firstColour(height: 1080, entry: (1, 63, 240, 102, 255))
        XCTAssertEqual(Int(hd.red), 255, accuracy: 3)
        XCTAssertEqual(Int(hd.green), 0, accuracy: 3)
        XCTAssertEqual(Int(hd.blue), 0, accuracy: 3)
        let sd = try firstColour(height: 480, entry: (1, 81, 240, 90, 255))
        XCTAssertEqual(Int(sd.red), 255, accuracy: 3)
        XCTAssertEqual(Int(sd.green), 0, accuracy: 3)
        XCTAssertEqual(Int(sd.blue), 0, accuracy: 3)
        // The same bytes read with the wrong matrix would be visibly different (sanity check of the switch at 720).
        let sdBytesAsHD = try firstColour(height: 720, entry: (1, 81, 240, 90, 255))
        XCTAssertGreaterThan(abs(Int(sdBytesAsHD.green) - Int(sd.green)) + abs(Int(sdBytesAsHD.blue) - Int(sd.blue)) + abs(Int(sdBytesAsHD.red) - Int(sd.red)), 5)
    }

    func testEpochStartForgetsEarlierObjects() throws {
        var e = PGSTestEncoder()
        e.showSet(pts: 1.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        e.clearSet(pts: 2.0)
        // New epoch that refers to object 1 without redefining it: it is gone.
        e.pcs(pts: 3.0, state: 0x80, objects: [PGSTestEncoder.CompObject(id: 1, x: 0, y: 0)])
        e.pds(pts: 3.0, entries: simplePalette)
        e.end(pts: 3.0)
        e.clearSet(pts: 4.0)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 1)
        XCTAssertTrue(r.warnings.contains { $0.contains("never defined") })
    }

    func testNormalCompositionKeepsObjectsFromEarlierInTheEpoch() throws {
        var e = PGSTestEncoder()
        e.showSet(pts: 1.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        e.clearSet(pts: 2.0)
        e.pcs(pts: 3.0, state: 0x00, objects: [PGSTestEncoder.CompObject(id: 1, x: 7, y: 8)])
        e.end(pts: 3.0)
        e.clearSet(pts: 4.0)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 2)
        XCTAssertEqual([r.cues[1].objects[0].x, r.cues[1].objects[0].y], [7, 8])
    }

    func testCroppedObject() throws {
        var e = PGSTestEncoder()
        let pixels: [UInt8] = (0..<(6 * 4)).map { UInt8($0 + 1) }   // 6x4, values 1...24
        e.pcs(pts: 1.0, state: 0x80, objects: [PGSTestEncoder.CompObject(id: 1, x: 200, y: 300, crop: (x: 2, y: 1, w: 3, h: 2))])
        e.pds(pts: 1.0, entries: simplePalette)
        e.ods(pts: 1.0, id: 1, width: 6, height: 4, indices: pixels)
        e.end(pts: 1.0)
        e.clearSet(pts: 2.0)
        let o = try XCTUnwrap(PGSParser.parse(e.data).cues.first?.objects.first)
        XCTAssertEqual([o.x, o.y, o.width, o.height], [200, 300, 3, 2])
        XCTAssertEqual(o.indices, [9, 10, 11, 15, 16, 17])
    }

    func testStreamWithoutClearingSetEndsAfterDefaultDuration() throws {
        var e = PGSTestEncoder()
        e.showSet(pts: 10.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        let c = try XCTUnwrap(PGSParser.parse(e.data).cues.first)
        XCTAssertEqual(c.end - c.start, PGSParser.unterminatedDuration, accuracy: 1e-5)
    }

    func testEmptyAndTinyInputs() {
        XCTAssertEqual(PGSParser.parse(Data()).cues.count, 0)
        XCTAssertEqual(PGSParser.parse(Data([0x50, 0x47])).cues.count, 0)
        XCTAssertEqual(PGSParser.parse(Data(repeating: 0, count: 100)).cues.count, 0)
    }

    // MARK: Corruption

    func testGarbageBetweenSegmentsResyncsAndLaterCuesSurvive() throws {
        var e = PGSTestEncoder()
        e.showSet(pts: 1.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        e.clearSet(pts: 2.0)
        e.data.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33, 0x50, 0x00, 0x50, 0x47, 0x01])   // junk with a fake "PG"
        e.showSet(pts: 5.0, bitmaps: [(1, 0, 0, 2, 2, [2, 2, 2, 2], false)], palette: simplePalette)
        e.clearSet(pts: 6.0)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 2)
        XCTAssertGreaterThan(r.damagedSegments, 0)
        XCTAssertEqual(r.cues[1].start, 5.0, accuracy: 1e-5)
        XCTAssertEqual(r.cues[1].objects[0].indices, [2, 2, 2, 2])
        XCTAssertTrue(r.warnings.contains { $0.contains("sync") })
    }

    func testTruncatedLastSegmentIsReportedAndEarlierCuesKept() {
        var e = PGSTestEncoder()
        e.showSet(pts: 1.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        e.clearSet(pts: 2.0)
        e.showSet(pts: 5.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        let cut = Data(e.data.prefix(e.data.count - 9))
        let r = PGSParser.parse(cut)
        XCTAssertGreaterThanOrEqual(r.cues.count, 1)
        XCTAssertEqual(r.cues[0].start, 1.0, accuracy: 1e-5)
        XCTAssertGreaterThan(r.damagedSegments, 0)
    }

    func testCorruptRLEMarksObjectDamagedButStillProducesACue() throws {
        var e = PGSTestEncoder()
        e.pcs(pts: 1.0, state: 0x80, objects: [PGSTestEncoder.CompObject(id: 1, x: 0, y: 0)])
        e.pds(pts: 1.0, entries: simplePalette)
        e.odsRaw(pts: 1.0, id: 1, width: 4, height: 3, rle: [1, 1, 1, 0, 0, 1, 1], fragmentSize: 100)   // one full line, one short line, one missing
        e.end(pts: 1.0)
        e.clearSet(pts: 2.0)
        let r = PGSParser.parse(e.data)
        let o = try XCTUnwrap(r.cues.first?.objects.first)
        XCTAssertTrue(o.isDamaged)
        XCTAssertEqual(o.indices.count, 12)
        XCTAssertGreaterThan(r.damagedSegments, 0)
    }

    func testContinuationWithoutStartAndAbsurdDimensionsAreDropped() {
        var e = PGSTestEncoder()
        // A continuation fragment (flag 0x40 only) for an object that never started.
        e.segment(type: 0x15, pts: 1.0, body: [0, 9, 0, 0x40, 1, 2, 3])
        // First fragment claiming 60000 x 60000 pixels.
        e.segment(type: 0x15, pts: 1.0, body: [0, 8, 0, 0xC0, 0, 0, 5, 0xEA, 0x60, 0xEA, 0x60, 0])
        e.pcs(pts: 1.0, state: 0x80, objects: [PGSTestEncoder.CompObject(id: 9, x: 0, y: 0), PGSTestEncoder.CompObject(id: 8, x: 0, y: 0)])
        e.pds(pts: 1.0, entries: simplePalette)
        e.end(pts: 1.0)
        let r = PGSParser.parse(e.data)
        XCTAssertEqual(r.cues.count, 0)
        XCTAssertGreaterThanOrEqual(r.damagedSegments, 2)
        XCTAssertTrue(r.warnings.contains { $0.contains("no start") })
    }

    func testUnknownSegmentTypesAreSkipped() throws {
        var e = PGSTestEncoder()
        e.segment(type: 0x18, pts: 0.5, body: [1, 2, 3, 4])     // interactive graphics, ignored
        e.showSet(pts: 1.0, bitmaps: [(1, 0, 0, 2, 2, [1, 1, 1, 1], false)], palette: simplePalette)
        e.clearSet(pts: 2.0)
        XCTAssertEqual(PGSParser.parse(e.data).cues.count, 1)
    }

    func testRandomBitFlipsNeverCrashOrHang() {
        var clean = PGSTestEncoder()
        for n in 0..<6 {
            let t = Double(n) * 3
            clean.showSet(pts: t + 1, bitmaps: [(1, 10, 10, 30, 12, gradient(30, 12, seed: UInt64(n)), n % 2 == 0), (2, 10, 40, 20, 8, gradient(20, 8, seed: UInt64(n + 50)), false)], palette: simplePalette, fragmentSize: 25)
            clean.clearSet(pts: t + 2)
        }
        var rng = SplitMix64(seed: 0xB17F11B)
        for round in 0..<300 {
            var bytes = [UInt8](clean.data)
            for _ in 0..<(1 + rng.int(12)) { bytes[rng.int(bytes.count)] = UInt8(truncatingIfNeeded: rng.next()) }
            if round % 5 == 0 { bytes.removeLast(rng.int(40)) }
            if round % 7 == 0 { bytes.insert(contentsOf: [UInt8](repeating: 0x50, count: 3), at: rng.int(bytes.count)) }
            let r = PGSParser.parse(Data(bytes))
            for c in r.cues {
                XCTAssertGreaterThan(c.end, c.start)
                for o in c.objects { XCTAssertEqual(o.indices.count, o.width * o.height) }
            }
        }
    }

    // MARK: Placement

    private func cue(frameW: Int = 1920, frameH: Int = 1080, objects: [(x: Int, y: Int, w: Int, h: Int)]) -> PGSBitmapCue {
        let palette = [SubtitleColor](repeating: SubtitleColor(red: 1, green: 2, blue: 3), count: 256)
        let objs = objects.map { PGSBitmapObject(x: $0.x, y: $0.y, width: $0.w, height: $0.h, indices: [UInt8](repeating: 0, count: $0.w * $0.h), palette: palette, isForced: false, isDamaged: false) }
        return PGSBitmapCue(start: 0, end: 1, frameWidth: frameW, frameHeight: frameH, objects: objs)
    }

    func testPlacementSameSizeAndScaledUp() {
        let c = cue(objects: [(400, 900, 1000, 100)])
        XCTAssertEqual(PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080), [PlacedRect(x: 400, y: 900, width: 1000, height: 100)])
        XCTAssertEqual(PGSPlacement.place(c, containerWidth: 3840, containerHeight: 2160), [PlacedRect(x: 800, y: 1800, width: 2000, height: 200)])
        XCTAssertEqual(PGSPlacement.place(c, containerWidth: 960, containerHeight: 540), [PlacedRect(x: 200, y: 450, width: 500, height: 50)])
    }

    func testPlacementFitCentresInADifferentAspect() throws {
        // 16:9 stream shown in a 4:3 container: scale 0.5 on both axes, bars above and below.
        let c = cue(objects: [(0, 0, 1920, 1080)])
        let r = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 960, containerHeight: 720).first)
        XCTAssertEqual(r.width, 960, accuracy: 1e-9)
        XCTAssertEqual(r.height, 540, accuracy: 1e-9)
        XCTAssertEqual(r.x, 0, accuracy: 1e-9)
        XCTAssertEqual(r.y, 90, accuracy: 1e-9)
        // Wider container: bars left and right.
        let w = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 2560, containerHeight: 1080).first)
        XCTAssertEqual(w.width, 1920, accuracy: 1e-9)
        XCTAssertEqual(w.x, 320, accuracy: 1e-9)
    }

    func testPlacementStretchUsesBothAxes() throws {
        let c = cue(objects: [(960, 540, 100, 100)])
        let r = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 960, containerHeight: 1080, options: PGSPlacementOptions(aspect: .stretch)).first)
        XCTAssertEqual(r, PlacedRect(x: 480, y: 540, width: 50, height: 100))
    }

    func testPlacementOtherStreamSizes() throws {
        // A 1280x720 stream in a 1920x1080 container scales by 1.5; a 720x480 DVD-sized stream by 2.25 (fit).
        let hd = cue(frameW: 1280, frameH: 720, objects: [(100, 600, 200, 40)])
        XCTAssertEqual(PGSPlacement.place(hd, containerWidth: 1920, containerHeight: 1080), [PlacedRect(x: 150, y: 900, width: 300, height: 60)])
        let sd = cue(frameW: 720, frameH: 480, objects: [(0, 400, 720, 50)])
        let r = try XCTUnwrap(PGSPlacement.place(sd, containerWidth: 1620, containerHeight: 1080).first)
        XCTAssertEqual(r.width, 1620, accuracy: 1e-9)
        XCTAssertEqual(r.y, 900, accuracy: 1e-9)
    }

    func testVerticalOffsetMovesLowerSubtitlesUp() throws {
        let c = cue(objects: [(500, 900, 900, 100)])
        let up = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: 0.05)).first)
        XCTAssertEqual(up.y, 900 - 54, accuracy: 1e-9)
        let down = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: -0.02)).first)
        XCTAssertEqual(down.y, 900 + 21.6, accuracy: 1e-9)
        XCTAssertEqual(up.x, 500)
    }

    func testVerticalOffsetIsClampedToTheScreenAndKeepsBlocksTogether() {
        let c = cue(objects: [(100, 800, 500, 80), (100, 900, 500, 100)])
        let down = PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: -0.2))
        XCTAssertEqual(down[1].maxY, 1080, accuracy: 1e-9, "stops at the bottom edge")
        XCTAssertEqual(down[1].y - down[0].y, 100, accuracy: 1e-9, "spacing between the two bitmaps is unchanged")
        let high = cue(objects: [(100, 300, 500, 80)])
        let up = PGSPlacement.place(high, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: 0.5, moveTopSubtitles: true))
        XCTAssertEqual(up[0].y, 0, accuracy: 1e-9, "stops at the top edge")
    }

    func testTopSubtitlesStayPutUnlessAsked() throws {
        let c = cue(objects: [(500, 60, 900, 80)])
        let still = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: 0.1)).first)
        XCTAssertEqual(still.y, 60)
        let moved = try XCTUnwrap(PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: -0.1, moveTopSubtitles: true)).first)
        XCTAssertEqual(moved.y, 60 + 108, accuracy: 1e-9)
    }

    func testPlacementRefusesNonsense() {
        let c = cue(objects: [(0, 0, 10, 10)])
        XCTAssertTrue(PGSPlacement.place(c, containerWidth: 0, containerHeight: 100).isEmpty)
        XCTAssertTrue(PGSPlacement.place(c, containerWidth: 100, containerHeight: -1).isEmpty)
        XCTAssertTrue(PGSPlacement.place(c, containerWidth: .nan, containerHeight: 100).isEmpty)
        XCTAssertTrue(PGSPlacement.place(cue(frameW: 0, objects: [(0, 0, 1, 1)]), containerWidth: 100, containerHeight: 100).isEmpty)
        XCTAssertTrue(PGSPlacement.place(cue(objects: []), containerWidth: 100, containerHeight: 100).isEmpty)
        // A NaN offset is treated as no offset.
        let r = PGSPlacement.place(c, containerWidth: 1920, containerHeight: 1080, options: PGSPlacementOptions(verticalOffset: .nan))
        XCTAssertEqual(r.count, 1)
    }
}
