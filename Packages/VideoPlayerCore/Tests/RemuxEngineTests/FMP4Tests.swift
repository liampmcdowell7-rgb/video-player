import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

final class FMP4WriterTests: XCTestCase {
    let writer = FMP4Writer()

    func hevcConfig(entry: String = "hvc1", dv: MKVDolbyVisionMapping? = nil, hdr: Bool = true) throws -> VideoTrackConfig {
        VideoTrackConfig(trackID: 1, codec: .hevc(try HVCConfig(parsing: makeHvcC())), width: 1280, height: 720, sampleEntry: entry,
                         colour: ColourInfo(primaries: 9, transfer: 16, matrix: 9, fullRange: false),
                         hdr: hdr ? HDRStaticMetadata(mdcv: SynthMKV.mdcv24, clli: SynthMKV.clliPayload) : HDRStaticMetadata(),
                         dolbyVision: dv, language: "eng", frameRate: 24)
    }

    func dvRecord(profile: Int, compat: Int) -> MKVDolbyVisionMapping {
        var rec: [UInt8] = [1, 0, UInt8(profile << 1), UInt8(6 << 3 | 0x05), UInt8(compat << 4)]
        rec += [UInt8](repeating: 0, count: 19)
        return MKVDolbyVisionMapping(type: profile <= 7 ? 0x64766343 : 0x64767643, record: rec)
    }

    func parse(_ b: [UInt8]) throws -> BoxNode { try BoxParser.parse(b) }

    func testHDR10VideoInitSegment() throws {
        let bytes = writer.initSegment(for: .video(try hevcConfig()))
        XCTAssertEqual(FMP4Checker.check(initSegment: bytes, expectedEntry: "hvc1"), [])
        let root = try parse(bytes)
        XCTAssertEqual(root.children.map { $0.type }, ["ftyp", "moov"])
        let ftyp = try XCTUnwrap(root.find("ftyp")).payload
        XCTAssertEqual(String(decoding: ftyp.prefix(4), as: UTF8.self), "iso6")
        XCTAssertTrue(String(decoding: ftyp, as: UTF8.self).contains("cmfc"))
        let entry = try XCTUnwrap(root.find("moov/trak/mdia/minf/stbl/stsd/hvc1"))
        XCTAssertEqual(entry.children.map { $0.type }, ["hvcC", "colr", "mdcv", "clli"])
        XCTAssertEqual(try XCTUnwrap(entry.find("hvcC")).payload, makeHvcC())
        XCTAssertEqual(try XCTUnwrap(entry.find("colr")).payload, Array("nclx".utf8) + [0, 9, 0, 16, 0, 9, 0])
        XCTAssertEqual(try XCTUnwrap(entry.find("mdcv")).payload, SynthMKV.mdcv24)
        XCTAssertEqual(try XCTUnwrap(entry.find("clli")).payload, SynthMKV.clliPayload)
        // Visual sample entry header: width / height at 24 / 26 inside the entry body.
        XCTAssertEqual(Array(entry.payload[24..<28]), [0x05, 0x00, 0x02, 0xD0])
        let mdhd = try XCTUnwrap(root.find("moov/trak/mdia/mdhd")).payload
        XCTAssertEqual(Array(mdhd[12..<16]), [0, 1, 0x5F, 0x90])               // timescale 90000
        XCTAssertEqual(Array(mdhd[20..<22]), [0x15, 0xC7])                     // "eng" packed
        let tkhd = try XCTUnwrap(root.find("moov/trak/tkhd")).payload
        XCTAssertEqual(Array(tkhd[tkhd.count - 8..<tkhd.count]), [0x05, 0x00, 0, 0, 0x02, 0xD0, 0, 0])
        XCTAssertEqual(try XCTUnwrap(root.find("moov/mvex/trex")).payload.count, 24)
    }

    func testFlagsInStaticTablesAreEmpty() throws {
        let root = try parse(writer.initSegment(for: .video(try hevcConfig())))
        for t in ["stts", "stsc", "stco"] { XCTAssertEqual(try XCTUnwrap(root.find("moov/trak/mdia/minf/stbl/\(t)")).payload, [0, 0, 0, 0, 0, 0, 0, 0], t) }
        XCTAssertEqual(try XCTUnwrap(root.find("moov/trak/mdia/minf/stbl/stsz")).payload, [UInt8](repeating: 0, count: 12))
    }

    func testDolbyVisionProfile8UsesHvc1WithDvvC() throws {
        let rec = dvRecord(profile: 8, compat: 1)
        let root = try parse(writer.initSegment(for: .video(try hevcConfig(dv: rec))))
        let entry = try XCTUnwrap(root.find("moov/trak/mdia/minf/stbl/stsd/hvc1"))
        XCTAssertEqual(entry.children.map { $0.type }, ["hvcC", "dvvC", "colr", "mdcv", "clli"])
        XCTAssertEqual(try XCTUnwrap(entry.find("dvvC")).payload, rec.record)
    }

