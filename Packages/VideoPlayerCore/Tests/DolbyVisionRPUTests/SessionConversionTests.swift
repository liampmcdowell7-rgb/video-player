import XCTest
import Foundation
@testable import RemuxEngine
@testable import DolbyVisionRPU

// The whole remux path on FIXTURE Matroska files (made by scripts/test-dovi.sh with mkvmerge): profile 7 FEL / MEL,
// a file that switches from profile 7 to 8.1 half way, and a plain profile 8.1 file. Checks the signalling, the
// samples against the reference tool, seeking, read volume, and an independent reading by ffprobe.

func flattenBody(_ r: LoopbackResponse) -> [UInt8] { r.body.chunks.flatMap { $0 } }

final class SessionConversionTests: XCTestCase {
    var converter: DolbyVisionProfile7Converter!

    override func setUpWithError() throws {
        guard let c = DolbyVisionProfile7Converter.native() else { throw XCTSkip("RPU library not linked (set VP_LIBDOVI, see scripts/test-dovi.sh)") }
        guard DoviMedia.dir != nil else { throw XCTSkip("VP_DOVI_MEDIA not set: run scripts/test-dovi.sh") }
        converter = c
    }

    func session(_ name: String, converter: (any DolbyVisionConverting)?) throws -> (MatroskaRemuxSession, DataReader) {
        let reader = DataReader(Data(try DoviMedia.bytes(name + ".mkv")))
        var o = RemuxOptions()
        o.targetSegmentSeconds = 1
        o.dolbyVisionConverter = converter
        return (MatroskaRemuxSession(reader: reader, options: o), reader)
    }

    /// Samples of every video segment, in decode order.
    func allSamples(_ s: MatroskaRemuxSession, count: Int, order: [Int]? = nil) async throws -> (samples: [[UInt8]], segments: [Int: [UInt8]]) {
        var segments: [Int: [UInt8]] = [:]
        for k in order ?? Array(0..<count) { segments[k] = flattenBody(try await s.resource(path: "seg_video_\(k).m4s")) }
        var samples: [[UInt8]] = []
        for k in 0..<count {
            guard let bytes = segments[k] else { continue }
            let f = try ParsedFragment.parse(bytes)
            var pos = bytes.count - f.mdatPayloadSize
            for smp in f.samples { samples.append(Array(bytes[pos..<(pos + Int(smp.size))])); pos += Int(smp.size) }
        }
        return (samples, segments)
    }

    /// Slices and RPU only: the Matroska muxer may drop delimiters and move parameter sets, which this app copies as they are.
    func pictureNALs(_ nals: [ArraySlice<UInt8>]) -> [[UInt8]] {
        nals.filter { let t = HEVCNAL.type(of: $0); return t < 32 || t == HEVCNAL.dolbyVisionRPU }.map(Array.init)
    }

