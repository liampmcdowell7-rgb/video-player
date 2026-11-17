import XCTest
import Foundation
import VideoPlayerCore
@testable import MetadataLocal

final class SidecarImageTests: XCTestCase {
    private func files(_ names: [String], in folder: String = "/Movies/Film") -> [SourceEntry] {
        names.map { SourceEntry(path: folder + "/" + $0, name: $0, isDirectory: false, size: 1000) }
    }

    private func dir(_ name: String, in folder: String = "/Shows/Show") -> SourceEntry {
        SourceEntry(path: folder + "/" + name, name: name, isDirectory: true)
    }

    private func name(_ entry: SourceEntry?) -> String? { entry?.name }

    // MARK: Movies

    func testMovieFolderImagesWhenFolderHoldsOneVideo() {
        let list = files(["Film (2020).mkv", "poster.jpg", "fanart.jpg", "clearlogo.png", "banner.jpg", "landscape.jpg", "thumb.jpg"])
        let found = SidecarImageFinder.images(forMovie: "Film (2020).mkv", in: list, folderHoldsOneVideo: true)
        XCTAssertEqual(name(found.poster), "poster.jpg")
        XCTAssertEqual(name(found.backdrop), "fanart.jpg")
        XCTAssertEqual(name(found.logo), "clearlogo.png")
        XCTAssertEqual(name(found.banner), "banner.jpg")
        XCTAssertEqual(name(found.landscape), "landscape.jpg")
        XCTAssertEqual(name(found.thumb), "thumb.jpg")
        XCTAssertFalse(found.isEmpty)
    }

    func testFolderWideImagesAreNotGivenToOneOfSeveralVideos() {
        let list = files(["A.mkv", "B.mkv", "poster.jpg", "fanart.jpg", "A-poster.jpg"])
        let a = SidecarImageFinder.images(forMovie: "A.mkv", in: list, folderHoldsOneVideo: false)
        let b = SidecarImageFinder.images(forMovie: "B.mkv", in: list, folderHoldsOneVideo: false)
        XCTAssertEqual(name(a.poster), "A-poster.jpg")
        XCTAssertNil(a.backdrop)
        XCTAssertTrue(b.isEmpty)
    }

    func testPosterNamePrecedence() {
        // Strongest first: same-name -poster, same-name .poster, plain same-name, then folder-wide poster/folder/cover.
        let everything = files(["Film.mkv", "cover.jpg", "folder.jpg", "poster.jpg", "Film.jpg", "Film.poster.jpg", "Film-poster.jpg"])
        func poster(removing names: [String]) -> String? {
            let list = everything.filter { !names.contains($0.name) }
            return name(SidecarImageFinder.images(forMovie: "Film.mkv", in: list, folderHoldsOneVideo: true).poster)
        }
        XCTAssertEqual(poster(removing: []), "Film-poster.jpg")
        XCTAssertEqual(poster(removing: ["Film-poster.jpg"]), "Film.poster.jpg")
        XCTAssertEqual(poster(removing: ["Film-poster.jpg", "Film.poster.jpg"]), "Film.jpg")
        XCTAssertEqual(poster(removing: ["Film-poster.jpg", "Film.poster.jpg", "Film.jpg"]), "poster.jpg")
        XCTAssertEqual(poster(removing: ["Film-poster.jpg", "Film.poster.jpg", "Film.jpg", "poster.jpg"]), "folder.jpg")
        XCTAssertEqual(poster(removing: ["Film-poster.jpg", "Film.poster.jpg", "Film.jpg", "poster.jpg", "folder.jpg"]), "cover.jpg")
        XCTAssertNil(poster(removing: ["Film-poster.jpg", "Film.poster.jpg", "Film.jpg", "poster.jpg", "folder.jpg", "cover.jpg"]))
    }

