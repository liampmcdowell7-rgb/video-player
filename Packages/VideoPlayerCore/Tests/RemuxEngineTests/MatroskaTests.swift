import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

final class BytesTests: XCTestCase {
    func testByteWriterBoxesAndPatch() throws {
        var w = ByteWriter()
        w.box("free") { w in w.u32(0xDEADBEEF) }
        XCTAssertEqual(w.bytes, [0, 0, 0, 12, 0x66, 0x72, 0x65, 0x65, 0xDE, 0xAD, 0xBE, 0xEF])
        w.u32(0); w.patchU32(at: 12, 0x01020304)
        XCTAssertEqual(Array(w.bytes[12..<16]), [1, 2, 3, 4])
        var f = ByteWriter()
        f.fullBox("mfhd", version: 1, flags: 0x000203) { w in w.u32(7) }
        XCTAssertEqual(f.bytes, [0, 0, 0, 16, 0x6D, 0x66, 0x68, 0x64, 1, 0, 2, 3, 0, 0, 0, 7])
    }

    func testCursorBoundsAreChecked() {
        var c = ByteCursor([1, 2, 3])
        XCTAssertNoThrow(try c.u16())
        XCTAssertThrowsError(try c.u32()) { XCTAssertEqual($0 as? RemuxError, .truncated("need 4 bytes at 2, have 1")) }
    }

    func testExpGolombReads() throws {
        // 1 | 010 | 011 | 00100 -> ue 0, 1, 2, 3
        var r = BitReader([0b1010_0110, 0b0100_0000])
        XCTAssertEqual(try r.ue(), 0); XCTAssertEqual(try r.ue(), 1); XCTAssertEqual(try r.ue(), 2); XCTAssertEqual(try r.ue(), 3)
        // se: ue 1 -> +1, ue 2 -> -1
        var s = BitReader([0b0100_1100])
        XCTAssertEqual(try s.se(), 1); XCTAssertEqual(try s.se(), -1)
    }

    func testEmulationPreventionRoundTrip() {
        let original: [UInt8] = [0, 0, 1, 0, 0, 0, 0, 0, 2, 5, 0, 0, 3]
        let escaped = escapeRBSP(original)
        XCTAssertFalse(escaped.isEmpty)
        XCTAssertGreaterThan(escaped.count, original.count)
        XCTAssertEqual(unescapeRBSP(escaped[...]), original)
    }

    func testEBMLSizesAndIDs() throws {
        XCTAssertEqual(try EBML.readSize([0x81], 0).0, 1)
        XCTAssertEqual(try EBML.readSize([0x40, 0x7F], 0).0, 127)
        XCTAssertNil(try EBML.readSize([0xFF], 0).0)                      // unknown size
        XCTAssertEqual(try EBML.readSize([0x01, 0, 0, 0, 0, 0, 0, 5], 0).0, 5)
        XCTAssertEqual(try EBML.readID([0x1A, 0x45, 0xDF, 0xA3], 0).0, 0x1A45DFA3)
        XCTAssertThrowsError(try EBML.readID([0x1A, 0x45], 0))
        for n in [0, 1, 126, 127, 16382, 16383, 1_000_000] {
            XCTAssertEqual(try EBML.readSize(EW.vint(n), 0).0, Int64(n), "vint \(n)")
        }
    }
}

final class MatroskaIndexTests: XCTestCase {
    func index(_ s: SynthMKV) async throws -> (MKVIndex, SynthMKV.Result) {
        let r = s.build()
        return (try await MatroskaIndexer.load(from: DataReader(r.data)), r)
    }

    func testTracksColourAndDuration() async throws {
        let (idx, r) = try await index(SynthMKV())
        XCTAssertEqual(idx.timecodeScale, 1_000_000)
        XCTAssertEqual(idx.durationNs, 6_000_000_000)
        XCTAssertEqual(idx.fileSize, Int64(r.data.count))
        XCTAssertEqual(idx.tracks.map { $0.codecID }, ["V_MPEGH/ISO/HEVC", "A_AC3", "A_AAC", "A_DTS"])
        let v = try XCTUnwrap(idx.videoTrack)
        XCTAssertEqual(v.number, 1); XCTAssertEqual(v.pixelWidth, 1280); XCTAssertEqual(v.pixelHeight, 720)
        XCTAssertEqual(v.defaultDurationNs, 41_666_666)
        XCTAssertEqual(v.codecPrivate, makeHvcC())
        let c = try XCTUnwrap(v.colour)
        XCTAssertEqual(c.matrix, 9); XCTAssertEqual(c.range, 1); XCTAssertEqual(c.transfer, 16); XCTAssertEqual(c.primaries, 9)
        XCTAssertEqual(c.maxCLL, 1000); XCTAssertEqual(c.maxFALL, 400)
        let m = try XCTUnwrap(c.mastering)
        XCTAssertEqual(m.gx, 0.265, accuracy: 1e-6); XCTAssertEqual(m.gy, 0.69, accuracy: 1e-6)
        XCTAssertEqual(m.maxLuminance, 1000, accuracy: 1e-6); XCTAssertEqual(m.minLuminance, 0.0001, accuracy: 1e-8)
        let ac3 = try XCTUnwrap(idx.track(number: 2))
        XCTAssertEqual(ac3.language, "eng"); XCTAssertEqual(ac3.name, "English 5.1"); XCTAssertEqual(ac3.channels, 6); XCTAssertEqual(ac3.sampleRate, 48000)
        XCTAssertEqual(idx.audioTracks.count, 3)
    }

