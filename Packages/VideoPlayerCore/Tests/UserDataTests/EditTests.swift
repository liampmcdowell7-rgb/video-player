import XCTest
@testable import UserData

/// R449: the user layer of metadata edits as records (reset per field and per item, newest edit wins per field, export and
/// import, a newer schema is kept and not read, identity after a rename).
final class EditTests: XCTestCase {
    let movie = UDEditKey.movie(tmdbID: 603)

    func testSetResetAndEditedStateArePerField() {
        let l = makeLedger("A")
        l.setEdit(movie, .title, .text("My Title"), at: at(1))
        l.setEdit(movie, .overview, .text("My plot"), at: at(2))
        var e = l.edits(for: [movie])
        XCTAssertEqual(e[.title]?.text, "My Title")
        XCTAssertTrue(e.isEdited(.overview))
        l.resetEdit(movie, .title, at: at(3))
        e = l.edits(for: [movie])
        XCTAssertFalse(e.isEdited(.title), "a reset field reads as not edited")
        XCTAssertEqual(e[.overview]?.text, "My plot", "the other field keeps its edit")
    }

    func testResetOfTheWholeItemClearsEveryFieldAndALaterEditRevivesIt() {
        let l = makeLedger("A")
        l.setEdit(movie, .title, .text("T"), at: at(1))
        l.setEdit(movie, .genres, .list(["Drama", "Noir"]), at: at(2))
        l.resetAllEdits(movie, at: at(3))
        XCTAssertTrue(l.edits(for: [movie]).isEmpty)
        l.setEdit(movie, .tagline, .text("Again"), at: at(4))
        let e = l.edits(for: [movie])
        XCTAssertEqual(e.values.count, 1, "only the edit made after the reset counts")
        XCTAssertEqual(e[.tagline]?.text, "Again")
    }

    func testEveryValueKindSurvivesTheRecord() {
        let l = makeLedger("A")
        l.setEdit(movie, .runtime, .number(142), at: at(1))
        l.setEdit(movie, .cast, .people([UDEditPerson(name: "A. Actor", role: "Neo"), UDEditPerson(name: "B. Actor")]), at: at(1))
        l.setEdit(movie, .poster, .artwork(.file("abc.jpg")), at: at(1))
        l.setEdit(movie, .backdrop, .artwork(.online("/x.jpg")), at: at(1))
        l.setEdit(movie, .logo, .artwork(.address("https://example.invalid/l.png")), at: at(1))
        let e = l.edits(for: [movie])
        XCTAssertEqual(e[.runtime]?.number, 142)
        XCTAssertEqual(e[.cast]?.people?.map(\.role), ["Neo", ""])
        XCTAssertEqual(e[.poster]?.artwork, .file("abc.jpg"))
        XCTAssertEqual(e[.backdrop]?.artwork, .online("/x.jpg"))
        XCTAssertEqual(e[.logo]?.artwork, .address("https://example.invalid/l.png"))
    }

    func testTheNewestEditWinsPerFieldAcrossTwoDevices() {
        let a = makeLedger("A"), b = makeLedger("B")
        a.setEdit(movie, .title, .text("From A"), at: at(10))
        a.setEdit(movie, .tagline, .text("A tagline"), at: at(30))
        b.setEdit(movie, .title, .text("From B"), at: at(20))
        b.setEdit(movie, .tagline, .text("B tagline"), at: at(5))
        for r in b.allRecords() { a.apply(r) }
        for r in a.allRecords() { b.apply(r) }
        XCTAssertEqual(a.edits(for: [movie]), b.edits(for: [movie]), "both devices converge")
        XCTAssertEqual(a.edits(for: [movie])[.title]?.text, "From B", "B edited the title later")
        XCTAssertEqual(a.edits(for: [movie])[.tagline]?.text, "A tagline", "A edited the tagline later")
    }

