import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// End-to-end tests of the session on hand-built Matroska files whose frame layout the test knows exactly.

func flatten(_ r: LoopbackResponse) -> [UInt8] { r.body.chunks.flatMap { $0 } }

struct Fragment {
    var parsed: ParsedFragment
    var payload: [UInt8]
    var bytes: [UInt8]
    init(_ bytes: [UInt8]) throws {
        parsed = try ParsedFragment.parse(bytes)
        payload = Array(bytes.suffix(parsed.mdatPayloadSize))
        self.bytes = bytes
    }
    var totalDuration: UInt64 { parsed.samples.reduce(0) { $0 + UInt64($1.duration) } }
}

final class CountingReader: ByteRangeReader, @unchecked Sendable {
    let inner: DataReader
    init(_ d: Data) { inner = DataReader(d) }
    var size: Int64 { inner.size }
    func read(_ range: ByteRange) async throws -> Data { try await inner.read(range) }
    var readCount: Int { inner.readCount }
    var bytesRead: Int64 { inner.bytesRead }
}

final class FakeFLACTranscoder: AudioTranscoding, @unchecked Sendable {
    var supportedCodecIDs: Set<String> { ["A_DTS"] }
    private let lock = NSLock()
    private(set) var calls: [(count: Int, first: Int64)] = []
    func outputConfig(for track: MKVTrack, firstFrame: [UInt8]) async throws -> AudioTrackConfig {
        AudioTrackConfig(trackID: UInt32(track.number), codec: .flac, sampleRate: 48000, channels: 6, bitsPerSample: 24,
                         specific: [0x80, 0, 0, 34] + [UInt8](repeating: 1, count: 34), language: track.language, samplesPerFrame: 1536, bitrate: 0, codecString: "fLaC")
    }
    func transcode(frames: [MKVFrame], track: MKVTrack, config: AudioTrackConfig) async throws -> [MKVFrame] {
        record(frames.count, frames[0].timeNs)
        return frames.map { var f = $0; f.data = ArraySlice([0xFF, 0xF8] + Array($0.data)); return f }
    }
    private func record(_ n: Int, _ t: Int64) { lock.lock(); calls.append((n, t)); lock.unlock() }
}

final class FakeDVConverter: DolbyVisionConverting, @unchecked Sendable {
    func outputRecord(for source: MKVDolbyVisionMapping) -> MKVDolbyVisionMapping {
        var rec: [UInt8] = [1, 0, UInt8(8 << 1), UInt8(6 << 3 | 0x05), 0x10]
        rec += [UInt8](repeating: 0, count: 19)
        return MKVDolbyVisionMapping(type: 0x64767643, record: rec)
    }
    var inspected: DolbyVisionSampleInfo? = DolbyVisionSampleInfo(profile: 7, enhancementLayer: .minimal, hasEnhancementLayerNALs: true)
    var fails = false
    func inspect(sample: [UInt8], lengthSize: Int) -> DolbyVisionSampleInfo? { inspected }
    private let lock = NSLock()
    private(set) var converted = 0
    func convert(sample: [UInt8], lengthSize: Int) throws -> [UInt8] {
        if fails { throw RemuxError.malformed("fake RPU rejected") }
        count(); return sample + [0xEE]
    }
    private func count() { lock.lock(); converted += 1; lock.unlock() }
}

final class SessionTests: XCTestCase {
    func session(_ s: SynthMKV, segmentSeconds: Double = 2, configure: (inout RemuxOptions) -> Void = { _ in }) -> (MatroskaRemuxSession, SynthMKV.Result, CountingReader) {
        let r = s.build()
        var o = RemuxOptions(); o.targetSegmentSeconds = segmentSeconds
        configure(&o)
        let reader = CountingReader(r.data)
        return (MatroskaRemuxSession(reader: reader, options: o), r, reader)
    }

    func entryNode(_ s: MatroskaRemuxSession, _ name: String) async throws -> BoxNode {
        let resource = try await s.resource(path: "init_video.mp4")
        return try XCTUnwrap(try BoxParser.parse(flatten(resource)).find("moov/trak/mdia/minf/stbl/stsd/" + name))
    }