    func testDolbyVisionProfile5UsesDvh1WithDvcC() throws {
        let rec = dvRecord(profile: 5, compat: 0)
        let bytes = writer.initSegment(for: .video(try hevcConfig(entry: "dvh1", dv: rec, hdr: false)))
        XCTAssertEqual(FMP4Checker.check(initSegment: bytes, expectedEntry: "dvh1"), [])
        let entry = try XCTUnwrap(try parse(bytes).find("moov/trak/mdia/minf/stbl/stsd/dvh1"))
        XCTAssertEqual(entry.children.map { $0.type }, ["hvcC", "dvcC", "colr"])
        XCTAssertEqual(try XCTUnwrap(entry.find("dvcC")).payload.count, 24)
    }

    func testAVCEntry() throws {
        let avcc: [UInt8] = [1, 100, 0, 31, 0xFF, 0xE1, 0, 4, 0x67, 100, 0, 31, 1, 0, 2, 0x68, 0xEE]
        let cfg = VideoTrackConfig(trackID: 1, codec: .avc(try AVCConfig(parsing: avcc)), width: 1280, height: 720, sampleEntry: "avc1",
                                   colour: nil, hdr: HDRStaticMetadata(), dolbyVision: nil, language: "und", frameRate: nil)
        let bytes = writer.initSegment(for: .video(cfg))
        XCTAssertEqual(FMP4Checker.check(initSegment: bytes, expectedEntry: "avc1"), [])
        let entry = try XCTUnwrap(try parse(bytes).find("moov/trak/mdia/minf/stbl/stsd/avc1"))
        XCTAssertEqual(entry.children.map { $0.type }, ["avcC"])
        XCTAssertEqual(try XCTUnwrap(entry.find("avcC")).payload, avcc)
        XCTAssertEqual(cfg.codecString, "avc1.64001F")
    }

    func audioConfig(_ codec: AudioCodec, specific: [UInt8], channels: Int = 6, bits: Int = 16, rate: UInt32 = 48000, perFrame: Int = 1536) -> AudioTrackConfig {
        AudioTrackConfig(trackID: 2, codec: codec, sampleRate: rate, channels: channels, bitsPerSample: bits, specific: specific, language: "fra",
                         samplesPerFrame: perFrame, bitrate: 640_000, codecString: codec == .aac ? "mp4a.40.2" : (codec == .flac ? "fLaC" : (codec == .ac3 ? "ac-3" : "ec-3")))
    }

    func testAudioSampleEntries() throws {
        let cases: [(AudioCodec, String, String, [UInt8])] = [
            (.ac3, "ac-3", "dac3", [0x10, 0x3D, 0xC0]),
            (.eac3, "ec-3", "dec3", [0x04, 0x00, 0x20, 0x0F, 0x00]),
            (.flac, "fLaC", "dfLa", [0x80, 0, 0, 34] + [UInt8](repeating: 7, count: 34)),
        ]
        for (codec, entryName, boxName, specific) in cases {
            let cfg = audioConfig(codec, specific: specific, channels: 8, bits: codec == .flac ? 24 : 16)
            let bytes = writer.initSegment(for: .audio(cfg))
            XCTAssertEqual(FMP4Checker.check(initSegment: bytes, expectedEntry: entryName).filter { !$0.contains("stsz") }, [], entryName)
            let root = try parse(bytes)
            let entry = try XCTUnwrap(root.find("moov/trak/mdia/minf/stbl/stsd/\(entryName)"))
            let box = try XCTUnwrap(entry.find(boxName), "\(boxName) in \(entryName)")
            XCTAssertEqual(codec == .flac ? Array(box.payload.dropFirst(4)) : box.payload, specific)
            XCTAssertEqual(Array(entry.payload[16..<18]), [0, 8])                                   // channel count
            XCTAssertEqual(Array(entry.payload[24..<28]), [0xBB, 0x80, 0, 0])                       // 48000 << 16
            XCTAssertNotNil(root.find("moov/trak/mdia/minf/smhd"))
            let mdhd = try XCTUnwrap(root.find("moov/trak/mdia/mdhd")).payload
            XCTAssertEqual(Array(mdhd[12..<16]), [0, 0, 0xBB, 0x80])                              // timescale = sample rate
        }
    }

    func testAACEntryCarriesTheAudioSpecificConfigInEsds() throws {
        let cfg = audioConfig(.aac, specific: [0x11, 0x90], channels: 2, perFrame: 1024)
        let root = try parse(writer.initSegment(for: .audio(cfg)))
        let esds = try XCTUnwrap(root.find("moov/trak/mdia/minf/stbl/stsd/mp4a/esds")).payload
        // ES_Descriptor 0x03, DecoderConfig 0x04 (object type 0x40 = MPEG-4 audio, stream type 0x15), DecoderSpecificInfo 0x05.
        XCTAssertEqual(esds[4], 0x03)
        let s = esds.map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(s.contains("04808080" ), s)
        XCTAssertTrue(s.contains("4015"), s)
        XCTAssertTrue(s.hasSuffix("05808080021190" + "068080800102"), s)
    }

