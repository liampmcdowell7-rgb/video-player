import XCTest
@testable import ScreenChecks

/// R471 (93): the show page's episode cards use the shared card menu (the page's actions), without the card extras.
extension ScreenChecksTests {
    func testShowPageEpisodeCardsOfferThePagesActionsOnALongPress() throws {
        guard let cards = try appSource("App/Features/Shows/EpisodeCards.swift"),
              let menu = try appSource("App/Shared/CardContextMenu.swift") else { return }
        XCTAssertTrue(cards.contains(".cardContextMenu(episode.longPressCard, extras: false)"), "the episode card's long press is not the shared menu")
        XCTAssertFalse(cards.contains(".contextMenu {"), "the episode card still builds its own Mark-only menu")
        XCTAssertTrue(menu.contains("if extras, let title = card.goToTitle {"), "Go to is not left out without extras")
        XCTAssertTrue(menu.contains("ForEach(ProductActions.cardList(context)"), "the shared menu no longer lists the page's actions")
    }
}
