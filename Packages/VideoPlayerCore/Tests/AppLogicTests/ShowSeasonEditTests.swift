import XCTest
import UserData
@testable import AppLogic

/// R471 (11), Part 4: the show and season edits of the show page are stored under their own keys, follow the online id when
/// known, never leak into each other, and replace the layers' description on the page.
final class ShowSeasonEditTests: XCTestCase {
    func ledger() -> UserDataLedger { UserDataLedger(deviceID: "A", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    func testSeasonKeysAreTheShowsKeysWithTheSeasonNumber() {
        XCTAssertEqual(EditTarget.seasonKeys(tmdbID: 1399, title: "Harbor Lights", season: 2).map(\.recordID),
                       ["show-1399-s2", "showname-harbor lights-s2"])
        XCTAssertEqual(EditTarget.seasonKeys(tmdbID: nil, title: "Harbor Lights", season: 0).map(\.recordID),
                       ["showname-harbor lights-s0"], "without an online id the season follows the show's name; the specials are season 0")
    }

    func testAShowEditAndASeasonEditStayApart() {
        let l = ledger()
        let show = EditTarget.showKeys(tmdbID: 1399, title: "Harbor Lights")
        let season = EditTarget.seasonKeys(tmdbID: 1399, title: "Harbor Lights", season: 1)
        l.setEdit(show[0], .overview, .text("The show, in my words"))
        l.setEdit(season[0], .overview, .text("Season one, in my words"))
        XCTAssertEqual(l.edits(for: show)[.overview]?.text, "The show, in my words")
        XCTAssertEqual(l.edits(for: season)[.overview]?.text, "Season one, in my words")
        XCTAssertNil(l.edits(for: EditTarget.seasonKeys(tmdbID: 1399, title: "Harbor Lights", season: 2))[.overview],
                     "another season has no edit")
    }

    func testAnEditMadeBeforeTheMatchIsStillReadAfterIt() {
        // Edited while the show had no online id (name key), then matched: the page reads both keys and still finds it.
        let l = ledger()
        l.setEdit(EditTarget.showKeys(tmdbID: nil, title: "Harbor Lights")[0], .overview, .text("Mine"))
        XCTAssertEqual(l.edits(for: EditTarget.showKeys(tmdbID: 1399, title: "Harbor Lights"))[.overview]?.text, "Mine")
    }

    func testTheShowsEditReplacesTheLayersDescription() {
        let l = ledger()
        let keys = EditTarget.showKeys(tmdbID: 1399, title: "Harbor Lights")
        let layers = TitleDetails(overview: "From the catalogue", cast: [])
        XCTAssertEqual(EditTarget.apply(l.edits(for: keys), to: layers)?.overview, "From the catalogue", "no edit: the layers stand")
        l.setEdit(keys[0], .overview, .text("Mine"))
        XCTAssertEqual(EditTarget.apply(l.edits(for: keys), to: layers)?.overview, "Mine")
    }

    func testTheShowsListOffersEditDetailsInsideManage() {
        var c = ProductActionContext(kind: .show)
        c.fixMatchAllowed = false
        XCTAssertTrue(ProductActions.list(c).contains(.manage))
        XCTAssertEqual(ProductActions.manageList(c), [.editMetadata])
    }
}
