import XCTest
@testable import PlaybackStatus

/// Hand-written expectations. They do NOT use StatusTable, so they check the rules independently of the
/// generated table. Each case has a tag; `testEveryRequiredCaseHasAnExpectation` fails if a required
/// tag from the brief has no case here.
final class ExpectedRowsTests: XCTestCase {

    // Routes
    static let atmosHDMI = AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .yes)
    static let hdmi8NoAtmos = AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .no)
    static let hdmi8AtmosUnknown = AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .unknown)
    static let hdmi6 = AudioRoute(kind: .hdmi, maxChannels: 6, passesDolbyBitstream: .yes, atmos: .no)
    static let arcStereo = AudioRoute(kind: .hdmi, maxChannels: 2, passesDolbyBitstream: .unknown, atmos: .unknown)
    static let bluetooth = AudioRoute(kind: .bluetooth, maxChannels: 2, passesDolbyBitstream: .no, atmos: .no)
    static let unknownRoute = AudioRoute.unknown

    struct AudioCase {
        let tag: String
        let track: AudioTrackContent
        let route: AudioRoute
        let engine: PlaybackEngine
        let output: String
        let note: String?
    }

    static let dd51 = AudioTrackContent(kind: .ac3, channels: 6)
    static let ddp51 = AudioTrackContent(kind: .eac3, channels: 6)
    static let ddpAtmos = AudioTrackContent(kind: .eac3, channels: 8, hasAtmos: true)
    static let thdCore = AudioTrackContent(kind: .trueHD, channels: 8, hasAC3Core: true)
    static let thd = AudioTrackContent(kind: .trueHD, channels: 8)
    static let thdAtmosCore = AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true, hasAC3Core: true)
    static let thdAtmos = AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true)
    /// The compatibility setting: the embedded Dolby Digital core plays instead of the full decode.
    static let thdCoreCompat = AudioTrackContent(kind: .trueHD, channels: 8, hasAC3Core: true, usesCompatibilityCore: true)
    static let thdAtmosCoreCompat = AudioTrackContent(kind: .trueHD, channels: 8, hasAtmos: true, hasAC3Core: true, usesCompatibilityCore: true)

    static let audioCases: [AudioCase] = [
        AudioCase(tag: "dd", track: dd51, route: hdmi6, engine: .primary, output: "Dolby Digital 5.1 (passthrough)", note: nil),
        AudioCase(tag: "dd-bluetooth", track: dd51, route: bluetooth, engine: .primary,
                  output: "Stereo PCM (decoded by Apple TV, downmixed from 5.1)",
                  note: "This audio output cannot take Dolby Digital, so Apple TV decodes it to PCM."),
        AudioCase(tag: "dd-route-unknown", track: dd51, route: unknownRoute, engine: .primary,
                  output: "Dolby Digital 5.1 (passthrough)",
                  note: "Apple TV does not report whether this output takes Dolby Digital, and decodes it if it does not."),
        AudioCase(tag: "ddplus", track: ddp51, route: atmosHDMI, engine: .primary, output: "Dolby Digital Plus 5.1 (passthrough)", note: nil),
        AudioCase(tag: "atmos", track: ddpAtmos, route: atmosHDMI, engine: .primary, output: "Dolby Atmos (passthrough)", note: nil),
        AudioCase(tag: "atmos-requested-route-not-atmos", track: ddpAtmos, route: hdmi8NoAtmos, engine: .primary,
                  output: "Dolby Digital Plus 7.1 (passthrough)",
                  note: "This audio output does not support Dolby Atmos, so only the channel bed plays."),
        AudioCase(tag: "atmos-route-unconfirmed", track: ddpAtmos, route: hdmi8AtmosUnknown, engine: .primary,
                  output: "Dolby Digital Plus 7.1 (passthrough)",
                  note: "Apple TV does not report whether Dolby Atmos is active on this output."),
        AudioCase(tag: "atmos-bluetooth", track: ddpAtmos, route: bluetooth, engine: .primary,
                  output: "Stereo PCM (decoded by Apple TV, downmixed from 7.1)",
                  note: "This audio output cannot take Dolby Digital Plus, so Apple TV decodes it to PCM, and the Atmos objects are not played."),
        AudioCase(tag: "truehd-core", track: thdCoreCompat, route: atmosHDMI, engine: .primary,
                  output: "Dolby Digital 5.1 (TrueHD core, passthrough)",
                  note: "Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used."),
        AudioCase(tag: "truehd-core-bluetooth", track: thdCoreCompat, route: bluetooth, engine: .primary,
                  output: "Stereo PCM (Dolby Digital core, decoded by Apple TV, downmixed from 5.1)",
                  note: "Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and this output cannot take Dolby Digital so Apple TV decodes it to PCM."),
        // A core in the file does not change the default: the full lossless decode plays.
        AudioCase(tag: "truehd-core-default-full-decode", track: thdCore, route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)", note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM."),
        AudioCase(tag: "truehd-nocore-71", track: thd, route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)", note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM."),
        AudioCase(tag: "truehd-nocore-51-route", track: thd, route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded, downmixed from 7.1)", note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM."),
        AudioCase(tag: "truehd-nocore-stereo-route", track: thd, route: bluetooth, engine: .primary,
                  output: "Stereo PCM (decoded, downmixed from 7.1)", note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM."),
        AudioCase(tag: "truehd-nocore-route-unknown", track: thd, route: unknownRoute, engine: .primary,
                  output: "7.1 PCM (decoded)",
                  note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the number of channels this output supports is unknown."),
        AudioCase(tag: "truehd-atmos", track: thdAtmos, route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)",
                  note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed."),
        AudioCase(tag: "truehd-atmos-core-default", track: thdAtmosCore, route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)",
                  note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the Atmos objects are not played, only the 7.1 bed."),
        AudioCase(tag: "truehd-atmos-core", track: thdAtmosCoreCompat, route: atmosHDMI, engine: .primary,
                  output: "Dolby Digital 5.1 (TrueHD core, passthrough)",
                  note: "Apple's player cannot pass Dolby TrueHD, so the Dolby Digital core is used, and the Atmos objects are not played."),
        AudioCase(tag: "dts", track: AudioTrackContent(kind: .dts, channels: 6), route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded)", note: "Apple's player cannot pass DTS audio, so it is decoded to PCM."),
        AudioCase(tag: "dtshd-71", track: AudioTrackContent(kind: .dtsHDMA, channels: 8), route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)", note: "Apple's player cannot pass DTS audio, so it is decoded to PCM."),
        AudioCase(tag: "dtshd-downmix-51", track: AudioTrackContent(kind: .dtsHDMA, channels: 8), route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded, downmixed from 7.1)", note: "Apple's player cannot pass DTS audio, so it is decoded to PCM."),
        AudioCase(tag: "dtshd-downmix-20", track: AudioTrackContent(kind: .dtsHDMA, channels: 8), route: bluetooth, engine: .primary,
                  output: "Stereo PCM (decoded, downmixed from 7.1)", note: "Apple's player cannot pass DTS audio, so it is decoded to PCM."),
        AudioCase(tag: "dtsx", track: AudioTrackContent(kind: .dtsX, channels: 8), route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)",
                  note: "Apple's player cannot pass DTS audio, so it is decoded to PCM, and the DTS:X objects are not rendered, only the 7.1 bed plays."),
        AudioCase(tag: "dtshd-hra", track: AudioTrackContent(kind: .dtsHDHRA, channels: 6), route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded)", note: "Apple's player cannot pass DTS audio, so it is decoded to PCM."),
        AudioCase(tag: "dtshd-96k", track: AudioTrackContent(kind: .dtsHDMA, channels: 8, sampleRate: 96000), route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)",
                  note: "Apple's player cannot pass DTS audio, so it is decoded to PCM, and the system does not report whether this output receives the full 96 kHz."),
        AudioCase(tag: "truehd-192k", track: AudioTrackContent(kind: .trueHD, channels: 6, sampleRate: 192000), route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded)",
                  note: "Apple's player cannot pass Dolby TrueHD, so it is decoded to PCM, and the system does not report whether this output receives the full 192 kHz."),
        AudioCase(tag: "dtshd-48k-no-rate-note", track: AudioTrackContent(kind: .dtsHDMA, channels: 8, sampleRate: 48000), route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM (decoded)", note: "Apple's player cannot pass DTS audio, so it is decoded to PCM."),
        AudioCase(tag: "vorbis-51", track: AudioTrackContent(kind: .vorbis, channels: 6), route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded)", note: nil),
        AudioCase(tag: "flac-88k-unknown-route", track: AudioTrackContent(kind: .flac, channels: 6, sampleRate: 88200), route: unknownRoute, engine: .primary,
                  output: "5.1 PCM (decoded)",
                  note: "The number of channels this output supports is unknown, and the system does not report whether this output receives the full 88.2 kHz."),
        AudioCase(tag: "pcm-71-on-8ch", track: AudioTrackContent(kind: .pcm, channels: 8), route: atmosHDMI, engine: .primary,
                  output: "7.1 PCM", note: nil),
        AudioCase(tag: "pcm-71-downmix", track: AudioTrackContent(kind: .pcm, channels: 8), route: hdmi6, engine: .primary,
                  output: "5.1 PCM (decoded, downmixed from 7.1)", note: nil),
        AudioCase(tag: "aac-stereo", track: AudioTrackContent(kind: .aac, channels: 2), route: bluetooth, engine: .primary,
                  output: "AAC Stereo (passthrough)", note: nil),
        AudioCase(tag: "flac", track: AudioTrackContent(kind: .flac, channels: 2), route: hdmi6, engine: .primary,
                  output: "Stereo PCM (decoded)", note: nil),
        AudioCase(tag: "pcm-stereo", track: AudioTrackContent(kind: .pcm, channels: 2), route: hdmi6, engine: .primary,
                  output: "Stereo PCM", note: nil),
        AudioCase(tag: "opus", track: AudioTrackContent(kind: .opus, channels: 2), route: hdmi6, engine: .primary,
                  output: "Stereo PCM (decoded)", note: nil),
        AudioCase(tag: "fallback-dd", track: dd51, route: hdmi6, engine: .fallback,
                  output: "5.1 PCM (decoded)", note: "The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable."),
        AudioCase(tag: "fallback-atmos", track: ddpAtmos, route: atmosHDMI, engine: .fallback,
                  output: "7.1 PCM (decoded)",
                  note: "The fallback player decodes all audio to PCM, so Dolby passthrough is unavailable, and the Atmos objects are not played."),
        AudioCase(tag: "fallback-dtsx", track: AudioTrackContent(kind: .dtsX, channels: 8), route: atmosHDMI, engine: .fallback,
                  output: "7.1 PCM (decoded)",
                  note: "The fallback player decodes all audio to PCM, so DTS passthrough is unavailable, and the DTS:X objects are not rendered."),
        AudioCase(tag: "fallback-aac", track: AudioTrackContent(kind: .aac, channels: 2), route: hdmi6, engine: .fallback,
                  output: "Stereo PCM (decoded)", note: nil),
        AudioCase(tag: "fallback-pcm", track: AudioTrackContent(kind: .pcm, channels: 2), route: hdmi6, engine: .fallback,
                  output: "Stereo PCM", note: nil)
    ]

    func testAudioCases() {
        for c in Self.audioCases {
            let s = StatusRules.audio(c.track, route: c.route, engine: c.engine)
            XCTAssertEqual(s.output, c.output, "[\(c.tag)] output")
            XCTAssertEqual(s.note, c.note, "[\(c.tag)] note")
        }
    }

    func testAudioContainsText() {
        XCTAssertEqual(StatusRules.audioContains(Self.thdAtmosCore), "Dolby TrueHD with Atmos 7.1 (with Dolby Digital core)")
        XCTAssertEqual(StatusRules.audioContains(Self.ddpAtmos), "Dolby Digital Plus with Atmos 7.1")
        XCTAssertEqual(StatusRules.audioContains(AudioTrackContent(kind: .dtsHDMA, channels: 8)), "DTS-HD Master Audio 7.1")
        XCTAssertEqual(StatusRules.audioContains(AudioTrackContent(kind: .aac, channels: 2)), "AAC Stereo")
        XCTAssertEqual(StatusRules.audioContains(AudioTrackContent(kind: .dtsHDHRA, channels: 6)), "DTS-HD High Resolution 5.1")
        XCTAssertEqual(StatusRules.audioContains(AudioTrackContent(kind: .vorbis, channels: 2)), "Vorbis Stereo")
    }

    // MARK: Video

    static let dvChain = DisplayState(availableHDR: [.dolbyVision, .hdr10, .hlg])
    static let hdr10Display = DisplayState(availableHDR: [.hdr10, .hlg])
    static let hlgOnly = DisplayState(availableHDR: [.hlg])
    static let sdrDisplay = DisplayState(availableHDR: [])
    static let unknownDisplay = DisplayState.unknown

    struct VideoCase {
        let tag: String
        let format: HDRFormat
        let display: DisplayState
        let engine: PlaybackEngine
        let p7: Profile7Conversion
        let output: String
        let note: String?
    }

    static let dvNotSupported = "This display does not support Dolby Vision, so the HDR10 base layer plays."

    static let videoCases: [VideoCase] = [
        VideoCase(tag: "sdr", format: .sdr, display: sdrDisplay, engine: .primary, p7: .available, output: "SDR", note: nil),
        VideoCase(tag: "hdr10-on-hdr10", format: .hdr10, display: hdr10Display, engine: .primary, p7: .available, output: "HDR10", note: nil),
        VideoCase(tag: "hdr10-on-sdr", format: .hdr10, display: sdrDisplay, engine: .primary, p7: .available,
                  output: "SDR (tone-mapped from HDR10)", note: "This display does not support HDR10, so the picture is tone-mapped to SDR."),
        VideoCase(tag: "hdr10-display-unknown", format: .hdr10, display: unknownDisplay, engine: .primary, p7: .available,
                  output: "Display mode: unknown", note: "Apple TV did not report which HDR modes this display supports."),
        VideoCase(tag: "hlg", format: .hlg, display: hdr10Display, engine: .primary, p7: .available, output: "HLG", note: nil),
        VideoCase(tag: "hlg-on-sdr", format: .hlg, display: sdrDisplay, engine: .primary, p7: .available,
                  output: "SDR (tone-mapped from HLG)", note: "This display does not support HLG, so the picture is tone-mapped to SDR."),
        VideoCase(tag: "hdr10plus", format: .hdr10Plus, display: hdr10Display, engine: .primary, p7: .available,
                  output: "HDR10", note: "The app could not tell whether this Apple TV model sends HDR10+ metadata, so this is shown as HDR10."),
        VideoCase(tag: "hdr10plus-3rd-gen", format: .hdr10Plus,
                  display: DisplayState(availableHDR: [.hdr10, .hlg], sendsHDR10Plus: .yes), engine: .primary, p7: .available,
                  output: "HDR10+ or HDR10",
                  note: "This Apple TV sends the HDR10+ metadata when the display supports it; it does not report whether the display uses it."),
        VideoCase(tag: "hdr10plus-2nd-gen", format: .hdr10Plus,
                  display: DisplayState(availableHDR: [.hdr10, .hlg], sendsHDR10Plus: .no), engine: .primary, p7: .available,
                  output: "HDR10", note: "This Apple TV model does not support HDR10+, so this plays as HDR10."),
        VideoCase(tag: "hdr10plus-3rd-gen-on-sdr", format: .hdr10Plus,
                  display: DisplayState(availableHDR: [], sendsHDR10Plus: .yes), engine: .primary, p7: .available,
                  output: "SDR (tone-mapped from HDR10)", note: "This display does not support HDR10, so the picture is tone-mapped to SDR."),
        VideoCase(tag: "dv5-on-dv", format: .dolbyVision(.p5), display: dvChain, engine: .primary, p7: .available, output: "Dolby Vision", note: nil),
        VideoCase(tag: "dv5-on-non-dv", format: .dolbyVision(.p5), display: hdr10Display, engine: .primary, p7: .available,
                  output: "Display mode: unknown",
                  note: "Dolby Vision Profile 5 has no HDR10 layer, so colors can look wrong on a display without Dolby Vision."),
        VideoCase(tag: "dv81-on-dv", format: .dolbyVision(.p8_1), display: dvChain, engine: .primary, p7: .available, output: "Dolby Vision", note: nil),
        VideoCase(tag: "dv81-on-non-dv", format: .dolbyVision(.p8_1), display: hdr10Display, engine: .primary, p7: .available,
                  output: "HDR10 (Dolby Vision base layer)", note: dvNotSupported),
        VideoCase(tag: "dv82-on-non-dv", format: .dolbyVision(.p8_2), display: hdr10Display, engine: .primary, p7: .available,
                  output: "SDR (Dolby Vision base layer)", note: "This display does not support Dolby Vision, so the SDR base layer plays."),
        VideoCase(tag: "dv84-on-dv", format: .dolbyVision(.p8_4), display: dvChain, engine: .primary, p7: .available, output: "Dolby Vision", note: nil),
        VideoCase(tag: "dv84-on-hlg", format: .dolbyVision(.p8_4), display: hdr10Display, engine: .primary, p7: .available,
                  output: "HLG (Dolby Vision base layer)", note: "This display does not support Dolby Vision, so the HLG base layer plays."),
        VideoCase(tag: "dv7fel-converted", format: .dolbyVision(.p7FEL), display: dvChain, engine: .primary, p7: .available,
                  output: "Dolby Vision (converted from Profile 7)",
                  note: "Profile 7 is converted to Profile 8.1, so the extra picture detail in its full enhancement layer (FEL) is not shown and the 10-bit base layer plays with the Dolby Vision metadata."),
        VideoCase(tag: "dv7mel-converted", format: .dolbyVision(.p7MEL), display: dvChain, engine: .primary, p7: .available,
                  output: "Dolby Vision (converted from Profile 7)",
                  note: "Profile 7 is converted to Profile 8.1, and its minimal enhancement layer (MEL) holds no picture detail, so nothing is lost."),
        VideoCase(tag: "dv7-unavailable", format: .dolbyVision(.p7FEL), display: dvChain, engine: .primary, p7: .notAvailableOnDevice,
                  output: "HDR10 (base layer)",
                  note: "Dolby Vision Profile 7 conversion is not available on this device, so the HDR10 base layer plays."),
        VideoCase(tag: "dv7-failed", format: .dolbyVision(.p7MEL), display: dvChain, engine: .primary, p7: .failedForThisFile,
                  output: "HDR10 (base layer)",
                  note: "Dolby Vision Profile 7 conversion failed for this file, so the HDR10 base layer plays."),
        VideoCase(tag: "dv7-on-non-dv", format: .dolbyVision(.p7FEL), display: hdr10Display, engine: .primary, p7: .available,
                  output: "HDR10 (base layer)", note: dvNotSupported),
        VideoCase(tag: "match-range-off", format: .hdr10, display: DisplayState(availableHDR: [.hdr10], matchDynamicRange: .no),
                  engine: .primary, p7: .available, output: "Display mode: unknown",
                  note: "Match Dynamic Range is off in Apple TV settings, so the display is not switched for this file."),
        VideoCase(tag: "active-mode-differs", format: .hdr10, display: DisplayState(availableHDR: [.dolbyVision, .hdr10], activeMode: .dolbyVision),
                  engine: .primary, p7: .available, output: "Dolby Vision", note: "The display is in Dolby Vision mode, not HDR10."),
        VideoCase(tag: "fallback-hdr10", format: .hdr10, display: hdr10Display, engine: .fallback, p7: .available,
                  output: "Display mode: unknown", note: "The fallback player does not confirm which display mode is active."),
        VideoCase(tag: "fallback-dv81", format: .dolbyVision(.p8_1), display: dvChain, engine: .fallback, p7: .available,
                  output: "Display mode: unknown",
                  note: "Dolby Vision is unavailable in fallback mode, so the HDR10 base layer plays, and the fallback player does not confirm which display mode is active."),
        VideoCase(tag: "fallback-sdr", format: .sdr, display: sdrDisplay, engine: .fallback, p7: .available, output: "SDR", note: nil)
    ]

    func testVideoCases() {
        for c in Self.videoCases {
            let s = StatusRules.video(c.format, display: c.display, engine: c.engine, profile7: c.p7)
            XCTAssertEqual(s.output, c.output, "[\(c.tag)] output")
            XCTAssertEqual(s.note, c.note, "[\(c.tag)] note")
        }
    }

    func testContainsText() {
        XCTAssertEqual(HDRFormat.dolbyVision(.p8_1).containsText, "Dolby Vision Profile 8.1 (HDR10 compatible)")
        XCTAssertEqual(HDRFormat.dolbyVision(.p8_4).containsText, "Dolby Vision Profile 8.4 (HLG compatible)")
        XCTAssertEqual(HDRFormat.dolbyVision(.p8_2).containsText, "Dolby Vision Profile 8.2 (SDR compatible)")
        XCTAssertEqual(HDRFormat.dolbyVision(.p5).containsText, "Dolby Vision Profile 5")
        XCTAssertEqual(HDRFormat.dolbyVision(.p7FEL).containsText, "Dolby Vision Profile 7 (FEL)")
    }

    func testFullStatusAddsFallbackNotice() {
        let fb = StatusRules.status(track: Self.dd51, route: Self.hdmi6, format: .hdr10, display: Self.hdr10Display,
                                    engine: .fallback, profile7: .available)
        XCTAssertEqual(fb.engineNotice, "Dolby Vision and Atmos are unavailable in fallback mode.")
        let primary = StatusRules.status(track: Self.dd51, route: Self.hdmi6, format: .hdr10, display: Self.hdr10Display,
                                         engine: .primary, profile7: .available)
        XCTAssertNil(primary.engineNotice)
    }

    // MARK: Coverage of the brief's required cases

    static let requiredTags: [String] = [
        "dd", "ddplus", "atmos", "atmos-requested-route-not-atmos", "truehd-core", "truehd-nocore-71", "truehd-nocore-51-route",
        "truehd-atmos", "dts", "dtshd-71", "dtsx", "pcm-71-on-8ch", "dtshd-downmix-51", "dtshd-downmix-20", "aac-stereo",
        "flac", "pcm-stereo", "opus",
        "hdr10-on-hdr10", "hdr10-on-sdr", "hlg", "hdr10plus", "dv5-on-dv", "dv5-on-non-dv", "dv81-on-non-dv", "dv84-on-hlg",
        "dv7fel-converted", "dv7mel-converted", "dv7-unavailable", "hdr10-display-unknown", "fallback-dd", "fallback-hdr10"
    ]

    func testEveryRequiredCaseHasAnExpectation() {
        let tags = Set(Self.audioCases.map(\.tag) + Self.videoCases.map(\.tag))
        for t in Self.requiredTags { XCTAssertTrue(tags.contains(t), "no expectation for required case \(t)") }
        XCTAssertEqual(tags.count, Self.audioCases.count + Self.videoCases.count, "tags must be unique")
    }
}
