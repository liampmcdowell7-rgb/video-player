import XCTest
@testable import RemuxEngine

// Dolby Vision record / level / NAL helpers and HDR10+ detection (no native library needed). The byte layouts below are
// BUILT BY THE TESTS from the published layouts (configuration record fields, ST 2094-40 T.35 header).

final class DynamicHDRTests: XCTestCase {
    /// An HDR10+ SEI payload start (FIXTURE, shaped like the ST 2094-40 user_data_registered_itu_t_t35 header) plus filler.
    let hdr10PlusPayload: [UInt8] = [0xB5, 0x00, 0x3C, 0x00, 0x01, 0x04, 0x01, 0x40, 0x00, 0x0C, 0x80]
    let rpuNAL: [UInt8] = [0x7C, 0x01, 0x19, 0x08, 0x09, 0x20]
    let elNAL: [UInt8] = [0x7E, 0x01, 0x26, 0x01, 0xAF, 0x09]
    let slice: [UInt8] = [0x26, 0x01, 0xAF, 0x06, 0x22]

    func testRecordForProfile81KeepsTheLevelAndDropsTheEnhancementLayer() {
        // A disc-style profile 7 record: level 6, rpu + el + bl, compatibility id 6.
        let p7 = MKVDolbyVisionMapping.make(profile: 7, level: 6, elPresent: true, compatibilityID: 6)
        XCTAssertEqual(p7.type, 0x64766343)
        XCTAssertEqual(Array(p7.record.prefix(5)), [0x01, 0x00, 0x0E, 0x37, 0x60])
        XCTAssertEqual([p7.profile, p7.level, p7.blCompatibilityID], [7, 6, 6])
        XCTAssertEqual([p7.rpuPresent, p7.elPresent, p7.blPresent], [true, true, true])
        let p81 = p7.profile81()
        XCTAssertEqual(p81.type, 0x64767643, "profile 8 uses dvvC")
        XCTAssertEqual(p81.record.count, 24)
        XCTAssertEqual(Array(p81.record.prefix(5)), [0x01, 0x00, 0x10, 0x35, 0x10])
        XCTAssertEqual([p81.profile, p81.level, p81.blCompatibilityID], [8, 6, 1])
        XCTAssertEqual([p81.rpuPresent, p81.elPresent, p81.blPresent], [true, false, true])
        // Level 13 sets the high level bit in byte 2.
        let high = MKVDolbyVisionMapping.make(profile: 8, level: 33, elPresent: false, compatibilityID: 1)
        XCTAssertEqual(high.level, 33); XCTAssertEqual(high.profile, 8)
    }

    func testLevelFromPictureSizeAndRate() {
        XCTAssertEqual(DolbyVisionLevel.level(width: 1280, height: 720, framesPerSecond: 24), 1)
        XCTAssertEqual(DolbyVisionLevel.level(width: 1920, height: 1080, framesPerSecond: 23.976), 3)
        XCTAssertEqual(DolbyVisionLevel.level(width: 1920, height: 1080, framesPerSecond: 60), 5)
        XCTAssertEqual(DolbyVisionLevel.level(width: 3840, height: 2160, framesPerSecond: 24), 6)
        XCTAssertEqual(DolbyVisionLevel.level(width: 3840, height: 2160, framesPerSecond: 30), 7)
        XCTAssertEqual(DolbyVisionLevel.level(width: 3840, height: 2160, framesPerSecond: 60), 9)
        XCTAssertEqual(DolbyVisionLevel.level(width: 3840, height: 1600, framesPerSecond: 24), 6, "a scope 4K picture is still level 6")
        XCTAssertEqual(DolbyVisionLevel.level(width: 7680, height: 4320, framesPerSecond: 30), 11)
    }