    func testCuesBeforeClusters() async throws {
        let (idx, r) = try await index(SynthMKV())
        XCTAssertFalse(idx.needsClusterScan)
        XCTAssertEqual(idx.cues.count, r.keyframeMs.count)
        XCTAssertEqual(idx.cues.map { $0.timeNs }, r.keyframeMs.map { Int64($0) * 1_000_000 })
        XCTAssertEqual(idx.cues.map { $0.clusterOffset }, r.clusterOffsets.map { Int64(r.segmentDataStart + $0) })
        XCTAssertEqual(idx.firstClusterOffset, Int64(r.segmentDataStart + r.clusterOffsets[0]))
        XCTAssertEqual(idx.segmentDataStart, Int64(r.segmentDataStart))
    }

    func testCuesAfterClustersFoundThroughSeekHead() async throws {
        var s = SynthMKV(); s.cuesAtEnd = true
        let (idx, r) = try await index(s)
        XCTAssertEqual(idx.cues.count, r.keyframeMs.count)
        XCTAssertEqual(idx.cues.map { $0.clusterOffset }, r.clusterOffsets.map { Int64(r.segmentDataStart + $0) })
        XCTAssertLessThan(idx.clusterRegionEnd, idx.fileSize)       // the cluster region ends where the Cues start
    }

    func testFileWithoutCuesNeedsScan() async throws {
        var s = SynthMKV(); s.withCues = false
        let (idx, r) = try await index(s)
        XCTAssertTrue(idx.needsClusterScan)
        let found = try await MatroskaClusterScanner.scan(reader: DataReader(r.data), index: idx, videoTrack: 1)
        XCTAssertEqual(found.map { $0.timeNs }, r.keyframeMs.map { Int64($0) * 1_000_000 })
        XCTAssertEqual(found.map { $0.clusterOffset }, r.clusterOffsets.map { Int64(r.segmentDataStart + $0) })
    }

    func testDolbyVisionMappingIsRead() async throws {
        var s = SynthMKV(); s.dolbyVisionProfile = 8
        let (idx, _) = try await index(s)
        let dv = try XCTUnwrap(idx.videoTrack?.dolbyVision)
        XCTAssertEqual(dv.profile, 8); XCTAssertEqual(dv.level, 6); XCTAssertTrue(dv.rpuPresent); XCTAssertTrue(dv.blPresent)
        XCTAssertEqual(dv.blCompatibilityID, 1); XCTAssertEqual(dv.record.count, 24)
    }

    func testNotMatroskaIsRejected() async {
        do { _ = try await MatroskaIndexer.load(from: DataReader(Data(repeating: 0x41, count: 4096))); XCTFail("expected a throw") }
        catch { XCTAssertTrue(error is RemuxError) }
    }

    func testIndexLoadUsesFewSmallReads() async throws {
        var big = SynthMKV(seconds: 30); big.videoFrameExtra = 4000
        let r = big.build()
        let reader = DataReader(r.data)
        _ = try await MatroskaIndexer.load(from: reader)
        XCTAssertLessThanOrEqual(reader.readCount, 8, "header walk should use a handful of reads")
        XCTAssertLessThan(reader.bytesRead, Int64(r.data.count) / 4, "the index must not read the clusters")
    }
}

final class MatroskaClusterTests: XCTestCase {
    func testClusterWindowParsesEveryFrame() async throws {
        let s = SynthMKV(seconds: 3)
        let r = s.build()
        let idx = try await MatroskaIndexer.load(from: DataReader(r.data))
        let start = Int(idx.firstClusterOffset)
        let window = [UInt8](r.data[start..<Int(idx.clusterRegionEnd)])
        let parsed = try MatroskaClusterParser.parse(window: window, windowOffset: idx.firstClusterOffset, tracks: idx.tracks, timecodeScale: idx.timecodeScale)
        XCTAssertFalse(parsed.endedInsideCluster)
        XCTAssertEqual(parsed.endOffset, idx.clusterRegionEnd)
        let video = parsed.frames.filter { $0.track == 1 }
        XCTAssertEqual(video.count, 72)
        XCTAssertEqual(video.map { $0.timeNs }, r.videoFrames.map { Int64($0.pts) * 1_000_000 })
        XCTAssertEqual(video.map { $0.isKeyframe }, r.videoFrames.map { $0.key })
        XCTAssertEqual(video.map { Array($0.data) }, r.videoFrames.map { $0.payload })
        let ac3 = parsed.frames.filter { $0.track == 2 }
        XCTAssertEqual(ac3.map { $0.timeNs }, r.audioFrames.map { Int64($0.ms) * 1_000_000 })
        XCTAssertEqual(ac3.first.map { Array($0.data) }, r.audioFrames.first?.payload)
    }

