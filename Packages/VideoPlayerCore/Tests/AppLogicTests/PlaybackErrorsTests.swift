import XCTest
import Foundation
@testable import RemuxEngine
import PlaybackStatus
@testable import AppLogic

// Error text for files the converting player cannot handle, the notices about left-out tracks, the status inputs, and the
// picture subtitle menu model. Everything here is pure logic; the player itself is on the device checklist.

final class PlaybackErrorsTests: XCTestCase {
    func testEveryEngineErrorGivesTextAndAdvice() {
        let errors: [RemuxError] = [
            .truncated("x"), .malformed("x"), .unsupported("x"), .notFound("x"), .io("x"), .cancelled, .reorderDepthExceeded(neededTicks: 5),
            .unsupported("no video track"), .unsupported("video codec V_VP9"), .unsupported("laced Matroska block without a duration (track 2)"),
            .unsupported("encrypted Matroska track"), .unsupported("Matroska content compression algorithm 1 (only header stripping and zlib are supported)"),
            .unsupported("unknown-size cluster in a file without Cues"), .malformed("not an EBML file"), .io("source did not report a size for a"),
            .io("bind() failed: errno 1"),
        ]
        for e in errors {
            let f = PlaybackFailures.map(e)
            XCTAssertFalse(f.message.isEmpty, "\(e)")
            if f.kind != .cancelled { XCTAssertFalse(f.advice.isEmpty, "\(e) needs a what-to-do line") }
            XCTAssertFalse(f.text.contains("RemuxError"), "no type names on screen")
            XCTAssertFalse(f.message.contains("errno"), "no raw system text on screen: \(f.message)")
        }
    }

