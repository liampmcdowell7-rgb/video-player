import XCTest
@testable import ScreenChecks

/// R424, R425, R427 (owner's reading of run #28 on 4af6cb0): each fix checked from the source (structure only: nothing is
/// compiled or run on tvOS here). Whether the next run agrees waits for it. R426 is tested in PlaybackStartLogTests.
extension ScreenChecksTests {
    /// The body of the first `declaration` in `source`.
    private func run28Body(of declaration: String, in source: String) throws -> String {
        let start: String.Index = try XCTUnwrap(source.range(of: declaration)?.lowerBound, "no \(declaration)")
        return String(try XCTUnwrap(Self.braceBody(of: source, after: start), "the body of \(declaration)"))
    }

    /// R424: every row of a product page is a full-width focus section, and the hero hands the focus to Play when Up
    /// comes back into it.
    func testProductPageRowsAreFullWidthFocusSections() throws {
        guard let parts = try appSource("App/Shared/ProductPageParts.swift"),
              let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        let row: String = try run28Body(of: "func productPageRow() -> some View {", in: parts)
        XCTAssertTrue(row.contains("frame(maxWidth: .infinity, alignment: .leading)\n            .focusSection()"), "a row is not one full-width focus section")
        let heroFocus: String = ".productHero(pageHeight: pageHeight)\n        // R424"
        XCTAssertTrue(detail.contains(heroFocus), "the movie and episode hero is not followed by its focus section")
        for source in [detail, seasons] {
            XCTAssertTrue(source.contains(".focusSection()\n        .defaultFocus($playFocused, true, priority: .userInitiated)")
                          || source.contains(".focusSection()\n                .defaultFocus($playFocused, true, priority: .userInitiated)"),
                          "a hero does not hand the focus to Play when Up comes back into it")
        }
        let cast: String = try run28Body(of: "struct CastShelf: View {", in: detail)
        XCTAssertTrue(cast.contains(".productPageRow()"), "the cast row is not a focus section")
        XCTAssertTrue(detail.contains("EpisodeShelfRow(episodes: other.episodes, model: seasonModel)\n                    }\n                    // R424"), "the episode page's other episodes are not a focus section")
        XCTAssertTrue(seasons.contains("seasonTabs\n                    // R424: Up from an episode card at the right (x 980 in run #28) reaches the picker at the left.\n                    .productPageRow()"), "the season tabs are not a focus section")
        XCTAssertTrue(seasons.contains(".id(season.season)\n                    // R424: Up from any cast entry reaches the episodes.\n                    .productPageRow()"), "the show page's episodes are not a focus section")
        // The Information block is one accessibility container with its own name (the "PG-13" of 58's Down path).
        let info: String = try run28Body(of: "private struct MediaInfoSection: View {", in: detail)
        XCTAssertTrue(info.contains(".accessibilityElement(children: .contain)"), "Information is not one accessibility container")
        XCTAssertTrue(info.contains(".accessibilityIdentifier(\"product.information\")"), "Information has no identifier of its own")
    }

    /// R425: test12's three test faults, and the settings read that accepts a launch argument.
    func testPlayerTestWaitsForWhatItChecks() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift"),
              let wiring = try appSource("App/Features/Player/SegmentsWiring.swift") else { return }
        let test12: String = try run28Body(of: "func test12_PlayerWithSampleClip() {", in: tests)
        // (b) the intro button stays up for the whole intro.
        XCTAssertTrue(test12.contains("extra: [\"-skipIntrosAutomatically\", \"NO\"]"), "test12 still runs with the automatic skip, a 5 s button")
        let flag: String = try run28Body(of: "private static func flag(_ key: SettingsKey) -> Bool {", in: wiring)
        XCTAssertTrue(flag.contains("defaults.bool(forKey: key.rawValue)"), "a setting given as a launch argument (a string) is read as missing")
        XCTAssertFalse(flag.contains("as? Bool"), "the setting is still read with as? Bool")
        // (a) no tree read and no waits between Down and the tab pictures.
        let down: Range<String.Index> = try XCTUnwrap(test12.range(of: "XCUIRemote.shared.press(.down); sleep(2); shot(\"24-player-info-panel\")"), "no Down to the panel")
        let firstRight: Range<String.Index> = try XCTUnwrap(test12.range(of: "XCUIRemote.shared.press(.right); sleep(1)"), "no Right to the tabs")
        let between: Substring = test12[down.upperBound..<firstRight.lowerBound]
        XCTAssertFalse(between.contains("hierarchy("), "the panel's tree is read before the tab pictures")
        XCTAssertFalse(between.contains("waitFor("), "the test waits before the tab pictures")
        // (c) the wait is for the Up Next card's own button, not a title the page underneath also shows.
        XCTAssertFalse(test12.contains("waitFor(\"The long way round\""), "the Up Next wait still matches the episode page under the player")
        XCTAssertTrue(test12.contains("let playNow: XCUIElement = app.buttons[ControlID.upNextPlayNow]\n        if playNow.waitForExistence(timeout: 90) {"), "the Up Next wait is not for Play Now")
    }

    /// R427: the three check faults.
    func testRun28CheckFaultsAreFixed() throws {
        guard let tests = try appSource("UITests/ScreenshotTests.swift"),
              let cards = try appSource("App/Features/Shows/EpisodeCards.swift") else { return }
        // (a) the caption inside the focused card.
        let caption: String = try run28Body(of: "func captionCheck(", in: tests)
        XCTAssertFalse(caption.contains("label CONTAINS %@\", caption)).firstMatch"), "the first text with the title anywhere is still taken")
        XCTAssertTrue(caption.contains("f.midX >= cardBox.minX && f.midX <= cardBox.maxX"), "the caption is not looked for inside the card")
        // (b) a card is never a badge.
        let badges: String = try run28Body(of: "func badgesNotCutCheck(", in: tests)
        XCTAssertTrue(badges.contains("element.elementType != .button && element.elementType != .cell"), "buttons and cells still count as badges")
        let card: String = try run28Body(of: "struct EpisodeCard: View {", in: cards)
        XCTAssertTrue(card.contains(".accessibilityIdentifier(\"card.episode.\\(episode.id)\")"), "the episode card has no identifier of its own")
        // (c) the row's identifier from inside the focused element.
        let rows: String = try run28Body(of: "func rowsReachable(", in: tests)
        XCTAssertTrue(rows.contains("let id: String = focusedRowIdentifier(focused)"), "the form check still reads only the focused element's own identifier")
        let inner: String = try run28Body(of: "func focusedRowIdentifier(", in: tests)
        XCTAssertTrue(inner.contains("focused.descendants(matching: .any)"), "no look inside the focused element")
    }
}
