import XCTest
@testable import AppLogic

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
}
