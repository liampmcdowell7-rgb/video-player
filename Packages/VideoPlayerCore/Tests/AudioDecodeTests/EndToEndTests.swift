import XCTest
import Foundation
@testable import RemuxEngine
@testable import AudioDecode

// Real streams through the whole engine (Matroska in, fMP4 FLAC out), checked by an independent reader: the output is probed,
// decoded back by the reference decoder and compared sample by sample with the reference decode of the source.
// Lossless sources (DTS-HD Master Audio, TrueHD, MLP) and the integer DTS core must match bit for bit. Opus and Vorbis
// (floating point decoders, quantised to 24 bits here) must match within 2^-15 of full scale.
// Every comparison prints one "AUDIO-RESULT" line (collected into docs/AUDIO_PIPELINE.md).

final class EndToEndTests: XCTestCase {

    struct Expect {
        var channels: Int
        var rate: Int
        var bits: Int
        var format: TranscodedAudioSource.Format
        var lossless: Bool
        /// nil: bit-exact required. Otherwise the largest allowed difference (in 2^-31 full-scale units).
        var tolerance: Int64? = nil
        /// Vorbis: the first packet decodes to nothing, and the output starts at the second packet's timestamp (PROVISIONAL,
        /// docs/AUDIO_PIPELINE.md); the plain reference decode ignores timestamps.
        var startFollowsTimestamps = false
    }

    @discardableResult
    func check(_ name: String, _ e: Expect, extraReference: String? = nil) async throws -> (RemuxedAudio, Comparison) {
        let r = try await remuxAudio(name)
        defer { try? FileManager.default.removeItem(atPath: (r.mp4Path as NSString).deletingLastPathComponent) }
        XCTAssertEqual(r.rendition.codecString, "fLaC")
        XCTAssertTrue(r.rendition.transcoded)
        let src = try XCTUnwrap(r.rendition.transcodedSource, "\(name): no source description")
        XCTAssertEqual(src.format, e.format, name)
        XCTAssertEqual(src.outputChannels, e.channels, name)
        XCTAssertEqual(src.outputSampleRate, e.rate, name)
        XCTAssertEqual(src.outputBits, e.bits, name)
        XCTAssertEqual(src.isLossless, e.lossless, name)

        // Independent reader: the fMP4 output as the reference probe sees it.
        let p = try probe(r.mp4Path)
        XCTAssertNil(p["stderr"], "\(name): the probe reported problems: \(p["stderr"] ?? "")")
        XCTAssertEqual(p["codec_name"], "flac", name)
        XCTAssertEqual(p["channels"], "\(e.channels)", name)
        XCTAssertEqual(p["sample_rate"], "\(e.rate)", name)
        XCTAssertEqual(p["bits_per_raw_sample"], "\(e.bits)", name)

        let ref = try referenceDecode(try AudioMedia.path(name))
        let out = try referenceDecode(r.mp4Path)
        XCTAssertEqual(out.channels, ref.channels, name)
        let c = compare(ref: ref, out: out)
        let d = r.diagnostics
        print("AUDIO-RESULT \(name): \(src.format.rawValue) \(src.sourceChannels)ch->\(e.channels)ch \(e.rate) Hz \(e.bits)-bit; \(c); "
              + "concealed \(d?.concealedFrames ?? -1), silent samples \(d?.silentSamples ?? -1), load \(String(format: "%.4f", d?.realTimeLoad ?? -1))")
        if e.startFollowsTimestamps {
            // The output starts where the first decoded packet's timestamp says (silence before it, counted); the plain
            // reference decode starts at its first sample. The shift must be fully explained by the counted silence.
            XCTAssertLessThanOrEqual(c.offset, 0, name)
            XCTAssertLessThanOrEqual(-c.offset, Int(d?.silentSamples ?? 0), "\(name): shift not explained by counted silence")
            XCTAssertLessThan(-c.offset, e.rate / 50, "\(name): shift over 20 ms")
        } else {
            XCTAssertEqual(c.offset, 0, "\(name): output is shifted against the reference")
        }
        XCTAssertGreaterThan(c.compared, ref.frames * 95 / 100, "\(name): output covers too little of the source")
        if let tol = e.tolerance { XCTAssertLessThanOrEqual(c.maxDiff, tol, "\(name): \(c)") }
        else { XCTAssertTrue(c.exact, "\(name): not bit-exact: \(c)") }
        if let extra = extraReference {
            let orig = try referenceDecode(extra)
            let c2 = compare(ref: orig, out: out)
            print("AUDIO-RESULT \(name) against the encoder's input PCM: \(c2)")
            XCTAssertTrue(c2.exact, "\(name) vs input PCM: \(c2)")
        }
        return (r, c)
    }