    func testTruncatedWindowReportsPartialCluster() async throws {
        let r = SynthMKV(seconds: 3).build()
        let idx = try await MatroskaIndexer.load(from: DataReader(r.data))
        let start = Int(idx.firstClusterOffset)
        let secondCluster = Int(r.segmentDataStart + r.clusterOffsets[1])
        let cut = secondCluster + 100
        let parsed = try MatroskaClusterParser.parse(window: [UInt8](r.data[start..<cut]), windowOffset: idx.firstClusterOffset, tracks: idx.tracks, timecodeScale: idx.timecodeScale)
        XCTAssertTrue(parsed.endedInsideCluster)
        XCTAssertEqual(parsed.endOffset, Int64(secondCluster))
        XCTAssertEqual(parsed.frames.filter { $0.track == 1 }.count, 24, "only the complete first cluster is returned")
    }

    func testLacedBlocksWithoutAnyDurationAreRejectedExplicitly() throws {
        let track = MKVTrack.testTrack(number: 2)
        let block = EW.el(EBMLID.simpleBlock, EW.vint(2) + [0, 0, 0x02 /* Xiph lacing */, 1, 1, 2, 3])
        let cluster = EW.el(EBMLID.cluster, EW.uint(EBMLID.clusterTimecode, 0) + block)
        XCTAssertThrowsError(try MatroskaClusterParser.parse(window: cluster, windowOffset: 0, tracks: [track], timecodeScale: 1_000_000)) {
            guard case RemuxError.unsupported(let m)? = $0 as? RemuxError else { return XCTFail("wrong error \($0)") }
            XCTAssertTrue(m.contains("laced") && m.contains("duration"))
        }
    }

    func testBlockGroupWithoutReferenceIsKeyframe() throws {
        let track = MKVTrack.testTrack(number: 1)
        let key = EW.el(EBMLID.blockGroup, EW.el(EBMLID.block, EW.vint(1) + [0, 0, 0, 9, 9]) + EW.uint(EBMLID.blockDuration, 40))
        let delta = EW.el(EBMLID.blockGroup, EW.el(EBMLID.block, EW.vint(1) + [0, 40, 0, 8]) + EW.el(EBMLID.referenceBlock, [0x00]))
        let cluster = EW.el(EBMLID.cluster, EW.uint(EBMLID.clusterTimecode, 1000) + key + delta)
        let parsed = try MatroskaClusterParser.parse(window: cluster, windowOffset: 0, tracks: [track], timecodeScale: 1_000_000)
        XCTAssertEqual(parsed.frames.map { $0.isKeyframe }, [true, false])
        XCTAssertEqual(parsed.frames.map { $0.timeNs }, [1_000_000_000, 1_040_000_000])
        XCTAssertEqual(parsed.frames[0].durationNs, 40_000_000)
    }

    func testHeaderStrippedTracksGetTheirHeaderBack() throws {
        var track = MKVTrack.testTrack(number: 1)
        track.strippedHeader = [0xAA, 0xBB]
        let cluster = EW.el(EBMLID.cluster, EW.uint(EBMLID.clusterTimecode, 0) + EW.el(EBMLID.simpleBlock, EW.vint(1) + [0, 0, 0x80, 1, 2]))
        let parsed = try MatroskaClusterParser.parse(window: cluster, windowOffset: 0, tracks: [track], timecodeScale: 1_000_000)
        XCTAssertEqual(Array(parsed.frames[0].data), [0xAA, 0xBB, 1, 2])
    }

    func testResyncFindsTheNextClusterStart() async throws {
        let r = SynthMKV(seconds: 4).build()
        let idx = try await MatroskaIndexer.load(from: DataReader(r.data))
        let third = Int64(r.segmentDataStart + r.clusterOffsets[2])
        let fourth = Int64(r.segmentDataStart + r.clusterOffsets[3])
        let found = try await MatroskaClusterScanner.resync(reader: DataReader(r.data), from: third + 50, limit: idx.clusterRegionEnd)
        XCTAssertEqual(found, fourth)
        let exact = try await MatroskaClusterScanner.resync(reader: DataReader(r.data), from: third, limit: idx.clusterRegionEnd)
        XCTAssertEqual(exact, third)
        let none = try await MatroskaClusterScanner.resync(reader: DataReader(r.data), from: fourth + 1, limit: idx.clusterRegionEnd)
        XCTAssertNil(none)
    }
}

extension MKVTrack {
    /// A bare track for tests that feed `MatroskaClusterParser` directly.
    static func testTrack(number: Int) -> MKVTrack {
        MKVTrack(number: number, uid: UInt64(number), type: number == 1 ? .video : .audio, codecID: "V_TEST", codecPrivate: [], name: "", language: "und",
                 isDefault: true, isEnabled: true, defaultDurationNs: nil, codecDelayNs: 0, seekPreRollNs: 0, pixelWidth: 0, pixelHeight: 0,
                 displayWidth: nil, displayHeight: nil, colour: nil, dolbyVision: nil, sampleRate: 48000, channels: 2, bitDepth: 0, strippedHeader: [])
    }
}
