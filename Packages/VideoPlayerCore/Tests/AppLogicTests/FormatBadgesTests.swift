import XCTest
@testable import AppLogic
import LibraryIndex

// R370 (owner's decision of 21 Nov 2026): every format the app detects maps to exactly one drawn badge, in one group.
final class FormatBadgesTests: XCTestCase {
    /// Every value of every detected kind gives one badge (or none where the owner's list says nothing: SDR, an unknown
    /// container, an unknown codec), and every badge text belongs to exactly one group.
    func testEveryDetectedFormatMapsToExactlyOneBadgeInOneGroup() {
        var seen: [String: FormatBadgeGroup] = [:]
        func record(_ badge: FormatBadgeItem?, _ group: FormatBadgeGroup, _ what: String) {
            guard let badge else { return }
            XCTAssertEqual(badge.group, group, what)
            XCTAssertFalse(badge.text.isEmpty, what)
            if let earlier = seen[badge.text] { XCTAssertEqual(earlier, group, "\(badge.text) is in two groups") }
            seen[badge.text] = group
        }
        for r in [ResolutionClass.sd, .hd720, .hd1080, .uhd4k] { record(FormatBadges.resolution(r), .resolution, "\(r)") }
        for h in [HDRFormat.hdr10, .hdr10Plus, .hlg, .dolbyVision] {
            XCTAssertNotNil(FormatBadges.hdr(h), "\(h)")
            record(FormatBadges.hdr(h), .hdr, "\(h)")
        }
        XCTAssertNil(FormatBadges.hdr(.sdr), "SDR shows nothing")
        XCTAssertNil(FormatBadges.hdr(Set([HDRFormat.sdr])))
        let audio = ["truehd", "mlp", "eac3", "ac3", "dts", "dts-hd ma", "dts-hd hra", "dtshd", "dtsx", "dts-es", "aac", "he-aac",
                     "flac", "pcm", "alac", "opus", "vorbis", "mp3", "atmos"]
        for a in audio {
            XCTAssertNotNil(FormatBadges.audio(codec: a, atmos: false), "audio \(a): every codec name the app knows has a badge")
            record(FormatBadges.audio(codec: a, atmos: false), .audio, a)
        }
        for n in 1...8 {
            XCTAssertNotNil(FormatBadges.channels(n))
            record(FormatBadges.channels(n), .channels, "\(n) channels")
        }
        let video = ["hevc", "h264", "av1", "vp9", "vp8", "mpeg2video", "mpeg4", "vc1", "xvid", "divx"]
        for v in video {
            XCTAssertNotNil(FormatBadges.videoCodec(v), "video \(v): every codec name the app knows has a badge")
            record(FormatBadges.videoCodec(v), .videoCodec, v)
        }
        for c in [ContainerFormat.mkv, .mp4, .m4v, .mov, .ts, .avi, .wmv, .webm] {
            XCTAssertNotNil(FormatBadges.container(c), "\(c)")
            record(FormatBadges.container(c), .container, "\(c)")
        }
        record(FormatBadges.container(.ts, fileExtension: "m2ts"), .container, "m2ts")
        XCTAssertNil(FormatBadges.container(.other))
        XCTAssertNil(FormatBadges.audio(codec: "something new", atmos: false), "an unknown codec is not guessed into a badge")
        XCTAssertNil(FormatBadges.videoCodec("something new"))
        XCTAssertNil(FormatBadges.channels(0))
        XCTAssertNil(FormatBadges.channels(nil))
    }

    /// Every name on the owner's list is reachable from a detected format.
    func testEveryNameOnTheOwnersListIsReachable() {
        var texts = Set<String>()
        for r in [ResolutionClass.sd, .hd720, .hd1080, .uhd4k] { texts.insert(FormatBadges.resolution(r).text) }
        for h in [HDRFormat.hdr10, .hdr10Plus, .hlg, .dolbyVision] { texts.formUnion([FormatBadges.hdr(h)?.text].compactMap { $0 }) }
        texts.insert(FormatBadges.audio(codec: nil, atmos: true)!.text)
        for a in ["truehd", "eac3", "ac3", "dtsx", "dts-hd ma", "dts", "aac", "flac", "pcm"] {
            texts.formUnion([FormatBadges.audio(codec: a, atmos: false)?.text].compactMap { $0 })
        }
        for n in [8, 6, 2] { texts.formUnion([FormatBadges.channels(n)?.text].compactMap { $0 }) }
        for v in ["hevc", "h264", "av1", "vp9", "mpeg2video", "vc1"] { texts.formUnion([FormatBadges.videoCodec(v)?.text].compactMap { $0 }) }
        for c in [ContainerFormat.mkv, .mp4, .mov, .avi] { texts.formUnion([FormatBadges.container(c)?.text].compactMap { $0 }) }
        texts.formUnion([FormatBadges.container(.ts, fileExtension: "m2ts")?.text].compactMap { $0 })
        let owners = ["4K", "1080p", "720p", "SD", "Dolby Vision", "HDR10", "HDR10+", "HLG",
                      "Dolby Atmos", "Dolby TrueHD", "Dolby Digital Plus", "Dolby Digital", "DTS:X", "DTS-HD MA", "DTS", "AAC", "FLAC", "PCM",
                      "7.1", "5.1", "Stereo", "HEVC", "H.264", "AV1", "VP9", "MPEG-2", "VC-1", "MKV", "MP4", "MOV", "AVI", "M2TS"]
        for name in owners { XCTAssertTrue(texts.contains(name), "\(name) is on the owner's list but no detected format gives it") }
    }

