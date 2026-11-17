import XCTest
@testable import RemuxEngine

// JOC (Dolby Atmos in E-AC-3) detection. The frames below are BUILT BY THE TESTS from the bit layout in the spec, they
// are not captured from a real Atmos stream (that check is on the device checklist). What these tests prove: the parser
// follows the documented field order, including every optional block, and fails closed (nil) on anything odd.

final class EAC3AtmosTests: XCTestCase {
    struct Layout {
        var acmod = 7
        var lfeon = 1
        var strmtyp = 0
        var withMixMetadata = false
        var withInfoMetadata = false
        var addbsi: (flag: Int, complexity: Int)? = (1, 16)
        var addbsiLengthField = 1                      // addbsil: number of additional bytes minus one
    }

    func frame(_ l: Layout, bytes: Int = 512) -> [UInt8] {
        var w = BitWriter()
        w.put(l.strmtyp, 2); w.put(0, 3); w.put(bytes / 2 - 1, 11)
        w.put(0, 2); w.put(3, 2)                       // fscod 48 kHz, numblkscod 3 (six blocks)
        w.put(l.acmod, 3); w.put(l.lfeon, 1); w.put(16, 5)
        w.put(27, 5)                                   // dialnorm
        w.put(0, 1)                                    // compre
        if l.acmod == 0 { w.put(0, 5); w.put(0, 1) }
        if l.withMixMetadata {
            w.put(1, 1)                                // mixmdate
            if l.acmod > 2 { w.put(0, 2) }             // dmixmod
            if l.acmod & 1 != 0 && l.acmod > 2 { w.put(0, 6) }
            if l.acmod & 4 != 0 { w.put(0, 6) }
            if l.lfeon == 1 { w.put(0, 1) }            // lfemixlevcode
            if l.strmtyp == 0 {
                w.put(0, 1)                            // pgmscle
                if l.acmod == 0 { w.put(0, 1) }
                w.put(0, 1)                            // extpgmscle
                w.put(0, 2)                            // mixdef
                if l.acmod < 2 { w.put(0, 1); if l.acmod == 0 { w.put(0, 1) } }
                w.put(0, 1)                            // frmmixcfginfoe
            }
        } else { w.put(0, 1) }
        if l.withInfoMetadata {
            w.put(1, 1)                                // infomdate
            w.put(0, 5)                                // bsmod, copyrightb, origbs
            if l.acmod == 2 { w.put(0, 4) }
            if l.acmod >= 6 { w.put(0, 2) }
            w.put(0, 1)                                // audprodie
            if l.acmod == 0 { w.put(0, 1) }
            w.put(0, 1)                                // sourcefscod
        } else { w.put(0, 1) }
        if let a = l.addbsi {
            w.put(1, 1); w.put(l.addbsiLengthField, 6)
            w.put(0, 7); w.put(a.flag, 1); w.put(a.complexity, 8)
        } else {
            w.put(0, 1)
        }
        var f: [UInt8] = [0x0B, 0x77] + w.bytes
        while f.count < bytes { f.append(0) }
        return f
    }

    func testAtmosFlagGivesTheComplexityIndex() {
        XCTAssertEqual(EAC3Atmos.complexityIndex(accessUnit: frame(Layout())), 16)
        var l = Layout(); l.addbsi = (1, 15)
        XCTAssertEqual(EAC3Atmos.complexityIndex(accessUnit: frame(l)), 15)
    }

    func testNoAdditionalInfoOrFlagClearMeansNotAtmos() {
        var none = Layout(); none.addbsi = nil
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: frame(none)))
        var off = Layout(); off.addbsi = (0, 16)
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: frame(off)), "flag_ec3_extension_type_a clear")
        var short = Layout(); short.addbsiLengthField = 0
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: frame(short)), "one additional byte cannot hold flag and index")
    }

    func testEveryOptionalMetadataBlockIsWalked() {
        var l = Layout(); l.withMixMetadata = true; l.withInfoMetadata = true
        XCTAssertEqual(EAC3Atmos.complexityIndex(accessUnit: frame(l)), 16)
        l.acmod = 2; l.lfeon = 0
        XCTAssertEqual(EAC3Atmos.complexityIndex(accessUnit: frame(l)), 16, "stereo bed")
        l.acmod = 7; l.lfeon = 0
        XCTAssertEqual(EAC3Atmos.complexityIndex(accessUnit: frame(l)), 16, "no LFE")
        l.acmod = 1; l.lfeon = 1
        XCTAssertEqual(EAC3Atmos.complexityIndex(accessUnit: frame(l)), 16, "mono bed")
    }

    func testBadInputFailsClosed() {
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: []))
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: [0x0B, 0x77]))
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: Array(repeating: 0xFF, count: 600)))
        XCTAssertNil(EAC3Atmos.complexityIndex(accessUnit: [0x20, 0x00] + Array(repeating: 0, count: 100)), "no sync word")
        let good = frame(Layout())
        // This layout ends at byte 10 (2 sync bytes + 60 bits); cutting inside the BSI must not return an index.
        for cut in [2, 5, 8, 9] {
            XCTAssertNil(EAC3Atmos.complexityIndex(syncframe: Array(good.prefix(cut))), "truncated at \(cut) bytes")
        }
        var dependent = Layout(); dependent.strmtyp = 1
        XCTAssertNil(EAC3Atmos.complexityIndex(syncframe: frame(dependent)), "a dependent substream is not where JOC lives")
    }

    func testConfigCarriesTheAtmosSignal() throws {
        let track = MKVTrack.testTrack(number: 2)
        let plain = try AudioConfigBuilder.eac3(track: track, firstAccessUnit: frame({ var l = Layout(); l.addbsi = nil; return l }()))
        XCTAssertFalse(plain.isAtmos)
        let atmos = try AudioConfigBuilder.eac3(track: track, firstAccessUnit: frame(Layout()))
        XCTAssertTrue(atmos.isAtmos)
        XCTAssertEqual(atmos.specific.count, plain.specific.count + 2, "the JOC extension adds two bytes to dec3")
    }
}