    func testVideoFragmentLayout() throws {
        let cfg = try hevcConfig()
        let payloads: [[UInt8]] = [[1, 2, 3, 4, 5], [6, 7], [8, 9, 10]]
        let samples = [
            FMP4Sample(data: payloads[0][...], duration: 3750, isSync: true, compositionOffset: 7500),
            FMP4Sample(data: payloads[1][...], duration: 3750, isSync: false, compositionOffset: 11250),
            FMP4Sample(data: payloads[2][...], duration: 3750, isSync: false, compositionOffset: 0),
        ]
        let frag = writer.fragment(for: .video(cfg), sequence: 4, baseDecodeTime: 1 << 33, samples: samples)
        XCTAssertEqual(FMP4Checker.check(fragment: frag), [])
        let p = try ParsedFragment.parse(frag)
        XCTAssertEqual(p.sequence, 4); XCTAssertEqual(p.trackID, 1); XCTAssertEqual(p.baseDecodeTime, 1 << 33)
        XCTAssertEqual(p.samples.map { $0.duration }, [3750, 3750, 3750])
        XCTAssertEqual(p.samples.map { $0.size }, [5, 2, 3])
        XCTAssertEqual(p.samples.map { $0.cto }, [7500, 11250, 0])
        XCTAssertEqual(p.samples[0].flags & 0x0001_0000, 0)                       // sync sample: is_non_sync clear
        XCTAssertNotEqual(p.samples[1].flags & 0x0001_0000, 0)                    // non sync
        XCTAssertEqual(Array(frag.suffix(10)), payloads.flatMap { $0 })
        XCTAssertEqual(Int(p.dataOffset), p.moofSize + 8)
        XCTAssertEqual(p.mdatPayloadSize, 10)
    }

    func testAudioFragmentHasNoCompositionOffsets() throws {
        let cfg = audioConfig(.ac3, specific: [0x10, 0x3D, 0xC0])
        let frames: [[UInt8]] = (0..<4).map { [UInt8](repeating: UInt8($0), count: 96) }
        let samples = frames.map { FMP4Sample(data: $0[...], duration: 1536, isSync: true) }
        let frag = writer.fragment(for: .audio(cfg), sequence: 1, baseDecodeTime: 48000, samples: samples)
        XCTAssertEqual(FMP4Checker.check(fragment: frag), [])
        let p = try ParsedFragment.parse(frag)
        XCTAssertEqual(p.baseDecodeTime, 48000); XCTAssertEqual(p.trackID, 2)
        XCTAssertEqual(p.samples.map { $0.duration }, [1536, 1536, 1536, 1536]); XCTAssertEqual(p.samples.map { $0.cto }, [0, 0, 0, 0])
        XCTAssertEqual(p.mdatPayloadSize, 384)
    }

    func testFragmentPartsShareTheSampleStorage() throws {
        let cfg = try hevcConfig()
        let storage: [UInt8] = Array(0..<100)
        let samples = [FMP4Sample(data: storage[10..<30], duration: 1, isSync: true), FMP4Sample(data: storage[30..<50], duration: 1, isSync: false)]
        let parts = writer.fragmentParts(for: .video(cfg), sequence: 1, baseDecodeTime: 0, samples: samples)
        XCTAssertEqual(parts.samples.count, 2)
        XCTAssertEqual(parts.samples[0].startIndex, 10)           // still slices of the original array, not copies
        XCTAssertEqual(parts.byteCount, parts.head.count + 40)
        XCTAssertEqual(parts.flattened(), writer.fragment(for: .video(cfg), sequence: 1, baseDecodeTime: 0, samples: samples))
    }

    func testCheckerReportsInconsistencies() throws {
        let cfg = try hevcConfig()
        var frag = writer.fragment(for: .video(cfg), sequence: 1, baseDecodeTime: 0,
                                   samples: [FMP4Sample(data: [1, 2, 3][...], duration: 1, isSync: true)])
        XCTAssertEqual(FMP4Checker.check(fragment: frag), [])
        frag.removeLast()                                                         // mdat shorter than the trun says
        XCTAssertTrue(FMP4Checker.check(fragment: frag).first?.contains("does not parse") ?? false)
        XCTAssertFalse(FMP4Checker.check(initSegment: [0, 0, 0, 8, 0x66, 0x72, 0x65, 0x65], expectedEntry: "hvc1").isEmpty)
        XCTAssertFalse(FMP4Checker.check(initSegment: [1, 2, 3], expectedEntry: "hvc1").isEmpty)
    }

    func testLanguagePacking() {
        XCTAssertEqual(FMP4Writer.packLanguage("eng"), 0x15C7)
        XCTAssertEqual(FMP4Writer.packLanguage("en"), 0x15C7)
        XCTAssertEqual(FMP4Writer.packLanguage("und"), 0x55C4)
        XCTAssertEqual(FMP4Writer.packLanguage("??"), 0x55C4)
        XCTAssertEqual(FMP4Writer.packLanguage(""), 0x55C4)
    }

    func testBoxParserRejectsOversizedBoxes() {
        XCTAssertThrowsError(try BoxParser.parse([0, 0, 0, 40, 0x66, 0x72, 0x65, 0x65, 1, 2]))
        XCTAssertThrowsError(try BoxParser.parse([0, 0, 0, 4, 0x66, 0x72, 0x65, 0x65]))
    }
}
