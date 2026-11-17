import XCTest
@testable import VideoPlayerCore

/// Collects every mismatch so one run shows all failures, with the file name that caused each.
final class ParserChecker {
    private(set) var checks = 0
    private(set) var failures: [String] = []

    func check(
        _ file: String, folders: [String] = [],
        title: String, year: Int? = nil, kind: ParsedMedia.Kind = .movie,
        season: Int? = nil, episodes: [Int] = [], absolute: Int? = nil, date: AirDate? = nil,
        special: Bool = false, edition: String? = nil, group: String? = nil,
        epTitle: String? = nil, part: Int? = nil, tmdb: Int? = nil, imdb: String? = nil
    ) {
        checks += 1
        let p = FilenameParser.parse(fileName: file, folders: folders)
        var problems: [String] = []
        func cmp<T: Equatable>(_ name: String, _ got: T, _ want: T) {
            if got != want { problems.append("\(name): got \(got), want \(want)") }
        }
        cmp("title", p.title, title)
        cmp("year", p.year, year)
        cmp("kind", p.kind, kind)
        cmp("season", p.season, season)
        cmp("episodes", p.episodes, episodes)
        cmp("absolute", p.absoluteEpisode, absolute)
        cmp("date", p.airDate, date)
        cmp("special", p.isSpecial, special)
        cmp("edition", p.edition, edition)
        cmp("group", p.releaseGroup, group)
        cmp("part", p.part, part)
        if let epTitle { cmp("episodeTitle", p.episodeTitle, epTitle) }
        if let tmdb { cmp("tmdb", p.tmdbID, tmdb) }
        if let imdb { cmp("imdb", p.imdbID, imdb) }
        if !problems.isEmpty {
            failures.append("\(file) \(folders.isEmpty ? "" : "in \(folders)") -> " + problems.joined(separator: "; "))
        }
    }

    func finish(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        print("PARSER-TESTS \(label): \(checks) checks, \(failures.count) failures")
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(checks) failed:\n" + failures.prefix(60).joined(separator: "\n"), file: file, line: line)
    }
}

final class FilenameParserTests: XCTestCase {

    // MARK: Hand-written realistic cases

