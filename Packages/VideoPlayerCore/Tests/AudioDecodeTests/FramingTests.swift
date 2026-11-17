import XCTest
@testable import RemuxEngine
@testable import AudioDecode

// Pure parts of the audio pipeline: FLAC frame renumbering and CRCs, channel layouts, the TrueHD / Dolby Digital splitter.

final class FramingTests: XCTestCase {

    /// A minimal fixed-block-size FLAC frame: 4096 samples (code 12), 48 kHz (code 10), stereo, 16-bit, one constant subframe each.
    private func sampleFrame(number: Int64) -> [UInt8] {
        var h: [UInt8] = [0xFF, 0xF8, 0xCA, 0x18] + FLACFraming.utf8Number(number)
        h.append(FLACFraming.crc8(h))
        var f = h + [0x00, 0x12, 0x34, 0x00, 0x56, 0x78]
        let c = FLACFraming.crc16(f)
        f.append(UInt8(c >> 8)); f.append(UInt8(c & 0xFF))
        return f
    }

    func testRenumberRewritesTheFrameNumberAndBothCRCs() throws {
        let f = sampleFrame(number: 0)
        for n: Int64 in [0, 1, 127, 128, 2047, 2048, 65535, 65536, 1 << 21, (1 << 31) - 1] {
            let r = try XCTUnwrap(FLACFraming.renumber(f, frameNumber: n))
            XCTAssertEqual(FLACFraming.frameNumber(r), n)
            let numLen = try XCTUnwrap(FLACFraming.utf8Length(lead: r[4]))
            let header = Array(r[0..<(4 + numLen)])
            XCTAssertEqual(r[4 + numLen], FLACFraming.crc8(header), "header CRC-8 for \(n)")
            XCTAssertEqual(FLACFraming.crc16(r), 0, "a frame including its CRC-16 checks to zero (\(n))")
            XCTAssertEqual(Array(r.suffix(8).prefix(6)), [0x00, 0x12, 0x34, 0x00, 0x56, 0x78], "subframes unchanged")
        }
        XCTAssertNil(FLACFraming.renumber([0xFF, 0xF9, 0, 0, 0, 0, 0, 0], frameNumber: 1), "variable block size frames are not renumbered")
        XCTAssertNil(FLACFraming.renumber(Array(repeating: 0, count: 10), frameNumber: 1))
    }

    func testCRCsMatchTheFLACReferenceValues() {
        // CRC-8 (poly 0x07) and CRC-16 (poly 0x8005) of "123456789", the usual check values: 0xF4 and 0xFEE8.
        let check = Array("123456789".utf8)
        XCTAssertEqual(FLACFraming.crc8(check), 0xF4)
        XCTAssertEqual(FLACFraming.crc16(check), 0xFEE8)
    }

    func testBlockSizeStaysInsideTheFLACSubset() {
        XCTAssertEqual(FLACFraming.blockSize(sampleRate: 44100), 4096)
        XCTAssertEqual(FLACFraming.blockSize(sampleRate: 48000), 4096)
        XCTAssertEqual(FLACFraming.blockSize(sampleRate: 96000), 8192)
        XCTAssertEqual(FLACFraming.blockSize(sampleRate: 192000), 16384)
    }

    // Library channel-mask bits: FL 0, FR 1, FC 2, LFE 3, BL 4, BR 5, BC 8, SL 9, SR 10.
    private let m51back: UInt64 = 0b11_1111, m51side: UInt64 = 0b110_0000_1111, m61: UInt64 = 0b111_0000_1111, m71: UInt64 = 0b110_0011_1111

