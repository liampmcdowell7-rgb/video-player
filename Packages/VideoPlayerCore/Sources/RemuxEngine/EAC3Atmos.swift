import Foundation

// Detects Dolby Atmos carried in Dolby Digital Plus (E-AC-3 with Joint Object Coding, "JOC").
//
// The signal is in the additional bit stream information (addbsi) at the end of the independent substream's BSI:
// the LSB of the first addbsi byte is `flag_ec3_extension_type_a` and the second byte is `complexity_index_type_a`
// (ETSI TS 103 420; the same fields the dec3 box carries, ETSI TS 102 366 Annex F). This is the method libavcodec's
// AC-3 header parser uses to detect Atmos.
//
// STATUS (PROVISIONAL): the BSI walk is written from ETSI TS 102 366 section E.1.2.2 and checked only against bit
// streams the tests build themselves (including a layout with every optional metadata block present). It has NOT been
// run against a real Atmos E-AC-3 stream. Any parse problem returns nil ("not Atmos"), never a guess: the cost of a
// false negative is that Atmos is not signalled (the 5.1 or 7.1 bed still plays); a false positive would write a wrong
// dec3 extension, so the check is deliberately strict. Alternative: take the flag from the container (Matroska has none).

public enum EAC3Atmos {
    /// The JOC complexity index (a number 0...16 or so) when the first independent syncframe of `accessUnit` signals
    /// Dolby Atmos, else nil.
    public static func complexityIndex(accessUnit: [UInt8]) -> Int? {
        var pos = 0
        while pos + 8 <= accessUnit.count, accessUnit[pos] == 0x0B, accessUnit[pos + 1] == 0x77 {
            guard let info = try? AudioConfigBuilder.parseEAC3Frame(accessUnit, at: pos) else { return nil }
            if info.streamType == 0 || info.streamType == 2 {
                let end = min(accessUnit.count, pos + info.frameBytes)
                return complexityIndex(syncframe: Array(accessUnit[pos..<end]))
            }
            pos += info.frameBytes
        }
        return nil
    }

    /// Walks the BSI of one independent syncframe up to `addbsi`.
    static func complexityIndex(syncframe f: [UInt8]) -> Int? {
        guard f.count > 8 else { return nil }
        var r = BitReader(Array(f[2...]))
        do {
            let strmtyp = try r.bits(2)
            guard strmtyp == 0 || strmtyp == 2 else { return nil }
            try r.skip(3 + 11)                                // substreamid, frmsiz
            let fscod = try r.bits(2)
            var numblkscod = 3
            if fscod == 3 { try r.skip(2) } else { numblkscod = try r.bits(2) }
            let acmod = try r.bits(3), lfeon = try r.bit()
            try r.skip(5)                                      // bsid
            try r.skip(5)                                      // dialnorm
            if try r.bit() == 1 { try r.skip(8) }              // compre, compr
            if acmod == 0 {
                try r.skip(5)                                  // dialnorm2
                if try r.bit() == 1 { try r.skip(8) }          // compr2e, compr2
            }
            if try r.bit() == 1 {                              // mixmdate
                if acmod > 2 { try r.skip(2) }                 // dmixmod
                if acmod & 1 != 0 && acmod > 2 { try r.skip(6) }
                if acmod & 4 != 0 { try r.skip(6) }
                if lfeon == 1, try r.bit() == 1 { try r.skip(5) }
                if strmtyp == 0 {
                    if try r.bit() == 1 { try r.skip(6) }      // pgmscle
                    if acmod == 0, try r.bit() == 1 { try r.skip(6) }
                    if try r.bit() == 1 { try r.skip(6) }      // extpgmscle
                    switch try r.bits(2) {                     // mixdef
                    case 1: try r.skip(5)
                    case 2: try r.skip(12)
                    case 3:
                        let len = try r.bits(5)
                        try r.skip(8 * (len + 2))
                    default: break
                    }
                    if acmod < 2 {
                        if try r.bit() == 1 { try r.skip(14) } // paninfoe
                        if acmod == 0, try r.bit() == 1 { try r.skip(14) }
                    }
                    if try r.bit() == 1 {                      // frmmixcfginfoe
                        if numblkscod == 0 { try r.skip(5) }
                        else {
                            let blocks = [1, 2, 3, 6][numblkscod]
                            for _ in 0..<blocks { if try r.bit() == 1 { try r.skip(5) } }
                        }
                    }
                }
            }
            if try r.bit() == 1 {                              // infomdate
                try r.skip(3 + 1 + 1)                          // bsmod, copyrightb, origbs
                if acmod == 2 { try r.skip(4) }                // dsurmod, dheadphonmod
                if acmod >= 6 { try r.skip(2) }                // dsurexmod
                if try r.bit() == 1 { try r.skip(8) }          // audprodie
                if acmod == 0, try r.bit() == 1 { try r.skip(8) }
                if fscod < 3 { try r.skip(1) }                 // sourcefscod
            }
            if strmtyp == 0 && numblkscod != 3 { try r.skip(1) }     // convsync
            if strmtyp == 2 {
                var blkid = 1
                if numblkscod != 3 { blkid = try r.bit() }
                if blkid == 1 { try r.skip(6) }                // frmsizecod
            }
            guard try r.bit() == 1 else { return nil }         // addbsie
            let addbsil = try r.bits(6)
            guard addbsil >= 1 else { return nil }             // need the flag byte and the complexity byte
            try r.skip(7)
            guard try r.bit() == 1 else { return nil }         // flag_ec3_extension_type_a
            return try r.bits(8)                               // complexity_index_type_a
        } catch {
            return nil
        }
    }
}
