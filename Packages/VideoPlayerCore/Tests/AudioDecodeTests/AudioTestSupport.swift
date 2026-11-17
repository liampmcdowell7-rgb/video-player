import XCTest
import Foundation
import RemuxEngine
import AudioDecode

// Test fixtures for the audio pipeline: media made by scripts/test-audio.sh (VP_AUDIO_MEDIA), the reference decoder and
// probe from the spike's LGPL tools (VP_AUDIO_TOOLS). A missing file or tool is an XCTSkip: reported as skipped, never passed.

enum AudioMedia {
    static var dir: String { ProcessInfo.processInfo.environment["VP_AUDIO_MEDIA"] ?? (NSHomeDirectory() + "/video-player-test-servers/audio-media") }
    static var tools: String { ProcessInfo.processInfo.environment["VP_AUDIO_TOOLS"] ?? (NSHomeDirectory() + "/vp-remux-spike/tools/lgpl8.1/bin") }

    static func path(_ name: String) throws -> String {
        let p = dir + "/" + name
        guard FileManager.default.fileExists(atPath: p) else { throw XCTSkip("test media \(p) is missing: run bash scripts/test-audio.sh media") }
        return p
    }
    static func tool(_ name: String) throws -> String {
        let p = tools + "/" + name
        guard FileManager.default.isExecutableFile(atPath: p) else { throw XCTSkip("reference tool \(p) is missing (scripts/spikes/remux/00-setup.sh)") }
        return p
    }
}

struct ToolResult { var status: Int32; var out: String; var err: String }