    func testMovieCases() {
        let c = ParserChecker()
        c.check("1917.2019.1080p.BluRay.x264-GRP.mkv", title: "1917", year: 2019, group: "GRP")
        c.check("2012.1080p.BluRay.mkv", title: "2012")
        c.check("Neon Runner 2049 (2017).mkv", title: "Neon Runner 2049", year: 2017)
        c.check("2001 Moon Station 1968.mkv", title: "2001 Moon Station", year: 1968)
        c.check("Iron-Wing (2010).mkv", title: "Iron-Wing", year: 2010)
        c.check("Mr. Fox Lantern (2012).mkv", title: "Mr Fox Lantern", year: 2012)
        c.check("The Baker's Daughter (2014).mkv", title: "The Baker's Daughter", year: 2014)
        c.check("Amélie Lanterne (2001).mkv", title: "Amélie Lanterne", year: 2001)
        c.check("Re-Entry (2013).mkv", title: "Re-Entry", year: 2013)
        c.check("Title.mkv", title: "Title")
        c.check("Title.2010.mkv", title: "Title", year: 2010)
        c.check("Title (2010) 480p.avi", title: "Title", year: 2010)
        c.check("Title 1920x1080.mkv", title: "Title")
        c.check("Spider-Ish.2010.1080p.BluRay.x264-GRP.mkv", title: "Spider-Ish", year: 2010, group: "GRP")
        c.check("The Quiet Harbor (2019) {tmdb-12345}.mkv", title: "The Quiet Harbor", year: 2019, tmdb: 12345)
        c.check("The Quiet Harbor (2019) [tmdbid-12345].mkv", title: "The Quiet Harbor", year: 2019, tmdb: 12345)
        c.check("The Quiet Harbor (2019) tt1234567.mkv", title: "The Quiet Harbor", year: 2019, imdb: "tt1234567")
        c.check("Film Name (2010) cd2.avi", title: "Film Name", year: 2010, part: 2)
        c.check("Some.Movie.2010.UNRATED.720p.mkv", title: "Some Movie", year: 2010, edition: "Unrated")
        c.check("Another.Film.2005.Final.Cut.1080p.mkv", title: "Another Film", year: 2005, edition: "Final Cut")
        c.check("Epic.Film.2010.IMAX.2160p.mkv", title: "Epic Film", year: 2010, edition: "IMAX")
        c.check("The.Long.Story.Special.Edition.2005.mkv", title: "The Long Story", year: 2005, edition: "Special Edition")
        c.check("Extended Family (2012).mkv", title: "Extended Family", year: 2012)
        c.check("The.Movie.2009.1080p.BluRay.DTS-HD.MA.5.1.x264-GRP.mkv", title: "The Movie", year: 2009, group: "GRP")
        c.check("A Film About Web Design (2015).mkv", title: "A Film About Web Design", year: 2015)
        c.check("Web of Lies (2011).mkv", title: "Web of Lies", year: 2011)
        c.check("Dual Lives (2014).mkv", title: "Dual Lives", year: 2014)
        c.check("The Multi Level Mystery (2010).mkv", title: "The Multi Level Mystery", year: 2010)
        c.check("Agent 7 (2015).mkv", title: "Agent 7", year: 2015)
        c.check("Nine Lives 2 (2019).mkv", title: "Nine Lives 2", year: 2019)
        c.check("Room 237 (2012).mkv", title: "Room 237", year: 2012)
        c.check("Title (2010) [1080p] [BluRay] [YTS.MX].mp4", title: "Title", year: 2010, group: "YTS.MX")
        c.check("[GRP] Title (2010) [1080p].mkv", title: "Title", year: 2010, group: "GRP")
        c.check("Show Name - 2010.mkv", title: "Show Name", year: 2010)
        c.check("Title (2010) {edition-Director's Cut}.mkv", title: "Title", year: 2010, edition: "Director's Cut")
        c.finish("movies")
    }

    func testFolderContextForMovies() {
        let c = ParserChecker()
        c.check("Title.2020.1080p.mkv", folders: ["Movies", "Title (2020)"], title: "Title", year: 2020)
        c.check("sample.mkv", folders: ["Title (2020)"], title: "Title", year: 2020)
        c.check("movie.mkv", folders: ["Some Film (1999)", "Movies"], title: "Some Film", year: 1999)
        c.check("Title (2010).mkv", folders: ["Title (2010)"], title: "Title", year: 2010)
        c.check("Title.mkv", folders: ["Title (2010)"], title: "Title", year: 2010)
        c.finish("movie-folders")
    }