    func testSpecificKinds() {
        XCTAssertEqual(PlaybackFailures.map(RemuxError.unsupported("no video track")).kind, .noVideo)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.unsupported("video codec V_VP9")).kind, .unsupportedVideo)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.unsupported("laced Matroska block without a duration (track 3)")).kind, .unsupportedLacing)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.unsupported("encrypted Matroska track")).kind, .encrypted)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.unsupported("Matroska content compression algorithm 2 (only header stripping and zlib are supported)")).kind, .unsupportedCompression)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.unsupported("unknown-size cluster in a file without Cues")).kind, .unsupportedStructure)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.malformed("not an EBML file")).kind, .notMatroska)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.malformed("no Cluster found")).kind, .damaged)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.truncated("block header")).kind, .damaged)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.io("bind() failed: errno 48")).kind, .localServer)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.io("source did not report a size for /a.mkv")).kind, .readFailed)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.notFound("seg")).kind, .readFailed)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.cancelled).kind, .cancelled)
        XCTAssertTrue(PlaybackFailures.map(RemuxError.cancelled).isSilentByDesign)
        XCTAssertEqual(PlaybackFailures.map(RemuxError.reorderDepthExceeded(neededTicks: 9)).kind, .unsupportedStructure)
    }

    func testUnsupportedVideoNamesTheCodecInWords() {
        XCTAssertTrue(PlaybackFailures.map(RemuxError.unsupported("video codec V_MPEG2")).message.contains("MPEG-2"))
        XCTAssertTrue(PlaybackFailures.map(RemuxError.unsupported("video codec V_AV1")).message.contains("AV1"))
        XCTAssertTrue(PlaybackFailures.map(RemuxError.unsupported("video codec V_VP9")).message.contains("VP9"))
        XCTAssertTrue(PlaybackFailures.map(RemuxError.unsupported("video codec V_MS/VFW/FOURCC")).message.contains("older Windows video format"))
        XCTAssertTrue(PlaybackFailures.map(RemuxError.unsupported("video codec V_SOMETHING_NEW")).message.contains("V_SOMETHING_NEW"),
                      "an unknown id is shown as written, not guessed")
    }

    func testOtherErrorsAndFailureTypesPassThrough() {
        XCTAssertEqual(PlaybackFailures.map(URLError(.notConnectedToInternet)).kind, .readFailed)
        XCTAssertEqual(PlaybackFailures.map(URLError(.timedOut)).kind, .readFailed)
        XCTAssertEqual(PlaybackFailures.map(URLError(.cancelled)).kind, .cancelled)
        XCTAssertEqual(PlaybackFailures.map(CancellationError()).kind, .cancelled)
        XCTAssertEqual(PlaybackFailures.map(PlaybackFailures.sourceGone), PlaybackFailures.sourceGone)
        struct Plain: LocalizedError { var errorDescription: String? { "The server refused the login." } }
        let f = PlaybackFailures.map(Plain())
        XCTAssertEqual(f.kind, .other)
        XCTAssertEqual(f.message, "The server refused the login.")
        XCTAssertEqual(PlaybackFailures.map(NSError(domain: NSPOSIXErrorDomain, code: 5)).kind, .readFailed)
    }

    func testContainers() {
        XCTAssertTrue(PlaybackFailures.canRemux(fileName: "Movie.MKV"))
        XCTAssertTrue(PlaybackFailures.canRemux(fileName: "a.b.webm"))
        XCTAssertFalse(PlaybackFailures.canRemux(fileName: "a.avi"))
        XCTAssertFalse(PlaybackFailures.canRemux(fileName: "noextension"))
        let f = PlaybackFailures.unsupportedContainer(fileExtension: "avi")
        XCTAssertEqual(f.kind, .unsupportedContainer)
        XCTAssertTrue(f.message.hasPrefix("AVI files cannot be played yet"), f.message)
        XCTAssertTrue(PlaybackFailures.unsupportedContainer(fileExtension: "").message.hasPrefix("This file type cannot be played yet"))
    }

    func testPlayerFailureHints() {
        for hint in PlayerFailureHint.allCases {
            let f = PlaybackFailures.playerFailure(hint)
            XCTAssertFalse(f.message.isEmpty); XCTAssertFalse(f.advice.isEmpty)
        }
        XCTAssertEqual(PlaybackFailures.playerFailure(.network).kind, .readFailed)
        XCTAssertEqual(PlaybackFailures.playerFailure(.decoderMissing).kind, .playerRejected)
    }

    /// docs/NAMES.md (user rule, 2026-11-17): formats keep their real names, but no text claims a certification or an
    /// endorsement, and no trademark signs are used. (The old ban on every product name is replaced by this rule; the
    /// design-lint `unknown-name` rule checks that each name in these strings is allowlisted.)
    func testErrorTextsMakeNoCertificationClaims() {
        let claims = ["certified", "works with", "made for", "endorsed", "approved by", "official", "™", "®", "(tm)", "(r)"]
        var texts: [String] = []
        let engineErrors: [RemuxError] = [.truncated("x"), .malformed("x"), .unsupported("x"), .notFound("x"), .io("x"), .reorderDepthExceeded(neededTicks: 1),
                                          .unsupported("no video track"), .unsupported("video codec V_VP9"), .unsupported("encrypted Matroska track")]
        for e in engineErrors {
            let f = PlaybackFailures.map(e); texts += [f.message, f.advice]
        }
        for hint in PlayerFailureHint.allCases { let f = PlaybackFailures.playerFailure(hint); texts += [f.message, f.advice] }
        for f in [PlaybackFailures.noFile, PlaybackFailures.sourceGone, PlaybackFailures.damaged, PlaybackFailures.readFailed(detail: nil),
                  PlaybackFailures.unsupportedContainer(fileExtension: "avi")] { texts += [f.message, f.advice] }
        texts.append(PlaybackFailure.title)
        for t in texts { for word in claims { XCTAssertFalse(t.lowercased().contains(word), "'\(word)' in: \(t)") } }
        XCTAssertTrue(texts.contains { $0.contains("VP9") }, "the unsupported codec is named by its real name")
    }
}

// MARK: - Status inputs and notices

