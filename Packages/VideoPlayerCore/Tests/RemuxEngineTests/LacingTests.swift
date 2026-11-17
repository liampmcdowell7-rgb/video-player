import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

// Matroska lacing (RFC 9559 section 10.3). The real-media tests found that mkvmerge laces small audio frames.
// These tests build one cluster by hand with one laced SimpleBlock and check the frames that come out.

final class LacingTests: XCTestCase {

    private func cluster(blockPayload: [UInt8], flags: UInt8, track: UInt8 = 0x82) -> [UInt8] {
        let block: [UInt8] = [track, 0x00, 0x00, flags] + blockPayload                 // track 2, relative time 0
        let simple: [UInt8] = [0xA3, 0x80 | UInt8(block.count)] + block
        let body: [UInt8] = [0xE7, 0x81, 0x0A] + simple                                   // Timecode = 10 ticks
        return [0x1F, 0x43, 0xB6, 0x75, 0x80 | UInt8(body.count)] + body
    }

    private func parse(_ bytes: [UInt8], defaultDurationNs: Int64? = 20_000_000) throws -> [MKVFrame] {
        var t = MKVTrack.testTrack(number: 2)
        t.defaultDurationNs = defaultDurationNs
        return try MatroskaClusterParser.parse(window: bytes, windowOffset: 0, tracks: [t], timecodeScale: 1_000_000).frames
    }

    func testXiphLacingSplitsThreeFrames() throws {
        // 3 frames of 2, 3 and 4 bytes: count-1 = 2, sizes 2 and 3 (the last is the rest).
        let frames = try parse(cluster(blockPayload: [0x02, 0x02, 0x03, 1, 1, 2, 2, 2, 3, 3, 3, 3], flags: 0x82))
        XCTAssertEqual(frames.map { Array($0.data) }, [[1, 1], [2, 2, 2], [3, 3, 3, 3]])
        XCTAssertEqual(frames.map { $0.timeNs }, [10_000_000, 30_000_000, 50_000_000], "block time + n * default duration")
        XCTAssertTrue(frames.allSatisfy { $0.isKeyframe && $0.track == 2 })
    }

    func testXiphLacingWithASizeOf255OrMore() throws {
        let big = [UInt8](repeating: 7, count: 300)
        let frames = try parse(bigCluster(big))
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].data.count, 300)
        XCTAssertEqual(Array(frames[1].data), [9, 9])
    }

    private func bigCluster(_ big: [UInt8]) -> [UInt8] {
        // Sizes need 2-byte EBML lengths here (the payload is over 127 bytes).
        let block: [UInt8] = [0x82, 0x00, 0x00, 0x82, 0x01, 0xFF, 45] + big + [9, 9]
        let simple: [UInt8] = [0xA3, 0x40 | UInt8(block.count >> 8), UInt8(block.count & 0xFF)] + block
        let body: [UInt8] = [0xE7, 0x81, 0x0A] + simple
        return [0x1F, 0x43, 0xB6, 0x75, 0x40 | UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body
    }

    func testFixedSizeLacingSplitsEvenly() throws {
        let frames = try parse(cluster(blockPayload: [0x02, 1, 1, 2, 2, 3, 3], flags: 0x84))
        XCTAssertEqual(frames.map { Array($0.data) }, [[1, 1], [2, 2], [3, 3]])
    }

    func testEBMLLacingUsesSignedDifferences() throws {
        // 4 frames of 3, 5, 4 and 2 bytes. First size 3 -> 0x83. Then +2 -> raw = 2 + 63 = 65 -> 0xC1. Then -1 -> raw = 62 -> 0xBE.
        let payload: [UInt8] = [0x03, 0x83, 0xC1, 0xBE] + [1, 1, 1] + [2, 2, 2, 2, 2] + [3, 3, 3, 3] + [4, 4]
        let frames = try parse(cluster(blockPayload: payload, flags: 0x86))
        XCTAssertEqual(frames.map { $0.data.count }, [3, 5, 4, 2])
        XCTAssertEqual(Array(frames[3].data), [4, 4])
    }

    func testBlockDurationOverridesTheDefaultDurationForLacedBlocks() throws {
        // BlockGroup with a BlockDuration of 60 ticks over 3 frames = 20 ms each, and no track default duration.
        let block: [UInt8] = [0x82, 0x00, 0x00, 0x02, 0x02, 0x01, 0x01, 5, 6, 7, 7]
        let group: [UInt8] = [0xA1, 0x80 | UInt8(block.count)] + block + [0x9B, 0x81, 60]
        let body: [UInt8] = [0xE7, 0x81, 0x00, 0xA0, 0x80 | UInt8(group.count)] + group
        let bytes: [UInt8] = [0x1F, 0x43, 0xB6, 0x75, 0x80 | UInt8(body.count)] + body
        let frames = try parse(bytes, defaultDurationNs: nil)
        XCTAssertEqual(frames.map { Array($0.data) }, [[5], [6], [7, 7]])
        XCTAssertEqual(frames.map { $0.timeNs }, [0, 20_000_000, 40_000_000])
    }

    func testLacedBlockWithNoDurationAnywhereIsReportedUnsupportedNotGuessed() throws {
        XCTAssertThrowsError(try parse(cluster(blockPayload: [0x01, 0x01, 1, 2, 2], flags: 0x82), defaultDurationNs: nil)) { error in
            guard case RemuxError.unsupported = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testAnOversizedLaceIsMalformed() throws {
        XCTAssertThrowsError(try parse(cluster(blockPayload: [0x01, 0x09, 1, 2], flags: 0x82)))
    }

    func testUnlacedBlocksAreUnchanged() throws {
        let frames = try parse(cluster(blockPayload: [1, 2, 3], flags: 0x80))
        XCTAssertEqual(frames.count, 1); XCTAssertEqual(Array(frames[0].data), [1, 2, 3]); XCTAssertEqual(frames[0].timeNs, 10_000_000)
    }
}
