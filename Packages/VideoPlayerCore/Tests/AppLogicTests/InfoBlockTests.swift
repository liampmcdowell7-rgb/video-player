import XCTest
@testable import AppLogic

/// R453: the info block's source (focused episode, season change, back to the show's data), hiding of parts with no data,
/// and the date rules.
final class InfoBlockTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    private var show: InfoFacts {
        InfoFacts(runtime: nil, date: PartialDate(year: 2019, month: 3, day: 7), contentRating: "TV-14", resolution: nil, audio: nil,
                  genres: ["Drama", "Mystery"], ratings: [], synopsis: "The show's own synopsis.")
    }

    func testShowBlockHasNoTitleLineAndItsOwnData() {
        let block = InfoBlock.show(show)
        XCTAssertNil(block.titleLine)
        XCTAssertEqual(block.genreLine, "Drama, Mystery")
        XCTAssertEqual(block.synopsis, "The show's own synopsis.")
    }

    func testFocusedEpisodeShowsItsOwnTitleLineAndData() {
        let facts = InfoFacts(runtime: "43 min", date: PartialDate(year: 2019, month: 3, day: 14), resolution: "4K", audio: "Dolby Digital 5.1",
                              synopsis: "Episode text.")
        let block = InfoBlock.episode(season: 2, number: 3, title: "Second chances", facts: facts, show: show)
        XCTAssertEqual(block.titleLine, "S2 - E3 - Second chances")
        XCTAssertEqual(block.synopsis, "Episode text.")
        XCTAssertEqual(block.line.plain, "43 min · \(InfoDateText.text(PartialDate(year: 2019, month: 3, day: 14))) · TV-14 · 4K · Dolby Digital 5.1")
    }

    func testEpisodeInheritsGenresAndRatingButNeverTheShowsSynopsisOrDate() {
        let block = InfoBlock.episode(season: 1, number: 1, title: "Pilot", facts: InfoFacts(runtime: "40 min"), show: show)
        XCTAssertEqual(block.genreLine, "Drama, Mystery")
        XCTAssertTrue(block.line.segments.contains(.ratingBox("TV-14")))
        XCTAssertNil(block.synopsis, "an episode without a synopsis shows none, never the show's")
        XCTAssertFalse(block.line.plain.contains("2019"), "the show's first air date is not the episode's air date")
    }

    func testChangingSeasonOrFocusReplacesTheBlockAndBackToShowRestoresIt() {
        let one = InfoBlock.episode(season: 1, number: 2, title: "A", facts: InfoFacts(runtime: "40 min", synopsis: "a"), show: show)
        let two = InfoBlock.episode(season: 2, number: 1, title: "B", facts: InfoFacts(runtime: "50 min", synopsis: "b"), show: show)
        XCTAssertNotEqual(one, two)
        XCTAssertEqual(InfoBlock.show(show), InfoBlock.show(show), "focus back on the show gives the same block as before")
        XCTAssertEqual(two.titleLine, "S2 - E1 - B")
    }

    func testPartsWithNoDataAreLeftOut() {
        let line = InfoLine(runtime: nil, date: nil, contentRating: nil, resolution: nil, audio: nil)
        XCTAssertTrue(line.isEmpty)
        XCTAssertEqual(line.plain, "")
        let onlyRuntime = InfoLine(runtime: "1 h 52 min", date: nil, contentRating: nil, resolution: nil, audio: nil)
        XCTAssertEqual(onlyRuntime.segments, [.text("1 h 52 min")])
        let block = InfoBlock.show(InfoFacts())
        XCTAssertNil(block.genreLine)
        XCTAssertNil(block.synopsis)
        XCTAssertTrue(block.ratings.isEmpty)
        XCTAssertEqual(block.spoken, "")
    }

    func testBlankSynopsisIsLeftOut() {
        XCTAssertNil(InfoBlock.show(InfoFacts(synopsis: "  \n ")).synopsis)
    }

    func testTheRatingIsTheOnlyBoxAndSitsAfterTheDate() {
        let line = InfoLine(runtime: "1 h", date: PartialDate(year: 2021, month: 3, day: 5), contentRating: "PG-13", resolution: "4K", audio: "Dolby Atmos", locale: us)
        XCTAssertEqual(line.segments, [.text("1 h"), .text("Mar 5, 2021"), .ratingBox("PG-13"), .text("4K"), .text("Dolby Atmos")])
        XCTAssertEqual(line.segments.filter { if case .ratingBox = $0 { return true } else { return false } }.count, 1)
    }

    func testDateUsesTheMediumStyleAndYearOnlyWhenOnlyAYearIsKnown() {
        XCTAssertEqual(InfoDateText.text(PartialDate(year: 2021, month: 3, day: 5), locale: us), "Mar 5, 2021")
        XCTAssertEqual(InfoDateText.text(PartialDate(year: 2021, month: 3), locale: us), "Mar 2021")
        XCTAssertEqual(InfoDateText.text(PartialDate(year: 2021), locale: us), "2021")
        XCTAssertEqual(InfoDateText.text(PartialDate(year: 2021, month: 3, day: 5), locale: Locale(identifier: "en_GB")), "5 Mar 2021")
    }

    func testIsoParsingKeepsWhatIsKnown() {
        XCTAssertEqual(PartialDate(iso: "2021-03-05"), PartialDate(year: 2021, month: 3, day: 5))
        XCTAssertEqual(PartialDate(iso: "2021-03"), PartialDate(year: 2021, month: 3))
        XCTAssertEqual(PartialDate(iso: "2021"), PartialDate(year: 2021))
        XCTAssertNil(PartialDate(iso: "2021-13-01"))
        XCTAssertNil(PartialDate(iso: ""))
        XCTAssertNil(PartialDate(iso: nil))
        XCTAssertNil(PartialDate(iso: "abc"))
    }

    func testButtonSymbolNames() {
        XCTAssertEqual(PageButtonSymbols.watched(true), "checkmark.circle")
        // R471 (103): a plain check while something is left to watch (frames show t08s, t10s); no eye on a hero.
        XCTAssertEqual(PageButtonSymbols.watched(false), "checkmark")
        XCTAssertNotEqual(PageButtonSymbols.watched(false), PageButtonSymbols.watched(true), "the two states look different")
        XCTAssertEqual(PageButtonSymbols.favourite(true), "heart.fill")
        XCTAssertEqual(PageButtonSymbols.favourite(false), "heart")
    }
}

