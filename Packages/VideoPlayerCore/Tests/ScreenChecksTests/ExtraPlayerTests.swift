import XCTest
@testable import ScreenChecks

/// R471 (24), PROVISIONAL: a Trailers or Bonus Content card plays its file; its facts stay in its long-press menu; the
/// extra's player saves nothing. Structure only, from the source: nothing is compiled or run on tvOS here.
extension ScreenChecksTests {
    func testAnExtraCardPlaysAndKeepsItsFactsInTheLongPressMenu() throws {
        guard let shelf = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(shelf.contains("Button { playing = ExtraPlayRequest(itemID: itemID, extraID: extra.id, seriesID: seriesID) } label:"), "Select plays")
        XCTAssertTrue(shelf.contains("Button(\"File Details\", systemImage: \"info.circle\") { shown = extra }"), "the facts stay reachable")
        XCTAssertTrue(shelf.contains("ExtraPlayerScreen(request: request)"))
        guard let page = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(page.contains("extras: shelves.trailers, itemID: content.itemID"))
        XCTAssertTrue(page.contains("extras: shelves.bonus, itemID: content.itemID"))
    }

    func testAnExtrasPlayerKeepsNoWatchStateAndStopsTheConverter() throws {
        guard let screen = try appSource("App/Features/Player/ExtraPlayerScreen.swift"),
              let resolve = try appSource("App/Support/ExtraPlayback.swift") else { return }
        for saving in ["updateProgress", "markWatched", "PlayerCoordinator", "watchSync", "upNext"] {
            XCTAssertFalse(screen.contains(saving), "the extra's player has no \(saving)")
            XCTAssertFalse(resolve.contains(saving), "resolving an extra has no \(saving)")
        }
        XCTAssertTrue(screen.contains("resolved.remux?.stop()"), "the converting player is stopped when the screen closes")
        XCTAssertTrue(resolve.contains("ExtraFiles.find(itemID: itemID, extraID: extraID, store: store)"), "only the title's own extra plays")
    }
}
