import XCTest
@testable import ScreenChecks

/// R471 (27) onwards, PROVISIONAL: differences the frame-by-frame audit of the product pages found, one check per fix.
/// Structure only, from the source: nothing is compiled or run on tvOS here, and nothing here proves the look.
extension ScreenChecksTests {
    /// R471 (27): the Information, Languages and Accessibility headings are a large bold system style.
    func testTheInfoColumnHeadingsAreLargeAndBold() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("Text(heading)\n                .font(.title3.weight(.bold))"), "the column heading style")
    }

    /// R471 (29): an episode's list entry is named "Show: Episode", interpolated, not the literal text.
    func testAnEpisodesListNameIsInterpolated() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift") else { return }
        XCTAssertTrue(detail.contains(#"return "\(content.title): \(episode)""#))
        XCTAssertFalse(detail.contains(#"return "(content.title): (episode)""#))
    }

    /// R471 (30): both product pages give the About card their genres; the card shows the line under the title.
    func testTheAboutCardHasTheGenreLine() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift"),
              let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(detail.contains("guidance: nil,\n                                 genres: details?.genres ?? [])"))
        XCTAssertTrue(seasons.contains("guidance: guidance,\n                                 genres: details?.genres ?? [])"))
        let title = try XCTUnwrap(sections.range(of: "FittingText(title, style: .headline)"))
        let genre = try XCTUnwrap(sections.range(of: "AboutGenres.line(genres)"))
        let summary = try XCTUnwrap(sections.range(of: "Text(summary)"))
        XCTAssertTrue(title.lowerBound < genre.lowerBound && genre.lowerBound < summary.lowerBound, "title, genres, synopsis")
    }

    /// R471 (31): Go to Season opens the show page on the episode's season (its own route), not the Go to Show route.
    func testGoToSeasonOpensTheEpisodesSeason() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let routes = try appSource("App/Shell/RouteDestinations.swift"),
              let series = try appSource("App/Features/Shows/SeriesView.swift"),
              let seasons = try appSource("App/Features/Shows/SeasonsList.swift") else { return }
        XCTAssertTrue(detail.contains("Route.seriesSeason(seriesID, season: $0)"))
        XCTAssertTrue(detail.contains("ProductAction.goToSeasonTitle(content.season)"))
        XCTAssertTrue(routes.contains("SeriesView(seriesID: id, startSeason: season)"))
        XCTAssertTrue(series.contains("startSeason: startSeason)"))
        XCTAssertTrue(seasons.contains("chosen: chosenSeason ?? startSeason"), "the person's own tab choice still wins")
    }

    /// R471 (38): the actions menu's Audio and Subtitles rows list the file's tracks, and the player applies a title's own pick.
    func testAudioAndSubtitlesInTheMenuReachThePlayer() throws {
        guard let detail = try appSource("App/Features/Detail/ItemDetailContentView.swift"),
              let menu = try appSource("App/Features/Detail/TrackChoiceMenu.swift"),
              let start = try appSource("App/Features/Player/StartTrackChoice.swift"),
              let player = try appSource("App/Features/Player/PlayerCoordinator.swift") else { return }
        XCTAssertTrue(detail.contains("case .audio, .subtitles:"))
        XCTAssertTrue(detail.contains("TrackChoiceMenu(kind:"))
        XCTAssertTrue(detail.contains("c.hasTracks ="))
        XCTAssertTrue(menu.contains(".pickerStyle(.menu)"), "a system menu picker, not custom rows")
        XCTAssertTrue(menu.contains("StartTrackChoice.keep(choice, itemID: itemID)"))
        XCTAssertTrue(start.contains("ItemTrackMenu.startChoice(item: itemChoice(itemID"), "a title's own pick wins at the start")
        XCTAssertTrue(player.contains("StartTrackChoice.apply(to: item, seriesTitle: resolved.content.seriesTitle, itemID: itemID)"))
        XCTAssertTrue(player.contains("StartTrackChoice.remember(from: item, seriesTitle: resolved.content.seriesTitle, itemID: itemID)"))
    }
}