    func frameIndex(_ ms: Int) -> Int64 { Int64((Double(ms) * 24 / 1000).rounded()) }

    func testPrepareDescribesTheFile() async throws {
        let (s, r, _) = session(SynthMKV())
        let info = try await s.prepare()
        XCTAssertEqual(info.segmentCount, 3); XCTAssertEqual(info.durationSeconds, 6, accuracy: 1e-6); XCTAssertEqual(info.targetSegmentSeconds, 2)
        XCTAssertEqual(info.width, 1280); XCTAssertEqual(info.height, 720); XCTAssertEqual(info.sampleEntry, "hvc1")
        XCTAssertEqual(info.videoCodecString, "hvc1.2.6.L120.90"); XCTAssertNil(info.supplementalCodecs); XCTAssertEqual(info.videoRange, .pq)
        XCTAssertEqual(info.audio.map { $0.trackNumber }, [2, 3])
        XCTAssertEqual(info.audio.map { $0.codecString }, ["ac-3", "mp4a.40.2"])
        XCTAssertEqual(info.audio.map { $0.isDefault }, [true, false], "exactly one default rendition")
        XCTAssertEqual(info.audio.map { $0.name }, ["English 5.1", "fra"])
        XCTAssertEqual(info.skippedAudio.map { $0.trackNumber }, [4]); XCTAssertEqual(info.skippedAudio.first?.codecID, "A_DTS")
        XCTAssertEqual(info.timelineOffsetSeconds, 7500.0 / 90000, accuracy: 1e-9)      // two frames of decode delay (SPS not parsable: default 2)
        XCTAssertTrue(info.warnings.contains { $0.contains("SPS not parsed") })
        XCTAssertFalse(info.usedClusterScan); XCTAssertFalse(info.isOverBudget)
        XCTAssertEqual(r.keyframeMs.count, 6)
        let again = try await s.prepare()
        XCTAssertEqual(again.segmentCount, info.segmentCount)
    }

    func testPlaylists() async throws {
        let (s, _, _) = session(SynthMKV())
        let master = String(decoding: flatten(try await s.resource(path: "master.m3u8")), as: UTF8.self)
        XCTAssertTrue(master.contains("CODECS=\"hvc1.2.6.L120.90,ac-3,mp4a.40.2\""), master)
        XCTAssertTrue(master.contains("RESOLUTION=1280x720")); XCTAssertTrue(master.contains("VIDEO-RANGE=PQ")); XCTAssertTrue(master.contains("FRAME-RATE=24.000"))
        XCTAssertTrue(master.contains("URI=\"audio_2.m3u8\"")); XCTAssertTrue(master.contains("LANGUAGE=\"fr\""))
        XCTAssertEqual(master.components(separatedBy: "DEFAULT=YES").count - 1, 1)
        let video = String(decoding: flatten(try await s.resource(path: "/video.m3u8")), as: UTF8.self)
        XCTAssertTrue(video.contains("#EXT-X-MAP:URI=\"init_video.mp4\""))
        XCTAssertEqual(video.components(separatedBy: "#EXTINF:2.00000,").count - 1, 3)
        XCTAssertTrue(video.contains("seg_video_2.m4s")); XCTAssertTrue(video.contains("#EXT-X-TARGETDURATION:2")); XCTAssertTrue(video.hasSuffix("#EXT-X-ENDLIST\n"))
        let audio = String(decoding: flatten(try await s.resource(path: "audio_3.m3u8")), as: UTF8.self)
        XCTAssertTrue(audio.contains("init_audio_3.mp4")); XCTAssertTrue(audio.contains("seg_audio_3_1.m4s"))
        let missing = try await s.resource(path: "audio_9.m3u8")
        XCTAssertEqual(missing.status, 404)
        let nothing = try await s.resource(path: "nothing"), outOfRange = try await s.resource(path: "seg_video_9.m4s")
        XCTAssertEqual(nothing.status, 404); XCTAssertEqual(outOfRange.status, 404)
    }