final class RemuxPlaybackModelTests: XCTestCase {
    func info(range: VideoRange = .pq, dvProfile: Int? = nil, el: Bool? = nil, compat: Int? = nil, converted: Bool = false,
              audio: [AudioRenditionInfo] = [], skippedAudio: [SkippedTrack] = [], skippedSubs: [SkippedSubtitle] = [],
              warnings: [String] = [], overBudget: Bool = false, elType: DolbyVisionSampleInfo.EnhancementLayer? = nil,
              conversionFailed: Bool = false, hdr10Plus: Bool = false) -> RemuxMediaInfo {
        var i = RemuxMediaInfo(durationSeconds: 100, segmentCount: 10, targetSegmentSeconds: 10, timelineOffsetSeconds: 0, firstKeyframeSeconds: 0,
                               videoCodecString: "hvc1.2.4.L153.B0", supplementalCodecs: nil, videoRange: range, width: 3840, height: 2160,
                               sampleEntry: "hvc1", audio: audio, skippedAudio: skippedAudio, subtitleTrackNumbers: [], usedClusterScan: false,
                               isOverBudget: overBudget, warnings: warnings)
        i.dolbyVisionSourceProfile = dvProfile
        i.dolbyVisionEnhancementLayer = el
        i.dolbyVisionCompatibilityID = compat
        i.dolbyVisionConverted = converted
        i.dolbyVisionEnhancementLayerType = elType
        i.dolbyVisionConversionFailed = conversionFailed
        i.hasHDR10PlusMetadata = hdr10Plus
        i.skippedSubtitles = skippedSubs
        return i
    }

    func track(_ n: Int, _ id: String, ch: Int = 6, atmos: Bool = false, def: Bool = false, transcoded: Bool = false) -> AudioRenditionInfo {
        AudioRenditionInfo(trackNumber: n, name: "t\(n)", language: "eng", codecID: id, codecString: "x", channels: ch, isDefault: def, transcoded: transcoded, isAtmos: atmos)
    }

