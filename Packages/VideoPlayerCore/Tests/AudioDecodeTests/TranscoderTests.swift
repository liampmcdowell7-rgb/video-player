import XCTest
import Foundation
@testable import RemuxEngine
@testable import AudioDecode

// The transcoder on its own, fed with frames cut from raw streams: damaged data, TrueHD with Dolby Digital frames inside
// it (built here: Matroska files from mkvmerge keep the two as separate tracks), and the CPU cost.

final class TranscoderTests: XCTestCase {

    private let auNs: Int64 = 833_333    // one TrueHD access unit at 48 kHz (40 samples)

    private func trueHDUnits() throws -> [ArraySlice<UInt8>] {
        let raw = try XCTUnwrap(FileManager.default.contents(atPath: try AudioMedia.path("raw_truehd_51.thd")))
        let units = TrueHDCoreSplitter.split([UInt8](raw)[...]).trueHD
        XCTAssertGreaterThan(units.count, 1000)
        return units
    }

    private func ac3Frames() throws -> [ArraySlice<UInt8>] {
        let raw = [UInt8](try XCTUnwrap(FileManager.default.contents(atPath: try AudioMedia.path("raw_ac3_51.ac3"))))
        var out: [ArraySlice<UInt8>] = []
        var p = 0
        let all = raw[...]
        while let n = TrueHDCoreSplitter.ac3FrameLength(all, at: p), p + n <= raw.count { out.append(all[p..<(p + n)]); p += n }
        XCTAssertGreaterThan(out.count, 100)
        return out
    }

    /// 24 access units (20 ms) per Matroska block.
    private func blocks(_ units: [ArraySlice<UInt8>], per: Int = 24) -> [MKVFrame] {
        stride(from: 0, to: units.count, by: per).map { i in
            let data = units[i..<min(units.count, i + per)].flatMap { $0 }
            return MKVFrame(track: 1, timeNs: Int64(i) * auNs, bytes: data[...])
        }
    }

    private func pcmOf(frames: [MKVFrame], config: AudioTrackConfig) throws -> PCM {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/out.flac"
        let file = FLACFraming.file(streamInfo: Array(config.specific.dropFirst(4)), frames: frames.map { Array($0.data) })
        try Data(file).write(to: URL(fileURLWithPath: path))
        return try referenceDecode(path)
    }

    func testDamagedFramesBecomeCountedSilenceAndPlaybackGoesOn() async throws {
        let units = try trueHDUnits()
        var frames = blocks(units)
        // Damage three blocks in the middle (bytes flipped inside every access unit), and cut one block short.
        for i in [100, 101, 160] {
            var d = Array(frames[i].data)
            for j in stride(from: 6, to: d.count, by: 37) { d[j] ^= 0x5A }
            frames[i].data = d[...]
        }
        frames[200].data = frames[200].data.prefix(frames[200].data.count / 3)
        let track = MKVTrackFixture.track(codecID: "A_TRUEHD")
        let tc = DecodedAudioTranscoder()
        let cfg = try await tc.outputConfig(for: track, firstFrames: Array(frames.prefix(20)))
        let out = try await tc.transcode(frames: frames, track: track, config: cfg)
        let d0 = await tc.diagnostics(for: 1); let d = try XCTUnwrap(d0)
        let pcm = try pcmOf(frames: out, config: cfg)
        let ref = try referenceDecode(try AudioMedia.path("raw_truehd_51.thd"))
        print("AUDIO-RESULT damaged TrueHD: concealed \(d.concealedFrames), silent samples \(d.silentSamples), errors \(d.errors.prefix(2)), out \(pcm.frames) frames, source \(ref.frames)")
        XCTAssertGreaterThan(d.concealedFrames, 0)
        XCTAssertGreaterThan(d.silentSamples, 0)
        XCTAssertFalse(d.errors.isEmpty)
        XCTAssertEqual(Double(pcm.frames), Double(units.count * 40), accuracy: 4096, "the damage did not shorten or stretch the track")
        // Before the damage the output is still the exact signal.
        let before = PCM(samples: Array(pcm.samples.prefix(90 * 24 * 40 * 6)), channels: 6)
        let c = compare(ref: ref, out: before, maxOffset: 0)
        XCTAssertTrue(c.exact, "\(c)")
        // After the damage it recovers: the last second is exact again.
        let tailStart = pcm.frames - 48000
        let tailOut = PCM(samples: Array(pcm.samples[(tailStart * 6)...]), channels: 6)
        let tailRef = PCM(samples: Array(ref.samples[(tailStart * 6)..<min(ref.samples.count, (tailStart + 48000) * 6)]), channels: 6)
        XCTAssertTrue(compare(ref: tailRef, out: tailOut, maxOffset: 0).exact, "recovered after the damaged blocks")
    }

    private func interleaved(units: [ArraySlice<UInt8>], ac3: [ArraySlice<UInt8>]) -> [MKVFrame] {
        // One block per Dolby Digital frame (1536 samples, 32 ms): the AC-3 frame, then the TrueHD units of the same 32 ms.
        var out: [MKVFrame] = []
        var u = 0
        for (i, a) in ac3.enumerated() {
            let endNs = Int64(i + 1) * 32_000_000
            var data = Array(a)
            while u < units.count, Int64(u) * auNs < endNs { data += units[u]; u += 1 }
            out.append(MKVFrame(track: 1, timeNs: Int64(i) * 32_000_000, bytes: data[...]))
            if u >= units.count { break }
        }
        return out
    }