    func testInitSegmentsCarryTheHDRDescription() async throws {
        for withColourElement in [true, false] {
            var f = SynthMKV(); f.colour = withColourElement
            let (s, _, _) = session(f)
            let bytes = flatten(try await s.resource(path: "init_video.mp4"))
            XCTAssertEqual(FMP4Checker.check(initSegment: bytes, expectedEntry: "hvc1"), [])
            let entry = try XCTUnwrap(try BoxParser.parse(bytes).find("moov/trak/mdia/minf/stbl/stsd/hvc1"))
            XCTAssertEqual(try XCTUnwrap(entry.find("mdcv")).payload, SynthMKV.mdcv24, "mdcv from \(withColourElement ? "the Colour element" : "the in-band SEI")")
            XCTAssertEqual(try XCTUnwrap(entry.find("clli")).payload, SynthMKV.clliPayload)
            if withColourElement { XCTAssertEqual(try XCTUnwrap(entry.find("colr")).payload, Array("nclx".utf8) + [0, 9, 0, 16, 0, 9, 0]) }
            else { XCTAssertNil(entry.find("colr"), "no Colour element and no VUI: no colr box") }
        }
        let (s, _, _) = session(SynthMKV())
        let ac3 = flatten(try await s.resource(path: "init_audio_2.mp4"))
        XCTAssertEqual(FMP4Checker.check(initSegment: ac3, expectedEntry: "ac-3").filter { !$0.contains("stsz") }, [])
        XCTAssertEqual(try XCTUnwrap(try BoxParser.parse(ac3).find("moov/trak/mdia/minf/stbl/stsd/ac-3/dac3")).payload, [0x10, 0x3D, 0xC0])
        let aac = flatten(try await s.resource(path: "init_audio_3.mp4"))
        XCTAssertNotNil(try BoxParser.parse(aac).find("moov/trak/mdia/minf/stbl/stsd/mp4a/esds"))
    }

    func testVideoSegmentsMatchTheSourceFramesWithoutReordering() async throws {
        let (s, r, _) = session(SynthMKV())
        var previousEnd: UInt64 = 0
        for k in 0..<3 {
            let frag = try Fragment(flatten(try await s.resource(path: "seg_video_\(k).m4s")))
            XCTAssertEqual(FMP4Checker.check(fragment: frag.bytes), [], "segment \(k)")
            XCTAssertEqual(frag.parsed.sequence, UInt32(k + 1)); XCTAssertEqual(frag.parsed.trackID, 1)
            XCTAssertEqual(frag.parsed.samples.count, 48)
            let expected = r.videoFrames[(k * 48)..<((k + 1) * 48)]
            XCTAssertEqual(frag.payload, expected.flatMap { $0.payload }, "samples are the source frames, unchanged")
            XCTAssertEqual(frag.parsed.samples.map { $0.duration }, [UInt32](repeating: 3750, count: 48))
            XCTAssertEqual(frag.parsed.baseDecodeTime, UInt64(k * 48 * 3750))
            if k > 0 { XCTAssertEqual(frag.parsed.baseDecodeTime, previousEnd, "contiguous") }
            previousEnd = frag.parsed.baseDecodeTime + frag.totalDuration
            XCTAssertEqual(frag.parsed.samples.map { $0.cto }, [Int32](repeating: 7500, count: 48), "no reordering: composition offset = decode delay")
            XCTAssertEqual(frag.parsed.samples.map { $0.flags & 0x0001_0000 == 0 }, expected.map { $0.key })
        }
    }

