import XCTest
import Foundation
@testable import MetadataLocal

// Every nfo below is a hand-written sample that follows the publicly documented NFO conventions. None is a recording of
// a file written by Jellyfin, Emby or any other tool. Real-world files from those tools are untested.

private let fullMovie = """
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <title>The Matrix</title>
  <originaltitle>The Matrix Original</originaltitle>
  <sorttitle>Matrix 1</sorttitle>
  <year>1999</year>
  <premiered>1999-03-31</premiered>
  <plot>A hacker learns the truth.</plot>
  <outline>Short outline.</outline>
  <tagline>Welcome to the Real World</tagline>
  <runtime>136</runtime>
  <mpaa>Rated R</mpaa>
  <genre>Action</genre>
  <genre>Sci-Fi</genre>
  <genre>action</genre>
  <studio>Warner Bros.</studio>
  <country>USA</country>
  <tag>cyberpunk</tag>
  <ratings>
    <rating name="imdb" max="10" default="true"><value>8.7</value><votes>1,900,000</votes></rating>
    <rating name="themoviedb" max="10"><value>8.2</value><votes>25000</votes></rating>
  </ratings>
  <criticrating>73</criticrating>
  <userrating>9</userrating>
  <uniqueid type="tmdb" default="true">603</uniqueid>
  <uniqueid type="imdb">tt0133093</uniqueid>
  <set>
    <name>The Matrix Collection</name>
    <tmdbcolid>2344</tmdbcolid>
  </set>
  <director>Lana Wachowski</director>
  <director>Lilly Wachowski</director>
  <credits>Lilly Wachowski</credits>
  <actor>
    <name>Keanu Reeves</name>
    <role>Neo</role>
    <order>0</order>
    <thumb>https://example.invalid/keanu.jpg</thumb>
  </actor>
  <actor>
    <name>Carrie-Anne Moss</name>
    <role>Trinity</role>
    <order>1</order>
  </actor>
  <thumb aspect="poster">poster.jpg</thumb>
  <thumb aspect="landscape">landscape.jpg</thumb>
  <fanart><thumb>fanart.jpg</thumb></fanart>
  <trailer>https://example.invalid/trailer</trailer>
  <playcount>2</playcount>
  <resume><position>120.5</position><total>8160</total></resume>
</movie>
"""

