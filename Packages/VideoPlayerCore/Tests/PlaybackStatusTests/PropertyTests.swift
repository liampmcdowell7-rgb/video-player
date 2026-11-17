import XCTest
@testable import PlaybackStatus

/// Rules that must hold for EVERY row of the generated table (the honesty guarantees).
final class PropertyTests: XCTestCase {

    func testTableSizes() {
        XCTAssertEqual(StatusTable.audioRows().count, 2 * 14 * 7 + 2 * 5 * 7)
        // + 2 x 8: HDR10+ rows by Apple TV model (sends HDR10+ / does not), appended after the others.
        XCTAssertEqual(StatusTable.videoRows().count, 112 + 80 + 2 * 8)
    }

    func testAudioNeverClaimsWhatIsNotInUse() {
        for r in StatusTable.audioRows() {
            let out = r.status.output
            let tag = "\(r.id) \(r.track.kind) on \(r.routeName) [\(r.engine)]"

            // Atmos is named only when the file has it, the player is the primary one and the route reports Atmos.
            if out.contains("Atmos") {
                XCTAssertTrue(r.engine == .primary && r.track.kind == .eac3 && r.track.hasAtmos
                              && r.route.atmos == .yes && r.route.passesDolbyBitstream != .no, "Atmos claimed: \(tag)")
            }
            // The fallback player never passes anything through.
            if r.engine == .fallback {
                XCTAssertFalse(out.contains("passthrough"), "fallback passthrough: \(tag)")
                XCTAssertTrue(r.status.path == .decodedByFallback || r.status.path == .pcm, tag)
            }
            // TrueHD (unless the compatibility core is chosen) and all DTS are never passed through.
            if (r.track.kind == .trueHD && !(r.track.hasAC3Core && r.track.usesCompatibilityCore))
                || [.dts, .dtsHDMA, .dtsX, .dtsHDHRA].contains(r.track.kind) {
                XCTAssertFalse(out.contains("passthrough"), "passthrough claimed: \(tag)")
                XCTAssertFalse(out.contains("TrueHD") || out.contains("DTS"), "codec named in decoded output: \(tag)")
            }
            // TrueHD Atmos is never claimed: the decoded path names the bed.
            if r.track.kind == .trueHD && r.track.hasAtmos && r.engine == .primary && !r.track.usesCompatibilityCore {
                XCTAssertTrue(r.status.note?.contains("only the 7.1 bed") == true, "TrueHD Atmos bed not said: \(tag)")
            }
            // TrueHD with the compatibility core chosen is shown as the Dolby Digital core, not as TrueHD.
            if r.track.kind == .trueHD && r.track.hasAC3Core && r.track.usesCompatibilityCore && r.engine == .primary
                && r.route.passesDolbyBitstream != .no {
                XCTAssertTrue(out.hasPrefix("Dolby Digital "), tag)
                XCTAssertFalse(out.hasPrefix("Dolby TrueHD"), tag)
            }
            // Channels never exceed what the route accepts, nor 8.
            if let ch = r.status.outputChannels {
                XCTAssertLessThanOrEqual(ch, 8, tag)
                if let m = r.route.maxChannels, r.status.path != .passthrough, r.status.path != .ac3CorePassthrough {
                    XCTAssertLessThanOrEqual(ch, m, "channels over route limit: \(tag)")
                }
            }
            // Downmix is always said out loud.
            if let ch = r.status.outputChannels, ch < r.track.channels, r.status.path != .passthrough, r.status.path != .ac3CorePassthrough {
                XCTAssertTrue(out.contains("downmixed from"), "silent downmix: \(tag)")
            }
            // Notes are one plain sentence.
            if let n = r.status.note {
                XCTAssertTrue(n.hasSuffix("."), tag)
                XCTAssertEqual(n.components(separatedBy: ". ").count, 1, "more than one sentence: \(tag): \(n)")
            }
            // An unavailable Atmos or object format always has a reason.
            if (r.track.hasAtmos || r.track.kind == .dtsX) && !out.contains("Dolby Atmos") {
                XCTAssertNotNil(r.status.note, "Atmos/DTS:X missing without a reason: \(tag)")
            }
        }
    }