    func testExportAndImportRoundTripKeepsEditsAndAnOlderBackupNeverOverwritesNewerEdits() throws {
        let a = makeLedger("A")
        a.setEdit(movie, .title, .text("Old"), at: at(1))
        let old = try UDExport.export(a, at: at(2))
        a.setEdit(movie, .title, .text("New"), at: at(3))
        try UDExport.import(old, into: a)
        XCTAssertEqual(a.edits(for: [movie])[.title]?.text, "New", "an older backup never overwrites a newer edit")
        let fresh = makeLedger("C")
        try UDExport.import(try UDExport.export(a, at: at(4)), into: fresh)
        XCTAssertEqual(fresh.edits(for: [movie])[.title]?.text, "New", "an empty Apple TV gets the edits back")
    }

    func testARecordFromANewerSchemaIsKeptButNotRead() {
        let l = makeLedger("A")
        var r = UDRecord(type: UDEdit.type, id: movie.recordID)
        r.set("schema", .int(Int64(UDEdit.schemaVersion + 1)), at: stamp(5))
        r.set("f.title", .string("tFrom the future"), at: stamp(5))
        l.apply(r)
        XCTAssertTrue(l.edits(for: [movie]).isEmpty, "not read")
        XCTAssertNotNil(l.record(type: UDEdit.type, id: movie.recordID), "kept untouched")
    }

    func testEditsFollowAFileThatWasRenamedAndAnOnlineKeyOutlivesIt() {
        let l = makeLedger("A")
        let old = UDEditKey.file(sourceID: "s1", path: "/Movies/Film (2001).mkv")
        let renamed = UDEditKey.file(sourceID: "s1", path: "Movies/Film 2001 1080p.mkv")
        l.setEdit(old, .title, .text("Kept"), at: at(1))
        XCTAssertTrue(l.edits(for: [renamed]).isEmpty, "a renamed file has a different file key")
        l.rekeyEdits(from: old, to: renamed, at: at(2))
        XCTAssertEqual(l.edits(for: [renamed])[.title]?.text, "Kept")
        XCTAssertTrue(l.edits(for: [old]).isEmpty, "the old key is released")
        // With an online id the edit is keyed by it and a rename changes nothing.
        l.setEdit(movie, .tagline, .text("Online keyed"), at: at(3))
        XCTAssertEqual(l.edits(for: [UDEditKey.file(sourceID: "s1", path: "any/new/name.mkv"), movie])[.tagline]?.text, "Online keyed")
    }

    func testPathsAreNormalised() {
        XCTAssertEqual(UDEditKey.file(sourceID: "s", path: "/a//b/c.mkv/"), UDEditKey.file(sourceID: "s", path: "a/b/c.mkv"))
        XCTAssertEqual(UDEditKey.file(sourceID: "s", path: "caf\u{65}\u{301}.mkv"), UDEditKey.file(sourceID: "s", path: "caf\u{e9}.mkv"))
    }

    func testSeasonAndEpisodeKeysBuildOnTheShow() {
        let show = UDEditKey.show(tmdbID: 1399)
        XCTAssertEqual(show.season(2).recordID, "show-1399-s2")
        XCTAssertEqual(show.episode(season: 2, episode: 5).recordID, "show-1399-s2e5")
    }

    func testTheChosenAudioAndSubtitleMoveTogetherAndSyncThroughExport() throws {
        let a = makeLedger("A"), b = makeLedger("B")
        a.setTrackChoice(itemKey: "item-1", UDTrackChoice(audio: "eng", subtitle: "fra", subtitlesOff: false), at: at(1))
        b.setTrackChoice(itemKey: "item-1", UDTrackChoice(audio: "jpn", subtitle: nil, subtitlesOff: true), at: at(2))
        try UDExport.import(try UDExport.export(b, at: at(3)), into: a)
        XCTAssertEqual(a.trackChoice(itemKey: "item-1"), UDTrackChoice(audio: "jpn", subtitle: nil, subtitlesOff: true), "the later choice wins as a whole")
    }
}