    func testProfile7FileIsSignalledAsProfile81AndMatchesTheReference() async throws {
        for (name, layer) in [("p7_fel", DolbyVisionSampleInfo.EnhancementLayer.full), ("p7_mel", .minimal)] {
            let (s, _) = try session(name, converter: converter)
            let info = try await s.prepare()
            XCTAssertTrue(info.dolbyVisionConverted, name)
            XCTAssertEqual(info.dolbyVisionSourceProfile, 7, name); XCTAssertEqual(info.dolbyVisionOutputProfile, 8, name)
            XCTAssertEqual(info.dolbyVisionEnhancementLayerType, layer, name)
            XCTAssertFalse(info.dolbyVisionConversionFailed, name)
            XCTAssertEqual(info.sampleEntry, "hvc1", name)
            XCTAssertEqual(info.supplementalCodecs?.hasPrefix("dvh1.08."), true, "\(name): \(info.supplementalCodecs ?? "nil")")
            XCTAssertEqual(info.supplementalCodecs?.hasSuffix("/db1p"), true, name)
            XCTAssertEqual(info.videoRange, .pq, name)
            let master = String(decoding: flattenBody(try await s.resource(path: "master.m3u8")), as: UTF8.self)
            XCTAssertTrue(master.contains("SUPPLEMENTAL-CODECS=\"dvh1.08."), master)
            XCTAssertTrue(master.contains("VIDEO-RANGE=PQ"), master)
            // The init segment: dvvC, profile 8, level kept, no EL, compatibility 1; no dvcC left.
            let initBytes = flattenBody(try await s.resource(path: "init_video.mp4"))
            let tree = try BoxParser.parse(initBytes)
            let dvvC = try XCTUnwrap(tree.find("moov/trak/mdia/minf/stbl/stsd/hvc1/dvvC"), name)
            XCTAssertNil(tree.find("moov/trak/mdia/minf/stbl/stsd/hvc1/dvcC"), name)
            let rec = MKVDolbyVisionMapping(type: 0x64767643, record: dvvC.payload)
            XCTAssertEqual([rec.profile, rec.blCompatibilityID], [8, 1], name)
            XCTAssertEqual([rec.rpuPresent, rec.elPresent, rec.blPresent], [true, false, true], name)

            let (samples, _) = try await allSamples(s, count: info.segmentCount)
            let reference = accessUnits(annexBNALs(try DoviMedia.bytes("ref81_" + name + ".hevc")))
            XCTAssertEqual(samples.count, reference.count, name)
            var differ: [Int] = []
            for (k, smp) in samples.enumerated() where k < reference.count {
                let nals = try splitLengthPrefixed(smp, lengthSize: 4)
                XCTAssertFalse(nals.contains(where: DolbyVisionNAL.isEnhancementLayer), "\(name) sample \(k)")
                if pictureNALs(nals) != pictureNALs(reference[k]) { differ.append(k) }
            }
            XCTAssertEqual(differ, [], "\(name): samples whose slices or RPU differ from the reference tool")
        }
    }

    func testSeekingInAnyOrderGivesTheSameBytesAndNoExtraReads() async throws {
        let (a, readerA) = try session("p7_fel", converter: converter)
        let n = try await a.prepare().segmentCount
        XCTAssertGreaterThan(n, 2)
        let sequential = try await allSamples(a, count: n).segments
        let (b, _) = try session("p7_fel", converter: DolbyVisionProfile7Converter.native())
        _ = try await b.prepare()
        let shuffled = try await allSamples(b, count: n, order: Array((0..<n).reversed())).segments
        for k in 0..<n { XCTAssertEqual(sequential[k], shuffled[k], "segment \(k) differs when fetched out of order") }
        // The conversion works on the bytes already read for the remux: the same bytes are read with and without it.
        let (c, readerC) = try session("p7_fel", converter: nil)
        let infoC = try await c.prepare()
        XCTAssertFalse(infoC.dolbyVisionConverted)
        _ = try await allSamples(c, count: n)
        XCTAssertEqual(readerA.bytesRead, readerC.bytesRead, "conversion must not add reads")
    }

    func testFileThatSwitchesFromProfile7To81() async throws {
        let (s, _) = try session("p7_switch", converter: converter)
        let info = try await s.prepare()
        // The muxer wrote a profile 8 record (dvvC) for this file although it starts with profile 7: the stream wins.
        XCTAssertTrue(info.dolbyVisionConverted)
        XCTAssertEqual(info.dolbyVisionSourceProfile, 7)
        XCTAssertEqual(info.dolbyVisionOutputProfile, 8)
        let (samples, _) = try await allSamples(s, count: info.segmentCount)
        let reference = accessUnits(annexBNALs(try DoviMedia.bytes("ref81_p7_switch.hevc")))
        XCTAssertEqual(samples.count, 96)
        for (k, smp) in samples.enumerated() where k < reference.count {
            let nals = try splitLengthPrefixed(smp, lengthSize: 4)
            XCTAssertEqual(pictureNALs(nals), pictureNALs(reference[k]), "sample \(k)")
            XCTAssertEqual(converter.inspect(sample: smp, lengthSize: 4)?.profile, 8, "sample \(k) RPU is profile 8 after conversion")
        }
    }