    func testHDRFormats() {
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .sdr)), .sdr)
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .pq)), .hdr10)
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .hlg)), .hlg)
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(dvProfile: 5, compat: 0)), .dolbyVision(.p5))
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(dvProfile: 8, compat: 1)), .dolbyVision(.p8_1))
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .sdr, dvProfile: 8, compat: 2)), .dolbyVision(.p8_2))
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .hlg, dvProfile: 8, compat: 4)), .dolbyVision(.p8_4))
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .pq, dvProfile: 8, compat: 0)), .dolbyVision(.p8_1), "no compat id: range decides")
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .hlg, dvProfile: 8, compat: nil)), .dolbyVision(.p8_4))
        // FEL / MEL come from the RPU, not from the record's enhancement-layer flag (set for both).
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(dvProfile: 7, el: true, compat: 6, elType: .full)), .dolbyVision(.p7FEL))
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(dvProfile: 7, el: true, compat: 6, elType: .minimal)), .dolbyVision(.p7MEL))
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(dvProfile: 7, el: true, compat: 6)), .dolbyVision(.p7FEL), "RPU not read: never claim MEL")
        // HDR10+ metadata in a PQ file without Dolby Vision.
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .pq, hdr10Plus: true)), .hdr10Plus)
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .pq, dvProfile: 8, compat: 1, hdr10Plus: true)), .dolbyVision(.p8_1), "Dolby Vision wins")
        XCTAssertEqual(RemuxPlaybackModel.hdrFormat(info(range: .pq, dvProfile: 4)), .hdr10, "a profile without a rule is described by its base layer")
    }

    func testProfile7ConversionAndStatusText() {
        XCTAssertEqual(RemuxPlaybackModel.profile7Conversion(info(dvProfile: 7)), .notAvailableOnDevice)
        XCTAssertEqual(RemuxPlaybackModel.profile7Conversion(info(dvProfile: 7, converted: true)), .available)
        XCTAssertEqual(RemuxPlaybackModel.profile7Conversion(info(dvProfile: 7, conversionFailed: true)), .failedForThisFile)
        XCTAssertTrue(RemuxPlaybackModel.notices(info(dvProfile: 7, audio: [track(2, "A_AC3")], conversionFailed: true))
            .contains { $0.text.contains("could not be converted") && $0.severity == .warning })
        // Converted MEL on a Dolby Vision display: "converted from Profile 7", nothing lost.
        let mel = info(dvProfile: 7, el: true, converted: true, audio: [track(2, "A_AC3", def: true)], elType: .minimal)
        let melStatus = StatusRules.video(RemuxPlaybackModel.hdrFormat(mel), display: DisplayState(availableHDR: [.hdr10, .dolbyVision]),
                                          engine: .primary, profile7: RemuxPlaybackModel.profile7Conversion(mel))
        XCTAssertEqual(melStatus.output, "Dolby Vision (converted from Profile 7)")
        XCTAssertTrue(melStatus.note?.contains("MEL") == true)
        // With no converter the status says HDR10 base layer, from the real rules.
        let i = info(dvProfile: 7, el: true, audio: [track(2, "A_AC3", def: true)])
        let status = StatusRules.status(track: RemuxPlaybackModel.audioContent(i)!,
                                        route: AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .unknown),
                                        format: RemuxPlaybackModel.hdrFormat(i),
                                        display: DisplayState(availableHDR: [.hdr10, .dolbyVision], activeMode: nil, matchDynamicRange: .yes),
                                        engine: .primary, profile7: RemuxPlaybackModel.profile7Conversion(i))
        XCTAssertEqual(status.video.output, "HDR10 (base layer)")
        XCTAssertEqual(status.video.path, .baseLayer)
    }

    func testAudioContent() {
        let i = info(audio: [track(2, "A_AC3", ch: 6, def: false), track(3, "A_EAC3", ch: 8, atmos: true, def: true), track(4, "A_AAC", ch: 2)])
        XCTAssertEqual(RemuxPlaybackModel.audioContent(i), AudioTrackContent(kind: .eac3, channels: 8, hasAtmos: true), "default rendition")
        XCTAssertEqual(RemuxPlaybackModel.audioContent(i, selectedTrack: 2), AudioTrackContent(kind: .ac3, channels: 6))
        XCTAssertEqual(RemuxPlaybackModel.audioContent(i, selectedTrack: 4), AudioTrackContent(kind: .aac, channels: 2))
        XCTAssertEqual(RemuxPlaybackModel.audioContent(i, selectedTrack: 99), AudioTrackContent(kind: .eac3, channels: 8, hasAtmos: true), "unknown track: default")
        XCTAssertNil(RemuxPlaybackModel.audioContent(info()), "no audio")
        let plain = info(audio: [track(3, "A_EAC3", ch: 6, atmos: false)])
        XCTAssertEqual(RemuxPlaybackModel.audioContent(plain)?.hasAtmos, false)
        XCTAssertEqual(RemuxPlaybackModel.audioContent(info(audio: [track(5, "A_FLAC", ch: 2)]))?.kind, .flac)
    }

    func testAtmosStatusFollowsTheRouteHonestly() {
        let i = info(audio: [track(3, "A_EAC3", ch: 8, atmos: true, def: true)])
        let content = RemuxPlaybackModel.audioContent(i)!
        let hdmi = AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .unknown)
        let s = StatusRules.status(track: content, route: hdmi, format: .hdr10, display: .unknown, engine: .primary, profile7: .notAvailableOnDevice)
        XCTAssertEqual(s.audio.path, .passthrough)
        let tv = AudioRoute(kind: .builtIn, maxChannels: 2, passesDolbyBitstream: .no, atmos: .no)
        let s2 = StatusRules.status(track: content, route: tv, format: .hdr10, display: .unknown, engine: .primary, profile7: .notAvailableOnDevice)
        XCTAssertNotEqual(s2.audio.path, .passthrough)
        XCTAssertNotNil(s2.audio.note, "when the output cannot take the bitstream the text says what happens instead")
    }

    func testSnapshot() {
        let i = info(range: .pq, audio: [track(3, "A_EAC3", ch: 8, atmos: true, def: true)])
        let s = RemuxPlaybackModel.snapshot(i)
        XCTAssertEqual(s.decodePath, .remux)
        XCTAssertEqual(s.engine, .primary)
        XCTAssertEqual(s.width, 3840); XCTAssertEqual(s.height, 2160)
        XCTAssertEqual(s.hdr, .hdr10)
        XCTAssertEqual(s.videoCodec, "HEVC")
        XCTAssertEqual(s.audio?.hasAtmos, true)
        var avc = i; avc.videoCodecString = "avc1.640028"
        XCTAssertEqual(RemuxPlaybackModel.snapshot(avc).videoCodec, "H.264")
    }

    func testNoAudioAtAllIsAnImportantNotice() {
        let skipped = [SkippedTrack(trackNumber: 2, codecID: "A_DTS", reason: "x"), SkippedTrack(trackNumber: 3, codecID: "A_TRUEHD", reason: "x"),
                       SkippedTrack(trackNumber: 4, codecID: "A_DTS", reason: "x")]
        let notices = RemuxPlaybackModel.notices(info(skippedAudio: skipped))
        XCTAssertEqual(notices.first?.severity, .important)
        let text = notices.first?.fullText ?? ""
        XCTAssertTrue(text.contains("DTS, Dolby TrueHD"), "each codec named once: \(text)")
        XCTAssertTrue(text.contains("plays without sound"))
        XCTAssertTrue(text.contains("Reason: x"))
    }

    func testSkippedAudioWhileOthersPlayIsAWarning() {
        let i = info(audio: [track(2, "A_AC3", def: true)], skippedAudio: [SkippedTrack(trackNumber: 3, codecID: "A_DTS", reason: "damaged header")])
        let notices = RemuxPlaybackModel.notices(i)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].severity, .warning)
        XCTAssertEqual(notices[0].text, "Audio track 3 (DTS) cannot be played: damaged header")
    }

    func testLostDefaultTrackNamesItsReplacement() {
        var i = info(audio: [track(4, "A_AC3", ch: 6, def: true)],
                     skippedAudio: [SkippedTrack(trackNumber: 2, codecID: "A_TRUEHD", reason: "the decoder rejected the first frames")])
        i.audioFallback = AudioFallbackInfo(unplayable: i.skippedAudio[0], replacement: 4)
        let notices = RemuxPlaybackModel.notices(i)
        XCTAssertEqual(notices.count, 1, "the lost track is named once, in the fallback notice")
        XCTAssertEqual(notices[0].severity, .important)
        XCTAssertEqual(notices[0].text, "The Dolby TrueHD track (track 2) could not be decoded, so the Dolby Digital 5.1 track plays instead.")
        XCTAssertFalse(notices[0].fullText.contains("without sound"))
    }

    func testDecodedTrackDescribesWhatItBecame() {
        var r = track(2, "A_TRUEHD", ch: 8, def: true, transcoded: true)
        r.transcodedSource = TranscodedAudioSource(format: .trueHDAtmos, sourceChannels: 8, outputChannels: 8, sourceSampleRate: 48000,
                                                   outputSampleRate: 48000, outputBits: 24, isLossless: true, hasEmbeddedCore: true)
        let i = info(audio: [r])
        XCTAssertEqual(RemuxPlaybackModel.audioContent(i),
                       AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true, hasAC3Core: true, sampleRate: 48000))
        let texts = RemuxPlaybackModel.notices(i).map(\.text)
        XCTAssertEqual(texts, ["Audio track 2: Dolby TrueHD with Atmos 7.1, decoded losslessly to FLAC (24-bit, 48 kHz); Atmos plays as its 7.1 bed."])
        var dts = r
        dts.transcodedSource = TranscodedAudioSource(format: .dtsHDHighResolution, sourceChannels: 6, outputChannels: 6, sourceSampleRate: 96000,
                                                     outputSampleRate: 96000, outputBits: 24, isLossless: false)
        XCTAssertEqual(RemuxPlaybackModel.audioContent(info(audio: [dts]))?.kind, .dtsHDHRA)
        XCTAssertEqual(RemuxPlaybackModel.audioContent(info(audio: [dts]))?.sampleRate, 96000)
        var core = r
        core.transcodedSource?.usesEmbeddedCore = true
        XCTAssertEqual(RemuxPlaybackModel.audioContent(info(audio: [core]))?.usesCompatibilityCore, true)
        let d = { var d = AudioTranscodeDiagnostics(); d.concealedFrames = 3; d.framesWithoutLosslessExtension = 2; return d }()
        let diag = RemuxPlaybackModel.audioDiagnosticNotices(trackNumber: 2, d).map(\.text)
        XCTAssertEqual(diag.count, 2)
        XCTAssertTrue(diag[0].contains("3 damaged frame(s) were replaced by silence"))
        XCTAssertTrue(RemuxPlaybackModel.audioDiagnosticNotices(trackNumber: 2, AudioTranscodeDiagnostics()).isEmpty)
    }

    func testSilentFileGetsAnHonestNotice() {
        let notices = RemuxPlaybackModel.notices(info())
        XCTAssertEqual(notices.map(\.text), ["This file has no audio track."])
    }

    func testOtherNotices() {
        let i = info(dvProfile: 7, el: true, audio: [track(2, "A_AC3", def: true)],
                     skippedSubs: [SkippedSubtitle(trackNumber: 9, codecID: "S_VOBSUB", reason: "picture subtitles of this kind are not supported")],
                     warnings: ["no Cues: keyframes found by scanning 40 cluster headers"], overBudget: true)
        let texts = RemuxPlaybackModel.notices(i).map(\.text)
        XCTAssertEqual(texts.count, 4)
        XCTAssertTrue(texts.contains { $0.contains("profile 7") && $0.contains("HDR10 base layer") })
        XCTAssertTrue(texts.contains { $0.hasPrefix("Subtitle track 9 is not offered") })
        XCTAssertTrue(texts.contains { $0.contains("no seek index") })
        XCTAssertTrue(texts.contains { $0.contains("very high bitrate") })
        // Warnings sort before infos.
        XCTAssertEqual(RemuxPlaybackModel.notices(i).first?.severity, .warning)
        // A converted profile 7 file has no such notice.
        XCTAssertFalse(RemuxPlaybackModel.notices(info(dvProfile: 7, converted: true, audio: [track(2, "A_AC3")])).contains { $0.text.contains("profile 7") })
        XCTAssertTrue(RemuxPlaybackModel.notices(info(audio: [track(2, "A_AC3")])).isEmpty, "a plain file has no notices")
    }

    func testAudioCodecNames() {
        let names = ["A_DTS": "DTS", "A_DTS/EXPRESS": "DTS Express", "A_DTS/LOSSLESS": "DTS-HD Master Audio", "A_TRUEHD": "Dolby TrueHD", "A_AC3": "Dolby Digital", "A_EAC3": "Dolby Digital Plus",
                     "A_AAC/MPEG4/LC": "AAC", "A_OPUS": "Opus", "A_VORBIS": "Vorbis", "A_MPEG/L3": "MP3", "A_WHAT": "A_WHAT"]
        for (id, name) in names { XCTAssertEqual(RemuxPlaybackModel.audioCodecName(id), name, id) }
    }
}

