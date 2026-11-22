import XCTest
import LibraryIndex
@testable import AppLogic

/// R313: the player says which episode, in the TV app's form "S1, E3"; never "S?"; films unchanged.
final class PlayerEpisodeTextTests: XCTestCase {
    /// An episode of the test library (Show One S1 E3), changed to what the case needs.
    private func episode(_ title: String, show: String? = "Sample Show 1", season: Int? = 1, episode: Int? = 3,
                         end: Int? = nil) async throws -> LibraryItem {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let all = try await rig.episodes(ofSeriesTitle: "Show One")
        var item = try XCTUnwrap(all.first { $0.season == 1 && $0.episode == 3 })
        item.title = title
        item.seriesTitle = show
        item.season = season
        item.episode = episode
        item.episodeEnd = end
        return item
    }

    func testCodeForms() async throws {
        XCTAssertEqual(PlayerEpisodeText.code(season: 1, episode: 3), "S1, E3")
        XCTAssertEqual(PlayerEpisodeText.code(season: 1, episode: 3, episodeEnd: 4), "S1, E3–E4")
        XCTAssertEqual(PlayerEpisodeText.code(season: 1, episode: 3, episodeEnd: 3), "S1, E3")
        XCTAssertEqual(PlayerEpisodeText.code(season: nil, episode: 3), "E3")
        XCTAssertEqual(PlayerEpisodeText.code(season: 2, episode: nil), "S2")
        XCTAssertNil(PlayerEpisodeText.code(season: nil, episode: nil))
    }

    func testEpisodeWithAName() async throws {
        let lines = PlayerEpisodeText.lines(for: try await episode("A quiet beginning"), filmTitle: "x", filmSubtitle: "y")
        // R396 (audit PL1): Apple's order, the show large and "S1, E3 • name" small above it.
        XCTAssertEqual(lines.title, "Sample Show 1")
        XCTAssertEqual(lines.subtitle, "S1, E3 • A quiet beginning")
    }

    func testEpisodeWithoutAName() async throws {
        for noName in ["", "S01E03", "Sample Show 1"] {
            let lines = PlayerEpisodeText.lines(for: try await episode(noName), filmTitle: "x", filmSubtitle: nil)
            XCTAssertEqual(lines.title, "Sample Show 1", noName)
            XCTAssertEqual(lines.subtitle, "S1, E3", noName)
        }
    }

    func testTwoPartFile() async throws {
        let lines = PlayerEpisodeText.lines(for: try await episode("Two parts", episode: 3, end: 4), filmTitle: "x", filmSubtitle: nil)
        XCTAssertEqual(lines.subtitle, "S1, E3–E4 • Two parts")
    }

    func testUnknownSeasonShowsOnlyWhatIsKnown() async throws {
        let lines = PlayerEpisodeText.lines(for: try await episode("Named", season: nil), filmTitle: "x", filmSubtitle: nil)
        XCTAssertEqual(lines.subtitle, "E3 • Named")
        let neither = PlayerEpisodeText.lines(for: try await episode("Named", season: nil, episode: nil), filmTitle: "x", filmSubtitle: nil)
        XCTAssertEqual(neither.title, "Sample Show 1")
        XCTAssertEqual(neither.subtitle, "Named")
        // Without a show the episode's own name is the large line.
        let noShow = PlayerEpisodeText.episodeLines(name: "Named", show: nil, season: 1, episode: 3)
        XCTAssertEqual(noShow.title, "Named")
        XCTAssertEqual(noShow.subtitle, "S1, E3")
        let bare = PlayerEpisodeText.episodeLines(name: nil, show: nil, season: nil, episode: nil)
        XCTAssertEqual(bare.title, "Untitled")
        XCTAssertNil(bare.subtitle)
        for text in [lines.subtitle, neither.subtitle, PlayerEpisodeText.upNextLine(show: nil, season: nil, episode: 4, name: nil)] {
            XCTAssertFalse(text?.contains("?") ?? false)
        }
    }

    func testFilmIsUnchanged() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let id = try await rig.movieID("Hexfall")
        let found = try await rig.store.item(id: id)
        var film = try XCTUnwrap(found)
        film.title = "Sample Movie 1"
        let lines = PlayerEpisodeText.lines(for: film, filmTitle: "Sample Movie 1", filmSubtitle: nil)
        XCTAssertEqual(lines.title, "Sample Movie 1")
        XCTAssertNil(lines.subtitle)
        XCTAssertNil(PlayerEpisodeText.errorLine(for: film))
    }

    func testUpNextAndErrorLines() async throws {
        XCTAssertEqual(PlayerEpisodeText.upNextLine(show: "Sample Show 1", season: 1, episode: 4, name: "The long way round"),
                       "Sample Show 1 · S1, E4 · The long way round")
        XCTAssertEqual(PlayerEpisodeText.upNextLine(show: "Sample Show 1", season: 1, episode: 4, name: nil), "Sample Show 1 · S1, E4")
        let named = try await episode("A quiet beginning")
        let unnamed = try await episode("")
        XCTAssertEqual(PlayerEpisodeText.errorLine(for: named), "Sample Show 1 · S1, E3 · A quiet beginning")
        XCTAssertEqual(PlayerEpisodeText.errorLine(for: unnamed), "Sample Show 1 · S1, E3")
    }

    /// The Episodes tab: each row's caption starts with its "S1, E3"; a row with no known number shows its name alone.
    func testEpisodesTabCaptions() async throws {
        let rig = try LibraryRig.make()
        try await rig.fill()
        let all = try await rig.episodes(ofSeriesTitle: "Show One")
        let current = try XCTUnwrap(all.first { $0.season == 1 && $0.episode == 3 })
        let loaded = await PlayerEpisodes.load(itemID: current.id, store: rig.store)
        let content = try XCTUnwrap(loaded)
        let row = try XCTUnwrap(content.season.episodes.first { $0.id == current.id })
        XCTAssertTrue(content.caption(for: row).hasPrefix("S1, E3 · "), content.caption(for: row))
        var bare = content
        bare.codes = [:]
        XCTAssertEqual(bare.caption(for: row), row.title)
    }
}
