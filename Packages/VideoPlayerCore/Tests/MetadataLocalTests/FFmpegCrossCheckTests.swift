import XCTest
import Foundation
import VideoPlayerCore
@testable import MetadataLocal

#if os(Linux) || os(macOS)
/// Optional: builds a real Matroska file with an ffmpeg binary and checks the reader against what ffmpeg was told to write.
/// The binary is looked up in `$VP_FFMPEG`, then `~/video-player-test-servers/ffmpeg/ffmpeg`. When neither exists the
/// test is SKIPPED (and reported as skipped). Nothing else in the suite depends on it.
final class FFmpegCrossCheckTests: XCTestCase {
    private func ffmpegPath() -> String? {
        let env = ProcessInfo.processInfo.environment
        let home = env["VP_TEST_HOME"] ?? (NSHomeDirectory() + "/video-player-test-servers")
        var candidates = [home + "/ffmpeg/ffmpeg", home + "/ffmpeg/bin/ffmpeg"]
        if let explicit = env["VP_FFMPEG"], !explicit.isEmpty { candidates.insert(explicit, at: 0) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testReaderAgreesWithAFileWrittenByFFmpeg() async throws {
        guard let ffmpeg = ffmpegPath() else {
            throw XCTSkip("No ffmpeg binary: set VP_FFMPEG or put one at ~/video-player-test-servers/ffmpeg/ffmpeg. The reader is then only tested against files from the test-side writer.")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vp-ffmpeg-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let meta = dir.appendingPathComponent("meta.txt")
        let out = dir.appendingPathComponent("out.mkv")
        let metadata = """
        ;FFMETADATA1
        title=FFmpeg Cross Check
        [CHAPTER]
        TIMEBASE=1/1000
        START=0
        END=2000
        title=First
        [CHAPTER]
        TIMEBASE=1/1000
        START=2000
        END=4000
        title=Second
        """
        try metadata.write(to: meta, atomically: true, encoding: .utf8)
        let result = try run(ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=4:size=320x240:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=4:sample_rate=48000",
            "-i", meta.path,
            "-map", "0:v", "-map", "1:a", "-map_metadata", "2", "-map_chapters", "2",
            "-c:v", "mpeg4", "-c:a", "ac3", "-metadata:s:a:0", "language=eng", "-f", "matroska", out.path,
        ])
        guard result.status == 0 else {
            throw XCTSkip("ffmpeg at \(ffmpeg) could not build the sample (exit \(result.status)): \(result.output.prefix(300))")
        }
        let bytes = [UInt8](try Data(contentsOf: out))
        let log = ReadLog()
        let m = try await MatroskaReader().read(using: memoryReader(bytes, log: log))
        XCTAssertEqual(m.docType, "matroska")
        XCTAssertEqual(try XCTUnwrap(m.durationSeconds), 4.0, accuracy: 0.2)
        XCTAssertEqual(m.info?.title, "FFmpeg Cross Check")
        XCTAssertTrue(m.info?.writingApp?.contains("Lavf") == true, "writing app: \(String(describing: m.info?.writingApp))")
        XCTAssertEqual(m.videoTracks.count, 1)
        XCTAssertEqual(m.audioTracks.count, 1)
        let v = try XCTUnwrap(m.videoTracks.first)
        XCTAssertEqual(v.pixelWidth, 320)
        XCTAssertEqual(v.pixelHeight, 240)
        XCTAssertEqual(try XCTUnwrap(v.frameRate), 25, accuracy: 0.01)
        let a = try XCTUnwrap(m.audioTracks.first)
        XCTAssertEqual(a.audioCodec, .ac3)
        XCTAssertEqual(a.samplingFrequency, 48000)
        XCTAssertEqual(a.language, "eng")
        let chapters = try XCTUnwrap(m.preferredEdition).chapters
        XCTAssertEqual(chapters.map { $0.title() }, ["First", "Second"])
        XCTAssertEqual(chapters.map(\.startSeconds), [0, 2])
        XCTAssertEqual(try XCTUnwrap(chapters.first?.endSeconds), 2, accuracy: 0.001)
        // The same file read through a tiny window gives the same content.
        let small = try await MatroskaReader(headBytes: 64).read(using: memoryReader(bytes))
        assertSameContent(small, m)
        XCTAssertEqual(m.warnings, [], "Warnings on a file ffmpeg wrote: \(m.warnings)")
    }
}
#endif
