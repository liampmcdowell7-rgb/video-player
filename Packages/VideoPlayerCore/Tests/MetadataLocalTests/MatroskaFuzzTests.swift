import XCTest
import Foundation
import VideoPlayerCore
@testable import MetadataLocal

/// Damage tests. They check that no input crashes the reader and that the only error it throws is `MatroskaError`.
/// A hang cannot be reported by a test: if the reader looped forever these would stall the test run, and the
/// per-test timing assertions would never be reached. The parser's loops all advance the read position or stop.
final class MatroskaFuzzTests: XCTestCase {
    /// Small, deterministic pseudo-random numbers (fixed seed, so a failure can be reproduced).
    struct LCG {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 11
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    }

    private func damagedFile() -> BuiltMKV {
        var f = richFile()
        f.clusterBytes = 300
        f.clusterCount = 2
        f.chaptersAtEnd = true
        f.tagsAtEnd = true
        f.voidBetweenElements = true
        f.crc = true
        return MKVBuilder.build(f)
    }

    /// Reads and returns the result; fails the test if the error is not a `MatroskaError`.
    @discardableResult
    private func read(_ bytes: [UInt8], headBytes: Int, beyondEnd: BeyondEnd = .throwError, file: StaticString = #filePath, line: UInt = #line) async -> EmbeddedMetadata? {
        do {
            return try await MatroskaReader(headBytes: headBytes).read(using: memoryReader(bytes, beyondEnd: beyondEnd))
        } catch is MatroskaError {
            return nil
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
            return nil
        }
    }

    func testTruncatedAtEveryByteBoundaryOfTheWholeFile() async {
        let built = damagedFile()
        let baseline = await read(built.bytes, headBytes: built.bytes.count + 100)
        XCTAssertEqual(baseline?.tracks.count, 7)
        let start = Date()
        var succeeded = 0
        var failed = 0
        for n in 0...built.bytes.count {
            let cut = Array(built.bytes[0..<n])
            for (head, mode) in [(512 * 1024, BeyondEnd.throwError), (64, BeyondEnd.empty)] {
                if let m = await read(cut, headBytes: head, beyondEnd: mode) {
                    succeeded += 1
                    XCTAssertLessThanOrEqual(m.tracks.count, 7)
                    XCTAssertLessThanOrEqual(m.editions.count, 2)
                    XCTAssertLessThanOrEqual(m.tags.count, 2)
                    XCTAssertLessThanOrEqual(m.attachments.count, 2)
                } else {
                    failed += 1
                }
            }
        }
        // A cut inside the EBML header or Segment header fails; every later cut still gives a result.
        XCTAssertGreaterThan(succeeded, failed, "succeeded \(succeeded), failed \(failed)")
        XCTAssertLessThan(Date().timeIntervalSince(start), 60)
    }

    func testTruncatedHeadWindowAtEveryByteBoundary() async {
        // Same file, but the *window* is what is cut: a window of n bytes over the complete file.
        let built = damagedFile()
        let baseline = await read(built.bytes, headBytes: built.bytes.count + 100)
        for n in 64...min(built.bytes.count, 4000) {
            if let m = await read(built.bytes, headBytes: n) {
                // Whatever the window size, a result never has more than the full read.
                XCTAssertLessThanOrEqual(m.tracks.count, baseline?.tracks.count ?? 0, "window \(n)")
                XCTAssertLessThanOrEqual(m.editions.count, baseline?.editions.count ?? 0, "window \(n)")
                XCTAssertEqual(m.docType, "matroska")
            }
        }
    }

    func testFlippedBytesWithAFixedSeed() async {
        let built = damagedFile()
        var rng = LCG(state: 0xDEAD_BEEF_CAFE_F00D)
        let start = Date()
        for round in 0..<2500 {
            var bytes = built.bytes
            let flips = 1 + rng.below(8)
            for _ in 0..<flips {
                let at = rng.below(bytes.count)
                switch rng.below(4) {
                case 0: bytes[at] = UInt8(truncatingIfNeeded: rng.next())
                case 1: bytes[at] = 0xFF
                case 2: bytes[at] = 0x00
                default: bytes[at] ^= UInt8(1 << rng.below(8))
                }
            }
            await read(bytes, headBytes: round % 2 == 0 ? 512 * 1024 : 100 + rng.below(2000))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 120)
    }

