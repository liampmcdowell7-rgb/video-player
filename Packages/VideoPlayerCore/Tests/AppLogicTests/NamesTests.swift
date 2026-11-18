import XCTest
import Foundation
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

// docs/NAMES.md (user rule, 2026-11-17): real names for formats, sources and services; required notices in Settings >
// About; honest claims only. These tests read docs/NAMES.md itself (found next to this package through #filePath, or
// through VP_PROJECT_ROOT as scripts/test-core.sh sets it), so the allowlist the lint uses and the texts the app shows
// cannot drift apart.

final class NamesTests: XCTestCase {
    // MARK: The allowlist file

    private func namesFile() throws -> String {
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["VP_PROJECT_ROOT"], !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent("docs/NAMES.md"))
        }
        // Tests/AppLogicTests/<this file> -> package root -> Packages -> project root
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(projectRoot.appendingPathComponent("docs/NAMES.md"))
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        #if os(Linux)
        XCTFail("docs/NAMES.md not found (tried \(candidates.map(\.path))). Set VP_PROJECT_ROOT to the project folder.")
        return ""
        #else
        // In a tvOS Simulator run the checkout may not be readable (xcodebuild passes only TEST_RUNNER_-prefixed
        // variables to the tests, so CI sets TEST_RUNNER_VP_PROJECT_ROOT). Reported as skipped, never as passed.
        throw XCTSkip("docs/NAMES.md is not readable from this test host (tried \(candidates.map(\.path))).")
        #endif
    }

    /// The entries of one fenced block (```names-allowlist or ```names-generic), as the lint reads them.
    private func block(_ name: String, in text: String) -> Set<String> {
        var inside = false, out: Set<String> = []
        for raw in text.replacingOccurrences(of: "\r", with: "").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("```") {
                if inside { inside = false; continue }
                if line == "```" + name { inside = true }
                continue
            }
            let t = line.trimmingCharacters(in: .whitespaces)
            if inside, !t.isEmpty, !t.hasPrefix("#") { out.insert(t) }
        }
        return out
    }

    func testTheAllowlistHasEveryGroupTheRuleNames() throws {
        let allow = block("names-allowlist", in: try namesFile())
        // One representative per group of the user's rule, plus the names the old rule had replaced with generic words.
        for name in ["Dolby Vision", "HDR10+", "HLG", "HEVC", "H.264", "AV1", "VP9",
                     "Dolby Atmos", "Dolby TrueHD", "DTS-HD Master Audio", "DTS:X", "AAC", "FLAC", "Opus", "Vorbis", "PCM",
                     "SubRip", "WebVTT", "PGS", "WebDAV", "SMB", "NFS", "SFTP", "FTPS", "UPnP/DLNA", "Jellyfin", "Emby", "Plex",
                     "OneDrive", "iCloud Drive", "TMDB", "OMDb", "IMDb", "Rotten Tomatoes", "Metacritic", "JustWatch",
                     "AirPlay", "Siri Remote", "iCloud", "Apple TV", "Top Shelf", "HDMI"] {
            XCTAssertTrue(allow.contains(name), "\(name) missing from the names-allowlist block")
        }
        XCTAssertGreaterThan(block("names-generic", in: try namesFile()).count, 20)
    }

    func testEverySourceTypeTitleIsAnAllowlistedRealName() throws {
        let text = try namesFile()
        let allowed = block("names-allowlist", in: text).union(block("names-generic", in: text))
        for info in SourceCatalog.catalog() {
            XCTAssertTrue(allowed.contains(info.title), "source type title \(info.title) is not in docs/NAMES.md")
        }
    }

    func testTheFormatNamesTheDetailPageShowsAreAllowlisted() throws {
        let allow = block("names-allowlist", in: try namesFile())
        let shown = [FormatNames.videoCodec("hevc"), FormatNames.videoCodec("x264"), FormatNames.videoCodec("av1"),
                     FormatNames.audioCodec("TrueHD"), FormatNames.audioCodec("DD+"), FormatNames.audioCodec("eac3"),
                     FormatNames.audioCodec("DD"), FormatNames.audioCodec("dts-hd ma"), FormatNames.audioCodec("DTS:X"),
                     FormatNames.audioCodec("Atmos"), FormatNames.audioCodec("opus"), FormatNames.audioCodec("vorbis")]
        for name in shown { XCTAssertTrue(allow.contains(name), "\(name) is shown but not allowlisted") }
    }

    // MARK: Format names on the detail page

    func testVideoCodecsGetTheirRealNames() {
        XCTAssertEqual(FormatNames.videoCodec("hevc"), "HEVC")
        XCTAssertEqual(FormatNames.videoCodec("x265"), "HEVC")
        XCTAssertEqual(FormatNames.videoCodec("h264"), "H.264")
        XCTAssertEqual(FormatNames.videoCodec("H.264"), "H.264")
        XCTAssertEqual(FormatNames.videoCodec("av1"), "AV1")
        XCTAssertEqual(FormatNames.videoCodec("vp9"), "VP9")
        XCTAssertEqual(FormatNames.videoCodec("Something New"), "Something New", "unknown text passes through, nothing guessed")
    }

    func testHDRNamesDolbyVisionFirstWithTheProfileAndTheFallbackLayer() {
        XCTAssertEqual(FormatNames.hdr([.dolbyVision, .hdr10], dolbyVisionProfile: 8), "Dolby Vision Profile 8 / HDR10")
        XCTAssertEqual(FormatNames.hdr([.dolbyVision], dolbyVisionProfile: nil), "Dolby Vision")
        XCTAssertEqual(FormatNames.hdr([.hdr10Plus, .hdr10], dolbyVisionProfile: nil), "HDR10+ / HDR10")
        XCTAssertEqual(FormatNames.hdr([.hlg], dolbyVisionProfile: nil), "HLG")
        XCTAssertNil(FormatNames.hdr([], dolbyVisionProfile: nil))
        XCTAssertNil(FormatNames.hdr([.sdr], dolbyVisionProfile: nil), "SDR is not an HDR format and gets no label")
    }

    func testAudioNamesCarryTheCodecTheLayoutAndAtmosOnlyWhereItCanBe() {
        XCTAssertEqual(FormatNames.audio(codec: "TrueHD", channels: 8, atmos: true), "Dolby TrueHD with Dolby Atmos 7.1")
        XCTAssertEqual(FormatNames.audio(codec: "DD+", channels: 6, atmos: false), "Dolby Digital Plus 5.1")
        XCTAssertEqual(FormatNames.audio(codec: "eac3", channels: 6, atmos: true), "Dolby Digital Plus with Dolby Atmos 5.1")
        XCTAssertEqual(FormatNames.audio(codec: "dts-hd ma", channels: 8, atmos: false), "DTS-HD Master Audio 7.1")
        XCTAssertEqual(FormatNames.audio(codec: "Atmos", channels: nil, atmos: true), "Dolby Atmos",
                       "a bare Atmos tag does not invent the codec")
        XCTAssertEqual(FormatNames.audio(codec: "AAC", channels: 2, atmos: false), "AAC Stereo")
        XCTAssertEqual(FormatNames.audio(codec: "DTS", channels: 6, atmos: true), "DTS 5.1",
                       "Atmos is never claimed for a codec that cannot carry it")
        XCTAssertEqual(FormatNames.audio(codec: nil, channels: 6, atmos: false), "5.1")
        XCTAssertNil(FormatNames.audio(codec: nil, channels: nil, atmos: false))
        XCTAssertEqual(FormatNames.audioCodec("DD"), "Dolby Digital")
        XCTAssertEqual(FormatNames.audioCodec("DD+"), "Dolby Digital Plus", "the + is not lost")
    }

    func testTheBadgesAndFilterChipsSayDolbyAtmosInFull() {
        XCTAssertEqual(FilterOption.atmos.title, "Dolby Atmos")
    }

    // MARK: Settings > About

    func testTheTrademarkLinesFollowTheOwnersPublishedNotices() {
        // Dolby's site footer (dolby.com, read 2026-11-17): "... are trademarks or registered trademarks of Dolby
        // Laboratories Licensing Corporation or its affiliates."
        XCTAssertTrue(TrademarkNotices.dolby.hasSuffix("are trademarks or registered trademarks of Dolby Laboratories Licensing Corporation or its affiliates."))
        XCTAssertTrue(TrademarkNotices.dolby.contains("the double-D symbol"))
        // Xperi media kit: "... are trademark(s) or registered trademark(s) of Xperi Inc. or its subsidiaries in the United
        // States and other countries."
        XCTAssertTrue(TrademarkNotices.dts.hasSuffix("of Xperi Inc. or its subsidiaries in the United States and other countries."))
        // Apple's form for distribution outside the U.S., with no trademark symbols.
        XCTAssertTrue(TrademarkNotices.apple.hasSuffix("are trademarks of Apple Inc., registered in the U.S. and other countries and regions."))
        // HDMI Licensing Administrator's brand page, word for word.
        XCTAssertEqual(TrademarkNotices.hdmi, "The terms HDMI, HDMI High-Definition Multimedia Interface, HDMI Trade Dress and the HDMI Logos are trademarks or registered trademarks of HDMI Licensing Administrator, Inc.")
        XCTAssertTrue(TrademarkNotices.microsoft.hasSuffix("are trademarks of the Microsoft group of companies."))
        for line in TrademarkNotices.lines {
            XCTAssertFalse(line.contains("™") || line.contains("®"), "no trademark symbols outside U.S.-only material: \(line)")
        }
    }

    func testTheNotAffiliatedSentenceIsFirstAndClaimsNoCertification() {
        XCTAssertEqual(TrademarkNotices.lines.first, TrademarkNotices.notAffiliated)
        XCTAssertTrue(TrademarkNotices.notAffiliated.contains("not affiliated with, endorsed by, sponsored by or certified by"))
        XCTAssertTrue(TrademarkNotices.notAffiliated.contains("does not mean that this app or your equipment is certified"))
        XCTAssertEqual(Set(TrademarkNotices.lines).count, TrademarkNotices.lines.count)
    }

    func testEveryNameTheTrademarkLinesAcknowledgeIsAllowlisted() throws {
        let allow = block("names-allowlist", in: try namesFile())
        for name in ["Dolby Vision", "Dolby Atmos", "Dolby Digital Plus", "Dolby TrueHD", "DTS-HD Master Audio", "DTS:X",
                     "Apple TV", "AirPlay", "HomePod", "iCloud Drive", "Siri Remote", "HDMI", "OneDrive", "Windows",
                     "HDR10+", "AV1", "Plex", "Jellyfin", "Emby", "TMDB", "OMDb", "IMDb", "Rotten Tomatoes", "Metacritic",
                     "JustWatch", "Bluetooth"] {
            XCTAssertTrue(TrademarkNotices.lines.contains { $0.contains(name) }, "\(name) has no acknowledgement")
            XCTAssertTrue(allow.contains(name), "\(name) is acknowledged but not allowlisted")
        }
    }

    func testEveryLicenceNoticeIsComplete() {
        XCTAssertFalse(LicenseNotices.all.isEmpty)
        XCTAssertEqual(Set(LicenseNotices.all.map(\.name)).count, LicenseNotices.all.count)
        for n in LicenseNotices.all {
            XCTAssertFalse(n.license.isEmpty || n.copyright.isEmpty || n.use.isEmpty, n.name)
        }
        XCTAssertTrue(LicenseNotices.all.contains { $0.name.hasPrefix("FFmpeg") && $0.license.hasPrefix("LGPL-2.1") })
        XCTAssertTrue(LicenseNotices.all.contains { $0.name == "libdovi" && $0.license == "MIT" })
        // The full texts are bundled now (R149); the intro points to them and the texts list is not empty.
        XCTAssertTrue(LicenseNotices.intro.contains("Full Licence Texts"), "the intro points to the bundled full texts")
        XCTAssertFalse(LicenseNotices.texts.isEmpty)
    }
}
