import XCTest
import LibraryIndex
import MetadataOnline
@testable import AppLogic

/// R471 item 4: How to Watch and the Information, Languages and Accessibility columns, from data we hold only.
final class ProductSectionsTests: XCTestCase {
    private let en = Locale(identifier: "en_US")

    func testHowToWatchNamesTheSourceAndWhatIsLeft() {
        let resume = HowToWatch.make(sourceKind: .plex, sourceName: "Living Room", progress: 0.5, durationSeconds: 3600)
        XCTAssertEqual(resume, HowToWatch(symbol: "server.rack", spokenKind: "Media server", sourceName: "Living Room", action: "Resume", detail: "30m left"))
        let play = HowToWatch.make(sourceKind: .smb, sourceName: "NAS", progress: nil, durationSeconds: 2580)
        XCTAssertEqual(play?.action, "Play")
        XCTAssertEqual(play?.detail, "43m")
        XCTAssertEqual(play?.symbol, "externaldrive.connected.to.line.below")
    }

    func testHowToWatchFallsBackToTheKindAndIsNilWithoutASource() {
        XCTAssertNil(HowToWatch.make(sourceKind: nil, sourceName: nil, progress: nil, durationSeconds: 60))
        XCTAssertNil(HowToWatch.make(sourceKind: nil, sourceName: "  ", progress: nil, durationSeconds: 60))
        XCTAssertEqual(HowToWatch.make(sourceKind: .webdav, sourceName: "", progress: nil, durationSeconds: nil)?.sourceName, "Network folder")
        XCTAssertNil(HowToWatch.make(sourceKind: .webdav, sourceName: "Box", progress: nil, durationSeconds: nil)?.detail)
    }

    func testAShowsCardSaysWhichSeasonsAreHeld() {
        XCTAssertEqual(HowToWatch.seasonsLine([1]), "Season 1")
        XCTAssertEqual(HowToWatch.seasonsLine([3, 1, 2, 4, 2]), "Seasons 1–4")
        XCTAssertEqual(HowToWatch.seasonsLine([1, 3, 5]), "Seasons 1, 3, 5")
        XCTAssertEqual(HowToWatch.seasonsLine([0, 1, 2]), "Seasons 1–2 · Specials")
        XCTAssertEqual(HowToWatch.seasonsLine([0]), "Specials")
        XCTAssertNil(HowToWatch.seasonsLine([]))
        let show = HowToWatch.make(sourceKind: .jellyfin, sourceName: "Den", progress: 0.2, durationSeconds: 1200, seasonsLine: "Seasons 1–4")
        XCTAssertEqual(show?.detail, "Seasons 1–4")
        XCTAssertEqual(show?.action, "Resume")
    }

    func testInformationListsOnlyWhatIsHeld() {
        let rows = ProductInfo.information(released: PartialDate(year: 2024, month: 3, day: 5), year: 2024, durationSeconds: 2580,
                                           rating: "TV-14", advisories: ["Language", "language", "Violence"], regions: ["United States"], locale: en)
        XCTAssertEqual(rows.map(\.label), ["Released", "Run Time", "Rated", "Content Advisories", "Region of Origin"])
        XCTAssertEqual(rows[1].value, "43 min")
        XCTAssertEqual(rows[3].value, "Language, Violence")
        XCTAssertNil(rows[3].full)
        let bare = ProductInfo.information(released: nil, year: 1999, durationSeconds: nil, rating: " ", advisories: [], regions: [])
        XCTAssertEqual(bare, [InfoEntry(label: "Released", value: "1999")])
        XCTAssertEqual(ProductInfo.information(released: nil, year: nil, durationSeconds: 0, rating: nil, advisories: [], regions: []), [])
    }