final class NFOTests: XCTestCase {
    private func parse(_ text: String) -> NFOFile { NFOParser.parse(text: text) }
    private func movie(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> NFOMetadata {
        let result = parse(text)
        return try XCTUnwrap(result.documents.first, "No document in \(result)", file: file, line: line)
    }

    // MARK: Movie

    func testFullMovie() throws {
        let file = parse(fullMovie)
        XCTAssertEqual(file.warnings, [])
        XCTAssertEqual(file.documents.count, 1)
        let m = try XCTUnwrap(file.documents.first)
        XCTAssertEqual(m.kind, .movie)
        XCTAssertEqual(m.title, "The Matrix")
        XCTAssertEqual(m.originalTitle, "The Matrix Original")
        XCTAssertEqual(m.sortTitle, "Matrix 1")
        XCTAssertEqual(m.year, 1999)
        XCTAssertEqual(m.premiered, CalendarDay(year: 1999, month: 3, day: 31))
        XCTAssertEqual(m.plot, "A hacker learns the truth.")
        XCTAssertEqual(m.outline, "Short outline.")
        XCTAssertEqual(m.tagline, "Welcome to the Real World")
        XCTAssertEqual(m.runtimeMinutes, 136)
        XCTAssertEqual(m.certification, "Rated R")
        XCTAssertEqual(m.genres, ["Action", "Sci-Fi"], "Duplicates ignoring case are dropped")
        XCTAssertEqual(m.studios, ["Warner Bros."])
        XCTAssertEqual(m.countries, ["USA"])
        XCTAssertEqual(m.tags, ["cyberpunk"])
        XCTAssertEqual(m.directors, ["Lana Wachowski", "Lilly Wachowski"])
        XCTAssertEqual(m.writers, ["Lilly Wachowski"])
        XCTAssertEqual(m.trailer, "https://example.invalid/trailer")
        XCTAssertEqual(m.playCount, 2)
        XCTAssertEqual(m.resumePositionSeconds, 120.5)
        XCTAssertEqual(m.resumeTotalSeconds, 8160)
    }

    func testRatingsFromSeveralSources() throws {
        let m = try movie(fullMovie)
        XCTAssertEqual(m.ratings.count, 4)
        let imdb = try XCTUnwrap(m.ratings.first { $0.name == "imdb" })
        XCTAssertEqual(imdb.value, 8.7)
        XCTAssertEqual(imdb.votes, 1_900_000)
        XCTAssertEqual(imdb.max, 10)
        XCTAssertTrue(imdb.isDefault)
        let tmdb = try XCTUnwrap(m.ratings.first { $0.name == "themoviedb" })
        XCTAssertEqual(tmdb.votes, 25000)
        XCTAssertFalse(tmdb.isDefault)
        let critic = try XCTUnwrap(m.ratings.first { $0.name == "critic" })
        XCTAssertEqual(critic.value, 73)
        XCTAssertEqual(critic.max, 100)
        XCTAssertEqual(try XCTUnwrap(m.ratings.first { $0.name == "user" }).value, 9)
    }

    func testUniqueIDsCollectionAndPeople() throws {
        let m = try movie(fullMovie)
        XCTAssertEqual(m.tmdbID, 603)
        XCTAssertEqual(m.imdbID, "tt0133093")
        XCTAssertNil(m.tvdbID)
        XCTAssertEqual(m.uniqueIDs.count, 2)
        XCTAssertTrue(m.uniqueIDs[0].isDefault)
        XCTAssertEqual(m.uniqueID("TMDB"), "603")
        XCTAssertEqual(m.collectionName, "The Matrix Collection")
        XCTAssertEqual(m.collectionTMDBID, 2344)
        XCTAssertEqual(m.actors.map(\.name), ["Keanu Reeves", "Carrie-Anne Moss"])
        XCTAssertEqual(m.actors[0].role, "Neo")
        XCTAssertEqual(m.actors[0].order, 0)
        XCTAssertEqual(m.actors[0].thumb, "https://example.invalid/keanu.jpg")
        XCTAssertNil(m.actors[1].thumb)
    }

    func testArtworkReferences() throws {
        let m = try movie(fullMovie)
        XCTAssertEqual(m.artwork.count, 3, "The actor's thumb is not movie artwork")
        XCTAssertEqual(m.artwork[0], NFOArtwork(kind: .poster, location: "poster.jpg"))
        XCTAssertEqual(m.artwork[1], NFOArtwork(kind: .landscape, location: "landscape.jpg"))
        XCTAssertEqual(m.artwork[2], NFOArtwork(kind: .fanart, location: "fanart.jpg"))
    }

    func testUniqueIDDefaultFlagWins() throws {
        let m = try movie("<movie><uniqueid type=\"tmdb\">1</uniqueid><uniqueid type=\"tmdb\" default=\"true\">2</uniqueid></movie>")
        XCTAssertEqual(m.tmdbID, 2)
        XCTAssertEqual(m.uniqueID("tmdb"), "2")
    }

    func testLegacyRatingVotesIDsAndSet() throws {
        let m = try movie("""
        <movie>
          <title>Old Style</title>
          <rating>7.5</rating>
          <votes>1,234</votes>
          <tmdbid>603</tmdbid>
          <imdbid>tt0133093</imdbid>
          <set>Trilogy</set>
          <id>tt0133093</id>
        </movie>
        """)
        XCTAssertEqual(m.ratings, [NFORating(name: nil, value: 7.5, votes: 1234, max: nil, isDefault: true)])
        XCTAssertEqual(m.tmdbID, 603)
        XCTAssertEqual(m.imdbID, "tt0133093")
        XCTAssertEqual(m.uniqueIDs.filter { $0.type == "imdb" }.count, 1, "The bare <id> does not duplicate <imdbid>")
        XCTAssertEqual(m.collectionName, "Trilogy")
        XCTAssertNil(m.collectionTMDBID)
    }

    func testRuntimeFallsBackToStreamDetails() throws {
        let m = try movie("""
        <movie><title>X</title><runtime></runtime>
        <fileinfo><streamdetails><video><durationinseconds>7230</durationinseconds></video></streamdetails></fileinfo></movie>
        """)
        XCTAssertEqual(m.runtimeMinutes, 121)
    }

    func testRuntimeWithUnitsTakesTheLeadingNumber() throws {
        XCTAssertEqual(try movie("<movie><runtime>120 min</runtime></movie>").runtimeMinutes, 120)
        XCTAssertNil(try movie("<movie><title>No runtime</title></movie>").runtimeMinutes)
    }

    func testYearFromPremieredWhenYearIsMissingOrInvalid() throws {
        XCTAssertEqual(try movie("<movie><premiered>2005-07-01</premiered></movie>").year, 2005)
        XCTAssertEqual(try movie("<movie><year>0</year><premiered>2005-07-01</premiered></movie>").year, 2005)
        XCTAssertEqual(try movie("<movie><year>2010</year></movie>").year, 2010)
        XCTAssertNil(try movie("<movie><year>unknown</year></movie>").year)
    }

    // MARK: Series and episodes

    func testTVShow() throws {
        let m = try movie("""
        <tvshow>
          <title>Example Show</title>
          <showtitle>Example Show</showtitle>
          <year>2011</year>
          <premiered>2011-04-17</premiered>
          <genre>Drama</genre>
          <studio>HBO</studio>
          <uniqueid type="tvdb" default="true">121361</uniqueid>
          <uniqueid type="imdb">tt0944947</uniqueid>
          <id>121361</id>
          <thumb aspect="poster" type="season" season="1">s1.jpg</thumb>
          <thumb aspect="poster" type="season" season="0">specials.jpg</thumb>
          <thumb aspect="poster" type="season" season="-1">all.jpg</thumb>
          <thumb aspect="banner">banner.jpg</thumb>
          <thumb>plain.jpg</thumb>
          <actor><name>Someone</name><role>Lead</role></actor>
        </tvshow>
        """)
        XCTAssertEqual(m.kind, .tvshow)
        XCTAssertEqual(m.tvdbID, 121361)
        XCTAssertEqual(m.imdbID, "tt0944947")
        XCTAssertEqual(m.uniqueIDs.filter { $0.type == "tvdb" }.count, 1)
        XCTAssertEqual(m.artwork.filter { $0.kind == .poster }.map(\.season), [1, 0, -1])
        XCTAssertEqual(m.artwork.first { $0.kind == .banner }?.location, "banner.jpg")
        XCTAssertEqual(m.artwork.last?.kind, .thumb)
    }

    func testMultiEpisodeFile() throws {
        let file = parse("""
        <episodedetails>
          <title>Pilot (1)</title>
          <showtitle>Example Show</showtitle>
          <season>1</season>
          <episode>1</episode>
          <aired>2011-04-17</aired>
          <runtime>58</runtime>
          <plot>Part one.</plot>
          <playcount>1</playcount>
        </episodedetails>
        <episodedetails>
          <title>Pilot (2)</title>
          <season>1</season>
          <episode>2</episode>
          <displayseason>0</displayseason>
          <displayepisode>5</displayepisode>
          <aired>2011-04-17</aired>
        </episodedetails>
        """)
        XCTAssertEqual(file.warnings, [])
        XCTAssertEqual(file.documents.count, 2)
        XCTAssertEqual(file.documents.map(\.kind), [.episode, .episode])
        XCTAssertEqual(file.documents.map(\.title), ["Pilot (1)", "Pilot (2)"])
        XCTAssertEqual(file.documents.map(\.episode), [1, 2])
        XCTAssertEqual(file.documents[0].season, 1)
        XCTAssertEqual(file.documents[0].showTitle, "Example Show")
        XCTAssertEqual(file.documents[0].premiered, CalendarDay(year: 2011, month: 4, day: 17))
        XCTAssertEqual(file.documents[1].displaySeason, 0)
        XCTAssertEqual(file.documents[1].displayEpisode, 5)
        XCTAssertEqual(file.documents[0].playCount, 1)
    }

    func testEpisodeDatePrefersAiredButMovieDatePrefersPremiered() throws {
        let both = "<premiered>2000-01-01</premiered><aired>2001-02-03</aired>"
        XCTAssertEqual(try movie("<episodedetails>\(both)</episodedetails>").premiered, CalendarDay(year: 2001, month: 2, day: 3))
        XCTAssertEqual(try movie("<movie>\(both)</movie>").premiered, CalendarDay(year: 2000, month: 1, day: 1))
    }

    // MARK: Encodings and damage

    func testByteOrderMarkAndEncodings() throws {
        let xml = "<movie><title>Amélie</title><plot>Café Noël — “quotes”</plot></movie>"
        let utf8 = Data(xml.utf8)
        let utf8BOM = Data([0xEF, 0xBB, 0xBF]) + utf8
        let utf16LEBOM = Data([0xFF, 0xFE]) + xml.data(using: .utf16LittleEndian)!
        let utf16BEBOM = Data([0xFE, 0xFF]) + xml.data(using: .utf16BigEndian)!
        let utf16LENoBOM = xml.data(using: .utf16LittleEndian)!
        let utf16BENoBOM = xml.data(using: .utf16BigEndian)!
        for (name, data) in [("utf8", utf8), ("utf8 BOM", utf8BOM), ("utf16 LE BOM", utf16LEBOM), ("utf16 BE BOM", utf16BEBOM),
                             ("utf16 LE", utf16LENoBOM), ("utf16 BE", utf16BENoBOM)] {
            let file = NFOParser.parse(data)
            XCTAssertEqual(file.documents.first?.title, "Amélie", name)
            XCTAssertEqual(file.documents.first?.plot, "Café Noël — “quotes”", name)
            XCTAssertEqual(file.warnings, [], name)
        }
    }

    func testWindows1252FallbackWhenNotValidUTF8() throws {
        // "Amélie" with é as the single byte 0xE9, as old Windows tools wrote it.
        var bytes = Array("<?xml version=\"1.0\" encoding=\"windows-1252\"?><movie><title>Am".utf8)
        bytes.append(0xE9)
        bytes += Array("lie</title></movie>".utf8)
        XCTAssertEqual(NFOParser.parse(Data(bytes)).documents.first?.title, "Amélie")
    }

    func testBadEntitiesAndBareAmpersands() throws {
        let m = try movie("""
        <movie>
          <title>Tom &amp; Jerry &eacute;dition &nbsp;extra</title>
          <plot>Fish & chips &unknown; and &#233; and &#xE9; &lt;3</plot>
          <studio>AT&T</studio>
        </movie>
        """)
        XCTAssertEqual(m.title, "Tom & Jerry édition \u{00A0}extra")
        XCTAssertEqual(m.plot, "Fish & chips &unknown; and é and é <3")
        XCTAssertEqual(m.studios, ["AT&T"])
    }

    func testHTMLEscapedPlotBecomesPlainText() throws {
        let escaped = try movie("<movie><plot>Line one.&lt;br /&gt;Line two.&lt;br&gt;&lt;i&gt;Italic&lt;/i&gt; &amp;amp; more</plot></movie>")
        XCTAssertEqual(escaped.plot, "Line one.\nLine two.\nItalic & more")
        let cdata = try movie("<movie><plot><![CDATA[<p>Para one.</p><p>Para two with <b>bold</b>.</p>]]></plot></movie>")
        XCTAssertEqual(cdata.plot, "Para one.\n\nPara two with bold.")
    }

    func testEmptyFieldsAreNilOrEmptyNotJunk() throws {
        let m = try movie("<movie><title/><originaltitle></originaltitle><plot>   </plot><genre></genre><year></year><actor><name></name></actor><thumb></thumb></movie>")
        XCTAssertNil(m.title)
        XCTAssertNil(m.originalTitle)
        XCTAssertNil(m.plot)
        XCTAssertEqual(m.genres, [])
        XCTAssertNil(m.year)
        XCTAssertEqual(m.actors, [])
        XCTAssertEqual(m.artwork, [])
    }

    func testCommentsDoctypeAndUnknownElementsAreIgnored() throws {
        let file = parse("""
        <?xml version="1.0"?>
        <!DOCTYPE movie>
        <!-- written by hand -->
        <movie>
          <title>Commented</title>
          <futurefield><nested>1</nested></futurefield>
        </movie>
        """)
        XCTAssertEqual(file.warnings, [])
        XCTAssertEqual(file.documents.first?.title, "Commented")
    }

    func testControlCharactersAreDropped() throws {
        XCTAssertEqual(try movie("<movie><title>Bad\u{0001}Char\u{0008}s</title></movie>").title, "BadChars")
    }

    func testMalformedXMLKeepsWhatWasRead() throws {
        let file = parse("<movie><title>Half</title><plot>never closed")
        XCTAssertEqual(file.documents.first?.title, "Half")
        XCTAssertTrue(file.warnings.contains { $0.contains("malformed") })
    }

    func testMismatchedTagsKeepEarlierFields() throws {
        let file = parse("<movie><title>Keep</title><genre>Drama</wrong></movie>")
        XCTAssertEqual(file.documents.first?.title, "Keep")
        XCTAssertFalse(file.warnings.isEmpty)
    }

    func testEmptyAndGarbageFiles() {
        XCTAssertEqual(NFOParser.parse(Data()).documents, [])
        XCTAssertFalse(NFOParser.parse(Data()).warnings.isEmpty)
        XCTAssertFalse(NFOParser.parse(text: "   \n  ").warnings.isEmpty)
        let noRoot = NFOParser.parse(text: "<html><body>hi</body></html>")
        XCTAssertEqual(noRoot.documents, [])
        XCTAssertTrue(noRoot.warnings.contains { $0.contains("no movie, tvshow or episodedetails") })
        let noXML = NFOParser.parse(text: "just some words")
        XCTAssertEqual(noXML.documents, [])
        XCTAssertNil(noXML.link)
        XCTAssertFalse(noXML.warnings.isEmpty)
    }

    // MARK: Link-only nfo

    func testBareURLNfo() {
        let tmdb = NFOParser.parse(text: "https://www.themoviedb.org/movie/603-the-matrix\n")
        XCTAssertEqual(tmdb.documents, [])
        XCTAssertEqual(tmdb.link?.service, .tmdb)
        XCTAssertEqual(tmdb.link?.id, "603")
        XCTAssertEqual(tmdb.link?.mediaType, "movie")
        let tv = NFOParser.parse(text: "https://www.themoviedb.org/tv/1399")
        XCTAssertEqual(tv.link?.mediaType, "tv")
        XCTAssertEqual(tv.link?.id, "1399")
        let imdb = NFOParser.parse(text: "https://www.imdb.com/title/tt0133093/")
        XCTAssertEqual(imdb.link?.service, .imdb)
        XCTAssertEqual(imdb.link?.id, "tt0133093")
        let tvdb = NFOParser.parse(text: "https://thetvdb.com/?tab=series&id=121361")
        XCTAssertEqual(tvdb.link?.service, .tvdb)
        XCTAssertEqual(tvdb.link?.id, "121361")
        let other = NFOParser.parse(text: "https://example.invalid/some/page")
        XCTAssertEqual(other.link?.service, .other)
        XCTAssertNil(other.link?.id)
    }

    func testURLAfterTheXML() throws {
        let file = parse("<movie><title>With Link</title></movie>\nhttps://www.themoviedb.org/movie/603\n")
        XCTAssertEqual(file.documents.first?.title, "With Link")
        XCTAssertEqual(file.link?.id, "603")
    }

    // MARK: CalendarDay

    func testCalendarDayParsing() {
        XCTAssertEqual(CalendarDay(parsing: "2019-04-26"), CalendarDay(year: 2019, month: 4, day: 26))
        XCTAssertEqual(CalendarDay(parsing: "2019-04-26 00:00:00"), CalendarDay(year: 2019, month: 4, day: 26))
        XCTAssertEqual(CalendarDay(parsing: "2019-04-26T10:20:30Z"), CalendarDay(year: 2019, month: 4, day: 26))
        XCTAssertEqual(CalendarDay(parsing: "2019/4/6"), CalendarDay(year: 2019, month: 4, day: 6))
        XCTAssertEqual(CalendarDay(parsing: "26.04.2019"), CalendarDay(year: 2019, month: 4, day: 26))
        XCTAssertEqual(CalendarDay(parsing: " 2019 "), CalendarDay(year: 2019))
        XCTAssertEqual(CalendarDay(parsing: "2019-13-40"), CalendarDay(year: 2019), "Impossible month and day are dropped, the year stays")
        XCTAssertNil(CalendarDay(parsing: "soon"))
        XCTAssertNil(CalendarDay(parsing: ""))
        XCTAssertNil(CalendarDay(parsing: "12"))
        XCTAssertTrue(CalendarDay(year: 2019, month: 4, day: 26) < CalendarDay(year: 2019, month: 5))
        XCTAssertTrue(CalendarDay(year: 2018) < CalendarDay(year: 2019))
    }

    func testPlainTextHelper() {
        XCTAssertEqual(NFOXML.plainText("a<br/>b"), "a\nb")
        XCTAssertEqual(NFOXML.plainText("  a  \n\n\n\n b  "), "a\n\nb")
        XCTAssertEqual(NFOXML.plainText("1 &lt; 2 &amp;&amp; 3 &gt; 2"), "1 < 2 && 3 > 2")
        XCTAssertEqual(NFOXML.plainText("x &#8212; y"), "x \u{2014} y")
        XCTAssertEqual(NFOXML.plainText("5 < 6"), "5 < 6", "A bare less-than that starts no tag survives")
    }

    // MARK: Never crashes

    func testTruncationAtEveryByteNeverCrashes() {
        let data = Data(fullMovie.utf8)
        for n in 0...data.count {
            let file = NFOParser.parse(data.prefix(n))
            XCTAssertLessThanOrEqual(file.documents.count, 1)
        }
    }

    func testRandomBytesNeverCrash() {
        var seed: UInt64 = 0x1234_5678_9ABC_DEF0
        func next() -> UInt8 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: seed >> 33)
        }
        let alphabet = Array("<>/&;=\"' abcdefghijklmnopqrstuvwxyz0123456789!?-[]".utf8)
        for round in 0..<400 {
            let count = Int(next()) + 1
            var bytes: [UInt8] = []
            for _ in 0..<count { bytes.append(round % 3 == 0 ? next() : alphabet[Int(next()) % alphabet.count]) }
            _ = NFOParser.parse(Data(bytes))
        }
    }

    func testFlippedBytesInAValidNfoNeverCrash() {
        var seed: UInt64 = 42
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: seed >> 33) & 0x7FFF_FFFF
        }
        let original = Array(fullMovie.utf8)
        for _ in 0..<500 {
            var bytes = original
            for _ in 0..<(1 + next() % 6) { bytes[next() % bytes.count] = UInt8(truncatingIfNeeded: next()) }
            _ = NFOParser.parse(Data(bytes))
        }
    }
}