    func testVideoSegmentsWithBFrameReorderingHaveCorrectDecodeAndCompositionTimes() async throws {
        var f = SynthMKV(); f.reorder = true
        let (s, r, _) = session(f)
        var previousEnd: UInt64 = 0
        for k in 0..<3 {
            let frag = try Fragment(flatten(try await s.resource(path: "seg_video_\(k).m4s")))
            XCTAssertEqual(FMP4Checker.check(fragment: frag.bytes), [])
            let expected = Array(r.videoFrames[(k * 48)..<((k + 1) * 48)])
            XCTAssertEqual(frag.payload, expected.flatMap { $0.payload }, "decode order is kept")
            let pts = expected.map { frameIndex($0.pts) * 3750 }
            let sorted = pts.sorted()
            for (i, sample) in frag.parsed.samples.enumerated() {
                let dts = Int64(frag.parsed.baseDecodeTime) + frag.parsed.samples[0..<i].reduce(0) { $0 + Int64($1.duration) }
                XCTAssertEqual(dts, sorted[i], "dts of sample \(i)")
                XCTAssertEqual(Int64(sample.cto), pts[i] + 7500 - dts, "cto of sample \(i)")
                XCTAssertGreaterThanOrEqual(sample.cto, 0)
            }
            if k > 0 { XCTAssertEqual(frag.parsed.baseDecodeTime, previousEnd) }
            previousEnd = frag.parsed.baseDecodeTime + frag.totalDuration
            XCTAssertTrue(frag.parsed.samples.contains { $0.cto != 7500 }, "B-frames really reorder")
        }
        XCTAssertEqual(previousEnd, 144 * 3750)
    }

    func testAudioSegmentsAreContiguousAndComplete() async throws {
        let (s, r, _) = session(SynthMKV())
        var ac3End: UInt64 = 0, aacEnd: UInt64 = 0
        var ac3Payload: [UInt8] = [], ac3Frames = 0
        for k in 0..<3 {
            let a = try Fragment(flatten(try await s.resource(path: "seg_audio_2_\(k).m4s")))
            XCTAssertEqual(FMP4Checker.check(fragment: a.bytes), []); XCTAssertEqual(a.parsed.trackID, 2)
            if k == 0 { XCTAssertEqual(a.parsed.baseDecodeTime, 4000, "start offset = decode delay in samples (83.3 ms at 48 kHz)") }
            else { XCTAssertEqual(a.parsed.baseDecodeTime, ac3End, "segment \(k) starts where \(k - 1) ended") }
            ac3End = a.parsed.baseDecodeTime + a.totalDuration
            XCTAssertTrue(a.parsed.samples.allSatisfy { $0.duration == 1536 })
            ac3Payload += a.payload; ac3Frames += a.parsed.samples.count
            let b = try Fragment(flatten(try await s.resource(path: "seg_audio_3_\(k).m4s")))
            if k > 0 { XCTAssertEqual(b.parsed.baseDecodeTime, aacEnd) }
            aacEnd = b.parsed.baseDecodeTime + b.totalDuration
            XCTAssertTrue(b.parsed.samples.allSatisfy { $0.duration == 1024 })
        }
        XCTAssertEqual(ac3Frames, r.audioFrames.count, "every AC-3 frame lands in exactly one segment")
        XCTAssertEqual(ac3Payload, r.audioFrames.flatMap { $0.payload })
    }

    func testSegmentIndexForSeconds() async throws {
        let (s, _, _) = session(SynthMKV())
        _ = try await s.prepare()
        var resolved: [Int] = []
        for t in [0.0, 1.9, 2.0, 3.5, 5.99, 6.0, 100] { resolved.append(await s.segmentIndex(forSeconds: t)) }
        XCTAssertEqual(resolved, [0, 0, 1, 1, 2, 2, 2])
    }

    func testFileWithoutCuesGivesTheSameSegments() async throws {
        var f = SynthMKV(); f.withCues = false
        let (s, r, _) = session(f)
        let info = try await s.prepare()
        XCTAssertTrue(info.usedClusterScan); XCTAssertEqual(info.segmentCount, 3)
        XCTAssertTrue(info.warnings.contains { $0.contains("no Cues") })
        let frag = try Fragment(flatten(try await s.resource(path: "seg_video_1.m4s")))
        XCTAssertEqual(frag.payload, r.videoFrames[48..<96].flatMap { $0.payload })
    }

