import XCTest
import MetadataOnline
import UserData
@testable import AppLogic

/// R449: the user layer beats every source, and nothing a source does can overwrite an edited field.
final class EditOverlayTests: XCTestCase {
    let key = UDEditKey.movie(tmdbID: 7)
    func ledger() -> UserDataLedger { UserDataLedger(deviceID: "A", clock: { Date(timeIntervalSince1970: 1_700_000_000) }) }

    func source(_ title: String) -> MetadataFields { MetadataFields(title: title, overview: title + " plot", genres: [title]) }

    func testTheUserLayerBeatsSidecarOnlineAndEmbedded() {
        let l = ledger()
        l.setEdit(key, .title, .text("Mine"))
        let user = EditOverlay.fields(from: l.edits(for: [key]))
        let merged = MetadataMerger.merge(user: user, sidecar: source("Sidecar"), tmdb: source("Online"), embedded: source("Embedded"))
        XCTAssertEqual(merged.fields.title, "Mine")
        XCTAssertEqual(merged.source(of: .title), .user)
        XCTAssertEqual(merged.fields.overview, "Sidecar plot", "a field not edited still follows the sources")
        XCTAssertEqual(merged.source(of: .overview), .sidecar)
    }

    func testEachSourceAloneIsOverriddenAndAResetShowsTheSourceAgain() {
        let l = ledger()
        l.setEdit(key, .overview, .text("Mine"), at: Date(timeIntervalSince1970: 1_700_000_001))
        for layer in 0..<3 {
            let s = source("S\(layer)")
            let merged = MetadataMerger.merge(user: EditOverlay.fields(from: l.edits(for: [key])),
                                              sidecar: layer == 0 ? s : nil, tmdb: layer == 1 ? s : nil, embedded: layer == 2 ? s : nil)
            XCTAssertEqual(merged.fields.overview, "Mine", "layer \(layer)")
        }
        l.resetEdit(key, .overview, at: Date(timeIntervalSince1970: 1_700_000_050))
        let after = MetadataMerger.merge(user: EditOverlay.fields(from: l.edits(for: [key])), tmdb: source("Online"))
        XCTAssertEqual(after.fields.overview, "Online plot")
        XCTAssertEqual(after.source(of: .overview), .tmdb)
    }

    func testARescanAFixMatchAndAnOnlineRefreshNeverOverwriteAnEdit() {
        let l = ledger()
        l.setEdit(key, .title, .text("Mine"))
        l.setEdit(key, .genres, .list(["Mine"]))
        // Fix Match chooses another title; a refresh brings new online data; a rescan reads a new sidecar: only the
        // layers below the user layer change, and the edit record is the same.
        let before = l.record(type: UDEdit.type, id: key.recordID)
        for round in 1...3 {
            let merged = MetadataMerger.merge(user: EditOverlay.fields(from: l.edits(for: [key])), sidecar: source("Scan \(round)"), tmdb: source("Match \(round)"))
            XCTAssertEqual(merged.fields.title, "Mine")
            XCTAssertEqual(merged.fields.genres, ["Mine"])
        }
        XCTAssertEqual(l.record(type: UDEdit.type, id: key.recordID), before, "nothing wrote to the edit record")
    }

    func testArtworkChoicesMapToTheRightReferences() {
        let l = ledger()
        l.setEdit(key, .poster, .artwork(.file("abc.png")))
        l.setEdit(key, .backdrop, .artwork(.online("/b.jpg")))
        l.setEdit(key, .logo, .artwork(.address("https://example.invalid/x.png")))
        let f = EditOverlay.fields(from: l.edits(for: [key]))
        XCTAssertEqual(f.poster, .local("useredits/abc.png"))
        XCTAssertEqual(f.backdrop, .tmdb("/b.jpg"))
        XCTAssertNil(f.logo, "an address that was not downloaded is not a picture yet")
    }

    func testCastAndYearAndRuntimeAreRead() {
        let l = ledger()
        l.setEdit(key, .cast, .people([UDEditPerson(name: "X", role: "Role")]))
        l.setEdit(key, .year, .number(1999))
        l.setEdit(key, .runtime, .number(101))
        let f = EditOverlay.fields(from: l.edits(for: [key]))
        XCTAssertEqual(f.cast.first?.character, "Role")
        XCTAssertEqual(f.releaseDate?.year, 1999)
        XCTAssertEqual(f.runtimeMinutes, 101)
    }
}