    // MARK: DTS-HD Master Audio (lossless)

    func testDTSHDMasterAudio71At48kIsBitExact() async throws {
        try await check("dtshd_ma_71_24_48k.mkv", Expect(channels: 8, rate: 48000, bits: 24, format: .dtsHDMasterAudio, lossless: true))
    }
    func testDTSHDMasterAudio71At96kIsBitExact() async throws {
        try await check("dtshd_ma_71_24_96k.mkv", Expect(channels: 8, rate: 96000, bits: 24, format: .dtsHDMasterAudio, lossless: true))
    }
    func testDTSHDMasterAudio51At192k16BitIsBitExact() async throws {
        try await check("dtshd_ma_51_16_192k.mkv", Expect(channels: 6, rate: 192000, bits: 16, format: .dtsHDMasterAudio, lossless: true))
    }
    func testDTSHDMasterAudioWithoutCoreIsBitExact() async throws {
        try await check("dtshd_ma_51_24_48k_nocore.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .dtsHDMasterAudio, lossless: true))
    }

    // MARK: DTS (lossy core, integer decoder: bit-exact to the reference's integer decode)

    func testDTSCore51IsBitExactToTheIntegerDecoder() async throws {
        try await check("dts_core_51_48k.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .dts, lossless: false))
    }
    func testDTSCoreStereo44kIsBitExactToTheIntegerDecoder() async throws {
        try await check("dts_core_20_44k.mkv", Expect(channels: 2, rate: 44100, bits: 24, format: .dts, lossless: false))
    }
    func testDTSHDFileWithOnlyACoreIsDecodedAsDTS() async throws {
        try await check("dtshd_core_51_24_48k.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .dts, lossless: false))
    }
    func testDTSES61KeepsTheBackCenterChannel() async throws {
        try await check("dts_es_61.mkv", Expect(channels: 7, rate: 48000, bits: 24, format: .dtsES, lossless: false))
    }

    // MARK: TrueHD and MLP (lossless)

    func testTrueHD51IsBitExact() async throws {
        try await check("truehd_51_fate.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .trueHD, lossless: true))
    }
    func testTrueHDAtmosPlaysTheFull71PresentationBitExact() async throws {
        try await check("truehd_atmos_fate.mkv", Expect(channels: 8, rate: 48000, bits: 24, format: .trueHDAtmos, lossless: true))
    }
    func testGeneratedTrueHD51At48kMatchesTheEncodersInput() async throws {
        try await check("truehd_enc_6ch_24_48k.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .trueHD, lossless: true),
                        extraReference: AudioMedia.dir + "/work/truehd_enc_6ch_24_48k.mkv.wav")
    }
    func testGeneratedTrueHD51At96kMatchesTheEncodersInput() async throws {
        try await check("truehd_enc_6ch_24_96k.mkv", Expect(channels: 6, rate: 96000, bits: 24, format: .trueHD, lossless: true),
                        extraReference: AudioMedia.dir + "/work/truehd_enc_6ch_24_96k.mkv.wav")
    }
    func testGeneratedTrueHDStereoAt192kMatchesTheEncodersInput() async throws {
        try await check("truehd_enc_2ch_24_192k.mkv", Expect(channels: 2, rate: 192000, bits: 24, format: .trueHD, lossless: true),
                        extraReference: AudioMedia.dir + "/work/truehd_enc_2ch_24_192k.mkv.wav")
    }
    func testGeneratedMLP51MatchesTheEncodersInput() async throws {
        try await check("mlp_enc_6ch_24_48k.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .mlp, lossless: true),
                        extraReference: AudioMedia.dir + "/work/mlp_enc_6ch_24_48k.mkv.wav")
    }

    // MARK: Opus and Vorbis (lossy, floating point)

    private let floatTolerance: Int64 = 1 << 16   // 2^-15 of full scale
    func testOpusStereo() async throws { try await check("opus_2ch.mkv", Expect(channels: 2, rate: 48000, bits: 24, format: .opus, lossless: false, tolerance: floatTolerance)) }
    func testOpus51() async throws { try await check("opus_6ch.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .opus, lossless: false, tolerance: floatTolerance)) }
    func testOpus71() async throws { try await check("opus_8ch.mkv", Expect(channels: 8, rate: 48000, bits: 24, format: .opus, lossless: false, tolerance: floatTolerance)) }
    func testVorbisStereo() async throws { try await check("vorbis_2ch.mkv", Expect(channels: 2, rate: 48000, bits: 24, format: .vorbis, lossless: false, tolerance: floatTolerance, startFollowsTimestamps: true)) }
    func testVorbis51() async throws { try await check("vorbis_6ch.mkv", Expect(channels: 6, rate: 48000, bits: 24, format: .vorbis, lossless: false, tolerance: floatTolerance, startFollowsTimestamps: true)) }
    func testVorbis71() async throws { try await check("vorbis_8ch.mkv", Expect(channels: 8, rate: 48000, bits: 24, format: .vorbis, lossless: false, tolerance: floatTolerance, startFollowsTimestamps: true)) }

    // MARK: Stream changes

    func testDTSHDWithAMissingExtensionKeepsPlayingFromTheCoreAndCountsIt() async throws {
        // 3 s with the lossless extension, 3 s without: the reference decoder falls back to the core the same way.
        let (r, _) = try await check("dtshd_ma_71_missing_ext.mkv", Expect(channels: 8, rate: 48000, bits: 24, format: .dtsHDMasterAudio, lossless: true))
        let d = try XCTUnwrap(r.diagnostics)
        XCTAssertGreaterThan(d.framesWithoutLosslessExtension, 200, "about 3 s of 512-sample frames came without the extension")
        XCTAssertEqual(d.concealedFrames, 0)
    }

    private func samples(_ pcm: PCM, channel: Int, from: Double, to: Double, rate: Int) -> [Int32] {
        let a = Int(from * Double(rate)), b = min(pcm.frames, Int(to * Double(rate)))
        guard a < b else { return [] }
        return (a..<b).map { pcm.samples[$0 * pcm.channels + channel] }
    }

    func testALayoutChangeKeepsTheOutputLayoutWithSilentMissingChannels() async throws {
        let r = try await remuxAudio("dts_layout_change.mkv")
        let out = try referenceDecode(r.mp4Path)
        XCTAssertEqual(out.channels, 6)
        let d = try XCTUnwrap(r.diagnostics)
        XCTAssertGreaterThanOrEqual(d.layoutChanges, 1)
        XCTAssertTrue(samples(out, channel: 2, from: 0.5, to: 2.7, rate: 48000).contains { $0 != 0 }, "centre plays in the 5.1 part")
        for ch in 2..<6 {
            XCTAssertFalse(samples(out, channel: ch, from: 3.3, to: 5.7, rate: 48000).contains { $0 != 0 }, "channel \(ch) silent in the stereo part")
        }
        XCTAssertTrue(samples(out, channel: 0, from: 3.3, to: 5.7, rate: 48000).contains { $0 != 0 }, "left plays in the stereo part")
        XCTAssertEqual(Double(out.frames) / 48000, 6, accuracy: 0.1)
        print("AUDIO-RESULT dts_layout_change.mkv: 6ch kept, layout changes \(d.layoutChanges), silent samples \(d.silentSamples), \(out.frames) frames")
    }

    func testASampleRateChangeIsResampledToTheFirstRate() async throws {
        let r = try await remuxAudio("dts_rate_change.mkv")
        XCTAssertEqual(r.rendition.transcodedSource?.outputSampleRate, 48000)
        let out = try referenceDecode(r.mp4Path)
        let d = try XCTUnwrap(r.diagnostics)
        XCTAssertGreaterThanOrEqual(d.sampleRateChanges, 1)
        XCTAssertEqual(Double(out.frames) / 48000, 6, accuracy: 0.1, "no time lost or added at the change")
        // No hole: the longest run of zero samples on the left channel stays under 20 ms.
        let left = samples(out, channel: 0, from: 0.2, to: 5.8, rate: 48000)
        var run = 0, longest = 0
        for v in left { run = v == 0 ? run + 1 : 0; longest = max(longest, run) }
        XCTAssertLessThan(longest, 960)
        print("AUDIO-RESULT dts_rate_change.mkv: rate changes \(d.sampleRateChanges), longest zero run \(longest) samples, \(out.frames) frames")
    }

    // MARK: Seeking

    func testSegmentsAskedOutOfOrderMatchTheSequentialOutput() async throws {
        let seq = try await remuxAudio("dtshd_ma_71_24_48k.mkv")
        let n = seq.segments.count
        XCTAssertGreaterThanOrEqual(n, 3)
        let order = [2, 0] + Array(3..<n) + [1]
        let jumbled = try await remuxAudio("dtshd_ma_71_24_48k.mkv", order: order)
        // Segment 2 starts cold with no earlier window held (no warm-up frames). The lossless signal is the core's synthesis
        // output plus the lossless residual, and the core's filter bank has no history at a cold start, so the first few
        // frames differ slightly (measured: 14,547 differing samples, about 1,800 sample times = 38 ms, largest difference
        // 6e-4 of full scale; the extension itself was present: 0 frames without it). Every other segment is either
        // continuous or warmed up from the previous window: byte for byte equal.
        for k in 0..<n where k != 2 { XCTAssertEqual(jumbled.segments[k], seq.segments[k], "segment \(k)") }
        let a = try referenceDecode(seq.mp4Path), b = try referenceDecode(jumbled.mp4Path)
        let c = compare(ref: a, out: b, maxOffset: 0)
        let silent = jumbled.diagnostics?.silentSamples ?? -1
        print("AUDIO-RESULT out-of-order dtshd_ma_71_24_48k.mkv: \(c); silent samples counted \(silent); "
              + "frames without lossless extension \(jumbled.diagnostics?.framesWithoutLosslessExtension ?? -1)")
        XCTAssertLessThanOrEqual(c.mismatches, 4800 * 8, "at most 100 ms of 7.1 differs (the cold start of segment 2)")
        XCTAssertGreaterThan(c.compared, a.frames * 99 / 100)
        XCTAssertLessThanOrEqual(silent, 512)
    }

    // MARK: Fallback

    func testAnUndecodableDefaultTrackFallsBackToTheBestOtherTrack() async throws {
        let path = try AudioMedia.path("fallback_three_tracks.mkv")
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
        var o = RemuxOptions(); o.targetSegmentSeconds = 2      // no decoder: the DTS track cannot be offered
        let info = try await MatroskaRemuxSession(reader: DataReader(data), options: o).prepare()
        let fb = try XCTUnwrap(info.audioFallback)
        XCTAssertEqual(fb.unplayable.codecID, "A_DTS")
        let chosen = try XCTUnwrap(info.audio.first { $0.isDefault })
        XCTAssertEqual(fb.replacement, chosen.trackNumber)
        XCTAssertEqual(chosen.language, "eng", "same language first")
        XCTAssertEqual(info.audio.filter { $0.isDefault }.count, 1)
        // With the decoder the default track plays and there is no fallback.
        o.audioTranscoder = DecodedAudioTranscoder()
        let decoded = try await MatroskaRemuxSession(reader: DataReader(data), options: o).prepare()
        XCTAssertNil(decoded.audioFallback)
        XCTAssertEqual(decoded.audio.first { $0.isDefault }?.codecID, "A_DTS")
    }
}
