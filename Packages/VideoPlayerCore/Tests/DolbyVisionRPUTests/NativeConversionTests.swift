import XCTest
import Foundation
@testable import RemuxEngine
@testable import DolbyVisionRPU

// The native converter on real profile 7 streams (FIXTURE media made by scripts/test-dovi.sh: an x265 HDR10 base layer,
// a quarter-size enhancement layer, generated RPUs muxed by the reference command line tool, and that tool's own
// profile 8.1 conversion as the reference). Skipped unless VP_DOVI_MEDIA points at that media and the library is linked.

enum DoviMedia {
    static var dir: URL? {
        guard let p = ProcessInfo.processInfo.environment["VP_DOVI_MEDIA"],
              FileManager.default.fileExists(atPath: p + "/done.96") else { return nil }
        return URL(fileURLWithPath: p)
    }
    static func bytes(_ name: String) throws -> [UInt8] {
        guard let d = dir else { throw XCTSkip("VP_DOVI_MEDIA not set: run scripts/test-dovi.sh") }
        return [UInt8](try Data(contentsOf: d.appendingPathComponent(name)))
    }
}

/// NAL units of an Annex B stream (start codes removed; trailing zero bytes before a start code removed).
func annexBNALs(_ b: [UInt8]) -> [ArraySlice<UInt8>] {
    var starts: [(code: Int, payload: Int)] = []
    var i = 0
    while i + 2 < b.count {
        if b[i] == 0, b[i + 1] == 0, b[i + 2] == 1 { starts.append((i, i + 3)); i += 3 } else { i += 1 }
    }
    var out: [ArraySlice<UInt8>] = []
    for (k, s) in starts.enumerated() {
        var end = k + 1 < starts.count ? starts[k + 1].code : b.count
        while end > s.payload, b[end - 1] == 0 { end -= 1 }
        out.append(b[s.payload..<end])
    }
    return out
}

/// Access units: a new one starts at every layer-0 access unit delimiter (the fixtures are encoded with AUDs).
func accessUnits(_ nals: [ArraySlice<UInt8>]) -> [[ArraySlice<UInt8>]] {
    var aus: [[ArraySlice<UInt8>]] = []
    for n in nals {
        if HEVCNAL.type(of: n) == 35, DolbyVisionNAL.layerID(of: n) == 0 || aus.isEmpty { aus.append([n]) } else { aus[aus.count - 1].append(n) }
    }
    return aus
}

func prefixed(_ nals: [ArraySlice<UInt8>]) -> [UInt8] {
    var out: [UInt8] = []
    for n in nals { appendLengthPrefixed(n, lengthSize: 4, to: &out) }
    return out
}

final class NativeConversionTests: XCTestCase {
    var converter: DolbyVisionProfile7Converter!

    override func setUpWithError() throws {
        guard let c = DolbyVisionProfile7Converter.native() else { throw XCTSkip("RPU library not linked (set VP_LIBDOVI, see scripts/test-dovi.sh)") }
        guard DoviMedia.dir != nil else { throw XCTSkip("VP_DOVI_MEDIA not set: run scripts/test-dovi.sh") }
        converter = c
    }

    /// Every access unit converted by this app equals the reference tool's `-m 2 convert --discard` output, NAL for NAL.
    func testElementaryStreamsMatchTheReferenceToolByteForByte() throws {
        for name in ["p7_fel", "p7_mel", "p7_switch"] {
            let source = accessUnits(annexBNALs(try DoviMedia.bytes(name + ".hevc")))
            let reference = accessUnits(annexBNALs(try DoviMedia.bytes("ref81_" + name + ".hevc")))
            XCTAssertEqual(source.count, 96, name); XCTAssertEqual(reference.count, source.count, name)
            var rpuCompared = 0, mismatches: [Int] = []
            for (k, au) in source.enumerated() where k < reference.count {
                let out = try splitLengthPrefixed(try converter.convert(sample: prefixed(au), lengthSize: 4), lengthSize: 4)
                if out.map(Array.init) != reference[k].map(Array.init) { mismatches.append(k) }
                XCTAssertFalse(out.contains(where: DolbyVisionNAL.isEnhancementLayer), "\(name) AU \(k): enhancement layer left")
                rpuCompared += out.filter { HEVCNAL.type(of: $0) == HEVCNAL.dolbyVisionRPU }.count
            }
            XCTAssertEqual(mismatches, [], "\(name): access units that differ from the reference tool")
            XCTAssertEqual(rpuCompared, 96, "\(name): one RPU per access unit")
            // The source really had an enhancement layer in the profile 7 part.
            XCTAssertTrue(source[0].contains(where: DolbyVisionNAL.isEnhancementLayer), name)
        }
        XCTAssertEqual(converter.stats.rejectedAccessUnits, 0)
    }

    func testInspectTellsFELFromMELAndSeesTheProfileSwitch() throws {
        let fel = accessUnits(annexBNALs(try DoviMedia.bytes("p7_fel.hevc")))
        let mel = accessUnits(annexBNALs(try DoviMedia.bytes("p7_mel.hevc")))
        let sw = accessUnits(annexBNALs(try DoviMedia.bytes("p7_switch.hevc")))
        XCTAssertEqual(converter.inspect(sample: prefixed(fel[0]), lengthSize: 4),
                       DolbyVisionSampleInfo(profile: 7, enhancementLayer: .full, hasEnhancementLayerNALs: true))
        XCTAssertEqual(converter.inspect(sample: prefixed(mel[0]), lengthSize: 4),
                       DolbyVisionSampleInfo(profile: 7, enhancementLayer: .minimal, hasEnhancementLayerNALs: true))
        XCTAssertEqual(converter.inspect(sample: prefixed(sw[95]), lengthSize: 4)?.profile, 8, "second half of the switching file is profile 8.1")
        XCTAssertEqual(converter.inspect(sample: prefixed(sw[95]), lengthSize: 4)?.hasEnhancementLayerNALs, false)
        // Converted RPUs read back as profile 8.
        let out = try converter.convert(sample: prefixed(fel[5]), lengthSize: 4)
        XCTAssertEqual(converter.inspect(sample: out, lengthSize: 4)?.profile, 8)
    }

    /// Converter cost on this machine (x86-64 WSL, not the target device): printed for the report, with a loose bound.
    func testConversionCostPerVideoSecond() throws {
        let aus = accessUnits(annexBNALs(try DoviMedia.bytes("p7_fel.hevc"))).map(prefixed)
        let rounds = 20
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<rounds { for au in aus { _ = try converter.convert(sample: au, lengthSize: 4) } }
        let perAU = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(rounds * aus.count) / 1000
        let rpuStart = DispatchTime.now().uptimeNanoseconds
        let rpus = aus.compactMap { try? splitLengthPrefixed($0, lengthSize: 4).first { HEVCNAL.type(of: $0) == HEVCNAL.dolbyVisionRPU } }
        for _ in 0..<rounds { for r in rpus { _ = try converter.codec.convertToProfile81(r) } }
        let perRPU = Double(DispatchTime.now().uptimeNanoseconds - rpuStart) / Double(rounds * rpus.count) / 1000
        print(String(format: "DOVI-COST: %.1f us per access unit (720p fixture, NAL rewrite + RPU), %.1f us per RPU alone; %.2f ms CPU per video second at 24 fps, %.2f ms at 60 fps",
                     perAU, perRPU, perAU * 24 / 1000, perAU * 60 / 1000))
        XCTAssertLessThan(perAU, 2000, "far below one frame time")
    }
}