    func testEnhancementLayerNALsAreFoundByTypeOrLayer() {
        XCTAssertTrue(DolbyVisionNAL.isEnhancementLayer(elNAL[...]))
        XCTAssertFalse(DolbyVisionNAL.isEnhancementLayer(rpuNAL[...]), "the RPU is layer 0, type 62")
        XCTAssertFalse(DolbyVisionNAL.isEnhancementLayer(slice[...]))
        let layer1Slice: [UInt8] = [0x02, 0x09, 0xAA]          // TRAIL_R with nuh_layer_id 1
        XCTAssertEqual(DolbyVisionNAL.layerID(of: layer1Slice[...]), 1)
        XCTAssertTrue(DolbyVisionNAL.isEnhancementLayer(layer1Slice[...]))
        XCTAssertTrue(DolbyVisionNAL.hasEnhancementLayer(lengthPrefixed([slice, elNAL, rpuNAL]), lengthSize: 4))
        XCTAssertFalse(DolbyVisionNAL.hasEnhancementLayer(lengthPrefixed([slice, rpuNAL]), lengthSize: 4))
    }

    func testBaseLayerOnlyDropsRPUAndEnhancementLayerAndKeepsTheRest() throws {
        let sei = makeSEINAL([(4, hdr10PlusPayload)])
        let au = lengthPrefixed([sei, slice, elNAL, elNAL, rpuNAL])
        XCTAssertEqual(try dropDolbyVisionNALs(au, lengthSize: 4), lengthPrefixed([sei, slice]))
        let plain = lengthPrefixed([slice])
        XCTAssertEqual(try dropDolbyVisionNALs(plain, lengthSize: 4), plain)
        // Two-byte lengths work too.
        let two: [UInt8] = [0, UInt8(slice.count)] + slice + [0, UInt8(rpuNAL.count)] + rpuNAL
        XCTAssertEqual(try dropDolbyVisionNALs(two, lengthSize: 2), [0, UInt8(slice.count)] + slice)
    }

    func testHDR10PlusSEIIsRecognisedAndOtherT35IsNot() {
        XCTAssertTrue(HDR10Plus.present(in: lengthPrefixed([makeSEINAL([(4, hdr10PlusPayload)]), slice]), lengthSize: 4))
        // Same SEI next to the mastering display message.
        XCTAssertTrue(HDR10Plus.present(in: lengthPrefixed([makeSEINAL([(137, SynthMKV.mdcv24), (4, hdr10PlusPayload)]), slice]), lengthSize: 4))
        // A T.35 message of another provider (closed captions: provider 0x0031) is not HDR10+.
        let captions: [UInt8] = [0xB5, 0x00, 0x31, 0x47, 0x41, 0x39, 0x34]
        XCTAssertFalse(HDR10Plus.present(in: lengthPrefixed([makeSEINAL([(4, captions)]), slice]), lengthSize: 4))
        XCTAssertFalse(HDR10Plus.present(in: lengthPrefixed([makeSEINAL([(137, SynthMKV.mdcv24)]), slice]), lengthSize: 4))
        // A suffix SEI is not where ST 2094-40 puts it: not counted.
        XCTAssertFalse(HDR10Plus.present(in: lengthPrefixed([slice, makeSEINAL([(4, hdr10PlusPayload)], suffix: true)]), lengthSize: 4))
    }

    func testPlannerDerivesARecordWhenTheFileHasNone() {
        let conv = FakeDVConverter()
        conv.inspected = DolbyVisionSampleInfo(profile: 7, enhancementLayer: .full, hasEnhancementLayerNALs: true)
        var warnings: [String] = []
        let d = DolbyVisionPlanner.decide(record: nil, firstKeyframe: lengthPrefixed([slice, elNAL, rpuNAL]), lengthSize: 4, converter: conv,
                                          transfer: 16, width: 3840, height: 2160, framesPerSecond: 23.976, warnings: &warnings)
        XCTAssertEqual(d.mode, .convertAll)
        XCTAssertTrue(d.facts.derived); XCTAssertEqual(d.facts.source?.profile, 7); XCTAssertEqual(d.facts.source?.level, 6)
        XCTAssertEqual(d.facts.enhancementLayer, .full)
        XCTAssertEqual(d.signalled?.profile, 8)
        XCTAssertTrue(warnings.contains { $0.contains("derived") })
        // Without a converter nothing can be read: the file stays as it is.
        warnings = []
        let none = DolbyVisionPlanner.decide(record: nil, firstKeyframe: lengthPrefixed([slice]), lengthSize: 4, converter: nil,
                                             transfer: 16, width: 1920, height: 1080, framesPerSecond: 24, warnings: &warnings)
        XCTAssertEqual(none.mode, .untouched); XCTAssertNil(none.signalled); XCTAssertFalse(none.facts.derived)
    }

