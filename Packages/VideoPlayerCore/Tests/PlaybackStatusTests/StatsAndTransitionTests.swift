import XCTest
@testable import PlaybackStatus

final class StatsOverlayTests: XCTestCase {

    func testFrameRates() {
        XCTAssertEqual(StatsOverlay.frameRateText(24000.0 / 1001.0), "23.976 fps")
        XCTAssertEqual(StatsOverlay.frameRateText(24), "24 fps")
        XCTAssertEqual(StatsOverlay.frameRateText(25), "25 fps")
        XCTAssertEqual(StatsOverlay.frameRateText(30000.0 / 1001.0), "29.97 fps")
        XCTAssertEqual(StatsOverlay.frameRateText(60000.0 / 1001.0), "59.94 fps")
        XCTAssertEqual(StatsOverlay.frameRateText(120000.0 / 1001.0), "119.88 fps")
        XCTAssertEqual(StatsOverlay.frameRateText(50), "50 fps")
    }

    func testBitrates() {
        XCTAssertEqual(StatsOverlay.bitrateText(45_200_000), "45.2 Mbps")
        XCTAssertEqual(StatsOverlay.bitrateText(1_000_000), "1.0 Mbps")
        XCTAssertEqual(StatsOverlay.bitrateText(640_000), "640 kbps")
        XCTAssertEqual(StatsOverlay.bitrateText(999), "999 bps")
        XCTAssertEqual(StatsOverlay.bitrateText(1_250_000_000), "1250.0 Mbps")
    }

    func testOtherFormats() {
        XCTAssertEqual(StatsOverlay.resolutionText(width: 3840, height: 2160), "3840 × 2160")
        XCTAssertEqual(StatsOverlay.bufferText(12.44), "12.4 s")
        XCTAssertEqual(StatsOverlay.droppedText(dropped: 12, total: 15000), "12 of 15000 frames (0.08%)")
        XCTAssertEqual(StatsOverlay.droppedText(dropped: 0, total: 0), "0 frames")
        XCTAssertEqual(StatsOverlay.fixed(0.05, places: 1), "0.1")
        XCTAssertEqual(StatsOverlay.fixed(-0.04, places: 1), "0.0")
    }

    func testEveryStatIsShownEvenWhenNothingIsKnown() {
        let rows = StatsOverlay.rows(PlaybackStatsSnapshot())
        XCTAssertEqual(rows.map(\.label), [
            "Resolution", "Frame rate", "Video codec", "Profile and level", "HDR format", "Bitrate (live)", "Bitrate (average)",
            "Audio codec", "Audio channels", "Audio output", "Network throughput", "Buffer health", "Dropped frames", "Decode path",
            "Container", "Pixel format", "Color primaries", "Transfer function", "Player"
        ])
        for r in rows where r.label != "Player" {
            XCTAssertEqual(r.value, "—", r.label)
            XCTAssertEqual(r.tone, .unavailable, r.label)
        }
        XCTAssertEqual(rows.last?.value, "Primary player")
    }

    func testFullSnapshot() {
        let track = AudioTrackContent(kind: .eac3, channels: 8, hasAtmos: true)
        let route = AudioRoute(kind: .hdmi, maxChannels: 8, passesDolbyBitstream: .yes, atmos: .yes)
        let status = StatusRules.status(track: track, route: route, format: .dolbyVision(.p8_1),
                                        display: DisplayState(availableHDR: [.dolbyVision, .hdr10]), engine: .primary, profile7: .available)
        let snap = PlaybackStatsSnapshot(width: 3840, height: 2160, frameRate: 24000.0 / 1001.0, videoCodec: "HEVC",
                                         videoProfile: "Main 10", videoLevel: "5.1", hdr: .dolbyVision(.p8_1),
                                         liveBitrate: 48_300_000, averageBitrate: 45_200_000, audio: track,
                                         throughput: 90_000_000, bufferSeconds: 28.0, droppedFrames: 0, totalFrames: 5000,
                                         decodePath: .remux, container: "Matroska", pixelFormat: "yuv420p10le",
                                         colorPrimaries: "BT.2020", transferFunction: "PQ")
        let rows = StatsOverlay.rows(snap, status: status)
        func value(_ l: String) -> String? { rows.first { $0.label == l }?.value }
        XCTAssertEqual(value("Resolution"), "3840 × 2160")
        XCTAssertEqual(value("Frame rate"), "23.976 fps")
        XCTAssertEqual(value("Profile and level"), "Main 10, level 5.1")
        XCTAssertEqual(value("HDR format"), "Dolby Vision Profile 8.1 (HDR10 compatible)")
        XCTAssertEqual(value("Bitrate (live)"), "48.3 Mbps")
        XCTAssertEqual(value("Audio codec"), "Dolby Digital Plus with Atmos 7.1")
        XCTAssertEqual(value("Audio channels"), "7.1")
        XCTAssertEqual(value("Audio output"), "Dolby Atmos (passthrough)")
        XCTAssertEqual(value("Decode path"), "Remux (Apple player)")
        XCTAssertEqual(value("Dropped frames"), "0 of 5000 frames (0.00%)")
        XCTAssertTrue(rows.allSatisfy { $0.tone == .normal })
        XCTAssertFalse(rows.contains { $0.value.contains("/") }, "no file path in the overlay")
    }

