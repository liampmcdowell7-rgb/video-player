import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

final class HEVCTests: XCTestCase {
    func testHvcCParsesAndBuildsCodecString() throws {
        let c = try HVCConfig(parsing: makeHvcC())
        XCTAssertEqual(c.profileIDC, 2); XCTAssertEqual(c.levelIDC, 120); XCTAssertEqual(c.lengthSize, 4)
        XCTAssertEqual(c.bitDepthLuma, 10); XCTAssertEqual(c.chromaFormat, 1)
        XCTAssertEqual(c.arrays.map { $0.type }, [32, 33, 34])
        XCTAssertEqual(c.nalus(ofType: 33).count, 1)
        // compatibility flags 0x60000000 reversed = 0x6; constraint bytes 90 00 00 00 00 00 -> "90"
        XCTAssertEqual(c.codecString(), "hvc1.2.6.L120.90")
        XCTAssertEqual(c.codecString(fourCC: "dvh1"), "dvh1.2.6.L120.90")
    }

    func testHvcCRejectsUnknownVersionAndTruncation() {
        var bad = makeHvcC(); bad[0] = 2
        XCTAssertThrowsError(try HVCConfig(parsing: bad))
        XCTAssertThrowsError(try HVCConfig(parsing: Array(makeHvcC().prefix(30))))
    }

    func testSEIMessagesAreParsed() throws {
        let nal = makeSEINAL([(137, SynthMKV.mdcv24), (144, SynthMKV.clliPayload)])
        let msgs = HEVCSEI.messages(inNAL: nal[...])
        XCTAssertEqual(msgs.map { $0.type }, [137, 144])
        XCTAssertEqual(msgs[0].payload, SynthMKV.mdcv24)       // the 00 00 00 01 inside needed an emulation prevention byte
        XCTAssertEqual(msgs[1].payload, SynthMKV.clliPayload)
        XCTAssertTrue(nal.contains(3), "the escaped NAL must contain an emulation prevention byte")
    }

    func testStaticMetadataFromSampleAndFromHvcC() throws {
        let cfg = try HVCConfig(parsing: makeHvcC())
        let sei = makeSEINAL([(137, SynthMKV.mdcv24), (144, SynthMKV.clliPayload)])
        let sample = lengthPrefixed([sei, [0x26, 0x01, 1, 2, 3]])
        let md = HEVCSEI.staticMetadata(config: cfg, firstKeyframe: sample)
        XCTAssertEqual(md.mdcv, SynthMKV.mdcv24); XCTAssertEqual(md.clli, SynthMKV.clliPayload)
        XCTAssertTrue(HEVCSEI.staticMetadata(config: cfg, firstKeyframe: lengthPrefixed([[0x26, 0x01, 1]])).isEmpty)
        // A suffix SEI is not looked at; a wrong-size mdcv payload is ignored.
        let wrong = lengthPrefixed([makeSEINAL([(137, [1, 2, 3])])])
        XCTAssertNil(HEVCSEI.staticMetadata(config: cfg, firstKeyframe: wrong).mdcv)
    }

    func testMdcvPayloadFromMatroskaMastering() {
        let m = MKVColour.Mastering(rx: 0.68, ry: 0.32, gx: 0.265, gy: 0.69, bx: 0.15, by: 0.06, wx: 0.3127, wy: 0.329,
                                    maxLuminance: 1000, minLuminance: 0.0001)
        XCTAssertEqual(HEVCSEI.mdcvPayload(m), SynthMKV.mdcv24)
    }

    func testDropNALsRemovesDolbyVisionUnitsOnly() throws {
        let base = [0x26, 0x01, 9, 9] as [UInt8], rpu = [0x7C, 0x01, 1, 2, 3] as [UInt8], el = [0x7E, 0x01, 4] as [UInt8]
        let sample = lengthPrefixed([base, el, rpu])
        let dropped = try dropNALs(sample, lengthSize: 4, hevc: true, drop: [62, 63])
        XCTAssertEqual(dropped, lengthPrefixed([base]))
        XCTAssertEqual(try dropNALs(lengthPrefixed([base]), lengthSize: 4, hevc: true, drop: [62, 63]), lengthPrefixed([base]))
        XCTAssertThrowsError(try splitLengthPrefixed([0, 0, 0, 9, 1, 2], lengthSize: 4))
    }