    func testProfile8RecordOverAProfile7StartIsConverted() {
        // A muxer wrote the record of a later profile 8.1 section; the first keyframe is profile 7 with an enhancement layer.
        let conv = FakeDVConverter()
        conv.inspected = DolbyVisionSampleInfo(profile: 7, enhancementLayer: .minimal, hasEnhancementLayerNALs: true)
        var warnings: [String] = []
        let rec = MKVDolbyVisionMapping.make(profile: 8, level: 6, elPresent: false, compatibilityID: 1)
        let d = DolbyVisionPlanner.decide(record: rec, firstKeyframe: lengthPrefixed([slice, elNAL, rpuNAL]), lengthSize: 4, converter: conv,
                                          transfer: 16, width: 3840, height: 2160, framesPerSecond: 24, warnings: &warnings)
        XCTAssertEqual(d.mode, .convertAll)
        XCTAssertEqual(d.facts.source?.profile, 7); XCTAssertEqual(d.facts.source?.level, 6); XCTAssertTrue(d.facts.derived)
        XCTAssertEqual(d.facts.enhancementLayer, .minimal)
        XCTAssertEqual(d.signalled?.profile, 8)
        XCTAssertTrue(warnings.contains { $0.contains("starts with profile 7") })
        // A profile 8 record over a profile 8 start stays as it is.
        conv.inspected = DolbyVisionSampleInfo(profile: 8, enhancementLayer: nil, hasEnhancementLayerNALs: false)
        warnings = []
        let p8 = DolbyVisionPlanner.decide(record: rec, firstKeyframe: lengthPrefixed([slice, rpuNAL]), lengthSize: 4, converter: conv,
                                           transfer: 16, width: 3840, height: 2160, framesPerSecond: 24, warnings: &warnings)
        XCTAssertEqual(p8.mode, .convertWhereEnhancementLayer); XCTAssertEqual(p8.signalled, rec); XCTAssertFalse(p8.facts.derived)
    }

    func testPlannerKeepsProfile5And8Untouched() {
        var warnings: [String] = []
        for (p, compat) in [(5, 0), (8, 1), (8, 4), (8, 2)] {
            let rec = MKVDolbyVisionMapping.make(profile: p, level: 6, elPresent: false, compatibilityID: compat)
            let d = DolbyVisionPlanner.decide(record: rec, firstKeyframe: lengthPrefixed([slice]), lengthSize: 4, converter: nil,
                                              transfer: 16, width: 3840, height: 2160, framesPerSecond: 24, warnings: &warnings)
            XCTAssertEqual(d.mode, .untouched); XCTAssertEqual(d.signalled, rec, "profile \(p) record is signalled as the file has it")
        }
        XCTAssertTrue(warnings.isEmpty)
    }

    func testPlannerNotesHDR10Plus() {
        var warnings: [String] = []
        let d = DolbyVisionPlanner.decide(record: nil, firstKeyframe: lengthPrefixed([makeSEINAL([(4, hdr10PlusPayload)]), slice]), lengthSize: 4,
                                          converter: nil, transfer: 16, width: 3840, height: 2160, framesPerSecond: 24, warnings: &warnings)
        XCTAssertTrue(d.facts.hdr10Plus); XCTAssertEqual(d.mode, .untouched)
    }
}
