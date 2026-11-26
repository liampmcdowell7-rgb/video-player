import XCTest
import LibraryIndex
@testable import AppLogic

/// R471 (93): a long press on a show page's episode card offers the page's own actions, as other episode cards do.
final class EpisodeCardLongPressTests: XCTestCase {
    private func row(watched: Bool, progress: Double? = nil) -> EpisodeRow {
        EpisodeRow(id: 9, title: "Pilot", number: 1, code: "S1 E1", runtimeText: nil, progress: progress, isWatched: watched,
                   artworkKey: "item-9")
    }

    func testTheCardOffersThePagesActionsNotOnlyMark() {
        let list = ProductActions.cardList(row(watched: false).longPressCard.actionContext)
        XCTAssertTrue(list.contains(.markWatched))
        XCTAssertFalse(list.contains(.markUnwatched), "never both marks (R471 (37))")
        for action in [ProductAction.changeArtwork, .editMetadata, .rate] {
            XCTAssertTrue(list.contains(action), "\(action) missing from the episode card's long press")
        }
        XCTAssertTrue(ProductActions.cardList(row(watched: true).longPressCard.actionContext).contains(.markUnwatched))
    }

    func testTheCardIsTheEpisodeWithoutAShowOrAMatch() {
        let card = row(watched: false, progress: 0.4).longPressCard
        XCTAssertEqual(card.id, 9)
        XCTAssertEqual(card.kind, .episode)
        XCTAssertEqual(card.progress, 0.4)
        XCTAssertNil(card.goToTitle, "no Go to Show on the show's own page")
        XCTAssertFalse(ProductActions.cardList(card.actionContext).contains(.unmatch), "Unmatch stays with the show's own actions")
    }
}
