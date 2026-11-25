import XCTest
import LibraryIndex
@testable import AppLogic

/// R471 (24): a Trailers or Bonus Content card plays its own file, found again among the title's extras.
/// FIXTURE: invented titles and file names.
final class ExtraPlaybackTests: XCTestCase {
    func testACardFindsItsTitlesExtraAndNothingElse() async throws {
        let rig = try LibraryRig.make()
        rig.source.put("/Movies/Hexfall (1995)/Hexfall (1995)-trailer.mkv", size: 300, modified: dayOffset(1))
        rig.source.put("/Movies/Hexfall (1995)/Trailers/First Look.mkv", size: 200, modified: dayOffset(1))
        rig.source.put("/Movies/Hexfall (1995)/Hexfall (1995).nfo", size: 20, modified: dayOffset(1))
        try await rig.fill()
        let hexfall = try await rig.movieID("Hexfall")
        let item = try await rig.store.item(id: hexfall)
        let preferred = try XCTUnwrap(item?.preferredFileID)
        let extras = try await rig.store.sidecars(for: preferred)
        let trailer = try XCTUnwrap(extras.first { $0.name == "Hexfall (1995)-trailer.mkv" })
        let firstLook = try XCTUnwrap(extras.first { $0.name == "First Look.mkv" })
        let nfo = try XCTUnwrap(extras.first { $0.kind == .nfo })

        let found = try await ExtraFiles.find(itemID: hexfall, extraID: trailer.id, store: rig.store)
        XCTAssertEqual(found?.path, "/Movies/Hexfall (1995)/Hexfall (1995)-trailer.mkv")
        let inFolder = try await ExtraFiles.find(itemID: hexfall, extraID: firstLook.id, store: rig.store)
        XCTAssertEqual(inFolder?.path, "/Movies/Hexfall (1995)/Trailers/First Look.mkv")
        let notVideo = try await ExtraFiles.find(itemID: hexfall, extraID: nfo.id, store: rig.store)
        XCTAssertNil(notVideo, "only a video plays")
        let other = try await ExtraFiles.find(itemID: try await rig.movieID("Aftlander"), extraID: trailer.id, store: rig.store)
        XCTAssertNil(other, "another title's card cannot play this file")
        let versions = try await rig.store.versions(of: hexfall)
        XCTAssertEqual(versions.count, 1, "the trailer is not a version of the film")
    }

    func testATrailerByItsFolderGoesOnTheTrailersShelf() {
        let rows = [ExtraRow(id: 1, name: "First Look.mkv", kindText: "Video", sizeText: nil, isVideo: true, isTrailer: true),
                    ExtraRow(id: 2, name: "Making Of.mkv", kindText: "Video", sizeText: nil, isVideo: true)]
        let split = ExtraShelves.split(rows)
        XCTAssertEqual(split.trailers.map(\.id), [1])
        XCTAssertEqual(split.bonus.map(\.id), [2])
        XCTAssertEqual(ExtraShelves.displayName("Hexfall-deletedscene.mkv"), "Hexfall")
        XCTAssertEqual(ExtraShelves.displayName("Hexfall-clip.mkv"), "Hexfall")
    }
}
