import XCTest
@testable import AppLogic
import LibraryIndex

// R350 (item D): the format badges of the movie and show pages, in the owner's order.
final class ProductPageTests: XCTestCase {
    func testTheBadgesKeepTheOwnersOrderWithTheChannelLayoutLast() {
        XCTAssertEqual(ProductPage.formatBadges(cardBadges: ["4K", "Dolby Vision", "Dolby Atmos"], maxChannels: 8),
                       ["4K", "Dolby Vision", "Dolby Atmos", "7.1"])
        XCTAssertEqual(ProductPage.formatBadges(cardBadges: ["4K", "HDR10"], maxChannels: 6), ["4K", "HDR10", "5.1"])
    }

    func testStereoMonoAndUnknownChannelsGetNoBadge() {
        XCTAssertEqual(ProductPage.formatBadges(cardBadges: [], maxChannels: 2), [])
        XCTAssertEqual(ProductPage.formatBadges(cardBadges: [], maxChannels: 1), [])
        XCTAssertEqual(ProductPage.formatBadges(cardBadges: ["4K"], maxChannels: nil), ["4K"])
    }

    func testChannelLayouts() {
        XCTAssertEqual(ProductPage.channelLayout(6), "5.1")
        XCTAssertEqual(ProductPage.channelLayout(7), "5.1")
        XCTAssertEqual(ProductPage.channelLayout(8), "7.1")
        XCTAssertEqual(ProductPage.channelLayout(12), "7.1")
        XCTAssertNil(ProductPage.channelLayout(5))
    }

    func testTheSectionsAreNamedAsInTheTVApp() {
        XCTAssertEqual(ProductPage.castHeading, "Cast & Crew")
        XCTAssertEqual(ProductPage.informationHeading, "Information")
    }

    func testTheShowPagesLineCountsTheSeasons() {
        XCTAssertEqual(ProductPage.showFacts(seasonCount: 0), "")
        XCTAssertEqual(ProductPage.showFacts(seasonCount: 1), "1 Season")
        XCTAssertEqual(ProductPage.showFacts(seasonCount: 3), "3 Seasons")
    }

    // R369 (owner's scan of ec27d52, finding 4): every technology badge, most important first, each with its Information row.
    func testEveryTechnologyBadgeInOrderEachWithItsInformationRow() {
        let t = FileTechnicalInfo(container: .mkv, width: 3840, height: 2160, hdrFormats: [.dolbyVision, .hdr10], dolbyVisionProfile: 8,
                                  videoCodec: "hevc", audioCodec: "truehd", audioChannels: 8, hasAtmos: true)
        let badges = ProductPage.badges(technical: t, maxChannels: nil)
        XCTAssertEqual(badges.map(\.text), ["4K", "Dolby Vision", "Dolby Atmos", "7.1", "HEVC", "MKV"])
        let rows = MediaInfo.rows(technical: t, size: 1, path: "/a.mkv", subtitleNames: [], sourceName: nil)
        for badge in badges {
            let row = rows.first { $0.label == badge.row || $0.label.hasPrefix(badge.row + " ") }
            XCTAssertNotNil(row, "\(badge.text): no \(badge.row) row")
            XCTAssertTrue(row?.value.contains(badge.text) ?? false, "\(badge.text) is not said in \(row?.value ?? "-")")
        }
    }

    func testTheAudioBadgesUseTheScansShortNames() {
        XCTAssertEqual(ProductPage.audioBadge(codec: "truehd", atmos: false), "TrueHD")
        XCTAssertEqual(ProductPage.audioBadge(codec: "dts-hd ma", atmos: false), "DTS-HD MA")
        XCTAssertEqual(ProductPage.audioBadge(codec: "eac3", atmos: false), "Dolby Digital Plus")
        XCTAssertEqual(ProductPage.audioBadge(codec: "ac3", atmos: false), "Dolby Digital")
        XCTAssertEqual(ProductPage.audioBadge(codec: "dts", atmos: false), "DTS")
        XCTAssertEqual(ProductPage.audioBadge(codec: "eac3", atmos: true), "Dolby Atmos")
        XCTAssertNil(ProductPage.audioBadge(codec: "aac", atmos: false))
        XCTAssertNil(ProductPage.audioBadge(codec: nil, atmos: false))
    }

    func testPlainFilesGetFewBadges() {
        let t = FileTechnicalInfo(container: .avi, height: 480, videoCodec: "xvid", audioCodec: "mp3", audioChannels: 2, hasAtmos: false)
        XCTAssertEqual(ProductPage.badges(technical: t, maxChannels: nil).map(\.text), ["AVI"])
        let h = FileTechnicalInfo(container: .mp4, height: 1080, videoCodec: "h264", audioCodec: "aac", audioChannels: 6, hasAtmos: false)
        XCTAssertEqual(ProductPage.badges(technical: h, maxChannels: nil).map(\.text), ["1080p", "5.1", "H.264", "MP4"])
    }
}