    func testWarnings() {
        let slow = StatsOverlay.rows(PlaybackStatsSnapshot(liveBitrate: 50_000_000, throughput: 20_000_000, bufferSeconds: 3, droppedFrames: 100, totalFrames: 10000))
        XCTAssertEqual(slow.first { $0.label == "Network throughput" }?.tone, .warning)
        XCTAssertEqual(slow.first { $0.label == "Buffer health" }?.tone, .warning)
        XCTAssertEqual(slow.first { $0.label == "Dropped frames" }?.tone, .warning)
        let fine = StatsOverlay.rows(PlaybackStatsSnapshot(liveBitrate: 20_000_000, throughput: 50_000_000, bufferSeconds: 20, droppedFrames: 1, totalFrames: 10000))
        XCTAssertEqual(fine.first { $0.label == "Network throughput" }?.tone, .normal)
        XCTAssertEqual(fine.first { $0.label == "Buffer health" }?.tone, .normal)
        XCTAssertEqual(fine.first { $0.label == "Dropped frames" }?.tone, .normal)
    }

    func testBadNumbersBecomeMissing() {
        let rows = StatsOverlay.rows(PlaybackStatsSnapshot(width: 0, height: 0, frameRate: .nan, liveBitrate: -5, bufferSeconds: .infinity))
        for l in ["Resolution", "Frame rate", "Bitrate (live)", "Buffer health"] {
            XCTAssertEqual(rows.first { $0.label == l }?.value, "—", l)
        }
    }

    func testStatusLines() {
        let status = StatusRules.status(track: AudioTrackContent(kind: .trueHD, channels: 8), route: AudioRoute(kind: .hdmi, maxChannels: 6, passesDolbyBitstream: .yes, atmos: .no),
                                        format: .hdr10, display: DisplayState(availableHDR: []), engine: .fallback, profile7: .available)
        let lines = StatsOverlay.statusLines(status)
        XCTAssertEqual(lines.first, "Audio: 5.1 PCM (decoded, downmixed from 7.1)")
        XCTAssertTrue(lines.contains("Video: Display mode: unknown"))
        XCTAssertEqual(lines.last, "Dolby Vision and Atmos are unavailable in fallback mode.")
    }
}

final class TransitionTests: XCTestCase {
    let dv: DisplayHDRModes = [.dolbyVision, .hdr10, .hlg]
    let hdr: DisplayHDRModes = [.hdr10, .hlg]

    func traits(_ f: HDRFormat, _ fps: Double? = 24000.0 / 1001.0, _ p7: Profile7Conversion = .available) -> EpisodeVideoTraits {
        EpisodeVideoTraits(format: f, frameRate: fps, profile7: p7)
    }

