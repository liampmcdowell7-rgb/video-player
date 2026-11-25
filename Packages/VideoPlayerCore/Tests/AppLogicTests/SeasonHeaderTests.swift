import XCTest
import MetadataOnline
import UserData
@testable import AppLogic

/// R471 (22): a season's own text on the show page. FIXTURE: invented names and synopses; no service is contacted.
final class SeasonHeaderTests: XCTestCase {
    private func ledger() -> UserDataLedger { UserDataLedger(deviceID: "A", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    func testTheSeasonsOnlineNameAndSynopsisWithoutEdits() {
        let online = SeasonMetadata(seriesID: 7, seasonNumber: 2, name: "The Long Winter", overview: "  Snow falls.  ")
        let header = SeasonHeader.make(libraryTitle: "Season 2", online: online, edits: UDEditValues())
        XCTAssertEqual(header, SeasonHeader(title: "The Long Winter", overview: "Snow falls."))
        XCTAssertTrue(header.isWorthShowing(libraryTitle: "Season 2", hasPoster: false))
    }

    func testTheUsersSeasonEditsWinOverTheOnlineText() {
        let l = ledger()
        let keys = EditTarget.seasonKeys(tmdbID: 7, title: "Show One", season: 2)
        l.setEdit(keys[0], .title, .text("Part Two"))
        l.setEdit(keys[0], .overview, .text("My own words."))
        let online = SeasonMetadata(seriesID: 7, seasonNumber: 2, name: "The Long Winter", overview: "Snow falls.")
        let header = SeasonHeader.make(libraryTitle: "Season 2", online: online, edits: l.edits(for: keys))
        XCTAssertEqual(header, SeasonHeader(title: "Part Two", overview: "My own words."))
    }

    func testAnEditByTheShowsNameAloneIsFound() {
        let l = ledger()
        let byName = EditTarget.seasonKeys(tmdbID: nil, title: "Show One", season: 1)
        l.setEdit(byName[0], .overview, .text("Written before the match."))
        let all = EditTarget.seasonKeys(tmdbID: 7, title: "Show One", season: 1)
        let header = SeasonHeader.make(libraryTitle: "Season 1", online: nil, edits: l.edits(for: all))
        XCTAssertEqual(header.overview, "Written before the match.")
        XCTAssertEqual(header.title, "Season 1")
    }

    func testNothingHeldMeansTheLibrarysNameAndNoHeader() {
        let blank = SeasonMetadata(seriesID: 7, seasonNumber: 0, name: " ", overview: "")
        let header = SeasonHeader.make(libraryTitle: "Specials", online: blank, edits: UDEditValues())
        XCTAssertEqual(header, SeasonHeader(title: "Specials", overview: nil))
        XCTAssertFalse(header.isWorthShowing(libraryTitle: "Specials", hasPoster: false))
        XCTAssertTrue(header.isWorthShowing(libraryTitle: "Specials", hasPoster: true), "a poster alone is worth the header")
        let same = SeasonHeader.make(libraryTitle: "Season 3", online: SeasonMetadata(seriesID: 7, seasonNumber: 3, name: "Season 3"),
                                     edits: UDEditValues())
        XCTAssertFalse(same.isWorthShowing(libraryTitle: "Season 3", hasPoster: false), "the same name as the picker says nothing more")
    }
}
