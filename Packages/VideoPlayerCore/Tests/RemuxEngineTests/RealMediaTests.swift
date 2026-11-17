import XCTest
import Foundation
@testable import RemuxEngine
import VideoPlayerCore

// The whole session over MKV files made by a real encoder and muxer (x265 / x264 + mkvmerge, scripts/remux-generate.sh),
// checked by our own box checker and by an independent reader (an LGPL ffprobe). Skipped, and reported as skipped, when the
// media or the tool was not generated (never counted as passed).

final class RealMediaTests: XCTestCase {

    private func remuxToFile(_ name: String, audioRendition: Bool) async throws -> (RemuxMediaInfo, String, Int) {
        let data = try TestMedia.load(name)
        var o = RemuxOptions(); o.targetSegmentSeconds = 4
        let s = MatroskaRemuxSession(reader: DataReader(data), options: o)
        let info = try await s.prepare()
        XCTAssertGreaterThan(info.segmentCount, 1)
        let initBytes = flatten(try await s.resource(path: "init_video.mp4"))
        XCTAssertEqual(FMP4Checker.check(initSegment: initBytes, expectedEntry: info.sampleEntry), [])
        var all = initBytes
        var frames = 0
        for k in 0..<info.segmentCount {
            let seg = flatten(try await s.resource(path: "seg_video_\(k).m4s"))
            XCTAssertEqual(FMP4Checker.check(fragment: seg), [], "video segment \(k)")
            let frag = try ParsedFragment.parse(seg)
            frames += frag.samples.count
            all += seg
        }
        if audioRendition, let a = info.audio.first {
            let ai = flatten(try await s.resource(path: "init_audio_\(a.trackNumber).mp4"))
            XCTAssertFalse(ai.isEmpty)
            for k in 0..<info.segmentCount {
                let seg = flatten(try await s.resource(path: "seg_audio_\(a.trackNumber)_\(k).m4s"))
                XCTAssertEqual(FMP4Checker.check(fragment: seg), [], "audio segment \(k)")
            }
        }
        let dir = makeTempDir()
        let path = dir + "/out.mp4"
        try Data(all).write(to: URL(fileURLWithPath: path))
        return (info, path, frames)
    }

    func testHDR10FileWithBFramesAndOpenGOPsRemuxesToFilesAnIndependentReaderAccepts() async throws {
        let probe = try TestMedia.tool("ffprobe")
        let (info, path, frames) = try await remuxToFile("engine_hdr10.mkv", audioRendition: true)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        XCTAssertEqual(info.sampleEntry, "hvc1")
        XCTAssertEqual(info.videoRange, .pq)
        XCTAssertEqual(info.height, 720)
        XCTAssertEqual(frames, 480, "20 s at 24 fps, every frame exactly once")
        let r = try runProcess(probe, ["-v", "error", "-count_packets", "-show_entries", "stream=codec_name,width,height,nb_read_packets", "-of", "csv=p=0", path])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(r.err.trimmingCharacters(in: .whitespacesAndNewlines), "", "ffprobe reported problems in our output")
        XCTAssertEqual(r.out.trimmingCharacters(in: .whitespacesAndNewlines), "hevc,1280,720,480")
    }

    func testH264FileRemuxesToFilesAnIndependentReaderAccepts() async throws {
        let probe = try TestMedia.tool("ffprobe")
        let (info, path, frames) = try await remuxToFile("engine_h264.mkv", audioRendition: true)
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        XCTAssertEqual(info.sampleEntry, "avc1")
        XCTAssertEqual(frames, 240, "10 s at 24 fps, every frame exactly once")
        let r = try runProcess(probe, ["-v", "error", "-count_packets", "-show_entries", "stream=codec_name,nb_read_packets", "-of", "csv=p=0", path])
        XCTAssertEqual(r.status, 0, r.err)
        XCTAssertEqual(r.err.trimmingCharacters(in: .whitespacesAndNewlines), "")
        XCTAssertEqual(r.out.trimmingCharacters(in: .whitespacesAndNewlines), "h264,240")
    }

    func testFileWithoutCuesUsesTheClusterScanOnRealMedia() async throws {
        let data = try TestMedia.load("engine_nocues.mkv")
        var o = RemuxOptions(); o.targetSegmentSeconds = 4
        let s = MatroskaRemuxSession(reader: DataReader(data), options: o)
        let info = try await s.prepare()
        XCTAssertTrue(info.usedClusterScan)
        XCTAssertGreaterThan(info.segmentCount, 1)
        let seg = flatten(try await s.resource(path: "seg_video_1.m4s"))
        XCTAssertEqual(FMP4Checker.check(fragment: seg), [])
    }
}
