import XCTest
import Foundation
import RemuxEngine
@testable import DolbyVisionRPU

// The NAL rewriting of the profile 7 converter, with a fake RPU codec (runs everywhere, no native library needed).
// All NAL bytes are FIXTURE values built here.

/// Fake codec: the "converted" RPU is the header plus the payload reversed; byte 2 = 0xFE makes it fail; byte 2 = 0x0F
/// describes FEL, anything else MEL.
struct FakeRPUCodec: DolbyVisionRPUCodec {
    func convertToProfile81(_ nal: ArraySlice<UInt8>) throws -> [UInt8] {
        let b = Array(nal)
        if b.count > 2, b[2] == 0xFE { throw DolbyVisionRPUError("fake rejection") }
        return [0x7C, 0x01] + b.dropFirst(2).reversed()
    }
    func describe(_ nal: ArraySlice<UInt8>) -> (profile: Int, enhancementLayer: DolbyVisionSampleInfo.EnhancementLayer?)? {
        let b = Array(nal)
        guard b.count > 2, b[2] != 0xFE else { return nil }
        return (7, b[2] == 0x0F ? .full : .minimal)
    }
}

func lengthPrefixed(_ nals: [[UInt8]], size: Int = 4) -> [UInt8] {
    var out: [UInt8] = []
    for n in nals { appendLengthPrefixed(n[...], lengthSize: size, to: &out) }
    return out
}

final class Profile7ConverterTests: XCTestCase {
    let aud: [UInt8] = [0x46, 0x01, 0x50]                     // AUD, layer 0
    let sps: [UInt8] = [0x42, 0x01, 0x01, 0x02]               // SPS, layer 0
    let sei: [UInt8] = [0x4E, 0x01, 0x89, 0x02, 0x00, 0x01, 0x80]
    let slice: [UInt8] = [0x26, 0x01, 0xAF, 0x06, 0x22]       // IDR_W_RADL
    let elWrapped: [UInt8] = [0x7E, 0x01, 0x26, 0x01, 0xAF]   // UNSPEC63 wrapping an EL slice
    let elLayer1: [UInt8] = [0x02, 0x09, 0xAA, 0xBB]           // TRAIL_R, nuh_layer_id 1
    let rpuFEL: [UInt8] = [0x7C, 0x01, 0x0F, 0x08, 0x09, 0x20]
    let rpuBad: [UInt8] = [0x7C, 0x01, 0xFE, 0x08]

    func testDropsTheEnhancementLayerAndConvertsTheRPUInPlace() throws {
        let conv = DolbyVisionProfile7Converter(codec: FakeRPUCodec())
        for size in [4, 2, 1] {
            let input = lengthPrefixed([aud, sps, sei, slice, elWrapped, elLayer1, rpuFEL], size: size)
            let converted: [UInt8] = [0x7C, 0x01, 0x20, 0x09, 0x08, 0x0F]
            XCTAssertEqual(try conv.convert(sample: input, lengthSize: size), lengthPrefixed([aud, sps, sei, slice, converted], size: size),
                           "length size \(size): order kept, EL gone, RPU converted")
        }
        XCTAssertEqual(conv.stats.convertedAccessUnits, 3)
    }

    func testASampleWithoutDolbyVisionNALsIsReturnedAsItIs() throws {
        let conv = DolbyVisionProfile7Converter(codec: FakeRPUCodec())
        let input = lengthPrefixed([aud, sps, sei, slice])
        XCTAssertEqual(try conv.convert(sample: input, lengthSize: 4), input)
        XCTAssertEqual(conv.stats, .init(), "nothing counted")
    }

    func testARejectedRPUThrowsAndIsCounted() {
        let conv = DolbyVisionProfile7Converter(codec: FakeRPUCodec())
        XCTAssertThrowsError(try conv.convert(sample: lengthPrefixed([slice, elWrapped, rpuBad]), lengthSize: 4))
        XCTAssertEqual(conv.stats.rejectedAccessUnits, 1)
        XCTAssertEqual(conv.stats.lastRejection, "fake rejection")
        XCTAssertThrowsError(try conv.convert(sample: [0, 0, 0, 9, 1], lengthSize: 4), "a broken length prefix is an error, not a silent pass")
    }

    func testInspectReadsTheRPUAndTheLayers() {
        let conv = DolbyVisionProfile7Converter(codec: FakeRPUCodec())
        XCTAssertEqual(conv.inspect(sample: lengthPrefixed([slice, elWrapped, rpuFEL]), lengthSize: 4),
                       DolbyVisionSampleInfo(profile: 7, enhancementLayer: .full, hasEnhancementLayerNALs: true))
        XCTAssertEqual(conv.inspect(sample: lengthPrefixed([slice, [0x7C, 0x01, 0x01, 0x02]]), lengthSize: 4),
                       DolbyVisionSampleInfo(profile: 7, enhancementLayer: .minimal, hasEnhancementLayerNALs: false))
        XCTAssertNil(conv.inspect(sample: lengthPrefixed([slice]), lengthSize: 4), "no RPU")
        XCTAssertNil(conv.inspect(sample: lengthPrefixed([slice, rpuBad]), lengthSize: 4), "unreadable RPU")
    }

    func testOutputRecordIsProfile81ForProfile7Only() {
        let conv = DolbyVisionProfile7Converter(codec: FakeRPUCodec())
        let p7 = MKVDolbyVisionMapping.make(profile: 7, level: 6, elPresent: true, compatibilityID: 6)
        let out = conv.outputRecord(for: p7)
        XCTAssertEqual(out.type, 0x64767643)
        XCTAssertEqual([out.profile, out.level, out.blCompatibilityID], [8, 6, 1])
        XCTAssertFalse(out.elPresent)
        let p8 = MKVDolbyVisionMapping.make(profile: 8, level: 9, elPresent: false, compatibilityID: 4)
        XCTAssertEqual(conv.outputRecord(for: p8), p8)
    }

    func testConcurrentUseCountsEveryAccessUnit() {
        let conv = DolbyVisionProfile7Converter(codec: FakeRPUCodec())
        let input = lengthPrefixed([slice, elWrapped, rpuFEL])
        let expected = try? conv.convert(sample: input, lengthSize: 4)
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            XCTAssertEqual(try? conv.convert(sample: input, lengthSize: 4), expected)
        }
        XCTAssertEqual(conv.stats.convertedAccessUnits, 201)
    }

    func testNativeConverterExistsExactlyWhenTheLibraryIsLinked() {
        XCTAssertEqual(DolbyVisionProfile7Converter.native() != nil, DolbyVisionProfile7Converter.isAvailable)
    }
}