    func testVideoNeverClaimsWhatIsNotInUse() {
        for r in StatusTable.videoRows() {
            let out = r.status.output
            let tag = "\(r.id) \(r.format) on \(r.displayName) [\(r.engine)]"
            let caps = r.display.availableHDR

            if r.engine == .fallback {
                XCTAssertFalse(out.contains("Dolby Vision") && r.display.activeMode != .dolbyVision, "fallback DV: \(tag)")
            }
            // An HDR mode is named only if the display supports it or the display says it is in it.
            if out.hasPrefix("Dolby Vision") {
                XCTAssertTrue(caps?.contains(.dolbyVision) == true || r.display.activeMode == .dolbyVision, "DV claimed: \(tag)")
            }
            if out.hasPrefix("HDR10") {
                XCTAssertTrue(caps?.contains(.hdr10) == true || r.display.activeMode == .hdr10, "HDR10 claimed: \(tag)")
            }
            if out.hasPrefix("HLG") {
                XCTAssertTrue(caps?.contains(.hlg) == true || r.display.activeMode == .hlg, "HLG claimed: \(tag)")
            }
            // Unknown display and no active mode: never a guess (SDR files and fallback SDR are the only exceptions).
            if caps == nil && r.display.activeMode == nil && r.format != .sdr && !(r.engine == .fallback && r.format == .dolbyVision(.p8_2)) {
                XCTAssertEqual(out, "Display mode: unknown", tag)
                XCTAssertNil(r.status.mode, tag)
            }
            // Profile 7 is only "converted" when conversion is available, DV is supported and the primary player is used.
            if out.contains("converted from Profile 7") {
                XCTAssertTrue(r.engine == .primary && r.profile7 == .available && caps?.contains(.dolbyVision) == true, tag)
            }
            // Every difference from the file has a reason, unless it is plain SDR / matching passthrough.
            if out.contains("base layer") || out.contains("tone-mapped") || out == "Display mode: unknown" {
                XCTAssertNotNil(r.status.note, "no reason: \(tag)")
            }
            if let n = r.status.note {
                XCTAssertTrue(n.hasSuffix("."), tag)
                XCTAssertEqual(n.components(separatedBy: ". ").count, 1, "more than one sentence: \(tag): \(n)")
            }
        }
    }

    func testFallbackAlwaysCarriesTheNotice() {
        for engine in PlaybackEngine.allCases {
            let s = StatusRules.status(track: AudioTrackContent(kind: .ac3, channels: 6), route: .unknown,
                                       format: .sdr, display: .unknown, engine: engine, profile7: .available)
            XCTAssertEqual(s.engineNotice != nil, engine == .fallback)
        }
    }

    func testRouteClassifier() {
        let arc = RouteClassifier.classify(kind: .hdmi, maxChannels: 2, atmosRenderingReported: nil)
        XCTAssertEqual(arc.passesDolbyBitstream, .unknown, "2 channels over HDMI is not proof that Dolby is refused")
        XCTAssertEqual(arc.atmos, .unknown)
        let avr = RouteClassifier.classify(kind: .hdmi, maxChannels: 8, atmosRenderingReported: true)
        XCTAssertEqual(avr.passesDolbyBitstream, .yes)
        XCTAssertEqual(avr.atmos, .yes)
        let avrNoAtmos = RouteClassifier.classify(kind: .hdmi, maxChannels: 8, atmosRenderingReported: nil)
        XCTAssertEqual(avrNoAtmos.atmos, .unknown, "no report must not become yes")
        let bt = RouteClassifier.classify(kind: .bluetooth, maxChannels: nil, atmosRenderingReported: nil)
        XCTAssertEqual(bt.maxChannels, 2)
        XCTAssertEqual(bt.passesDolbyBitstream, .no)
        XCTAssertEqual(bt.atmos, .no)
        let unknown = RouteClassifier.classify(kind: .unknown, maxChannels: nil, atmosRenderingReported: nil)
        XCTAssertEqual(unknown, AudioRoute.unknown)
    }
}