/// Runs a tool with stdout and stderr in files (binary output goes to a file named in the arguments).
func runTool(_ exe: String, _ args: [String]) throws -> ToolResult {
    let dir = NSTemporaryDirectory()
    let outPath = dir + "/ad-out-\(UUID().uuidString)", errPath = dir + "/ad-err-\(UUID().uuidString)"
    FileManager.default.createFile(atPath: outPath, contents: nil); FileManager.default.createFile(atPath: errPath, contents: nil)
    defer { try? FileManager.default.removeItem(atPath: outPath); try? FileManager.default.removeItem(atPath: errPath) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    p.standardOutput = FileHandle(forWritingAtPath: outPath)
    p.standardError = FileHandle(forWritingAtPath: errPath)
    try p.run()
    p.waitUntilExit()
    return ToolResult(status: p.terminationStatus,
                      out: String(decoding: FileManager.default.contents(atPath: outPath) ?? Data(), as: UTF8.self),
                      err: String(decoding: FileManager.default.contents(atPath: errPath) ?? Data(), as: UTF8.self))
}

func tempDir() -> String {
    let d = NSTemporaryDirectory() + "/ad-test-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

func flattenBody(_ r: LoopbackResponse) -> [UInt8] { r.body.chunks.flatMap { $0 } }

struct PCM {
    var samples: [Int32]    // interleaved, 32-bit full scale
    var channels: Int
    var frames: Int { channels > 0 ? samples.count / channels : 0 }
}

/// Decodes the first audio stream of a file with the reference decoder to 32-bit PCM (`bitexact`: integer DTS core).
func referenceDecode(_ path: String, bitexact: Bool = true) throws -> PCM {
    let ff = try AudioMedia.tool("ffmpeg")
    let raw = tempDir() + "/ref.s32"
    var args = ["-hide_banner", "-v", "error", "-y"]
    if bitexact { args += ["-flags", "+bitexact"] }
    args += ["-i", path, "-map", "0:a:0", "-c:a", "pcm_s32le", "-f", "s32le", raw]
    let r = try runTool(ff, args)
    guard r.status == 0 else { throw XCTSkip("reference decode failed for \(path): \(r.err)") }
    let ch = try probe(path)["channels"].flatMap { Int($0) } ?? 0
    let data = FileManager.default.contents(atPath: raw) ?? Data()
    try? FileManager.default.removeItem(atPath: (raw as NSString).deletingLastPathComponent)
    var s = [Int32](repeating: 0, count: data.count / 4)
    _ = s.withUnsafeMutableBytes { data.copyBytes(to: $0) }
    return PCM(samples: s, channels: ch)
}

/// key=value of the first audio stream (ffprobe), plus "stderr" when the probe complained.
func probe(_ path: String) throws -> [String: String] {
    let fp = try AudioMedia.tool("ffprobe")
    let r = try runTool(fp, ["-v", "error", "-select_streams", "a:0", "-show_entries",
                             "stream=codec_name,profile,channels,channel_layout,sample_rate,bits_per_raw_sample,sample_fmt",
                             "-of", "default=nw=1", path])
    var out: [String: String] = [:]
    for line in r.out.split(separator: "\n") {
        let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
        if kv.count == 2 { out[kv[0]] = kv[1] }
    }
    let err = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
    if !err.isEmpty { out["stderr"] = err }
    return out
}

struct Comparison: CustomStringConvertible {
    var offset: Int           // output frame i corresponds to reference frame i + offset
    var compared: Int         // frames compared
    var mismatches: Int       // samples that differ
    var maxDiff: Int64
    var refFrames: Int
    var outFrames: Int
    var exact: Bool { mismatches == 0 && compared > 0 }
    var description: String {
        "offset \(offset), compared \(compared) frames (ref \(refFrames), out \(outFrames)), mismatching samples \(mismatches), max diff \(maxDiff) (2^-31 FS)"
    }
}

/// Aligns `out` against `ref` (offset 0 first; otherwise the offset with the smallest difference on a probe window from
/// the middle) and compares every overlapping sample.
func compare(ref: PCM, out: PCM, maxOffset: Int = 8192) -> Comparison {
    precondition(ref.channels == out.channels)
    let ch = ref.channels
    func diffAt(_ o: Int, from: Int, count: Int) -> Int64 {
        var sum: Int64 = 0
        var i = from
        while i < from + count {
            let r = i + o
            if r < 0 || r >= ref.frames || i >= out.frames { return Int64.max }
            for c in 0..<ch { sum += abs(Int64(out.samples[i * ch + c]) - Int64(ref.samples[r * ch + c])) }
            i += 1
        }
        return sum
    }
    let probeStart = max(0, out.frames / 2 - 128), probeLen = min(256, max(0, out.frames - probeStart))
    var best = 0
    if diffAt(0, from: probeStart, count: probeLen) != 0 {
        var bestScore = Int64.max
        for o in -maxOffset...maxOffset {
            let s = diffAt(o, from: probeStart, count: probeLen)
            if s < bestScore { bestScore = s; best = o; if s == 0 { break } }
        }
    }
    var mismatches = 0, maxDiff: Int64 = 0, compared = 0
    for i in 0..<out.frames {
        let r = i + best
        if r < 0 || r >= ref.frames { continue }
        compared += 1
        for c in 0..<ch {
            let d = abs(Int64(out.samples[i * ch + c]) - Int64(ref.samples[r * ch + c]))
            if d != 0 { mismatches += 1; maxDiff = max(maxDiff, d) }
        }
    }
    return Comparison(offset: best, compared: compared, mismatches: mismatches, maxDiff: maxDiff, refFrames: ref.frames, outFrames: out.frames)
}

struct RemuxedAudio {
    var info: RemuxMediaInfo
    var rendition: AudioRenditionInfo
    var mp4Path: String
    var segments: [[UInt8]]
    var initSegment: [UInt8]
    var diagnostics: AudioTranscodeDiagnostics?
    var seconds: Double
}

/// Runs a Matroska file through the engine with the decoding transcoder and writes the audio rendition (init segment and
/// every media segment, in playlist order) to an fMP4 file. `order` changes the order the segments are requested in.
func remuxAudio(_ name: String, settings: DecodedAudioSettings = DecodedAudioSettings(), order: [Int]? = nil,
                segmentSeconds: Double = 2) async throws -> RemuxedAudio {
    let path = try AudioMedia.path(name)
    guard let data = FileManager.default.contents(atPath: path) else { throw XCTSkip("cannot read \(path)") }
    var o = RemuxOptions()
    o.targetSegmentSeconds = segmentSeconds
    o.audioTranscoder = DecodedAudioTranscoder(settings: settings)
    let s = MatroskaRemuxSession(reader: DataReader(data), options: o)
    let t0 = Date()
    let info = try await s.prepare()
    guard let a = info.audio.first else {
        XCTFail("\(name): no audio rendition; skipped: \(info.skippedAudio)")
        throw XCTSkip("no rendition")
    }
    let initBytes = flattenBody(try await s.resource(path: "init_audio_\(a.trackNumber).mp4"))
    var segs = [[UInt8]](repeating: [], count: info.segmentCount)
    for k in order ?? Array(0..<info.segmentCount) {
        segs[k] = flattenBody(try await s.resource(path: "seg_audio_\(a.trackNumber)_\(k).m4s"))
    }
    let seconds = Date().timeIntervalSince(t0)
    let out = tempDir() + "/out.mp4"
    try Data(initBytes + segs.flatMap { $0 }).write(to: URL(fileURLWithPath: out))
    let diag = await s.audioDiagnostics()[a.trackNumber]
    return RemuxedAudio(info: info, rendition: a, mp4Path: out, segments: segs, initSegment: initBytes, diagnostics: diag, seconds: seconds)
}