    func testCuesAtTheEndOfTheFile() async throws {
        var f = SynthMKV(); f.cuesAtEnd = true
        let (s, r, _) = session(f)
        let frag = try Fragment(flatten(try await s.resource(path: "seg_video_2.m4s")))
        XCTAssertEqual(frag.payload, r.videoFrames[96..<144].flatMap { $0.payload })
    }

    func testWindowsAreReadOnceAndSmall() async throws {
        let (s, r, reader) = session(SynthMKV(seconds: 12))
        _ = try await s.prepare()
        let afterPrepare = reader.readCount
        let bytesAfterPrepare = reader.bytesRead      // prepare() reads a fixed-size header probe, which is most of this tiny file
        for k in 0..<6 {
            _ = try await s.resource(path: "seg_video_\(k).m4s")
            _ = try await s.resource(path: "seg_audio_2_\(k).m4s")
            _ = try await s.resource(path: "seg_audio_3_\(k).m4s")
        }
        let loads = await s.windowLoads
        XCTAssertEqual(loads, 6, "one window read per segment, shared by video and both audio tracks")
        XCTAssertLessThan(reader.bytesRead - bytesAfterPrepare, Int64(Double(r.data.count) * 1.8), "windows overlap by one cluster per segment, nothing is read twice beyond that")
        XCTAssertLessThan(reader.readCount - afterPrepare, 6 * 3 + 6, "about two reads per window (cluster size probe + window)")
    }

    func testHighBitrateStreamStaysInsideTheWindowBudget() async throws {
        var f = SynthMKV(seconds: 12); f.audio = false; f.videoFrameExtra = 625_000        // about 120 Mbps
        let r = f.build()
        var o = RemuxOptions(); o.budget = EngineBudget()
        let reader = CountingReader(r.data)
        let s = MatroskaRemuxSession(reader: reader, options: o)
        let info = try await s.prepare()
        let bitrate = Double(r.data.count) * 8 / info.durationSeconds
        print("[session-budget] bitrate \(Int(bitrate / 1e6)) Mbps, segment \(String(format: "%.2f", info.targetSegmentSeconds)) s, \(info.segmentCount) segments")
        XCTAssertGreaterThan(bitrate, 100e6)
        XCTAssertEqual(info.targetSegmentSeconds, o.budget.targetSegmentSeconds(bitrate: bitrate), accuracy: 0.01)
        XCTAssertLessThan(info.targetSegmentSeconds, 6, "the budget shortens segments at 100+ Mbps")
        for k in 0..<info.segmentCount { _ = try await s.resource(path: "seg_video_\(k).m4s") }
        let largest = await s.largestWindowBytes, peak = await s.peakCachedWindows
        print("[session-budget] largest window \(largest / 1_048_576) MiB, peak cached windows \(peak)")
        XCTAssertLessThanOrEqual(Int64(peak) * largest, o.budget.memoryBytes, "windows held at once x window size fits the budget")
        XCTAssertLessThan(Double(largest), 1.6 * info.targetSegmentSeconds * bitrate / 8 + 2_000_000, "a window is about 1.5 segments")
    }

    func testCancelStopsEverything() async throws {
        let (s, _, _) = session(SynthMKV())
        _ = try await s.prepare()
        await s.cancel()
        do { _ = try await s.resource(path: "seg_video_0.m4s"); XCTFail("expected cancellation") }
        catch { XCTAssertEqual(error as? RemuxError, .cancelled) }
    }

    func testUnsupportedVideoCodecIsReported() async throws {
        var data = SynthMKV(audio: false).build().data
        let needle = Array("V_MPEGH/ISO/HEVC".utf8)
        let hay = [UInt8](data)
        let at = try XCTUnwrap(hay.firstRange(of: needle)).lowerBound
        data.replaceSubrange(at..<(at + needle.count), with: Array("V_MPEGH/ISO/XXXX".utf8))
        let s = MatroskaRemuxSession(reader: DataReader(data))
        do { _ = try await s.prepare(); XCTFail("expected a throw") }
        catch { guard case RemuxError.unsupported(let m)? = error as? RemuxError else { return XCTFail("\(error)") }; XCTAssertTrue(m.contains("video codec")) }
    }