    func testFlipsConcentratedInTheHeadersOfElements() async {
        // Flip bytes right at element boundaries: IDs and size fields are the most dangerous bytes.
        let built = damagedFile()
        var rng = LCG(state: 7)
        for _ in 0..<1500 {
            var bytes = built.bytes
            let at = rng.below(min(bytes.count, 700))
            bytes[at] = UInt8(truncatingIfNeeded: rng.next())
            if at + 1 < bytes.count { bytes[at + 1] = UInt8(truncatingIfNeeded: rng.next()) }
            await read(bytes, headBytes: 700)
            await read(bytes, headBytes: 64)
        }
    }

    func testRandomBytesAfterAValidHeader() async {
        let built = damagedFile()
        var rng = LCG(state: 99)
        let header = Array(built.bytes[0..<built.segmentDataStart])
        for _ in 0..<500 {
            var bytes = header
            for _ in 0..<(1 + rng.below(3000)) { bytes.append(UInt8(truncatingIfNeeded: rng.next())) }
            await read(bytes, headBytes: 4096)
        }
    }

    func testPureRandomFilesAreRejectedOrEmpty() async {
        var rng = LCG(state: 5)
        for _ in 0..<500 {
            var bytes: [UInt8] = []
            for _ in 0..<(rng.below(2000)) { bytes.append(UInt8(truncatingIfNeeded: rng.next())) }
            let m = await read(bytes, headBytes: 4096)
            XCTAssertNil(m, "Random bytes should not look like Matroska")
        }
    }

    func testHugeDeclaredSizesDoNotAllocateOrLoop() async throws {
        // A Chapters element that claims 2^56-2 bytes, then a Tags element that claims to be 1 GiB.
        let header = W.master(MKV.ebmlHeader, [W.string(MKV.docType, "matroska")])
        let info = W.master(MKV.info, [W.uint(MKV.timecodeScale, 1_000_000)])
        let hugeChapters = W.id(MKV.chapters) + [0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE]
        let gibTags = W.id(MKV.tags) + W.size(1 << 30, minLength: 8)
        for tail in [hugeChapters, gibTags] {
            let body = info + tail
            let bytes = header + W.id(MKV.segment) + W.size(body.count + (1 << 40), minLength: 8) + body
            let log = ReadLog()
            let m = try await MatroskaReader().read(using: memoryReader(bytes, log: log))
            XCTAssertNotNil(m.info)
            XCTAssertTrue(m.warnings.contains { $0.contains("byte limit") || $0.contains("cut off") || $0.contains("could not be read") }, "\(m.warnings)")
            XCTAssertLessThan(log.totalBytes, 16 * 1024 * 1024)
        }
    }

    func testSegmentWithHugeKnownSizeAndNoContent() async throws {
        let header = W.master(MKV.ebmlHeader, [W.string(MKV.docType, "webm")])
        let bytes = header + W.id(MKV.segment) + W.size((1 << 50), minLength: 8)
        let m = try await MatroskaReader().read(using: memoryReader(bytes))
        XCTAssertEqual(m.docType, "webm")
        XCTAssertTrue(m.tracks.isEmpty)
    }

    func testEveryTopLevelElementClaimingToBeUnknownSize() async {
        // Replace each top-level size with "unknown" in turn.
        let built = damagedFile()
        var positions: [Int] = []
        var i = built.segmentDataStart
        while i < built.bytes.count, let id = EBMLView.readID(built.bytes, at: i, limit: built.bytes.count),
              let size = EBMLView.readSize(built.bytes, at: i + id.length, limit: built.bytes.count), let declared = size.value {
            positions.append(i + id.length)
            let next = i + id.length + size.length + Int(declared)
            if next <= i { break }
            i = next
            if id.id == MKV.cluster { break }
        }
        XCTAssertGreaterThan(positions.count, 4)
        for p in positions {
            var bytes = built.bytes
            // Rewrite the size field as the 1-byte unknown size marker where it is 1 byte, otherwise as all ones.
            let length = bytes[p].leadingZeroBitCount + 1
            for k in 0..<length where p + k < bytes.count { bytes[p + k] = (k == 0) ? UInt8(0xFF >> (length - 1)) | UInt8(0x80 >> (length - 1)) : 0xFF }
            await read(bytes, headBytes: 512 * 1024)
        }
    }
}