    func testLanguagesComeFromTheFilesTracksEachOnce() {
        let tracks = FileTrackDetails(
            frameRate: nil,
            audio: [.init(codec: "eac3", channels: 6, language: "eng", name: nil, isDefault: false),
                    .init(codec: "aac", channels: 2, language: "fre", name: nil, isDefault: true),
                    .init(codec: "aac", channels: 2, language: "en", name: "Commentary", isDefault: false, isCommentary: true),
                    .init(codec: "aac", channels: 2, language: "und", name: nil, isDefault: false)],
            subtitles: [.init(codec: "subrip", language: "eng", name: nil, isForced: false, isHearingImpaired: false),
                        .init(codec: "subrip", language: "en", name: "SDH", isForced: false, isHearingImpaired: true),
                        .init(codec: "subrip", language: "spa", name: nil, isForced: false, isHearingImpaired: false),
                        .init(codec: "subrip", language: "ger", name: nil, isForced: false, isHearingImpaired: false),
                        .init(codec: "subrip", language: "jpn", name: nil, isForced: false, isHearingImpaired: false)])
        let rows = ProductInfo.languages(tracks: tracks)
        XCTAssertEqual(rows.map(\.label), ["Original Audio", "Audio", "Subtitles"])
        XCTAssertEqual(rows[0].value, "French", "no catalogue language: the default audio track")
        XCTAssertEqual(rows[1].value, "English, French")
        XCTAssertEqual(rows[2].value, "English, Spanish, German")
        XCTAssertEqual(rows[2].full, ["English", "Spanish", "German", "Japanese"], "More opens the whole list")
        XCTAssertEqual(ProductInfo.languages(tracks: tracks, originalLanguage: "ja").first?.value, "Japanese")
        XCTAssertEqual(ProductInfo.languages(tracks: nil), [])
    }

    func testRegionNamesAndTheDirectorLine() {
        XCTAssertEqual(ProductInfo.regionNames(["US", "GB"], locale: en), ["United States", "United Kingdom"])
        XCTAssertEqual(ProductInfo.regionNames(["ZZ"], locale: en).count, 1)
        XCTAssertEqual(ProductInfo.directorLine(["Ada Vale"])?.label, "Director")
        XCTAssertEqual(ProductInfo.directorLine(["Ada Vale", "Bo Lin", "ada vale"])?.label, "Directors")
        XCTAssertEqual(ProductInfo.directorLine(["Ada Vale", "Bo Lin"])?.names, "Ada Vale, Bo Lin")
        XCTAssertNil(ProductInfo.directorLine([" "]))
    }

    func testTheCatalogueFactsComeFromTheCrewCountriesAndLanguage() {
        var details = TitleDetails(overview: nil, cast: [])
        details.addCatalogueFacts(crew: [Person(id: 1, name: "Ada Vale", job: "Director"), Person(id: 2, name: "Cy Moor", job: "Writer"),
                                         Person(id: 1, name: "Ada Vale", job: "Director")],
                                  countries: ["US"], originalLanguage: " ")
        XCTAssertEqual(details.directors, ["Ada Vale"])
        XCTAssertEqual(details.regions, ["US"])
        XCTAssertNil(details.originalLanguage)
        XCTAssertFalse(details.isEmpty)
    }

    func testTheLayersKeepTheFactsOfTheFirstLayerThatHasThem() {
        var tmdb = TitleDetails(overview: "From the catalogue.", cast: [])
        tmdb.genres = ["Drama"]
        tmdb.releaseDate = PartialDate(year: 2001, month: 2, day: 3)
        tmdb.directors = ["Ada Vale"]
        tmdb.regions = ["US"]
        tmdb.originalLanguage = "en"
        var own = TitleDetails(overview: nil, cast: [])
        own.genres = ["Thriller"]
        let merged = LayeredDetails.merge([(.source, own), (.tmdb, tmdb)]).details
        XCTAssertEqual(merged?.genres, ["Thriller"], "the first layer with genres wins")
        XCTAssertEqual(merged?.releaseDate, PartialDate(year: 2001, month: 2, day: 3))
        XCTAssertEqual(merged?.directors, ["Ada Vale"])
        XCTAssertEqual(merged?.regions, ["US"])
        XCTAssertEqual(merged?.originalLanguage, "en")
        XCTAssertEqual(merged?.overview, "From the catalogue.")
    }

    func testAccessibilityExplainsEachFeatureTheFileCarries() {
        let rows = ProductInfo.accessibility([.sdh, .ad])
        XCTAssertEqual(rows.map(\.label), ["Subtitles for the deaf and hard of hearing", "Audio description"])
        XCTAssertTrue(rows.allSatisfy { !$0.value.isEmpty })
        XCTAssertEqual(ProductInfo.accessibility([]), [])
    }
}