// MARK: - Picture subtitle menu

final class PictureSubtitleMenuTests: XCTestCase {
    func model(textOn: Bool = false) -> PictureSubtitleMenuModel {
        var m = PictureSubtitleMenuModel(choices: [
            PictureSubtitleChoice(id: 4, title: "English", language: "en"),
            PictureSubtitleChoice(id: 6, title: "Japanese", language: "ja", isForced: true),
            PictureSubtitleChoice(id: 7, title: "English SDH", language: "en", isHearingImpaired: true),
        ])
        if textOn { _ = m.textSelectionChanged(isOn: true) }
        return m
    }

    func testRows() {
        let m = model()
        XCTAssertTrue(m.isVisible)
        XCTAssertEqual(m.rows.map(\.title), ["Off", "English", "Japanese", "English SDH"])
        XCTAssertEqual(m.rows.map(\.isSelected), [true, false, false, false], "starts off")
        XCTAssertEqual(m.rows[2].detail, "Forced")
        XCTAssertEqual(m.rows[3].detail, "For the deaf and hard of hearing")
        XCTAssertNil(m.rows[1].detail)
        XCTAssertEqual(m.rows.map(\.id), [-1, 4, 6, 7], "ids are unique")
        XCTAssertTrue(m.initialEffects.isEmpty, "nothing is chosen for the person")
    }