    func testAFilesFullSetIsInTheOwnersOrderAndTheHeadlineIsTheFirstThreeGroups() {
        let t = FileTechnicalInfo(container: .mkv, width: 3840, height: 2160, hdrFormats: [.dolbyVision, .hdr10], dolbyVisionProfile: 8,
                                  videoCodec: "hevc", audioCodec: "truehd", audioChannels: 8, hasAtmos: true)
        let all = FormatBadges.all(technical: t, fileExtension: "mkv")
        XCTAssertEqual(all.map(\.text), ["4K", "Dolby Vision", "Dolby Atmos", "7.1", "HEVC", "MKV"])
        XCTAssertEqual(all.map(\.group), [.resolution, .hdr, .audio, .channels, .videoCodec, .container])
        XCTAssertEqual(FormatBadges.headline(all).map(\.text), ["4K", "Dolby Vision", "Dolby Atmos"])
        let plain = FileTechnicalInfo(container: .ts, height: 1080, videoCodec: "h264", audioCodec: "aac", audioChannels: 2, hasAtmos: false)
        XCTAssertEqual(FormatBadges.all(technical: plain, fileExtension: "M2TS").map(\.text), ["1080p", "AAC", "Stereo", "H.264", "M2TS"])
        XCTAssertEqual(FormatBadges.all(technical: plain, fileExtension: "ts").last?.text, "MPEG-TS")
    }

    /// Each group names an Information row that exists for a file with every fact, so a badge dropped from a line is never lost.
    func testEveryBadgeGroupHasItsInformationRow() {
        let t = FileTechnicalInfo(container: .mkv, width: 3840, height: 2160, hdrFormats: [.hdr10], videoCodec: "hevc",
                                  audioCodec: "eac3", audioChannels: 6, hasAtmos: false)
        let rows = MediaInfo.rows(technical: t, size: 1, path: "/a.mkv", subtitleNames: [], sourceName: nil)
        for badge in FormatBadges.all(technical: t) {
            let row = rows.first { $0.label == badge.group.informationRow || $0.label.hasPrefix(badge.group.informationRow + " ") }
            XCTAssertNotNil(row, "\(badge.text): no \(badge.group.informationRow) row")
            XCTAssertTrue(row?.value.contains(badge.text) ?? false, "\(badge.text) is not said in \(row?.value ?? "-")")
        }
    }

    func testDolbyAtmosReplacesTheCodecItTravelsIn() {
        XCTAssertEqual(FormatBadges.audio(codec: "eac3", atmos: true)?.text, "Dolby Atmos")
        XCTAssertEqual(FormatBadges.audio(codec: "truehd", atmos: false)?.text, "Dolby TrueHD")
        XCTAssertEqual(FormatBadges.audio(codec: "dts-hd ma", atmos: false)?.text, "DTS-HD MA")
        XCTAssertNil(FormatBadges.audio(codec: nil, atmos: false))
    }

    func testTheCardTextsParseIntoTheirGroups() {
        XCTAssertEqual(FormatBadges.parse(cardText: "4K"), FormatBadgeItem(.resolution, "4K"))
        XCTAssertEqual(FormatBadges.parse(cardText: "HDR10+"), FormatBadgeItem(.hdr, "HDR10+"))
        XCTAssertEqual(FormatBadges.parse(cardText: "Dolby Atmos"), FormatBadgeItem(.audio, "Dolby Atmos"))
        XCTAssertNil(FormatBadges.parse(cardText: "Something"))
        XCTAssertEqual(FormatBadges.headlineGroups, [.resolution, .hdr, .audio])
    }
}