    func testBackdropNamePrecedence() {
        let everything = files(["Film.mkv", "background.jpg", "backdrop.jpg", "fanart.jpg", "Film-fanart.jpg"])
        func backdrop(removing names: [String]) -> String? {
            let list = everything.filter { !names.contains($0.name) }
            return name(SidecarImageFinder.images(forMovie: "Film.mkv", in: list, folderHoldsOneVideo: true).backdrop)
        }
        XCTAssertEqual(backdrop(removing: []), "Film-fanart.jpg")
        XCTAssertEqual(backdrop(removing: ["Film-fanart.jpg"]), "fanart.jpg")
        XCTAssertEqual(backdrop(removing: ["Film-fanart.jpg", "fanart.jpg"]), "backdrop.jpg")
        XCTAssertEqual(backdrop(removing: ["Film-fanart.jpg", "fanart.jpg", "backdrop.jpg"]), "background.jpg")
    }

    func testPlainSameNameImageIsAPosterNotABackdrop() {
        let found = SidecarImageFinder.images(forMovie: "Film.mkv", in: files(["Film.mkv", "Film.jpg"]), folderHoldsOneVideo: false)
        XCTAssertEqual(name(found.poster), "Film.jpg")
        XCTAssertNil(found.backdrop)
        XCTAssertNil(found.thumb)
    }

    func testExtensionPreferenceAndCaseInsensitivity() {
        let list = files(["Film.mkv", "POSTER.PNG", "poster.webp", "Poster.JPG", "poster.tbn"])
        XCTAssertEqual(name(SidecarImageFinder.images(forMovie: "Film.mkv", in: list, folderHoldsOneVideo: true).poster), "Poster.JPG")
        let noJpg = files(["Film.mkv", "poster.tbn", "poster.webp", "poster.png"])
        XCTAssertEqual(name(SidecarImageFinder.images(forMovie: "Film.mkv", in: noJpg, folderHoldsOneVideo: true).poster), "poster.png")
        let jpeg = files(["Film.mkv", "poster.jpeg", "poster.png"])
        XCTAssertEqual(name(SidecarImageFinder.images(forMovie: "Film.mkv", in: jpeg, folderHoldsOneVideo: true).poster), "poster.jpeg")
        let tbn = files(["Film.mkv", "Film-poster.tbn"])
        XCTAssertEqual(name(SidecarImageFinder.images(forMovie: "Film.mkv", in: tbn, folderHoldsOneVideo: true).poster), "Film-poster.tbn")
        let webp = files(["Film.mkv", "fanart.webp"])
        XCTAssertEqual(name(SidecarImageFinder.images(forMovie: "Film.mkv", in: webp, folderHoldsOneVideo: true).backdrop), "fanart.webp")
    }

    func testNonImagesAndFoldersAreIgnored() {
        var list = files(["Film.mkv", "poster.txt", "poster.nfo", "poster.jpg.part", "poster"])
        list.append(SourceEntry(path: "/Movies/Film/poster.jpg", name: "poster.jpg", isDirectory: true))
        XCTAssertTrue(SidecarImageFinder.images(forMovie: "Film.mkv", in: list, folderHoldsOneVideo: true).isEmpty)
    }

    func testSameNameMatchingIsCaseInsensitiveAndKeepsTheEntry() {
        let list = files(["FILM (2020).MKV", "film (2020)-POSTER.JPG"])
        let found = SidecarImageFinder.images(forMovie: "FILM (2020).MKV", in: list, folderHoldsOneVideo: false)
        XCTAssertEqual(found.poster?.path, "/Movies/Film/film (2020)-POSTER.JPG")
    }

    func testNamesWithDotsInTheBaseName() {
        let list = files(["Mr. Nobody.2009.1080p.mkv", "Mr. Nobody.2009.1080p-poster.jpg"])
        XCTAssertEqual(name(SidecarImageFinder.images(forMovie: "Mr. Nobody.2009.1080p.mkv", in: list, folderHoldsOneVideo: false).poster),
                       "Mr. Nobody.2009.1080p-poster.jpg")
    }

    func testRoleSubscript() {
        var images = SidecarImages()
        XCTAssertTrue(images.isEmpty)
        for role in SidecarImageRole.allCases {
            images[role] = SourceEntry(path: "/\(role.rawValue).jpg", name: "\(role.rawValue).jpg", isDirectory: false)
            XCTAssertEqual(images[role]?.name, "\(role.rawValue).jpg")
        }
        XCTAssertFalse(images.isEmpty)
        XCTAssertEqual(images.logo?.name, "logo.jpg")
    }