    func testEpisodeCases() {
        let c = ParserChecker()
        let ep = ParsedMedia.Kind.episode
        c.check("Show.Name.S01E01.mkv", title: "Show Name", kind: ep, season: 1, episodes: [1])
        c.check("Show Name - 1x05 - Title.mkv", title: "Show Name", kind: ep, season: 1, episodes: [5], epTitle: "Title")
        c.check("Show.Name.2019.S02E10.1080p.mkv", title: "Show Name", year: 2019, kind: ep, season: 2, episodes: [10])
        c.check("show_name_s01e02_720p.mkv", title: "show name", kind: ep, season: 1, episodes: [2])
        c.check("The.Show.S01.1080p.BluRay.mkv", title: "The Show", kind: ep, season: 1)
        c.check("Daily.Report.2023.11.05.720p.WEB.h264-GRP.mkv", title: "Daily Report", kind: ep,
                date: AirDate(year: 2023, month: 11, day: 5), group: "GRP")
        c.check("Daily Report - 2023-11-05.mkv", title: "Daily Report", kind: ep, date: AirDate(year: 2023, month: 11, day: 5))
        c.check("Show Name Season 2 Episode 11.mkv", title: "Show Name", kind: ep, season: 2, episodes: [11])
        c.check("Show.Name.S02E03.PROPER.720p.HDTV.x264-GRP.mkv", title: "Show Name", kind: ep, season: 2, episodes: [3], group: "GRP")
        c.check("Show.S01E01E02.mkv", title: "Show", kind: ep, season: 1, episodes: [1, 2])
        c.check("Show - S01E01-E03.mkv", title: "Show", kind: ep, season: 1, episodes: [1, 2, 3])
        c.check("Show.S10E105.mkv", title: "Show", kind: ep, season: 10, episodes: [105])
        c.check("Show 1x01-02.mkv", title: "Show", kind: ep, season: 1, episodes: [1, 2])
        c.check("Show Name S01E02 Episode Title 1080p WEB-DL.mkv", title: "Show Name", kind: ep, season: 1, episodes: [2], epTitle: "Episode Title")
        c.check("Show.Name.E05.mkv", title: "Show Name", kind: ep, episodes: [5])
        c.check("Show Name - 105.mkv", title: "Show Name", kind: ep, absolute: 105)
        c.check("Show.Name.S01E01.1080p.WEB-DL.DDP5.1.Atmos.DV.HEVC-GRP.mkv", title: "Show Name", kind: ep, season: 1, episodes: [1], group: "GRP")
        c.finish("episodes")
    }

    func testAnimeAndSpecials() {
        let c = ParserChecker()
        let ep = ParsedMedia.Kind.episode
        c.check("[SubGroup] Show Name - 012 [720p].mkv", title: "Show Name", kind: ep, absolute: 12, group: "SubGroup")
        c.check("[SubGroup] Show Name - 12v2 [1080p][HEVC].mkv", title: "Show Name", kind: ep, absolute: 12, group: "SubGroup")
        c.check("[SubGroup] Show Name - S02E05 [1080p].mkv", title: "Show Name", kind: ep, season: 2, episodes: [5], group: "SubGroup")
        c.check("[SubGroup] Show Name - 045 [1080p][ABCD1234].mkv", title: "Show Name", kind: ep, absolute: 45, group: "SubGroup")
        c.check("Show.Name.S00E03.mkv", title: "Show Name", kind: ep, season: 0, episodes: [3], special: true)
        c.check("Show Name Special 2.mkv", title: "Show Name", kind: ep, season: 0, episodes: [2], special: true)
        c.finish("anime-specials")
    }

    func testFolderContextForEpisodes() {
        let c = ParserChecker()
        let ep = ParsedMedia.Kind.episode
        c.check("01 - Pilot.mkv", folders: ["Season 1", "Harbor Lights (2015)"], title: "Harbor Lights", year: 2015, kind: ep, season: 1, episodes: [1], epTitle: "Pilot")
        c.check("Episode 05.mkv", folders: ["Season 2", "Paper Kingdom"], title: "Paper Kingdom", kind: ep, season: 2, episodes: [5])
        c.check("S00E01 - Behind the Scenes.mkv", folders: ["Specials", "Harbor Lights"], title: "Harbor Lights", kind: ep, season: 0, episodes: [1], special: true, epTitle: "Behind the Scenes")
        c.check("Show - S01E01.mkv", folders: ["Season 1", "Show"], title: "Show", kind: ep, season: 1, episodes: [1])
        c.check("S01E02.mkv", folders: ["Season 1", "Show Name (2018)"], title: "Show Name", year: 2018, kind: ep, season: 1, episodes: [2])
        c.check("E07.mkv", folders: ["Season 03", "TV Shows"], title: "", kind: ep, season: 3, episodes: [7])
        c.finish("episode-folders")
    }