    func testTrueHDWithDolbyDigitalInsideIsFullyDecodedByDefault() async throws {
        let units = try trueHDUnits(), ac3 = try ac3Frames()
        let frames = interleaved(units: units, ac3: ac3)
        let track = MKVTrackFixture.track(codecID: "A_TRUEHD")
        let tc = DecodedAudioTranscoder()
        let cfg = try await tc.outputConfig(for: track, firstFrames: Array(frames.prefix(10)))
        XCTAssertEqual(cfg.codec, .flac)
        let s0 = await tc.sourceInfo(for: track); let src = try XCTUnwrap(s0)
        XCTAssertTrue(src.hasEmbeddedCore)
        XCTAssertFalse(src.usesEmbeddedCore)
        XCTAssertTrue(src.isLossless)
        let out = try await tc.transcode(frames: frames, track: track, config: cfg)
        let pcm = try pcmOf(frames: out, config: cfg)
        let ref = try referenceDecode(try AudioMedia.path("raw_truehd_51.thd"))
        let c = compare(ref: ref, out: pcm, maxOffset: 0)
        print("AUDIO-RESULT TrueHD with Dolby Digital inside, default (full decode): \(c)")
        XCTAssertTrue(c.exact, "\(c)")
    }

    func testTheCompatibilitySettingPassesTheDolbyDigitalFramesThroughUnchanged() async throws {
        let units = try trueHDUnits(), ac3 = try ac3Frames()
        let frames = interleaved(units: units, ac3: ac3)
        let track = MKVTrackFixture.track(codecID: "A_TRUEHD")
        let tc = DecodedAudioTranscoder(settings: DecodedAudioSettings(trueHDUseEmbeddedCore: true))
        let cfg = try await tc.outputConfig(for: track, firstFrames: Array(frames.prefix(10)))
        XCTAssertEqual(cfg.codec, .ac3)
        XCTAssertEqual(cfg.codecString, "ac-3")
        let s0 = await tc.sourceInfo(for: track); let src = try XCTUnwrap(s0)
        XCTAssertTrue(src.usesEmbeddedCore)
        XCTAssertFalse(src.isLossless)
        let out = try await tc.transcode(frames: frames, track: track, config: cfg)
        XCTAssertEqual(out.map { Array($0.data) }, ac3.prefix(frames.count).map { Array($0) })
        // Without Dolby Digital frames inside, the setting changes nothing: full decode.
        let plain = DecodedAudioTranscoder(settings: DecodedAudioSettings(trueHDUseEmbeddedCore: true))
        let plainCfg = try await plain.outputConfig(for: track, firstFrames: Array(blocks(units).prefix(10)))
        XCTAssertEqual(plainCfg.codec, .flac)
    }

    func testAMaximumSampleRateResamplesAndSaysTheOutputIsNoLongerLossless() async throws {
        let units = try trueHDUnits()
        let track = MKVTrackFixture.track(codecID: "A_TRUEHD")
        // The source is 48 kHz: a 44.1 kHz ceiling forces a conversion.
        let tc = DecodedAudioTranscoder(settings: DecodedAudioSettings(maxSampleRate: 44100))
        let frames = blocks(units)
        let cfg = try await tc.outputConfig(for: track, firstFrames: Array(frames.prefix(10)))
        XCTAssertEqual(cfg.sampleRate, 44100)
        let s0 = await tc.sourceInfo(for: track); let src = try XCTUnwrap(s0)
        XCTAssertFalse(src.isLossless)
        let out = try await tc.transcode(frames: frames, track: track, config: cfg)
        let pcm = try pcmOf(frames: out, config: cfg)
        XCTAssertEqual(Double(pcm.frames) / 44100, Double(units.count * 40) / 48000, accuracy: 0.1)
    }

    // MARK: CPU

    /// Time spent per second of audio, decode plus FLAC encode, on this machine (the device is NOT measured; the
    /// estimate for it is in docs/AUDIO_PIPELINE.md). Prints for the report; fails only when slower than real time here.
    func testCPUCostOfLosslessDecodeAndEncode() async throws {
        for name in ["dtshd_ma_71_24_48k.mkv", "dtshd_ma_71_24_96k.mkv", "truehd_atmos_fate.mkv", "dtshd_ma_51_16_192k.mkv", "opus_8ch.mkv"] {
            let r = try await remuxAudio(name)
            let d = try XCTUnwrap(r.diagnostics)
            print("AUDIO-CPU \(name): \(String(format: "%.4f", d.realTimeLoad)) s per s of audio (decode+encode, level 5), "
                  + "\(String(format: "%.2f", d.producedSeconds)) s produced; whole engine \(String(format: "%.3f", r.seconds)) s")
            XCTAssertLessThan(d.realTimeLoad, 1.0, name)
        }
        for level in [0, 2, 5, 8] {
            let r = try await remuxAudio("dtshd_ma_71_24_96k.mkv", settings: DecodedAudioSettings(flacCompression: level))
            let d = try XCTUnwrap(r.diagnostics)
            let bytes = r.segments.reduce(0) { $0 + $1.count }
            print("AUDIO-CPU flac level \(level), 7.1 24-bit 96 kHz: \(String(format: "%.4f", d.realTimeLoad)) s/s, "
                  + "\(Int(Double(bytes) * 8 / max(0.001, d.producedSeconds) / 1000)) kb/s")
        }
    }
}