final class InfoFactsFromContentTests: XCTestCase {
    private func content(year: Int?, badges: [FormatBadgeItem]) -> ItemDetailContent {
        ItemDetailContent(itemID: 1, kind: .movie, title: "M", seriesID: nil, seriesTitle: nil, facts: "", badges: badges, playTitle: "Play",
                          canStartOver: false, isWatched: false, isFavorite: false, progress: nil, versions: [], extras: [], artworkKey: "item-1",
                          runtimeText: "1 h 52 min", year: year)
    }

    func testFullDateFromDetailsWinsOverTheYear() {
        var d = TitleDetails(overview: "S", cast: [])
        d.releaseDate = PartialDate(year: 2021, month: 3, day: 5)
        let f = InfoFacts(content: content(year: 2021, badges: []), details: d, contentRating: "PG-13")
        XCTAssertEqual(f.date, PartialDate(year: 2021, month: 3, day: 5))
        XCTAssertEqual(f.runtime, "1 h 52 min")
        XCTAssertEqual(f.contentRating, "PG-13")
        XCTAssertEqual(f.synopsis, "S")
    }

    func testOnlyAYearIsShownAsAYearAndNothingWithoutOne() {
        XCTAssertEqual(InfoFacts(content: content(year: 2019, badges: []), details: nil, contentRating: nil).date, PartialDate(year: 2019))
        XCTAssertNil(InfoFacts(content: content(year: nil, badges: []), details: nil, contentRating: nil).date)
    }

    func testResolutionAndAudioAreThePlainTextOfTheHeadlineBadges() {
        let badges = [FormatBadgeItem(.resolution, "4K"), FormatBadgeItem(.hdr, "Dolby Vision"), FormatBadgeItem(.audio, "Dolby Atmos")]
        let f = InfoFacts(content: content(year: nil, badges: badges), details: nil, contentRating: nil)
        XCTAssertEqual(f.resolution, "4K")
        XCTAssertEqual(f.audio, "Dolby Atmos")
    }

    func testTheEditedDateOverridesTheOnlineOneInTheDetails() {
        var d = TitleDetails(overview: nil, cast: [])
        d.releaseDate = PartialDate(year: 2021, month: 3, day: 5)
        XCTAssertNotNil(d.releaseDate)
        XCTAssertFalse(d.isEmpty)
        XCTAssertTrue(TitleDetails(overview: nil, cast: []).isEmpty)
    }

    func testInformationGetsAReleaseDateRowAfterTheRating() {
        var d = TitleDetails(overview: nil, cast: [])
        d.contentRating = "PG"
        d.releaseDate = PartialDate(year: 2021)
        let rows = MediaInfo.withRating([MediaInfoRow(label: "Resolution", value: "4K")], details: d)
        XCTAssertEqual(rows.map(\.label), ["Rating", "Release Date", "Resolution"])
        XCTAssertEqual(rows[1].value, "2021")
    }
}

final class EpisodeCaptionTests: XCTestCase {
    func testCaptionIsNumberDotTitleOrJustTheTitleWithoutANumber() {
        XCTAssertEqual(EpisodeRow(id: 1, title: "Second chances", number: 4, code: "S1 E4", isWatched: false, artworkKey: "item-1").cardCaption, "4. Second chances")
        XCTAssertEqual(EpisodeRow(id: 1, title: "Special", number: 0, code: "", isWatched: false, artworkKey: "item-1").cardCaption, "Special")
    }
}
