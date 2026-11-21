import XCTest
import LibraryIndex
@testable import AppLogic

// Rule S1 (OPEN_QUESTIONS R165) and the card texts from the screenshot review of run 44401030622 (items 3a, 3b).

final class ShortLineTests: XCTestCase {
    func testCandidatesDropTheLowestPriorityWholeSegmentsOneByOne() {
        let line = ShortLine([.init("S2 E1", priority: 3), .init("The Return", priority: 2), .init("41 min left", priority: 1)])
        XCTAssertEqual(line.full, "S2 E1 · The Return · 41 min left")
        XCTAssertEqual(line.candidates, ["S2 E1 · The Return · 41 min left", "S2 E1 · The Return", "S2 E1"])
    }

    func testOrderedSegmentsDropFromTheEnd() {
        let badges = ShortLine(ordered: ["4K", "Dolby Vision", "Dolby Atmos"])
        XCTAssertEqual(badges.candidates, ["4K · Dolby Vision · Dolby Atmos", "4K · Dolby Vision", "4K"])
        XCTAssertTrue(badges.candidates.allSatisfy { !$0.contains("…") && !$0.contains("Dolb ") }, "names stay whole")
    }

    func testAMiddleSegmentWithTheLowestPriorityGoesFirst() {
        let line = ShortLine([.init("2021", priority: 1), .init("Because you watched Hexfall", priority: 2)])
        XCTAssertEqual(line.candidates, ["2021 · Because you watched Hexfall", "Because you watched Hexfall"])
    }

    func testEmptySegmentsAreLeftOut() {
        XCTAssertTrue(ShortLine([.init("", priority: 3), .init("  ", priority: 1)]).isEmpty)
        XCTAssertEqual(ShortLine([]).candidates, [])
        XCTAssertEqual(ShortLine([.init("S1 E1", priority: 2), .init("", priority: 1)]).candidates, ["S1 E1"])
    }

    func testChooseTakesTheFirstCandidateThatFitsAtTheMinimumScale() {
        // Natural widths 500, 300, 100 in a 300-wide slot, minimum scale 0.7: 500 × 0.7 = 350 does not fit, 300 does.
        XCTAssertEqual(ShortLine.choose(idealWidths: [500, 300, 100], available: 300, minimumScale: 0.7), 1)
        XCTAssertEqual(ShortLine.choose(idealWidths: [420, 300, 100], available: 300, minimumScale: 0.7), 0, "420 × 0.7 = 294 fits")
        XCTAssertEqual(ShortLine.choose(idealWidths: [900, 800], available: 300, minimumScale: 0.7), 1, "none fits: the shortest")
        XCTAssertEqual(ShortLine.choose(idealWidths: [], available: 300), 0)
        XCTAssertEqual(ShortLine.choose(idealWidths: [500, 100], available: 0), 0, "not measured yet: the full line")
    }

    func testTheScaleNeverGoesBelowAppleMinimumTextSize() {
        // Apple, tvOS Typography: minimum 23 pt (Caption 2). Rule S1: 0.7. The larger of the two wins (R165).
        XCTAssertEqual(ShortLine.minimumScale(forPointSize: TVTextStyle.caption2.pointSize), 1, accuracy: 0.0001)
        XCTAssertEqual(ShortLine.minimumScale(forPointSize: TVTextStyle.caption.pointSize), 23.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(ShortLine.minimumScale(forPointSize: TVTextStyle.body.pointSize), 23.0 / 29.0, accuracy: 0.0001)
        XCTAssertEqual(ShortLine.minimumScale(forPointSize: TVTextStyle.title1.pointSize), 0.7, accuracy: 0.0001)
        for style in TVTextStyle.allCases {
            XCTAssertGreaterThanOrEqual(style.pointSize * ShortLine.minimumScale(forPointSize: style.pointSize), 23 - 0.0001, style.rawValue)
        }
    }
}

final class CardTextTests: XCTestCase {
    private func episode(title: String) async throws -> LibraryItem {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let episodes = try await rig.episodes(ofSeriesTitle: "Show One")
        var e = try XCTUnwrap(episodes.first { $0.season == 2 && $0.episode == 1 })
        e.title = title
        return e
    }

    func testAnEpisodeCardIsTitledWithItsShowAndNamesTheEpisodeOnce() async throws {
        let card = CardBuilder.card(try await episode(title: "Return"))
        XCTAssertEqual(card.title, "Show One")
        XCTAssertEqual(card.subtitle, "S2, E1 · Return")
    }

    func testAnEpisodeWithoutARealTitleShowsOnlyTheCode() async throws {
        for placeholder in ["", "S02E01", "s2e1", "S02 E01", "2x01", "Episode 1", "Show One"] {
            let card = CardBuilder.card(try await episode(title: placeholder))
            XCTAssertEqual(card.title, "Show One", placeholder)
            XCTAssertEqual(card.subtitle, "S2, E1", "title \(placeholder.debugDescription) is not a real episode title")
        }
    }

    /// #17 C: the episode title is dropped first; the episode number and the time left stay longest ("S2 E1 · 31 min left"
    /// was cut to "S2 E1" in the Larger Text screenshot 80).
    func testContinueWatchingKeepsTheEpisodeNumberAndTimeLeftLongest() async throws {
        var e = try await episode(title: "Return")
        e.watch.position = 600
        e.watch.duration = 3_000
        let card = CardBuilder.card(e, style: .continueWatching)
        XCTAssertEqual(card.subtitleLine.candidates, ["S2, E1 · Return · 40 min left", "S2, E1 · 40 min left", "S2, E1"])
        XCTAssertEqual(card.subtitleLine.full, "S2, E1 · Return · 40 min left", "display order is unchanged")
    }

    /// #17 C drop order of the badge line, lowest priority first: audio (Dolby Atmos), then HDR, then resolution.
    func testBadgesDropAudioThenHDRThenResolution() async throws {
        var e = try await episode(title: "Return")
        e.maxResolution = .uhd4k
        e.hdrFormats = [.dolbyVision]
        e.hasAtmos = true
        let card = CardBuilder.card(e)
        XCTAssertEqual(card.badges, ["4K", "Dolby Vision", "Dolby Atmos"])
        XCTAssertEqual(card.badgeLine.candidates, ["4K · Dolby Vision · Dolby Atmos", "4K · Dolby Vision", "4K"])
    }

    /// The order comes from what each badge is, not from where it stands in the list.
    func testBadgeDropOrderDoesNotDependOnListPosition() {
        XCTAssertEqual(CardBuilder.badgeLine(["Dolby Atmos", "HDR10", "4K"]).candidates,
                       ["Dolby Atmos · HDR10 · 4K", "HDR10 · 4K", "4K"])
        XCTAssertEqual(CardBuilder.badgeLine(["HDR10+", "Dolby Atmos"]).candidates, ["HDR10+ · Dolby Atmos", "HDR10+"])
        XCTAssertEqual(CardBuilder.badgeLine(["HLG"]).candidates, ["HLG"])
        XCTAssertTrue(CardBuilder.badgeLine([]).isEmpty)
    }
}