    func testNoPictureTracksMeansNoMenu() {
        let m = PictureSubtitleMenuModel(choices: [])
        XCTAssertFalse(m.isVisible)
        XCTAssertEqual(m.rows.map(\.title), ["Off"])
    }

    func testChoosingAPictureTrackShowsItAndTurnsTextOff() {
        var m = model(textOn: true)
        XCTAssertEqual(m.choose(6), [.turnOffText, .showPicture(track: 6)])
        XCTAssertEqual(m.selected, 6)
        XCTAssertFalse(m.textIsOn)
        XCTAssertEqual(m.rows.map(\.isSelected), [false, false, true, false])
        // Text was already off: only the picture effect.
        var n = model()
        XCTAssertEqual(n.choose(4), [.showPicture(track: 4)])
    }

    func testSwitchingBetweenPictureTracks() {
        var m = model()
        _ = m.choose(4)
        XCTAssertEqual(m.choose(7), [.showPicture(track: 7)])
        XCTAssertEqual(m.selected, 7)
        XCTAssertEqual(m.choose(7), [], "choosing the same row again does nothing")
    }

    func testOffHidesThePicture() {
        var m = model()
        XCTAssertEqual(m.choose(nil), [], "already off")
        _ = m.choose(4)
        XCTAssertEqual(m.choose(nil), [.hidePicture])
        XCTAssertNil(m.selected)
    }