    func testUnicodeNormalizationNFDMatchesNFC() {
        let nfd = "Ame\u{0301}lie Lanterne (2001).mkv"
        let nfc = "Amélie Lanterne (2001).mkv"
        XCTAssertEqual(FilenameParser.parse(fileName: nfd).title, FilenameParser.parse(fileName: nfc).title)
        XCTAssertEqual(FilenameParser.parse(fileName: nfd).title, "Amélie Lanterne")
    }

    func testTechnicalDetails() {
        let a = FilenameParser.parse(fileName: "The.Movie.2022.2160p.UHD.BluRay.DV.HDR10.HEVC.TrueHD.7.1.Atmos-GRP.mkv")
        XCTAssertEqual(a.resolution, "2160p")
        XCTAssertEqual(a.source, "Blu-ray")
        XCTAssertEqual(a.videoCodec, "HEVC")
        XCTAssertEqual(a.audioCodec, "Atmos")
        XCTAssertEqual(a.hdr, "Dolby Vision")
        let b = FilenameParser.parse(fileName: "The.Movie.2015.1080p.WEB-DL.DDP5.1.H.264-GRP.mkv")
        XCTAssertEqual(b.resolution, "1080p")
        XCTAssertEqual(b.source, "WEB-DL")
        XCTAssertEqual(b.videoCodec, "H.264")
        XCTAssertEqual(b.audioCodec, "DD+")
        XCTAssertNil(b.hdr)
        let c = FilenameParser.parse(fileName: "Title.2008.720p.HDTV.x264.AAC-GRP.mp4")
        XCTAssertEqual(c.source, "HDTV")
        XCTAssertEqual(c.audioCodec, "AAC")
    }

    // MARK: Generated sets (fictional titles only)

    private let movieTitles = [
        "The Quiet Harbor", "Midnight Orchard", "Paper Lanterns", "Blue Meridian", "Iron Meadow",
        "A Long Way Home Again", "Nine Lives Two", "Silver Creek Road", "Winter Garden", "Glass Mountain",
        "The Last Lighthouse Keeper", "Saffron Skies", "Harvest Moon Club", "Copper Valley", "Northern Static",
        "Echoes of Tomorrow", "Paper Moon Cafe", "Velvet Thunder", "Hidden Staircase", "Tin Soldier Parade"
    ]
    private let years = [1974, 1999, 2008, 2016, 2021]

    func testGeneratedMovieNames() {
        let c = ParserChecker()
        for (i, title) in movieTitles.enumerated() {
            let y = years[i % years.count]
            let dot = title.replacingOccurrences(of: " ", with: ".")
            let under = title.replacingOccurrences(of: " ", with: "_")
            c.check("\(dot).\(y).1080p.BluRay.x264-GRP.mkv", title: title, year: y, group: "GRP")
            c.check("\(title) (\(y)).mkv", title: title, year: y)
            c.check("\(title) (\(y)) [1080p].mp4", title: title, year: y)
            c.check("\(dot).\(y).2160p.UHD.BluRay.REMUX.HDR10.HEVC.TrueHD.7.1.Atmos-GRP.mkv", title: title, year: y, group: "GRP")
            c.check("\(dot).\(y).720p.WEB-DL.DD+5.1.H.264-GRP.mp4", title: title, year: y, group: "GRP")
            c.check("\(title) \(y) 1080p BluRay DTS-HD MA 5.1 x265 10bit-GRP.mkv", title: title, year: y, group: "GRP")
            c.check("\(under)_\(y)_DVDRip_XviD-GRP.avi", title: title.replacingOccurrences(of: " ", with: " "), year: y, group: "GRP")
            c.check("\(title) (\(y)) {edition-Director's Cut}.mkv", title: title, year: y, edition: "Director's Cut")
            c.check("\(dot).\(y).Directors.Cut.1080p.BluRay.x264-GRP.mkv", title: title, year: y, edition: "Director's Cut", group: "GRP")
            c.check("\(dot).\(y).EXTENDED.2160p.WEB-DL.DDP5.1.Atmos.DV.HDR.H.265-GRP.mkv", title: title, year: y, edition: "Extended", group: "GRP")
            c.check("\(title) [\(y)] [1080p] [YTS.MX].mp4", title: title, year: y, group: "YTS.MX")
            c.check("\(dot).\(y).mkv", title: title, year: y)
            c.check("movie.mkv", folders: ["\(title) (\(y))", "Movies"], title: title, year: y)
            c.check("\(title) (\(y)) - 2160p.mkv", title: title, year: y)
            c.check("\(dot).\(y).1080p.WEB-DL.DDP5.1.H.264-GRP.ts", title: title, year: y, group: "GRP")
        }
        c.finish("generated-movies")
    }