    // MARK: Episodes

    func testEpisodeImagesAreSameNameOnly() {
        let list = files(["S01E01.mkv", "S01E01.jpg", "S01E02.mkv", "S01E02-thumb.jpg", "S01E03.mkv", "S01E03.thumb.jpg",
                          "poster.jpg", "fanart.jpg", "folder.jpg"], in: "/Shows/Show/Season 1")
        XCTAssertEqual(name(SidecarImageFinder.images(forEpisode: "S01E01.mkv", in: list).thumb), "S01E01.jpg")
        XCTAssertEqual(name(SidecarImageFinder.images(forEpisode: "S01E02.mkv", in: list).thumb), "S01E02-thumb.jpg")
        XCTAssertEqual(name(SidecarImageFinder.images(forEpisode: "S01E03.mkv", in: list).thumb), "S01E03.thumb.jpg")
        let none = SidecarImageFinder.images(forEpisode: "S01E04.mkv", in: list)
        XCTAssertTrue(none.isEmpty, "The folder's poster and fanart belong to the season or show, not to an episode")
    }

    func testEpisodeThumbPrecedenceAndExtras() {
        let list = files(["E.mkv", "E.jpg", "E-thumb.jpg", "E.thumb.jpg", "E-poster.jpg", "E-fanart.jpg", "E-landscape.png", "E-clearlogo.png"])
        let found = SidecarImageFinder.images(forEpisode: "E.mkv", in: list)
        XCTAssertEqual(name(found.thumb), "E-thumb.jpg")
        XCTAssertEqual(name(found.poster), "E-poster.jpg")
        XCTAssertEqual(name(found.backdrop), "E-fanart.jpg")
        XCTAssertEqual(name(found.landscape), "E-landscape.png")
        XCTAssertEqual(name(found.logo), "E-clearlogo.png")
        let second = SidecarImageFinder.images(forEpisode: "E.mkv", in: list.filter { $0.name != "E-thumb.jpg" })
        XCTAssertEqual(name(second.thumb), "E.thumb.jpg")
        let third = SidecarImageFinder.images(forEpisode: "E.mkv", in: list.filter { $0.name != "E-thumb.jpg" && $0.name != "E.thumb.jpg" })
        XCTAssertEqual(name(third.thumb), "E.jpg")
    }

    // MARK: Show and season

    func testShowFolderImages() {
        let list = files(["poster.jpg", "fanart.jpg", "banner.jpg", "clearlogo.png", "landscape.jpg", "season01-poster.jpg", "tvshow.nfo"], in: "/Shows/Show")
        let found = SidecarImageFinder.images(forShowFolder: list)
        XCTAssertEqual(name(found.poster), "poster.jpg")
        XCTAssertEqual(name(found.backdrop), "fanart.jpg")
        XCTAssertEqual(name(found.banner), "banner.jpg")
        XCTAssertEqual(name(found.logo), "clearlogo.png")
        XCTAssertEqual(name(found.landscape), "landscape.jpg")
        XCTAssertNil(found.thumb)
        let folderJpg = SidecarImageFinder.images(forShowFolder: files(["folder.jpg", "show.jpg"]))
        XCTAssertEqual(name(folderJpg.poster), "folder.jpg")
        let showJpg = SidecarImageFinder.images(forShowFolder: files(["show.jpg"]))
        XCTAssertEqual(name(showJpg.poster), "show.jpg")
    }

    func testSeasonPostersFromTheShowFolder() {
        let list = files(["season01-poster.jpg", "season02-poster.png", "season-specials-poster.jpg", "season03.jpg", "season04-banner.jpg",
                          "season-all-poster.jpg", "poster.jpg"], in: "/Shows/Show")
        func poster(_ n: Int) -> String? { name(SidecarImageFinder.images(forSeason: n, showFolder: list, seasonFolder: nil).poster) }
        XCTAssertEqual(poster(1), "season01-poster.jpg")
        XCTAssertEqual(poster(2), "season02-poster.png")
        XCTAssertEqual(poster(0), "season-specials-poster.jpg")
        XCTAssertEqual(poster(3), "season03.jpg")
        XCTAssertNil(poster(5))
        XCTAssertEqual(name(SidecarImageFinder.images(forSeason: 4, showFolder: list, seasonFolder: nil).banner), "season04-banner.jpg")
    }

