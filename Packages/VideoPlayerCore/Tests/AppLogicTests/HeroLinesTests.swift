import XCTest
import VideoPlayerCore
import LibraryIndex
@testable import AppLogic

/// R471 item 2: the hero's kind line, facts line, glyph badges and the access features read from a file's tracks.
final class HeroLinesTests: XCTestCase {
    let en = Locale(identifier: "en_US")

    func testAMoviesKindLineHasTheGlyphTheWordTheGenresAndTheRatingBox() {
        let line = HeroLines.kindLine(kind: .movie, source: .plex, genres: ["Animation", "Kids & Family"], rating: "G")
        XCTAssertEqual(line, [.glyph(symbol: "server.rack", spoken: "Media server"), .text("Movie"), .text("Animation"),
                              .text("Kids & Family"), .ratingBox("G")])
    }

    func testAShowSaysTVShowAndAnEpisodeHasNoKindWord() {
        XCTAssertEqual(HeroLines.kindLine(kind: .show, source: nil, genres: ["Comedy"], rating: nil), [.text("TV Show"), .text("Comedy")])
        XCTAssertEqual(HeroLines.kindLine(kind: .episode, source: .smb, genres: ["Comedy", "Sports"], rating: "TV-MA"),
                       [.glyph(symbol: "externaldrive.connected.to.line.below", spoken: "Network folder"), .text("Comedy"), .text("Sports"),
                        .ratingBox("TV-MA")])
    }

    func testGenresAreCappedDeduplicatedAndBlankOnesDropped() {
        let line = HeroLines.kindLine(kind: .movie, source: nil, genres: ["Drama", " ", "drama", "Crime", "Thriller", "Mystery"], rating: " ")
        XCTAssertEqual(line, [.text("Movie"), .text("Drama"), .text("Crime"), .text("Thriller")])
    }

    func testAGlyphAloneIsNoLine() {
        XCTAssertEqual(HeroLines.kindLine(kind: .episode, source: .plex, genres: [], rating: nil), [])
    }

    func testEverySourceKindHasAGenericSystemSymbolAndAName() {
        for kind in SourceKind.allCases {
            XCTAssertFalse(SourceGlyph.symbol(kind).isEmpty)
            XCTAssertFalse(SourceGlyph.spoken(kind).isEmpty)
            // No service's name in what is spoken: the glyph is generic.
            for brand in ["Plex", "Jellyfin", "Emby", "Google", "Dropbox", "OneDrive"] {
                XCTAssertFalse(SourceGlyph.spoken(kind).contains(brand), "\(kind)")
            }
        }
    }

    func testTheFactsLineGivesAnEpisodesFullDateAndAMoviesYear() {
        XCTAssertEqual(HeroLines.factsText(kind: .episode, date: PartialDate(year: 2026, month: 8, day: 26), year: nil, durationSeconds: 43 * 60, locale: en),
                       ["Aug 26, 2026", "43m"])
        XCTAssertEqual(HeroLines.factsText(kind: .movie, date: PartialDate(year: 1973, month: 11, day: 20), year: 1973, durationSeconds: 25 * 60, locale: en),
                       ["1973", "25m"])
        XCTAssertEqual(HeroLines.factsText(kind: .movie, date: nil, year: nil, durationSeconds: nil, locale: en), [])
        XCTAssertEqual(HeroLines.factsText(kind: .episode, date: nil, year: 2020, durationSeconds: 0, locale: en), ["2020"])
    }

    func testShortDurationsAndTimeLeft() {
        XCTAssertEqual(ShortDuration.text(43 * 60), "43m")
        XCTAssertEqual(ShortDuration.text(112 * 60), "1h 52m")
        XCTAssertEqual(ShortDuration.text(120 * 60), "2h")
        XCTAssertEqual(ShortDuration.text(10), "1m")
        XCTAssertEqual(ShortDuration.left(17 * 60 + 5), "18m", "time left rounds up")
        XCTAssertEqual(ShortDuration.left(3), "1m")
        XCTAssertNil(ShortDuration.left(0))
        XCTAssertNil(ShortDuration.left(.nan))
    }

    func testTheDescriptionPrefixes() {
        XCTAssertEqual(HeroLines.episodePrefix(code: "S4, E4"), "S4, E4:")
        XCTAssertNil(HeroLines.episodePrefix(code: nil))
        XCTAssertNil(HeroLines.episodePrefix(code: " "))
        XCTAssertEqual(HeroLines.nextUpPrefix(code: "S4, E4", title: "A Day Off"), "S4, E4 · A Day Off:")
        XCTAssertEqual(HeroLines.nextUpPrefix(code: nil, title: "A Day Off"), "A Day Off:")
        XCTAssertNil(HeroLines.nextUpPrefix(code: nil, title: nil))
    }

    func testGlyphBadgesSayHDNot1080pAndSplitTwoWordNames() {
        let badges = HeroBadges.make(format: [FormatBadgeItem(.resolution, "1080p"), FormatBadgeItem(.hdr, "Dolby Vision"),
                                              FormatBadgeItem(.audio, "Dolby Atmos"), FormatBadgeItem(.channels, "5.1"),
                                              FormatBadgeItem(.container, "MKV")],
                                     access: [.cc, .sdh, .ad])
        XCTAssertEqual(badges.map(\.lines), [["HD"], ["Dolby", "Vision"], ["Dolby", "Atmos"], ["CC"], ["SDH"], ["AD"]])
        XCTAssertFalse(badges.contains { $0.lines.joined().contains("1080p") })
        XCTAssertEqual(badges.first?.spoken, "HD, resolution")
        XCTAssertEqual(HeroBadges.make(format: [FormatBadgeItem(.resolution, "4K")], access: []).map(\.lines), [["4K"]])
        XCTAssertEqual(HeroBadges.make(format: [FormatBadgeItem(.resolution, "SD"), FormatBadgeItem(.audio, "DTS-HD MA")], access: []).map(\.lines),
                       [["SD"], ["DTS-HD", "MA"]])
    }

    func testAccessFeaturesComeOnlyFromTheTracks() {
        XCTAssertEqual(AccessFeature.detect(nil), [])
        var tracks = FileTrackDetails(frameRate: nil, audio: [], subtitles: [])
        XCTAssertEqual(AccessFeature.detect(tracks), [])
        tracks.subtitles = [.init(codec: "subrip", language: "en", name: "English", isForced: false, isHearingImpaired: true),
                            .init(codec: "eia_608", language: "en", name: nil, isForced: false, isHearingImpaired: false)]
        tracks.audio = [.init(codec: "eac3", channels: 6, language: "en", name: "English", isDefault: true),
                        .init(codec: "aac", channels: 2, language: "en", name: "English (Audio Description)", isDefault: false)]
        XCTAssertEqual(AccessFeature.detect(tracks), [.cc, .sdh, .ad])
        XCTAssertTrue(AccessFeature.isDescription("English AD"))
        XCTAssertTrue(AccessFeature.isDescription("Descriptive Audio"))
        XCTAssertFalse(AccessFeature.isDescription("Headphones mix"), "letters 'ad' inside a word are no AD")
        XCTAssertFalse(AccessFeature.isDescription(nil))
    }
}