    func testChoosingATextTrackInTheSystemMenuTurnsThePictureOff() {
        var m = model()
        _ = m.choose(6)
        XCTAssertEqual(m.textSelectionChanged(isOn: true), [.hidePicture])
        XCTAssertNil(m.selected)
        XCTAssertTrue(m.textIsOn)
        // Text turned off again: nothing to undo and nothing comes back by itself.
        XCTAssertEqual(m.textSelectionChanged(isOn: false), [])
        XCTAssertNil(m.selected)
    }

    func testTextOffWithoutPictureChangesNothing() {
        var m = model()
        XCTAssertEqual(m.textSelectionChanged(isOn: true), [])
        XCTAssertEqual(m.textSelectionChanged(isOn: false), [])
    }

    func testUnknownTrackIsIgnored() {
        var m = model()
        XCTAssertEqual(m.choose(99), [])
        XCTAssertNil(m.selected)
    }

    func testBuiltFromEngineInfo() {
        let info = [PictureSubtitleInfo(trackNumber: 8, name: "Japanese", language: "ja", isDefault: true, isForced: false, isHearingImpaired: false)]
        let m = PictureSubtitleMenuModel(info: info)
        XCTAssertEqual(m.choices, [PictureSubtitleChoice(id: 8, title: "Japanese", language: "ja", isDefault: true)])
    }

    func testOnlyOneSourceIsEverActive() {
        // A random walk through both menus: never a picture selected while text is on.
        var m = model()
        var seed: UInt64 = 12345
        func next() -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) }
        for _ in 0..<500 {
            switch next() % 4 {
            case 0: _ = m.choose([nil, 4, 6, 7][next() % 4])
            case 1: _ = m.textSelectionChanged(isOn: true)
            case 2: _ = m.textSelectionChanged(isOn: false)
            default: _ = m.choose(99)
            }
            XCTAssertFalse(m.textIsOn && m.selected != nil)
        }
    }
}
