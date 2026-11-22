import XCTest
import MetadataOnline
@testable import AppLogic

/// R379 (audit #29): every Missing Episodes line can take focus, so the remote reaches and scrolls the whole list.
final class MissingEpisodeLinesTests: XCTestCase {
    private func group(_ episodes: [MissingEpisode]) -> MissingEpisodesGroup {
        MissingEpisodesGroup(seriesTMDBID: 1, seriesTitle: "Sample Show 1", episodes: episodes)
    }

    func testEveryEpisodeLineTakesFocus() {
        let episodes: [MissingEpisode] = (1...30).map { MissingEpisode(season: 1, episode: $0, name: "Sample Episode \($0)") }
        let lines: [MissingEpisodeLine] = MissingEpisodeLines.lines(group(episodes))
        XCTAssertEqual(lines.count, 30)
        XCTAssertTrue(lines.allSatisfy(\.isFocusable), "a long list needs a focus stop on every line to scroll")
        XCTAssertEqual(lines.map(\.id), episodes.map(\.id), "the group's order is kept")
    }

    func testTheWordingIsUnchanged() {
        let dated = MissingEpisode(season: 2, episode: 3, name: "Sample Episode", airDate: CalendarDate(year: 2024, month: 1, day: 31))
        let undated = MissingEpisode(season: 1, episode: 2, name: "Sample Episode")
        XCTAssertEqual(MissingEpisodeLines.text(undated), "S1, E2  Sample Episode")
        XCTAssertEqual(MissingEpisodeLines.text(dated), "S2, E3  Sample Episode  (aired \(CalendarDate(year: 2024, month: 1, day: 31)))")
    }

    func testAGroupWithNoEpisodesHasNoLines() {
        XCTAssertTrue(MissingEpisodeLines.lines(group([])).isEmpty)
    }
}