    func testProfile81FileIsLeftByteForByte() async throws {
        let (s, _) = try session("p81", converter: converter)
        let info = try await s.prepare()
        XCTAssertFalse(info.dolbyVisionConverted); XCTAssertEqual(info.dolbyVisionSourceProfile, 8)
        let (plain, _) = try session("p81", converter: nil)
        _ = try await plain.prepare()
        let x = try await allSamples(s, count: info.segmentCount).samples
        let y = try await allSamples(plain, count: info.segmentCount).samples
        XCTAssertEqual(x, y, "a profile 8.1 file without enhancement layer is not touched")
        XCTAssertEqual(converter.stats.convertedAccessUnits, 0)
    }

    /// Independent check: ffprobe (LGPL build) reads the remuxed fMP4 and reports the configuration record and per-frame RPU fields.
    func testFFprobeReadsProfile81ConfigurationAndRPU() async throws {
        let probe = ProcessInfo.processInfo.environment["VP_FFPROBE"] ?? (NSHomeDirectory() + "/vp-remux-spike/tools/lgpl/bin/ffprobe")
        guard FileManager.default.isExecutableFile(atPath: probe) else { throw XCTSkip("ffprobe not found at \(probe)") }
        for name in ["p7_fel", "p7_mel"] {
            let (s, _) = try session(name, converter: converter)
            let info = try await s.prepare()
            var file = flattenBody(try await s.resource(path: "init_video.mp4"))
            let segs = try await allSamples(s, count: info.segmentCount).segments
            for k in 0..<info.segmentCount { file += segs[k] ?? [] }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vp-dovi-\(name)-\(UUID().uuidString).mp4")
            try Data(file).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let streams = try runJSON(probe, ["-v", "error", "-show_streams", "-select_streams", "v:0", "-of", "json", url.path])
            let stream = try XCTUnwrap((streams["streams"] as? [[String: Any]])?.first, name)
            let side = (stream["side_data_list"] as? [[String: Any]]) ?? []
            let dovi = try XCTUnwrap(side.first { ($0["side_data_type"] as? String)?.contains("DOVI") == true }, "\(name): \(side)")
            XCTAssertEqual(dovi["dv_profile"] as? Int, 8, name)
            XCTAssertEqual(dovi["el_present_flag"] as? Int, 0, name)
            XCTAssertEqual(dovi["bl_present_flag"] as? Int, 1, name)
            XCTAssertEqual(dovi["rpu_present_flag"] as? Int, 1, name)
            XCTAssertEqual(dovi["dv_bl_signal_compatibility_id"] as? Int, 1, name)

            let frames = try runJSON(probe, ["-v", "error", "-select_streams", "v:0", "-read_intervals", "%+#4", "-show_frames", "-of", "json", url.path])
            let list = try XCTUnwrap(frames["frames"] as? [[String: Any]], name)
            XCTAssertFalse(list.isEmpty, name)
            for f in list {
                let sd = (f["side_data_list"] as? [[String: Any]]) ?? []
                let meta = try XCTUnwrap(sd.first { $0["disable_residual_flag"] != nil }, "\(name): no parsed RPU side data: \(sd)")
                XCTAssertEqual(meta["disable_residual_flag"] as? Int, 1, "\(name): profile 8.1 RPU has no residual")
                XCTAssertEqual(meta["el_spatial_resampling_filter_flag"] as? Int, 0, name)
            }
        }
    }

    func runJSON(_ tool: String, _ args: [String]) throws -> [String: Any] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DolbyVisionRPUError("ffprobe failed: " + String(decoding: errData, as: UTF8.self)) }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