    func testSameFormatKeepsMode() {
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10), to: traits(.hdr10), availableHDR: hdr), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.dolbyVision(.p8_1)), to: traits(.dolbyVision(.p8_1)), availableHDR: dv), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.sdr), to: traits(.sdr), availableHDR: nil), .keep)
    }

    func testDifferentFormatSameResultingModeKeeps() {
        // HDR10 and HDR10+ both end in HDR10; DV 8.1 on an HDR10-only display ends in HDR10 too.
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10), to: traits(.hdr10Plus), availableHDR: hdr), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10), to: traits(.dolbyVision(.p8_1)), availableHDR: hdr), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.dolbyVision(.p7FEL)), to: traits(.dolbyVision(.p7MEL)), availableHDR: dv), .keep)
    }

    func testDynamicRangeChange() {
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10), to: traits(.dolbyVision(.p8_1)), availableHDR: dv), .change(.dynamicRange))
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.sdr), to: traits(.hdr10), availableHDR: hdr), .change(.dynamicRange))
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hlg), to: traits(.hdr10), availableHDR: hdr), .change(.dynamicRange))
    }

    func testProfile7UnconvertedPlaysHDR10() {
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.dolbyVision(.p7FEL), 24, .notAvailableOnDevice), to: traits(.hdr10, 24), availableHDR: dv), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.dolbyVision(.p7FEL), 24, .available), to: traits(.hdr10, 24), availableHDR: dv), .change(.dynamicRange))
    }

    func testFrameRateChange() {
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10, 23.976), to: traits(.hdr10, 25), availableHDR: hdr), .change(.frameRate))
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10, 23.976), to: traits(.hdr10, 23.976023976), availableHDR: hdr), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10, 23.976), to: traits(.hdr10, 25), availableHDR: hdr, matchFrameRate: false), .keep)
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10, nil), to: traits(.hdr10, 25), availableHDR: hdr), .keep)
    }

    func testMatchDynamicRangeOffIgnoresFormatChange() {
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10), to: traits(.dolbyVision(.p8_1)), availableHDR: dv, matchDynamicRange: false), .keep)
    }

    func testUnknownDisplayWithDifferentFormats() {
        XCTAssertEqual(Transitions.displayModeChange(from: traits(.hdr10), to: traits(.hlg), availableHDR: nil), .change(.displayUnknown))
    }

    // MARK: Next episode preparation

    func testPreparesAtCredits() {
        var p = NextEpisodePreparer(duration: 3000, creditsStart: 2850, hasNextEpisode: true)
        XCTAssertEqual(p.triggerPosition, 2850)
        XCTAssertEqual(p.update(position: 100), .none)
        XCTAssertEqual(p.update(position: 2849.9), .none)
        XCTAssertEqual(p.update(position: 2850), .startPreparing)
        XCTAssertEqual(p.phase, .preparing)
        XCTAssertEqual(p.update(position: 2900), .none, "starts only once")
        p.finishedPreparing()
        XCTAssertEqual(p.phase, .ready)
        XCTAssertEqual(p.update(position: 100), .none, "seeking back does not prepare again")
    }

    func testFallbackLeadWhenCreditsUnknown() {
        var p = NextEpisodePreparer(duration: 3000, creditsStart: nil, hasNextEpisode: true)
        XCTAssertEqual(p.triggerPosition, 2970)
        XCTAssertEqual(p.update(position: 2969), .none)
        XCTAssertEqual(p.update(position: 2971), .startPreparing)
    }

    func testNoNextEpisodeOrBadDuration() {
        var none = NextEpisodePreparer(duration: 3000, creditsStart: 2850, hasNextEpisode: false)
        XCTAssertNil(none.triggerPosition)
        XCTAssertEqual(none.update(position: 2999), .none)
        var bad = NextEpisodePreparer(duration: 0, creditsStart: nil, hasNextEpisode: true)
        XCTAssertNil(bad.triggerPosition)
        XCTAssertEqual(bad.update(position: 10), .none)
        let weird = NextEpisodePreparer(duration: 100, creditsStart: 500, hasNextEpisode: true)
        XCTAssertEqual(weird.triggerPosition, 70, "credits after the end are ignored")
        let short = NextEpisodePreparer(duration: 20, creditsStart: nil, hasNextEpisode: true)
        XCTAssertEqual(short.triggerPosition, 0)
    }

    func testCancelAllowsAgain() {
        var p = NextEpisodePreparer(duration: 100, creditsStart: 50, hasNextEpisode: true)
        XCTAssertEqual(p.update(position: 60), .startPreparing)
        p.cancel()
        XCTAssertEqual(p.update(position: 61), .startPreparing)
    }
}
