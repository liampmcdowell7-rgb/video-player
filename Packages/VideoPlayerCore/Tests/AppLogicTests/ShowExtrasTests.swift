import XCTest
@testable import LibraryIndex
@testable import AppLogic

/// R471 (39): a show's own Trailers and Bonus Content, from its folder and its season folders.
/// FIXTURE: invented titles and file names.
final class ShowExtrasTests: XCTestCase {
    private func filledRig() async throws -> LibraryRig {
        let rig = try LibraryRig.make()
        rig.source.put("/TV/Show One (2010)/Trailers/Season One Look.mkv", size: 300, modified: dayOffset(1))
        rig.source.put("/TV/Show One (2010)/Show One (2010)-featurette.mkv", size: 200, modified: dayOffset(1))
        rig.source.put("/TV/Show One (2010)/Extras/Cast Chat.mkv", size: 250, modified: dayOffset(1))
        rig.source.put("/TV/Show One (2010)/Season 1/Extras/Set Visit.mkv", size: 150, modified: dayOffset(1))
        rig.source.put("/TV/Show One (2010)/Season 1/Show One - S01E01 - Ep 1-deletedscene.mkv", size: 120, modified: dayOffset(1))
        rig.source.put("/TV/Show One (2010)/Season 2/Trailers/Next Season.mkv", size: 180, modified: dayOffset(1))
        try await rig.fill()
        return rig
    }

    private func seriesID(_ rig: LibraryRig, _ title: String) async throws -> Int64 {
        let episodes = try await rig.episodes(ofSeriesTitle: title)
        return try XCTUnwrap(episodes.first?.seriesID)
    }

    func testTheShowsFolderAndItsSeasonFoldersAreRead() async throws {
        let rig = try await filledRig()
        let found = try await ShowExtras.load(seriesID: try await seriesID(rig, "Show One"), store: rig.store)
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.row.name, $0) })
        XCTAssertEqual(byName["Season One Look.mkv"]?.season, .some(nil), "the show's Trailers folder belongs to the whole show")
        XCTAssertEqual(byName["Season One Look.mkv"]?.row.isTrailer, true)
        XCTAssertEqual(byName["Show One (2010)-featurette.mkv"]?.season, .some(nil))
        XCTAssertEqual(byName["Cast Chat.mkv"]?.row.isTrailer, false)
        XCTAssertEqual(byName["Set Visit.mkv"]?.season, 1)
        XCTAssertEqual(byName["Next Season.mkv"]?.season, 2)
        XCTAssertNil(byName["Show One - S01E01 - Ep 1-deletedscene.mkv"], "an episode's own extra stays on the episode's page")
        XCTAssertEqual(Set(found.map(\.file.id)).count, found.count, "each file once")
    }

    func testTheShelvesShowTheWholeShowAndTheSeasonOnScreen() async throws {
        let rig = try await filledRig()
        let found = try await ShowExtras.load(seriesID: try await seriesID(rig, "Show One"), store: rig.store)
        let seasonOne = ShowExtras.rows(found, season: 1).map(\.name)
        XCTAssertTrue(seasonOne.contains("Set Visit.mkv"))
        XCTAssertFalse(seasonOne.contains("Next Season.mkv"), "another season's extras wait for its tab")
        XCTAssertEqual(seasonOne.first, found.first { $0.season == nil }?.row.name, "the whole show's extras first")
        let split = ExtraShelves.split(ShowExtras.rows(found, season: 2))
        XCTAssertEqual(Set(split.trailers.map(\.name)), ["Season One Look.mkv", "Next Season.mkv"])
        XCTAssertTrue(split.bonus.map(\.name).contains("Cast Chat.mkv"))
    }

    func testACardFindsItsShowsExtraAndNotAnotherShows() async throws {
        let rig = try await filledRig()
        let one = try await seriesID(rig, "Show One")
        let found = try await ShowExtras.load(seriesID: one, store: rig.store)
        let trailer = try XCTUnwrap(found.first { $0.row.name == "Season One Look.mkv" })
        let again = try await ShowExtras.find(seriesID: one, extraID: trailer.file.id, store: rig.store)
        XCTAssertEqual(again?.path, "/TV/Show One (2010)/Trailers/Season One Look.mkv")
        let other = try await ShowExtras.find(seriesID: try await seriesID(rig, "Show Two"), extraID: trailer.file.id, store: rig.store)
        XCTAssertNil(other)
    }

    func testAShowWithNoExtrasHasNoShelves() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let found = try await ShowExtras.load(seriesID: try await seriesID(rig, "Show Two"), store: rig.store)
        XCTAssertTrue(found.isEmpty)
    }

    func testTheShowsFolderIsTheOneAboveASeasonFolder() {
        let file = StoredFile(id: 1, sourceID: "s", path: "/TV/A/Season 3/a.mkv", name: "a.mkv", parentPath: "/TV/A/Season 3",
                              kind: .video, size: nil, modified: nil, etag: nil, serverToken: nil, itemID: 1, technical: nil,
                              firstSeen: Date(timeIntervalSince1970: 0), versionLabel: nil)
        let loose = StoredFile(id: 2, sourceID: "s", path: "/TV/B/b.mkv", name: "b.mkv", parentPath: "/TV/B",
                               kind: .video, size: nil, modified: nil, etag: nil, serverToken: nil, itemID: 2, technical: nil,
                               firstSeen: Date(timeIntervalSince1970: 0), versionLabel: nil)
        let places = ShowExtras.places(episodeFiles: [(3, file), (nil, loose)])
        XCTAssertEqual(places.map(\.folder), ["/TV/A", "/TV/B", "/TV/A/Season 3"])
        XCTAssertEqual(places.last?.season, 3)
    }
}