    private let shows = [
        "Harbor Lights", "Paper Kingdom", "The Midnight Diner", "Copper Street", "Northern Reach", "Silent Orchard",
        "Blue Hour", "The Lantern Club", "Iron Valley", "Summer Static", "Glass Harbor", "Winter Ledger"
    ]
    private let episodeTitles = ["The Long Night", "First Light", "A Quiet Morning", "Crossing Over"]

    func testGeneratedEpisodeNames() {
        let c = ParserChecker()
        let ep = ParsedMedia.Kind.episode
        for (i, show) in shows.enumerated() {
            let s = 1 + i % 3
            let e = 2 + i % 6          // 2...7
            let x = episodeTitles[i % episodeTitles.count]
            let dot = show.replacingOccurrences(of: " ", with: ".")
            c.check("\(dot).S0\(s)E0\(e).1080p.WEB-DL.DD5.1.H.264-GRP.mkv", title: show, kind: ep, season: s, episodes: [e], group: "GRP")
            c.check("\(show) - S0\(s)E0\(e) - \(x).mkv", title: show, kind: ep, season: s, episodes: [e], epTitle: x)
            c.check("\(show) (2015) - S0\(s)E0\(e) - \(x) [1080p].mkv", title: show, year: 2015, kind: ep, season: s, episodes: [e], epTitle: x)
            c.check("\(dot).\(s)x0\(e).720p.HDTV.x264-GRP.mkv", title: show, kind: ep, season: s, episodes: [e], group: "GRP")
            c.check("\(show) Season \(s) Episode \(e).mkv", title: show, kind: ep, season: s, episodes: [e])
            c.check("\(dot).S0\(s)E0\(e)E0\(e + 1).1080p.mkv", title: show, kind: ep, season: s, episodes: [e, e + 1])
            c.check("\(show) - S0\(s)E0\(e)-E0\(e + 2) - \(x).mkv", title: show, kind: ep, season: s, episodes: [e, e + 1, e + 2], epTitle: x)
            c.check("\(dot).S0\(s)E0\(e)-0\(e + 1).mkv", title: show, kind: ep, season: s, episodes: [e, e + 1])
            c.check("\(show) - 2023-05-14 - \(x).mkv", title: show, kind: ep, date: AirDate(year: 2023, month: 5, day: 14), epTitle: x)
            c.check("0\(e) - \(x).mkv", folders: ["Season \(s)", show], title: show, kind: ep, season: s, episodes: [e], epTitle: x)
            c.check("\(dot).S00E0\(e).mkv", title: show, kind: ep, season: 0, episodes: [e], special: true)
            c.check("[SubGroup] \(show) - 04\(e) [1080p][ABCD1234].mkv", title: show, kind: ep, absolute: 40 + e, group: "SubGroup")
            c.check("\(dot).S0\(s)E0\(e).2160p.WEB-DL.DDP5.1.Atmos.DV.HEVC-GRP.mkv", title: show, kind: ep, season: s, episodes: [e], group: "GRP")
        }
        c.finish("generated-episodes")
    }
}