    func testSeasonNumberVariantsInFileNames() {
        func poster(_ stem: String, season: Int) -> String? {
            name(SidecarImageFinder.images(forSeason: season, showFolder: files(["\(stem).jpg"]), seasonFolder: nil).poster)
        }
        XCTAssertEqual(poster("season1-poster", season: 1), "season1-poster.jpg")
        XCTAssertEqual(poster("season-01-poster", season: 1), "season-01-poster.jpg")
        XCTAssertEqual(poster("season 01-poster", season: 1), "season 01-poster.jpg")
        XCTAssertEqual(poster("season00-poster", season: 0), "season00-poster.jpg")
        XCTAssertEqual(poster("season01-poster", season: 10), nil, "Season 1 art is not season 10 art")
        XCTAssertEqual(poster("season10-poster", season: 1), nil)
    }

    func testSeasonFolderImagesFillTheGaps() {
        let show = files(["season01-poster.jpg"], in: "/Shows/Show")
        let season = files(["poster.jpg", "fanart.jpg", "folder.jpg"], in: "/Shows/Show/Season 1")
        let found = SidecarImageFinder.images(forSeason: 1, showFolder: show, seasonFolder: season)
        XCTAssertEqual(name(found.poster), "season01-poster.jpg", "The show folder's season poster wins over the season folder's own")
        XCTAssertEqual(name(found.backdrop), "fanart.jpg")
        let withoutShowPoster = SidecarImageFinder.images(forSeason: 1, showFolder: [], seasonFolder: season)
        XCTAssertEqual(name(withoutShowPoster.poster), "poster.jpg")
        let named = SidecarImageFinder.images(forSeason: 2, showFolder: [], seasonFolder: files(["season02-poster.jpg"], in: "/Shows/Show/Season 2"))
        XCTAssertEqual(name(named.poster), "season02-poster.jpg")
    }

    func testSeasonFolderNumbers() {
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Season 1"), 1)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Season 02"), 2)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "season.3"), 3)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Season_04"), 4)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Series 5"), 5)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Staffel 6"), 6)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Saison 7"), 7)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Temporada 8"), 8)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "S9"), 9)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "s10"), 10)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "Specials"), 0)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: "specials"), 0)
        XCTAssertEqual(SidecarImageFinder.seasonNumber(ofFolder: " Season 3 "), 3)
        XCTAssertNil(SidecarImageFinder.seasonNumber(ofFolder: "Extras"))
        XCTAssertNil(SidecarImageFinder.seasonNumber(ofFolder: "Season"))
        XCTAssertNil(SidecarImageFinder.seasonNumber(ofFolder: "Season 1 Extras"))
        XCTAssertNil(SidecarImageFinder.seasonNumber(ofFolder: "Seasoned 1"))
        XCTAssertNil(SidecarImageFinder.seasonNumber(ofFolder: "Show Name"))
    }

    func testDirectoryEntriesNeverCountAsImages() {
        let list = [dir("poster.jpg"), dir("season01-poster.jpg")]
        XCTAssertTrue(SidecarImageFinder.images(forShowFolder: list).isEmpty)
        XCTAssertTrue(SidecarImageFinder.images(forSeason: 1, showFolder: list, seasonFolder: nil).isEmpty)
        XCTAssertTrue(SidecarImageFinder.images(forEpisode: "x.mkv", in: [dir("x.jpg")]).isEmpty)
    }

    func testSplitHelper() {
        XCTAssertEqual(SidecarImageFinder.split("Poster.JPG")?.stem, "poster")
        XCTAssertEqual(SidecarImageFinder.split("Poster.JPG")?.ext, "jpg")
        XCTAssertNil(SidecarImageFinder.split("poster.gif"))
        XCTAssertNil(SidecarImageFinder.split(".jpg"), "A name that is only an extension is not an image of anything")
        XCTAssertNil(SidecarImageFinder.split("noextension"))
    }
}