    func testRealSPSGivesSizeAndReorderDepth() throws {
        let data = try TestMedia.load("engine_hdr10.mkv")
        let idx = try blocking { try await MatroskaIndexer.load(from: DataReader(data)) }
        let track = try XCTUnwrap(idx.videoTrack)
        let hvcc = try HVCConfig(parsing: track.codecPrivate)
        let sps = try XCTUnwrap(hvcc.nalus(ofType: 33).first.flatMap { HEVCSPS.parse($0) })
        XCTAssertEqual(sps.width, 1280); XCTAssertEqual(sps.height, 720)
        XCTAssertEqual(sps.bitDepthLuma, 10)
        XCTAssertGreaterThanOrEqual(sps.maxNumReorderPics, 2, "x265 with bframes=4 reorders")
        XCTAssertEqual(sps.colourPrimaries, 9); XCTAssertEqual(sps.transferCharacteristics, 16); XCTAssertEqual(sps.matrixCoefficients, 9)
        XCTAssertTrue(hvcc.codecString().hasPrefix("hvc1.2."), hvcc.codecString())
        XCTAssertTrue(hvcc.codecString().contains(".L93"), hvcc.codecString())
    }
}

final class AudioConfigTests: XCTestCase {
    func testAC3FrameAndDac3() throws {
        let frame = makeAC3Frame()
        let info = try AudioConfigBuilder.parseAC3(frame)
        XCTAssertEqual(info.acmod, 7); XCTAssertEqual(info.lfeon, 1); XCTAssertEqual(info.channels, 6); XCTAssertEqual(info.sampleRate, 48000)
        XCTAssertEqual(info.bsid, 8); XCTAssertEqual(info.frmsizecod, 28)
        let cfg = try AudioConfigBuilder.ac3(track: MKVTrack.testTrack(number: 2), firstFrame: frame)
        // fscod 0, bsid 8, bsmod 0, acmod 7, lfeon 1, bit_rate_code 14, reserved 0 = 0001 0000 0011 1101 1100 0000
        XCTAssertEqual(cfg.specific, [0x10, 0x3D, 0xC0])
        XCTAssertEqual(cfg.samplesPerFrame, 1536); XCTAssertEqual(cfg.bitrate, 384_000); XCTAssertEqual(cfg.channels, 6)
        XCTAssertEqual(cfg.codecString, "ac-3"); XCTAssertEqual(cfg.timescale, 48000)
        XCTAssertThrowsError(try AudioConfigBuilder.parseAC3([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    func eac3Frame(bytes: Int = 256, channels acmod: Int = 7, strmtyp: Int = 0) -> [UInt8] {
        var w = BitWriter()
        w.put(strmtyp, 2); w.put(0, 3); w.put(bytes / 2 - 1, 11); w.put(0, 2); w.put(3, 2)      // 6 blocks, 48 kHz
        w.put(acmod, 3); w.put(1, 1); w.put(16, 5)
        var f: [UInt8] = [0x0B, 0x77] + w.bytes
        while f.count < bytes { f.append(0) }
        return f
    }

    func testEAC3FrameAndDec3() throws {
        let f = eac3Frame()
        let info = try AudioConfigBuilder.parseEAC3Frame(f)
        XCTAssertEqual(info.streamType, 0); XCTAssertEqual(info.frameBytes, 256); XCTAssertEqual(info.numBlocks, 6)
        XCTAssertEqual(info.acmod, 7); XCTAssertEqual(info.lfeon, 1); XCTAssertEqual(info.bsid, 16); XCTAssertEqual(info.sampleRate, 48000)
        let cfg = try AudioConfigBuilder.eac3(track: MKVTrack.testTrack(number: 2), firstAccessUnit: f)
        // data_rate 64 kbit/s (13 bits: 0000001000000) + 0 extra independent substreams (3 bits) = 02 00 | fscod 0 bsid 16 = 20 | acmod 7 lfeon 1 = 0F | 00
        XCTAssertEqual(cfg.specific, [0x02, 0x00, 0x20, 0x0F, 0x00])
        XCTAssertEqual(cfg.samplesPerFrame, 1536); XCTAssertEqual(cfg.channels, 6); XCTAssertEqual(cfg.codecString, "ec-3")
        let atmos = try AudioConfigBuilder.eac3(track: MKVTrack.testTrack(number: 2), firstAccessUnit: f, jocComplexityIndex: 16)
        XCTAssertEqual(atmos.specific.count, cfg.specific.count + 2, "the JOC extension adds two bytes")
    }

    func testAACConfig() throws {
        var t = MKVTrack.testTrack(number: 3); t.codecPrivate = [0x11, 0x90]
        let cfg = try AudioConfigBuilder.aac(track: t)
        XCTAssertEqual(cfg.sampleRate, 48000); XCTAssertEqual(cfg.channels, 2); XCTAssertEqual(cfg.codecString, "mp4a.40.2"); XCTAssertEqual(cfg.samplesPerFrame, 1024)
        t.codecPrivate = []
        XCTAssertThrowsError(try AudioConfigBuilder.aac(track: t))
    }

    func streamInfoTrack(rate: Int = 48000, channels: Int = 8, bits: Int = 24, block: Int = 4096) -> MKVTrack {
        var si = ByteWriter()
        si.u16(UInt16(block)); si.u16(UInt16(block)); si.u24(0); si.u24(0)
        si.u8(UInt8(rate >> 12)); si.u8(UInt8((rate >> 4) & 0xFF))
        si.u8(UInt8((rate & 0xF) << 4) | UInt8(((channels - 1) << 1) & 0x0E) | UInt8(((bits - 1) >> 4) & 1))
        si.u8(UInt8(((bits - 1) & 0xF) << 4)); si.u32(0); si.zeros(16)
        let cp = Array("fLaC".utf8) + [0x80, 0, 0, 34] + si.bytes
        XCTAssertEqual(cp.count, 42)
        var t = MKVTrack.testTrack(number: 4); t.codecPrivate = cp
        return t
    }

    func testFLACConfigAndFrameSizes() throws {
        let cfg = try AudioConfigBuilder.flac(track: streamInfoTrack())
        XCTAssertEqual(cfg.sampleRate, 48000); XCTAssertEqual(cfg.channels, 8); XCTAssertEqual(cfg.bitsPerSample, 24)
        XCTAssertEqual(cfg.samplesPerFrame, 4096); XCTAssertEqual(cfg.specific.count, 38)
        XCTAssertEqual(Array(cfg.specific.prefix(4)), [0x80, 0, 0, 34])
        XCTAssertEqual(AudioConfigBuilder.flacFrameSamples([0xFF, 0xF8, 0xC9, 0x18, 0, 0]), 4096)
        XCTAssertEqual(AudioConfigBuilder.flacFrameSamples([0xFF, 0xF8, 0x19, 0x18, 0, 0]), 192)
        XCTAssertEqual(AudioConfigBuilder.flacFrameSamples([0xFF, 0xF8, 0x69, 0x18, 0x00, 0x7F, 0]), 128)   // explicit 8-bit size 127 + 1
        XCTAssertNil(AudioConfigBuilder.flacFrameSamples([1, 2, 3, 4, 5, 6]))
        var variable = streamInfoTrack(); variable.codecPrivate[4 + 4 + 2] = 0x20       // max block size != min
        XCTAssertEqual(try AudioConfigBuilder.flac(track: variable).samplesPerFrame, 0)
    }

    func testFrameSamplesPerCodec() throws {
        let ac3 = try AudioConfigBuilder.ac3(track: MKVTrack.testTrack(number: 2), firstFrame: makeAC3Frame())
        XCTAssertEqual(AudioConfigBuilder.frameSamples(ac3, frame: makeAC3Frame()), 1536)
        let e = try AudioConfigBuilder.eac3(track: MKVTrack.testTrack(number: 2), firstAccessUnit: eac3Frame())
        XCTAssertEqual(AudioConfigBuilder.frameSamples(e, frame: eac3Frame()), 1536)
    }
}
