import XCTest
import VideoPlayerCore
@testable import LibraryIndex

/// R471 (24): trailers and bonus videos get no item of their own and are listed with their title's sidecars.
/// FIXTURE: invented titles and file names.
final class ExtraVideoTests: XCTestCase {
    func testTheRoleComesFromTheNameTagOrTheFolder() {
        XCTAssertEqual(ExtraVideo.role(name: "Hexfall (1995)-trailer.mkv", parentPath: "/Movies/Hexfall (1995)"), .trailer)
        XCTAssertEqual(ExtraVideo.role(name: "Hexfall (1995)-Teaser.mp4", parentPath: "/M"), .trailer)
        XCTAssertEqual(ExtraVideo.role(name: "Hexfall (1995)-featurette.mkv", parentPath: "/M"), .bonus)
        XCTAssertEqual(ExtraVideo.role(name: "Hexfall (1995)-deletedscene.mkv", parentPath: "/M"), .bonus)
        XCTAssertEqual(ExtraVideo.role(name: "First Look.mkv", parentPath: "/Movies/Hexfall (1995)/Trailers"), .trailer)
        XCTAssertEqual(ExtraVideo.role(name: "Making Of.mkv", parentPath: "/Movies/Hexfall (1995)/Behind The Scenes"), .bonus)
        XCTAssertNil(ExtraVideo.role(name: "Hexfall (1995).mkv", parentPath: "/Movies/Hexfall (1995)"))
        XCTAssertNil(ExtraVideo.role(name: "The Interview (2014).mkv", parentPath: "/Movies"), "a title that only contains a tag word")
        XCTAssertNil(ExtraVideo.role(name: "-trailer.mkv", parentPath: "/M"), "a tag alone is no extra")
        XCTAssertNil(ExtraVideo.role(name: "Film.mkv", parentPath: "/Movies/Shorts"), "Shorts is left out (R471 (24))")
        XCTAssertNil(ExtraVideo.role(name: "Film.mkv", parentPath: "/Movies/Other"))
    }

    func testExtrasGetNoItemAndAreTheTitlesSidecars() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995).mkv", size: 10_000, modified: day(1))
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995)-trailer.mkv", size: 300, modified: day(1))
        h.source.put("/Movies/Hexfall (1995)/Hexfall (1995)-featurette.mp4", size: 400, modified: day(1))
        h.source.put("/Movies/Hexfall (1995)/Trailers/First Look.mkv", size: 200, modified: day(1))
        h.source.put("/Movies/Hexfall (1995)/Extras/Making Of.mkv", size: 500, modified: day(1))
        try await h.syncer.sync()
        let all = try await h.store.page(ItemQuery(), limit: 10, offset: 0)
        XCTAssertEqual(titles(all), ["Hexfall"])
        let hexfall = try XCTUnwrap(all.first)
        XCTAssertEqual(hexfall.versionCount, 1, "a trailer is not a version of the film")
        let sidecars = try await h.store.sidecars(for: try XCTUnwrap(hexfall.preferredFileID))
        XCTAssertEqual(Set(sidecars.map(\.name)), ["Hexfall (1995)-trailer.mkv", "Hexfall (1995)-featurette.mp4", "First Look.mkv", "Making Of.mkv"])
        XCTAssertTrue(sidecars.allSatisfy { $0.kind == .video && $0.itemID == nil })

        // A second scan leaves them as they are.
        let again = try await h.syncer.sync()
        XCTAssertEqual(again.progress.unchanged, 5)
        try await expectEqual(try await h.store.counts().items, 1)
    }

    func testAnExtrasFolderSharedByTitlesGivesEachOnlyItsOwnExtras() async throws {
        let h = try Harness.make()
        defer { h.cleanup() }
        h.source.put("/Movies/Hexfall (1995).mkv", size: 10_000, modified: day(1))
        h.source.put("/Movies/Zornwick (2007).mkv", size: 9_000, modified: day(1))
        h.source.put("/Movies/Hexfall (1995)-trailer.mkv", size: 300, modified: day(1))
        h.source.put("/Movies/Trailers/Zornwick (2007) Teaser.mkv", size: 300, modified: day(1))
        h.source.put("/Movies/Trailers/Unnamed.mkv", size: 300, modified: day(1))
        try await h.syncer.sync()
        let all = try await h.store.page(ItemQuery(), limit: 10, offset: 0)
        XCTAssertEqual(titles(all), ["Hexfall", "Zornwick"])
        let hexfall = try await h.store.sidecars(for: try XCTUnwrap(all[0].preferredFileID))
        XCTAssertEqual(hexfall.map(\.name), ["Hexfall (1995)-trailer.mkv"])
        let zornwick = try await h.store.sidecars(for: try XCTUnwrap(all[1].preferredFileID))
        XCTAssertEqual(zornwick.map(\.name), ["Zornwick (2007) Teaser.mkv"], "a folder shared by two titles: only the extras named after one")
    }
}