    func testCommonLayoutsMapOneToOneInFLACOrder() {
        let l71 = ChannelLayoutMap.choose(mask: m71, channels: 8)
        XCTAssertEqual(l71.output.count, 8); XCTAssertEqual(l71.sourceIndex, [0, 1, 2, 3, 4, 5, 6, 7]); XCTAssertEqual(l71.dropped, [])
        let l51 = ChannelLayoutMap.choose(mask: m51back, channels: 6)
        XCTAssertEqual(l51.sourceIndex, [0, 1, 2, 3, 4, 5])
        let side = ChannelLayoutMap.choose(mask: m51side, channels: 6)
        XCTAssertEqual(side.output, [.frontLeft, .frontRight, .frontCenter, .lfe, .backLeft, .backRight])
        XCTAssertEqual(side.sourceIndex, [0, 1, 2, 3, 4, 5], "5.1 with side surrounds goes in the FLAC surround slots")
        let es = ChannelLayoutMap.choose(mask: m61, channels: 7)
        XCTAssertEqual(es.output, [.frontLeft, .frontRight, .frontCenter, .lfe, .backCenter, .sideLeft, .sideRight])
        XCTAssertEqual(es.sourceIndex, [0, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(ChannelLayoutMap.choose(mask: 0b11, channels: 2).sourceIndex, [0, 1])
        XCTAssertEqual(ChannelLayoutMap.choose(mask: 0b100, channels: 1).output, [.frontCenter])
    }

    func testLayoutsWithoutAFLACEquivalentGetSilentChannelsNotADownmix() {
        // 2.1 (FL FR LFE): the smallest FLAC layout holding all three is 5.1, with FC, BL, BR silent.
        let m = ChannelLayoutMap.choose(mask: 0b1011, channels: 3)
        XCTAssertEqual(m.output.count, 6)
        XCTAssertEqual(m.sourceIndex, [0, 1, nil, 2, nil, nil])
        // 7.0 (no LFE) goes into 7.1 with a silent LFE.
        let m70 = ChannelLayoutMap.choose(mask: m71 & ~0b1000, channels: 7)
        XCTAssertEqual(m70.output.count, 8); XCTAssertEqual(m70.sourceIndex[3], nil); XCTAssertEqual(m70.dropped, [])
        // Wide fronts (FLC FRC) have no FLAC slot next to a full 7.1: reported as dropped.
        let wide = ChannelLayoutMap.choose(mask: m71 | 0b1100_0000, channels: 10)
        XCTAssertEqual(wide.output.count, 8); XCTAssertEqual(Set(wide.dropped), ["FLC", "FRC"])
    }

    func testALayoutChangeKeepsTheOutputLayout() {
        let out = ChannelLayoutMap.choose(mask: m51side, channels: 6).output
        let stereo = ChannelLayoutMap.assign(source: ChannelLayoutMap.speakers(mask: 0b11, channels: 2), to: out)
        XCTAssertEqual(stereo.sourceIndex, [0, 1, nil, nil, nil, nil])
        let bigger = ChannelLayoutMap.assign(source: ChannelLayoutMap.speakers(mask: m71, channels: 8), to: out)
        XCTAssertEqual(bigger.sourceIndex, [0, 1, 2, 3, 4, 5]); XCTAssertEqual(bigger.dropped, ["SL", "SR"])
    }

    func testSplitterSeparatesDolbyDigitalFramesFromTrueHDAccessUnits() {
        // One TrueHD access unit of 8 bytes (length 4 words), an AC-3 frame (48 kHz, frmsizecod 0: 64 words), another unit.
        let au: [UInt8] = [0xF0, 0x04, 0x00, 0x00, 1, 2, 3, 4]
        var ac3 = [UInt8](repeating: 0, count: 128)
        ac3[0] = 0x0B; ac3[1] = 0x77; ac3[4] = 0x00; ac3[5] = 8 << 3
        let parts = TrueHDCoreSplitter.split((au + ac3 + au)[...])
        XCTAssertEqual(parts.trueHD.count, 2)
        XCTAssertEqual(parts.ac3.count, 1)
        XCTAssertEqual(parts.ac3.first.map { Array($0) }, ac3)
        XCTAssertEqual(TrueHDCoreSplitter.split(au[...]).ac3.count, 0)
    }

    func testTrackRankingPrefersTheSameLanguageThenLosslessThenChannels() {
        func r(_ n: Int, _ lang: String, _ ch: Int) -> AudioRenditionInfo {
            AudioRenditionInfo(trackNumber: n, name: "", language: lang, codecID: "A_AC3", codecString: "ac-3", channels: ch, isDefault: false, transcoded: false)
        }
        let offered = [r(2, "eng", 2), r(3, "fre", 8), r(4, "eng", 6), r(5, "eng", 6)]
        var lost = MKVTrackFixture.track(language: "eng")
        XCTAssertEqual(AudioTrackRanking.replacement(for: lost, among: offered, losslessTracks: [])?.trackNumber, 4)
        XCTAssertEqual(AudioTrackRanking.replacement(for: lost, among: offered, losslessTracks: [5])?.trackNumber, 5)
        lost.language = "und"
        XCTAssertEqual(AudioTrackRanking.replacement(for: lost, among: offered, losslessTracks: [])?.trackNumber, 3)
        XCTAssertNil(AudioTrackRanking.replacement(for: lost, among: [], losslessTracks: []))
    }
}

enum MKVTrackFixture {
    static func track(number: Int = 1, codecID: String = "A_DTS", language: String = "und", codecPrivate: [UInt8] = [],
                      sampleRate: Double = 48000, channels: Int = 6) -> MKVTrack {
        MKVTrack(number: number, uid: UInt64(number), type: .audio, codecID: codecID, codecPrivate: codecPrivate, name: "", language: language,
                 isDefault: true, isEnabled: true, defaultDurationNs: nil, codecDelayNs: 0, seekPreRollNs: 0, pixelWidth: 0, pixelHeight: 0,
                 displayWidth: nil, displayHeight: nil, colour: nil, dolbyVision: nil, sampleRate: sampleRate, channels: channels, bitDepth: 0,
                 strippedHeader: [])
    }
}