    func testTranscodedAudioIsOfferedAsFLAC() async throws {
        let t = FakeFLACTranscoder()
        let (s, _, _) = session(SynthMKV()) { $0.audioTranscoder = t }
        let info = try await s.prepare()
        XCTAssertEqual(info.audio.map { $0.trackNumber }, [2, 3, 4]); XCTAssertEqual(info.audio.last?.codecString, "fLaC"); XCTAssertEqual(info.audio.last?.transcoded, true)
        XCTAssertTrue(info.skippedAudio.isEmpty)
        let init4 = flatten(try await s.resource(path: "init_audio_4.mp4"))
        XCTAssertNotNil(try BoxParser.parse(init4).find("moov/trak/mdia/minf/stbl/stsd/fLaC/dfLa"))
        let frag = try Fragment(flatten(try await s.resource(path: "seg_audio_4_1.m4s")))
        XCTAssertEqual(FMP4Checker.check(fragment: frag.bytes), [])
        XCTAssertEqual(frag.parsed.samples.first?.size, 8 + 2, "the transcoder's output frames are what is muxed")
        XCTAssertEqual(frag.parsed.samples.count, 62, "frames at 2016 ... 3968 ms")
        XCTAssertFalse(t.calls.isEmpty)
        let master = String(decoding: flatten(try await s.resource(path: "master.m3u8")), as: UTF8.self)
        XCTAssertTrue(master.contains("fLaC"), master)
    }

    func testDolbyVisionSignalling() async throws {
        // Profile 8.1: hvc1 + dvvC, supplemental codecs with the db1p brand.
        var f = SynthMKV(); f.dolbyVisionProfile = 8
        var (s, _, _) = session(f)
        var info = try await s.prepare()
        XCTAssertEqual(info.sampleEntry, "hvc1"); XCTAssertEqual(info.supplementalCodecs, "dvh1.08.06/db1p")
        var entry = try await entryNode(s, "hvc1")
        XCTAssertNotNil(entry.find("dvvC")); XCTAssertNil(entry.find("dvcC"))
        // Profile 5: dvh1 + dvcC, CODECS names Dolby Vision itself.
        f.dolbyVisionProfile = 5
        (s, _, _) = session(f)
        info = try await s.prepare()
        XCTAssertEqual(info.sampleEntry, "dvh1"); XCTAssertEqual(info.videoCodecString, "dvh1.05.06"); XCTAssertNil(info.supplementalCodecs)
        entry = try await entryNode(s, "dvh1")
        XCTAssertNotNil(entry.find("dvcC"))
    }

    func testProfile7FallsBackToTheBaseLayerOrUsesTheConverter() async throws {
        var f = SynthMKV(); f.dolbyVisionProfile = 7
        // Without a converter: no DV box, the RPU / EL NAL units are dropped, a warning says so.
        let (plain, _, _) = session(f)
        let info = try await plain.prepare()
        XCTAssertNil(info.supplementalCodecs); XCTAssertEqual(info.sampleEntry, "hvc1")
        XCTAssertTrue(info.warnings.contains { $0.contains("profile 7") })
        let entry = try await entryNode(plain, "hvc1")
        XCTAssertNil(entry.find("dvcC")); XCTAssertNil(entry.find("dvvC"))
        // With a converter: the converter's record is signalled as profile 8.1 and every sample goes through it.
        let conv = FakeDVConverter()
        let (converted, r, _) = session(f) { $0.dolbyVisionConverter = conv }
        let info2 = try await converted.prepare()
        XCTAssertEqual(info2.supplementalCodecs, "dvh1.08.06/db1p")
        XCTAssertTrue(info2.dolbyVisionConverted); XCTAssertEqual(info2.dolbyVisionEnhancementLayerType, .minimal)
        XCTAssertEqual(info2.dolbyVisionSourceProfile, 7); XCTAssertEqual(info2.dolbyVisionOutputProfile, 8)
        XCTAssertEqual(conv.converted, 1, "prepare probes the first keyframe once")
        let frag = try Fragment(flatten(try await converted.resource(path: "seg_video_0.m4s")))
        XCTAssertEqual(conv.converted, 1 + 48)
        XCTAssertEqual(frag.parsed.samples[0].size, UInt32(r.videoFrames[0].payload.count + 1))
    }

    func testProfile7WhoseFirstRPUIsRejectedPlaysTheBaseLayerAndSaysSo() async throws {
        var f = SynthMKV(); f.dolbyVisionProfile = 7
        let conv = FakeDVConverter(); conv.fails = true
        let (s, _, _) = session(f) { $0.dolbyVisionConverter = conv }
        let info = try await s.prepare()
        XCTAssertFalse(info.dolbyVisionConverted); XCTAssertTrue(info.dolbyVisionConversionFailed)
        XCTAssertNil(info.supplementalCodecs); XCTAssertNil(info.dolbyVisionOutputProfile)
        XCTAssertTrue(info.warnings.contains { $0.contains("conversion failed") }, "\(info.warnings)")
        let entry = try await entryNode(s, "hvc1")
        XCTAssertNil(entry.find("dvcC")); XCTAssertNil(entry.find("dvvC"))
    }

    func testProfile8FileOnlyConvertsAccessUnitsThatCarryAnEnhancementLayer() async throws {
        var f = SynthMKV(); f.dolbyVisionProfile = 8
        let conv = FakeDVConverter()
        conv.inspected = DolbyVisionSampleInfo(profile: 8, enhancementLayer: nil, hasEnhancementLayerNALs: false)
        let (s, r, _) = session(f) { $0.dolbyVisionConverter = conv }
        let info = try await s.prepare()
        XCTAssertEqual(info.supplementalCodecs, "dvh1.08.06/db1p"); XCTAssertFalse(info.dolbyVisionConverted)
        let frag = try Fragment(flatten(try await s.resource(path: "seg_video_0.m4s")))
        XCTAssertEqual(conv.converted, 0, "profile 8 samples without an enhancement layer are never touched")
        XCTAssertEqual(frag.parsed.samples[0].size, UInt32(r.videoFrames[0].payload.count))
    }

    func testReorderDeeperThanTheDecodeDelayIsAnError() async throws {
        let (s, _, _) = session(SynthMKV())
        _ = try await s.prepare()
        let timeline = VideoTimeline(originNs: 0, frameNs: 41_666_666, delayFrames: 0)
        let frames = [0, 3, 1, 2].map { MKVFrame(track: 1, timeNs: Int64($0) * 41_666_666, isKeyframe: $0 == 0, durationNs: nil, data: [1, 2][...]) }
        let cfg = VideoTrackConfig(trackID: 1, codec: .hevc(try HVCConfig(parsing: makeHvcC())), width: 16, height: 16, sampleEntry: "hvc1",
                                   colour: nil, hdr: HDRStaticMetadata(), dolbyVision: nil, language: "und", frameRate: 24)
        do { _ = try await s.videoSamples(frames, timeline: timeline, config: cfg); XCTFail("expected reorderDepthExceeded") }
        catch { guard case RemuxError.reorderDepthExceeded(let needed)? = error as? RemuxError else { return XCTFail("\(error)") }; XCTAssertEqual(needed, 3750) }
    }

    func testTimelineGridSnapsMillisecondTimestamps() {
        let tl = VideoTimeline(originNs: 0, frameNs: 41_666_666, delayFrames: 2)
        XCTAssertEqual(tl.delayTicks, 7500)
        XCTAssertEqual([0, 42, 83, 125, 167, 208].map { tl.tick(Int64($0) * 1_000_000) }, [0, 3750, 7500, 11250, 15000, 18750])
        XCTAssertEqual(tl.tickAfter(208_000_000), 22500)
        let free = VideoTimeline(originNs: 1_000_000_000, frameNs: nil, delayFrames: 2)
        XCTAssertEqual(free.tick(1_500_000_000), 45000)
        XCTAssertEqual(free.delayTicks, 7500)
    }
}

